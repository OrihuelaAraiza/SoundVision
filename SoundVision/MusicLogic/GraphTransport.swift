import Foundation

/// Recorre el grafo desde el núcleo Play. Los ciclos se visitan una vez por
/// sesión para que una conexión accidental no genere reproducción infinita.
@MainActor
final class GraphTransport: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentNodeID: UUID?

    private var playbackTask: Task<Void, Never>?

    func toggle(
        nodes: [SoundNode],
        connections: [SoundConnection],
        bpm: Double,
        onTrigger: @escaping (SoundNode) -> Void
    ) {
        isPlaying ? stop() : start(nodes: nodes, connections: connections, bpm: bpm, onTrigger: onTrigger)
    }

    func start(
        nodes: [SoundNode],
        connections: [SoundConnection],
        bpm: Double,
        onTrigger: @escaping (SoundNode) -> Void
    ) {
        guard !isPlaying else { return }
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var queue = connections
            .filter { $0.sourceNodeID == nil }
            .map { ($0.destinationNodeID, $0.durationBeats) }

        guard !queue.isEmpty else { return }
        isPlaying = true
        playbackTask = Task { @MainActor [weak self] in
            var visited = Set<UUID>()

            while let self, self.isPlaying, !Task.isCancelled, !queue.isEmpty {
                let (nodeID, durationBeats) = queue.removeFirst()
                guard !visited.contains(nodeID), let node = nodesByID[nodeID] else { continue }
                visited.insert(nodeID)
                currentNodeID = node.isActive ? nodeID : nil
                if node.isActive { onTrigger(node) }
                let seconds = max(0.06, durationBeats * 60 / max(bpm, 1))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

                queue.append(contentsOf: connections
                    .filter { $0.sourceNodeID == nodeID }
                    .map { ($0.destinationNodeID, $0.durationBeats) })
            }

            self?.isPlaying = false
            self?.currentNodeID = nil
        }
    }

    func stop() {
        isPlaying = false
        currentNodeID = nil
        playbackTask?.cancel()
        playbackTask = nil
    }

    deinit {
        playbackTask?.cancel()
    }
}
