import Foundation

struct CompositionEditSnapshot: Codable, Equatable {
    let nodes: [SoundNode]
    let connections: [SoundConnection]
    let selectedNodeID: UUID?
    let isSpatialTestScene: Bool
    let bpm: Double
    let loopPasses: Int

    func hasSameContent(as other: Self) -> Bool {
        nodes == other.nodes && connections == other.connections && bpm == other.bpm
            && loopPasses == other.loopPasses && isSpatialTestScene == other.isSpatialTestScene
    }
}

/// Value semantics let lessons reserve the entire history without sharing edits.
struct CompositionHistory: Codable {
    struct Entry: Codable {
        let label: String
        let snapshot: CompositionEditSnapshot
    }
    private(set) var undo: [Entry] = []
    private(set) var redo: [Entry] = []
    private(set) var transaction: Entry?
    static let capacity = 24

    mutating func begin(_ label: String, at snapshot: CompositionEditSnapshot) {
        guard transaction == nil else { return }
        transaction = Entry(label: label, snapshot: snapshot)
    }

    mutating func end(at snapshot: CompositionEditSnapshot) {
        guard let entry = transaction else { return }
        transaction = nil
        guard !entry.snapshot.hasSameContent(as: snapshot) else { return }
        record(entry.label, at: entry.snapshot)
    }

    mutating func record(_ label: String, at snapshot: CompositionEditSnapshot) {
        guard transaction == nil else { return }
        undo.append(Entry(label: label, snapshot: snapshot))
        if undo.count > Self.capacity { undo.removeFirst() }
        redo = []
    }

    mutating func takeUndo(at snapshot: CompositionEditSnapshot) -> Entry? {
        end(at: snapshot)
        guard let entry = undo.popLast() else { return nil }
        redo.append(Entry(label: entry.label, snapshot: snapshot))
        return entry
    }

    mutating func takeRedo(at snapshot: CompositionEditSnapshot) -> Entry? {
        end(at: snapshot)
        guard let entry = redo.popLast() else { return nil }
        undo.append(Entry(label: entry.label, snapshot: snapshot))
        return entry
    }
}
