import Foundation

@MainActor
final class Sequencer: ObservableObject {
    nonisolated static let totalSteps = 16

    @Published var bpm: Double = 120
    @Published private(set) var currentStep = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var lastTickTime = Date.timeIntervalSinceReferenceDate

    var onStep: ((Int) -> Void)?
    private var clockTask: Task<Void, Never>?

    var secondsPerStep: Double {
        (60.0 / max(bpm, 1)) / 4.0
    }

    func togglePlayback() {
        isPlaying ? stop() : start()
    }

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        tick()

        clockTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isPlaying {
                let nanoseconds = UInt64(self.secondsPerStep * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled, self.isPlaying else { break }
                self.currentStep = (self.currentStep + 1) % Self.totalSteps
                self.tick()
            }
        }
    }

    func stop() {
        isPlaying = false
        clockTask?.cancel()
        clockTask = nil
    }

    func reset() {
        stop()
        currentStep = 0
    }

    private func tick() {
        lastTickTime = Date.timeIntervalSinceReferenceDate
        onStep?(currentStep)
    }

    deinit {
        clockTask?.cancel()
    }
}
