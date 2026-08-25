import Foundation

struct GraphPlaybackEvent: Equatable, Sendable {
    let nodeID: UUID
    let beat: Double
}

/// Construye primero una línea de tiempo completa del grafo. El audio puede
/// agendar esa línea de tiempo contra su propio reloj mientras estas tareas
/// solo mantienen sincronizada la representación visual.
@MainActor
final class GraphTransport: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var loopPasses = 2

    private var visualTask: Task<Void, Never>?
    private var completion: (() -> Void)?

    @discardableResult
    func start(
        nodes: [SoundNode],
        connections: [SoundConnection],
        bpm: Double,
        onSchedule: ([GraphPlaybackEvent], Double) -> TimeInterval?,
        onVisualTrigger: @escaping (SoundNode) -> Void,
        onCompletion: @escaping () -> Void = {}
    ) -> Bool {
        guard !isPlaying else { return false }
        let timeline = Self.makeSchedule(
            nodes: nodes,
            connections: connections,
            loopPasses: loopPasses
        )
        guard !timeline.isEmpty else { return false }

        let secondsPerBeat = 60 / max(bpm, 1)
        // Tolerante a identificadores repetidos: `uniqueKeysWithValues` aborta
        // el proceso en el acto, y una composición cargada con dos nodos del
        // mismo id convertía Play en un cierre inesperado.
        let nodesByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let visualLeadIn = onSchedule(timeline, secondsPerBeat) else { return false }
        isPlaying = true
        completion = onCompletion

        // Una sola tarea recorre la línea de tiempo en orden. Antes se creaba
        // una por evento —hasta 512 tareas dormidas a la vez— y todas competían
        // por el hilo principal justo mientras sonaba la música.
        let ordered = timeline.sorted { $0.beat < $1.beat }
        let endBeat = ordered.last?.beat ?? 0
        visualTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let origin = clock.now

            for event in ordered {
                guard let node = nodesByID[event.nodeID] else { continue }
                // Cada espera se mide contra el origen, no contra la anterior:
                // así el destello número cien no acumula el retraso de los
                // noventa y nueve anteriores.
                let target = origin.advanced(by: .seconds(visualLeadIn + event.beat * secondsPerBeat))
                try? await clock.sleep(until: target)
                guard let self, self.isPlaying, !Task.isCancelled else { return }
                if node.isActive { onVisualTrigger(node) }
            }

            // La última voz puede ser un Pad sostenido. Cerrar la sesión con una
            // cola fija de 1.2 s truncaba notas perfectamente válidas y hacía
            // parecer que algunos organismos no se reproducían completos.
            let end = origin.advanced(by: .seconds(
                visualLeadIn + endBeat * secondsPerBeat + VoiceSynthesis.maximumDuration + 0.15
            ))
            try? await clock.sleep(until: end)
            guard let self, !Task.isCancelled else { return }
            self.finishPlayback()
        }
        return true
    }

    func stop() {
        visualTask?.cancel()
        visualTask = nil
        isPlaying = false
        completion = nil
    }

    /// Cada salida de un nodo crea una rama con el mismo tiempo de partida.
    /// Los ciclos son intencionales y cada conexión puede recorrerse el número
    /// de veces indicado por `loopPasses`; el límite global protege ante grafos
    /// exponenciales creados accidentalmente.
    nonisolated static func makeSchedule(
        nodes: [SoundNode],
        connections: [SoundConnection],
        loopPasses: Int,
        maximumEvents: Int = 512
    ) -> [GraphPlaybackEvent] {
        struct PendingVisit {
            let nodeID: UUID
            let beat: Double
            let traversalCounts: [UUID: Int]
        }

        let validNodeIDs = Set(nodes.map(\.id))
        let outgoing = Dictionary(grouping: connections.compactMap { connection -> SoundConnection? in
            guard connection.sourceNodeID != nil,
                  validNodeIDs.contains(connection.destinationNodeID)
            else { return nil }
            return connection
        }, by: { $0.sourceNodeID! })
        let root = connections.first {
            $0.sourceNodeID == nil && validNodeIDs.contains($0.destinationNodeID)
        }

        // Defensa en profundidad: aunque un archivo hostil consiguiera saltarse
        // la sanitización, PLAY jamás dispara más de una rama.
        var pending = root.map {
            [PendingVisit(nodeID: $0.destinationNodeID, beat: 0, traversalCounts: [:])]
        } ?? []
        var result: [GraphPlaybackEvent] = []
        let passLimit = max(1, min(loopPasses, 8))

        while !pending.isEmpty, result.count < maximumEvents {
            pending.sort { lhs, rhs in
                lhs.beat == rhs.beat
                    ? lhs.nodeID.uuidString < rhs.nodeID.uuidString
                    : lhs.beat < rhs.beat
            }
            let visit = pending.removeFirst()
            result.append(GraphPlaybackEvent(nodeID: visit.nodeID, beat: visit.beat))

            for connection in outgoing[visit.nodeID, default: []] {
                let traversed = visit.traversalCounts[connection.id, default: 0]
                guard traversed < passLimit else { continue }
                var counts = visit.traversalCounts
                counts[connection.id] = traversed + 1
                let duration = connection.durationBeats.isFinite
                    ? max(0.0625, min(connection.durationBeats, 32))
                    : 1
                pending.append(PendingVisit(
                    nodeID: connection.destinationNodeID,
                    beat: visit.beat + duration,
                    traversalCounts: counts
                ))
            }
        }

        // Una convergencia que alcanza el mismo nodo en el mismo instante es
        // un solo ataque musical, aunque ambas rutas sigan siendo recorridas.
        var seen = Set<String>()
        return result.filter { event in
            let key = "\(event.nodeID.uuidString):\(Int64((event.beat * 1_000_000).rounded()))"
            return seen.insert(key).inserted
        }
    }

    private func finishPlayback() {
        visualTask = nil
        isPlaying = false
        let callback = completion
        completion = nil
        callback?()
    }

    deinit {
        visualTask?.cancel()
    }
}
