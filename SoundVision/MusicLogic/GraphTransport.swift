import Combine
import Foundation

/// Construye primero una línea de tiempo completa del grafo. El audio puede
/// agendar esa línea de tiempo contra su propio reloj mientras estas tareas
/// solo mantienen sincronizada la representación visual.
@MainActor
final class GraphTransport: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var loopPasses = 2

    private var visualTask: Task<Void, Never>?
    private(set) var effectiveStartSeconds: TimeInterval?

    @discardableResult
    func start(
        nodes: [SoundNode],
        connections: [SoundConnection],
        bpm: Double,
        scheduleUsesHostClock: Bool = false,
        onSchedule: ([GraphPlaybackEvent], Double, Double) -> TimeInterval?,
        onVisualTrigger: @escaping (SoundNode) -> Void
    ) -> Bool {
        guard !isPlaying else { return false }
        let plan = GraphSchedule.makePlan(
            nodes: nodes,
            connections: connections,
            loopPasses: loopPasses
        )
        guard !plan.isTruncated, !plan.events.isEmpty else { return false }
        let timeline = plan.events

        let secondsPerBeat = 60 / max(bpm, 1)
        let loopDurationBeats = Self.loopDurationBeats(for: timeline)
        // Tolerante a identificadores repetidos: `uniqueKeysWithValues` aborta
        // el proceso en el acto, y una composición cargada con dos nodos del
        // mismo id convertía Play en un cierre inesperado.
        let nodesByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let scheduledStart = onSchedule(timeline, secondsPerBeat, loopDurationBeats) else { return false }
        let start = scheduleUsesHostClock ? scheduledStart : PlaybackClock.now + scheduledStart
        effectiveStartSeconds = start
        isPlaying = true

        // Una sola tarea recorre la línea de tiempo en orden. Antes se creaba
        // una por evento —hasta 512 tareas dormidas a la vez— y todas competían
        // por el hilo principal justo mientras sonaba la música.
        let ordered = timeline.sorted { $0.beat < $1.beat }
        visualTask = Task { @MainActor [weak self] in
            var loopOffsetBeats = 0.0

            // El grafo es un patrón, no una reproducción de una sola toma. La
            // agenda de audio repite el mismo patrón con su reloj sample-accurate
            // y esta tarea hace lo propio con los destellos hasta que llegue Stop.
            while let self, self.isPlaying, !Task.isCancelled {
                for event in ordered {
                    guard let node = nodesByID[event.nodeID] else { continue }
                    // Cada espera se mide contra el origen, no contra la anterior:
                    // así ni las ramas simultáneas ni las vueltas largas acumulan
                    // el retraso de los eventos anteriores.
                    let target = start + (loopOffsetBeats + event.beat) * secondsPerBeat
                    let delay = max(0, target - PlaybackClock.now)
                    try? await Task.sleep(for: .seconds(delay))
                    guard self.isPlaying, !Task.isCancelled else { return }
                    onVisualTrigger(node)
                }
                loopOffsetBeats += loopDurationBeats
            }
        }
        return true
    }

    func stop() {
        visualTask?.cancel()
        visualTask = nil
        isPlaying = false
        effectiveStartSeconds = nil
    }

    nonisolated static func makeSchedule(
        nodes: [SoundNode], connections: [SoundConnection], loopPasses: Int, maximumEvents: Int = 512
    ) -> [GraphPlaybackEvent] {
        GraphSchedule.makePlan(nodes: nodes, connections: connections, loopPasses: loopPasses,
                               maximumEvents: maximumEvents).events
    }

    /// Una vuelta termina un beat después del último ataque. Así un patrón de
    /// un solo organismo también tiene pulso y el último sonido no coincide con
    /// el primero de la siguiente vuelta por accidente.
    nonisolated static func loopDurationBeats(for timeline: [GraphPlaybackEvent]) -> Double {
        max(1, (timeline.map(\.beat).max() ?? 0) + 1)
    }

    deinit {
        visualTask?.cancel()
    }
}
