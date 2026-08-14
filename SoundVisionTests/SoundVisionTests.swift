import XCTest
@testable import SoundVision

final class SoundVisionTests: XCTestCase {
    func testStarterPatternHasEightNodesAcrossEvenSteps() {
        let nodes = SoundNode.starterPattern()
        XCTAssertEqual(nodes.count, 8)
        XCTAssertEqual(nodes.map(\.stepIndex), [0, 2, 4, 6, 8, 10, 12, 14])
        XCTAssertEqual(Set(nodes.map(\.type)), Set(SoundNodeType.allCases))
    }

    func testCompositionRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: "composition.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        let storage = CompositionStorage(customURL: url)
        let composition = Composition(title: "Test", bpm: 108, steps: 16, nodes: SoundNode.starterPattern())
        try storage.save(composition)
        XCTAssertEqual(try storage.load(), composition)
    }

    @MainActor
    func testSequencerStepDurationAt120BPM() {
        let sequencer = Sequencer()
        sequencer.bpm = 120
        XCTAssertEqual(sequencer.secondsPerStep, 0.125, accuracy: 0.000_001)
    }
}
