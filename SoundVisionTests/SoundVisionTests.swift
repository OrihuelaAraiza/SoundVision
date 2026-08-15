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

    func testGraphScheduleStartsBranchesAtTheSameBeat() {
        let source = SoundNode(name: "Source", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0)
        let branchA = SoundNode(name: "A", type: .bass, positionX: 1, positionY: 1.25, positionZ: 0)
        let branchB = SoundNode(name: "B", type: .pad, positionX: -1, positionY: 1.25, positionZ: 0)
        let connections = [
            SoundConnection(sourceNodeID: nil, destinationNodeID: source.id),
            SoundConnection(sourceNodeID: source.id, destinationNodeID: branchA.id, durationBeats: 1.5),
            SoundConnection(sourceNodeID: source.id, destinationNodeID: branchB.id, durationBeats: 1.5)
        ]

        let schedule = GraphTransport.makeSchedule(
            nodes: [source, branchA, branchB],
            connections: connections,
            loopPasses: 1
        )

        XCTAssertEqual(schedule.first, GraphPlaybackEvent(nodeID: source.id, beat: 0))
        XCTAssertEqual(Set(schedule.dropFirst().map(\.beat)), [1.5])
        XCTAssertEqual(Set(schedule.dropFirst().map(\.nodeID)), [branchA.id, branchB.id])
    }

    func testGraphScheduleBoundsIntentionalCycle() {
        let nodeA = SoundNode(name: "A", type: .lead, positionX: 0, positionY: 1.25, positionZ: 0)
        let nodeB = SoundNode(name: "B", type: .fx, positionX: 1, positionY: 1.25, positionZ: 0)
        let connections = [
            SoundConnection(sourceNodeID: nil, destinationNodeID: nodeA.id),
            SoundConnection(sourceNodeID: nodeA.id, destinationNodeID: nodeB.id, durationBeats: 1),
            SoundConnection(sourceNodeID: nodeB.id, destinationNodeID: nodeA.id, durationBeats: 1)
        ]

        let schedule = GraphTransport.makeSchedule(
            nodes: [nodeA, nodeB],
            connections: connections,
            loopPasses: 2
        )

        XCTAssertEqual(schedule.map(\.beat), [0, 1, 2, 3, 4])
        XCTAssertEqual(schedule.map(\.nodeID), [nodeA.id, nodeB.id, nodeA.id, nodeB.id, nodeA.id])
    }

    @MainActor
    func testSpatialDeviceSceneIsReadyToPlay() {
        let state = CompositionState()
        state.loadSpatialTestScene()

        XCTAssertEqual(state.nodes.count, 5)
        XCTAssertEqual(state.connections.count, 7)
        XCTAssertTrue(state.isSpatialTestScene)
        XCTAssertNotNil(state.selectedNode)
        XCTAssertTrue(state.nodes.contains { $0.positionZ > 1.8 }, "La demo debe incluir una fuente detrás del usuario")

        let timeline = GraphTransport.makeSchedule(
            nodes: state.nodes,
            connections: state.connections,
            loopPasses: state.graphTransport.loopPasses
        )
        XCTAssertEqual(timeline.filter { $0.beat == 0 }.count, 2)
        XCTAssertLessThan(timeline.count, 20)
    }

    @MainActor
    func testNewCompositionLeavesDemoAndSpecificInstrumentCanBeAdded() {
        let state = CompositionState()
        state.loadSpatialTestScene()

        state.startNewComposition()
        let id = state.createNode(of: .bass, at: [0.4, 1.4, 0])

        XCTAssertFalse(state.isSpatialTestScene)
        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes.first?.id, id)
        XCTAssertEqual(state.nodes.first?.type, .bass)
        XCTAssertEqual(state.connections.first?.sourceNodeID, nil)
    }

    func testSpatialSceneStaysAtHumanHeightAndMapsDrawerDrop() {
        XCTAssertEqual(SpatialSceneLayout.rootPosition.y, 0, accuracy: 0.001)

        let center = SpatialSceneLayout.dropPosition(
            at: CGPoint(x: 500, y: 400),
            in: CGSize(width: 1_000, height: 800)
        )
        let upperRight = SpatialSceneLayout.dropPosition(
            at: CGPoint(x: 900, y: 100),
            in: CGSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(center.y, 1.325, accuracy: 0.001)
        XCTAssertGreaterThan(upperRight.x, center.x)
        XCTAssertGreaterThan(upperRight.y, center.y)
    }

    @MainActor
    func testSequencerStepDurationAt120BPM() {
        let sequencer = Sequencer()
        sequencer.bpm = 120
        XCTAssertEqual(sequencer.secondsPerStep, 0.125, accuracy: 0.000_001)
    }
}
