import Foundation

struct CompositionStorage {
    enum StorageError: LocalizedError {
        case noSavedComposition

        var errorDescription: String? {
            "Todavía no existe una composición guardada."
        }
    }

    private let fileManager: FileManager
    private let customURL: URL?

    init(fileManager: FileManager = .default, customURL: URL? = nil) {
        self.fileManager = fileManager
        self.customURL = customURL
    }

    func save(_ composition: Composition) throws {
        let destination = try fileURL()
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(composition).write(to: destination, options: .atomic)
    }

    func load() throws -> Composition {
        let source = try fileURL()
        guard fileManager.fileExists(atPath: source.path) else {
            throw StorageError.noSavedComposition
        }
        return try JSONDecoder().decode(Composition.self, from: Data(contentsOf: source))
    }

    private func fileURL() throws -> URL {
        if let customURL { return customURL }
        let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return directory.appending(path: "SoundVision", directoryHint: .isDirectory)
            .appending(path: "composition.json", directoryHint: .notDirectory)
    }
}
