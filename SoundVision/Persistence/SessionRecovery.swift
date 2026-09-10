import Foundation

struct SessionRecovery: Codable {
    let version: Int
    let current: CompositionEditSnapshot
    let history: CompositionHistory
    let lesson: MusicLesson?
    let original: CompositionEditSnapshot?
    let originalHistory: CompositionHistory?
    let savedAt: Date

    func validated() throws -> Self {
        guard version == 1, (lesson == nil) == (original == nil),
              (original == nil) == (originalHistory == nil) else { throw RecoveryError.invalid }
        let histories = [history, originalHistory].compactMap { $0 }
        let snapshots = [current, original].compactMap { $0 }
            + histories.flatMap { ($0.undo + $0.redo + [$0.transaction].compactMap { $0 }).map(\.snapshot) }
        guard histories.allSatisfy({ $0.undo.count + $0.redo.count <= CompositionHistory.capacity }) else {
            throw RecoveryError.invalid
        }
        for snapshot in snapshots {
            let composition = Composition(title: "Recuperación", bpm: snapshot.bpm, steps: 16,
                nodes: snapshot.nodes, connections: snapshot.connections, loopPasses: snapshot.loopPasses)
            guard snapshot.nodes.count <= SoundNode.maximumCount,
                  composition == composition.sanitized(repairMissingPlayEntry: false) else { throw RecoveryError.invalid }
        }
        return self
    }

    enum RecoveryError: Error { case invalid }
}

struct RecoveryStorage {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("previous") }

    func load() -> SessionRecovery? {
        for candidate in [url, backupURL] {
            if let data = try? Data(contentsOf: candidate),
               let session = try? JSONDecoder().decode(SessionRecovery.self, from: data).validated() {
                return session
            }
        }
        return nil
    }

    func save(_ session: SessionRecovery) throws {
        let data = try JSONEncoder().encode(session.validated())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only a known-good current file may replace the known-good backup.
        if let previous = try? Data(contentsOf: url),
           (try? JSONDecoder().decode(SessionRecovery.self, from: previous).validated()) != nil {
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

/// Debounces disk work independently of gestures and audio publication.
@MainActor
final class RecoveryCoordinator {
    let storage: RecoveryStorage
    private var pending: Task<Void, Never>?

    init(storage: RecoveryStorage) { self.storage = storage }

    func schedule(_ save: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func flush(_ session: SessionRecovery) throws {
        pending?.cancel()
        pending = nil
        try storage.save(session)
    }

    deinit { pending?.cancel() }
}
