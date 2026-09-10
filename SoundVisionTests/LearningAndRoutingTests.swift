import XCTest
@testable import SoundVision

final class LearningAndRoutingTests: XCTestCase {
    func testConvergenceMergesSimultaneousArrivalsAndRetriggersLater() {
        var composition = MusicLesson.branches.composition()
        let bell = composition.nodes[3]
        func beats() -> [Double] {
            GraphSchedule.makePlan(nodes: composition.nodes, connections: composition.connections, loopPasses: 1)
                .events.filter { $0.nodeID == bell.id }.map(\.beat)
        }
        XCTAssertEqual(beats(), [2])
        composition.connections[4].durationBeats = 2
        XCTAssertEqual(beats(), [2, 3])
    }

    func testDenseConvergenceDoesNotConsumeUniqueEventBudget() {
        func node() -> SoundNode { SoundNode(name: "N", type: .bell, positionX: 0, positionY: 1.25, positionZ: 0) }
        let root = node()
        var nodes = [root]
        var edges = [SoundConnection(sourceNodeID: nil, destinationNodeID: root.id)]
        var previous = root
        for _ in 0..<9 {
            let a = node(), b = node(), end = node()
            nodes += [a, b, end]
            edges += [(previous, a), (previous, b), (a, end), (b, end)].map {
                SoundConnection(sourceNodeID: $0.0.id, destinationNodeID: $0.1.id)
            }
            previous = end
        }
        let plan = GraphSchedule.makePlan(nodes: nodes, connections: edges, loopPasses: 1, maximumEvents: nodes.count)
        XCTAssertFalse(plan.isTruncated)
        XCTAssertEqual(plan.events.count, nodes.count)
        XCTAssertEqual(plan.events.last?.nodeID, previous.id)
        XCTAssertEqual(plan.events.last?.beat, 18)
    }

    func testEventOverflowIsExplicitAndStable() {
        let composition = MusicLesson.branches.composition()
        let plan = GraphSchedule.makePlan(nodes: composition.nodes, connections: composition.connections,
                                          loopPasses: 1, maximumEvents: 2)
        XCTAssertTrue(plan.isTruncated)
        XCTAssertEqual(plan.events.count, 2)
        let forward = GraphSchedule.makePlan(nodes: composition.nodes, connections: composition.connections, loopPasses: 1)
        let reverse = GraphSchedule.makePlan(nodes: composition.nodes, connections: composition.connections.reversed(), loopPasses: 1)
        XCTAssertEqual(forward.events, reverse.events)
    }

    func testLessonsRequireTheCorrectMusicalResult() {
        for lesson in MusicLesson.allCases {
            var composition = lesson.composition()
            XCTAssertFalse(lesson.isComplete(composition), "El ejercicio no debe nacer resuelto")
            switch lesson {
            case .pulse, .harmony:
                for index in composition.connections.indices where composition.connections[index].sourceNodeID != nil {
                    composition.connections[index].durationBeats = 1
                }
            case .melody:
                composition.nodes[1].pitch = 3
                composition.nodes[2].pitch = 7
            case .branches:
                composition.connections[4].durationBeats = 2
            }
            XCTAssertTrue(lesson.isComplete(composition))
            composition.nodes[composition.nodes.count - 1].isActive = false
            XCTAssertFalse(lesson.isComplete(composition), "Un destino muteado no completa la práctica")
        }
    }

    func testLegacyConnectionsKeepSpatialTimingAndDefaultLoopCount() throws {
        let original = MusicLesson.branches.composition()
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "loopPasses")
        var edges = try XCTUnwrap(json["connections"] as? [[String: Any]])
        for index in edges.indices { edges[index].removeValue(forKey: "usesSpatialTiming") }
        json["connections"] = edges
        let decoded = try JSONDecoder().decode(Composition.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.loopPasses, 2)
        XCTAssertTrue(decoded.connections.allSatisfy(\.usesSpatialTiming))
    }

    @MainActor
    func testLearningRestoresCompositionTempoCyclesSelectionAndUndo() {
        let state = CompositionState()
        let id = state.createNode(of: .pluck)
        state.sequencer.bpm = 135
        state.graphTransport.loopPasses = 4
        let before = state.snapshot
        let label = state.undoLabel
        state.beginLesson(.melody)
        state.beginLesson(.harmony)
        state.finishLesson()
        XCTAssertEqual(state.snapshot, before)
        XCTAssertEqual(state.selectedNodeID, id)
        XCTAssertEqual(state.undoLabel, label)
        XCTAssertNil(state.activeLesson)
        state.undo()
        XCTAssertTrue(state.nodes.isEmpty)
    }

    @MainActor
    func testFixedConnectionSurvivesMovementSaveLoadAndUndo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let state = CompositionState(storage: CompositionStorage(customURL: url))
        let a = state.createNode(of: .tom)
        let b = state.createNode(of: .bell)
        state.connect(sourceID: a, destinationID: b)
        let edge = try XCTUnwrap(state.connections.last)
        state.setConnectionBeats(id: edge.id, beats: 0.5)
        state.moveNode(id: b, to: [2, 2, -1])
        XCTAssertEqual(state.connections.last?.durationBeats, 0.5)
        state.graphTransport.loopPasses = 5
        state.save()
        state.load()
        XCTAssertEqual(state.connections.last?.durationBeats, 0.5)
        XCTAssertEqual(state.connections.last?.usesSpatialTiming, false)
        XCTAssertEqual(state.graphTransport.loopPasses, 5)
        state.setConnectionBeats(id: edge.id, beats: 2)
        state.undo()
        XCTAssertEqual(state.connections.last?.durationBeats, 0.5)
    }

    @MainActor
    func testStructuralEditsStopButTimingEditsPreservePlayback() throws {
        let state = CompositionState()
        let a = state.createNode(of: .kick)
        let b = state.createNode(of: .bell)
        state.togglePlayback()
        XCTAssertTrue(state.graphTransport.isPlaying)
        state.connect(sourceID: a, destinationID: b)
        XCTAssertFalse(state.graphTransport.isPlaying)
        XCTAssertNil(state.spatialAudioSession)
        state.togglePlayback()
        let edge = try XCTUnwrap(state.connections.last)
        let session = state.spatialAudioSession?.id
        state.setConnectionBeats(id: edge.id, beats: 2)
        XCTAssertTrue(state.graphTransport.isPlaying)
        XCTAssertEqual(state.spatialAudioSession?.id, session)
        XCTAssertTrue(state.hasPendingTimingChanges)
        state.stopPlayback()
    }

    func testNoteReadoutUsesTheInstrumentRegister() {
        let bass = SoundNode(name: "Bass", type: .bass, positionX: 0, positionY: 1.25, positionZ: 0)
        let organ = SoundNode(name: "Órgano", type: .organ, pitch: 3, positionX: 0, positionY: 1.25, positionZ: 0)
        XCTAssertEqual(SpatialParameterMapper.noteName(for: bass), "La1")
        var lowBass = bass
        lowBass.pitch = -24
        XCTAssertEqual(SpatialParameterMapper.noteName(for: lowBass), "La-1")
        XCTAssertEqual(SpatialParameterMapper.noteName(for: organ), "Do4")
    }
}
