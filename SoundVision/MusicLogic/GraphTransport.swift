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

    private var visualTasks: [Task<Void, Never>] = []
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
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        guard let visualLeadIn = onSchedule(timeline, secondsPerBeat) else { return false }
        isPlaying = true
        completion = onCompletion

        for event in timeline {
            guard let node = nodesByID[event.nodeID] else { continue }
            let delay = visualLeadIn + event.beat * secondsPerBeat
            // El destello lo sostiene quien recibe `onVisualTrigger`; llevar
            // aquí un segundo conjunto de nodos activos duplicaba ese trabajo y
            // publicaba un cambio por nota, reevaluando toda la interfaz.
            visualTasks.append(Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.isPlaying, !Task.isCancelled, node.isActive else { return }
                onVisualTrigger(node)
            })
        }

        let endDelay = visualLeadIn + (timeline.map(\.beat).max() ?? 0) * secondsPerBeat + 1.2
        visualTasks.append(Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(endDelay))
            guard let self, !Task.isCancelled else { return }
            self.finishPlayback()
        })
        return true
    }

    func stop() {
        visualTasks.forEach { $0.cancel() }
        visualTasks = []
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
        let roots = connections.filter {
            $0.sourceNodeID == nil && validNodeIDs.contains($0.destinationNodeID)
        }

        var pending = roots.map {
            PendingVisit(nodeID: $0.destinationNodeID, beat: 0, traversalCounts: [:])
        }
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
                pending.append(PendingVisit(
                    nodeID: connection.destinationNodeID,
                    beat: visit.beat + max(0.0625, connection.durationBeats),
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
        visualTasks.forEach { $0.cancel() }
        visualTasks = []
        isPlaying = false
        let callback = completion
        completion = nil
        callback?()
    }

    deinit {
        visualTasks.forEach { $0.cancel() }
    }
}
