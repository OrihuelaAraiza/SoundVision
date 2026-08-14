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
        let nodes = SoundNode.starterPattern()
        let connection = SoundConnection(sourceNodeID: nil, destinationNodeID: nodes[0].id, durationBeats: 1.5)
        let composition = Composition(title: "Test", bpm: 108, steps: 16, nodes: nodes, connections: [connection])
        try storage.save(composition)
        XCTAssertEqual(try storage.load(), composition)
    }

    func testSpatialMappingUsesEveryAxis() {
        XCTAssertGreaterThan(SpatialParameterMapper.pitch(forHeight: 1.8), 0)
        XCTAssertLessThan(SpatialParameterMapper.pitch(forHeight: 0.7), 0)
        XCTAssertGreaterThan(SpatialParameterMapper.volume(forDepth: 0.8), SpatialParameterMapper.volume(forDepth: -0.8))

        let near = SpatialParameterMapper.durationBeats(from: [0, 1.25, 0], to: [0.25, 2, 0])
        let far = SpatialParameterMapper.durationBeats(from: [0, 1.25, 0], to: [1.5, 0.4, 0])
        XCTAssertGreaterThan(far, near)
    }

    func testRotationMapsToIndependentEffects() {
        let effects = SpatialParameterMapper.effects(from: [.pi / 2, .pi / 4, .pi])
        XCTAssertEqual(effects.reverb, 0.5, accuracy: 0.001)
        XCTAssertEqual(effects.delay, 0.25, accuracy: 0.001)
        XCTAssertEqual(effects.distortion, 1, accuracy: 0.001)
    }

    @MainActor
    func testSequencerStepDurationAt120BPM() {
        let sequencer = Sequencer()
        sequencer.bpm = 120
        XCTAssertEqual(sequencer.secondsPerStep, 0.125, accuracy: 0.000_001)
    }
}
