import Foundation

struct GraphPlaybackEvent: Equatable, Sendable {
    let nodeID: UUID
    let beat: Double
}

struct GraphPlaybackPlan: Sendable {
    let events: [GraphPlaybackEvent]
    let isTruncated: Bool
}

/// Cada arista retrasa el ataque desde su origen, independientemente de las
/// otras salidas. Llegadas simultáneas se fusionan; llegadas distintas repiten
/// la nota. Los silencios siguen propagando el pulso. Cada camino conserva su
/// presupuesto de ciclos, por lo que una rama nunca consume el de otra.
enum GraphSchedule {
    private struct Visit {
        let nodeID: UUID
        let beat: Double
        let counts: [UUID: Int]
    }

    static func makePlan(
        nodes: [SoundNode], connections: [SoundConnection], loopPasses: Int,
        maximumEvents: Int = 512
    ) -> GraphPlaybackPlan {
        let validIDs = Set(nodes.map(\.id))
        let outgoing = Dictionary(grouping: connections.filter {
            $0.sourceNodeID.map(validIDs.contains) == true && validIDs.contains($0.destinationNodeID)
        }, by: { $0.sourceNodeID! })
        guard let root = connections.first(where: {
            $0.sourceNodeID == nil && validIDs.contains($0.destinationNodeID)
        }) else { return .init(events: [], isTruncated: false) }

        // Heap: ordenar toda la cola en cada visita bloqueaba el hilo principal
        // en grafos con muchas bifurcaciones. Inserción/extracción O(log n).
        var pending: [Visit] = []
        func precedes(_ a: Visit, _ b: Visit) -> Bool {
            a.beat == b.beat ? a.nodeID.uuidString < b.nodeID.uuidString : a.beat < b.beat
        }
        func push(_ visit: Visit) {
            pending.append(visit)
            var index = pending.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard precedes(pending[index], pending[parent]) else { break }
                pending.swapAt(index, parent)
                index = parent
            }
        }
        func pop() -> Visit {
            if pending.count == 1 { return pending.removeLast() }
            let first = pending[0]
            pending[0] = pending.removeLast()
            var index = 0
            while index * 2 + 1 < pending.count {
                let left = index * 2 + 1
                let right = left + 1
                let child = right < pending.count && precedes(pending[right], pending[left]) ? right : left
                guard precedes(pending[child], pending[index]) else { break }
                pending.swapAt(child, index)
                index = child
            }
            return first
        }
        struct AttackKey: Hashable { let nodeID: UUID; let microbeat: Int64 }
        var seen: Set<AttackKey> = []
        var events: [GraphPlaybackEvent] = []
        let limit = max(0, min(maximumEvents, 512))
        let passes = max(1, min(loopPasses, 8))
        let workLimit = 16_384
        var visits = 0
        push(Visit(nodeID: root.destinationNodeID, beat: 0, counts: [:]))
        while !pending.isEmpty {
            guard visits < workLimit else { return .init(events: events, isTruncated: true) }
            visits += 1
            let visit = pop()
            let key = AttackKey(nodeID: visit.nodeID, microbeat: Int64((visit.beat * 1_000_000).rounded()))
            if seen.insert(key).inserted {
                // El límite cuenta ataques únicos, nunca duplicados de una convergencia.
                guard events.count < limit else { return .init(events: events, isTruncated: true) }
                events.append(.init(nodeID: visit.nodeID, beat: visit.beat))
            }
            for edge in outgoing[visit.nodeID, default: []] {
                let count = visit.counts[edge.id, default: 0]
                guard count < passes else { continue }
                guard pending.count < workLimit else { return .init(events: events, isTruncated: true) }
                var counts = visit.counts
                counts[edge.id] = count + 1
                let beats = edge.durationBeats.isFinite ? max(0.0625, min(edge.durationBeats, 32)) : 1
                push(Visit(nodeID: edge.destinationNodeID, beat: visit.beat + beats, counts: counts))
            }
        }
        return .init(events: events, isTruncated: false)
    }
}
