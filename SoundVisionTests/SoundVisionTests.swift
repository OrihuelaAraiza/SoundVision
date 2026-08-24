import simd
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
        let initialRevision = state.sceneContentRevision
        state.loadSpatialTestScene()
        XCTAssertEqual(state.sceneContentRevision, initialRevision + 1)

        state.startNewComposition()
        XCTAssertEqual(state.sceneContentRevision, initialRevision + 2)
        let id = state.createNode(of: .bass, at: [0.4, 1.4, 0])
        XCTAssertEqual(state.sceneContentRevision, initialRevision + 3)

        XCTAssertFalse(state.isSpatialTestScene)
        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes.first?.id, id)
        XCTAssertEqual(state.nodes.first?.type, .bass)
        XCTAssertEqual(state.connections.first?.sourceNodeID, nil)
    }

    func testSpatialSceneStaysAtHumanHeight() {
        XCTAssertEqual(SpatialSceneLayout.rootPosition.y, 0, accuracy: 0.001)
    }

    /// Girar, soltar y volver a girar debe continuar desde donde quedó el nodo.
    @MainActor
    func testRotationAccumulatesAcrossGestures() {
        let state = CompositionState()
        let id = state.createNode(of: .pad, at: [0, 1.25, 0])

        state.rotateNode(id: id, addingTo: .zero, delta: [.pi / 2, 0, 0])
        guard let afterFirst = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertEqual(afterFirst.rotationX, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(afterFirst.reverb, 0.5, accuracy: 0.001)

        let origin = SIMD3<Float>(afterFirst.rotationX, afterFirst.rotationY, afterFirst.rotationZ)
        state.rotateNode(id: id, addingTo: origin, delta: [.pi / 4, 0, 0])
        guard let afterSecond = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertEqual(afterSecond.rotationX, .pi * 0.75, accuracy: 0.001)
        XCTAssertEqual(afterSecond.reverb, 0.75, accuracy: 0.001)
    }

    /// Mover un nodo debe reescribir pitch y volumen desde su nueva posición.
    @MainActor
    func testMovingNodeRemapsPitchAndVolume() {
        let state = CompositionState()
        let id = state.createNode(of: .lead, at: [0, 1.25, 0])

        state.moveNode(id: id, to: [0.5, 1.9, 0.8])
        guard let moved = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertEqual(moved.positionY, 1.9, accuracy: 0.001)
        XCTAssertEqual(moved.pitch, SpatialParameterMapper.pitch(forHeight: 1.9), accuracy: 0.001)
        XCTAssertEqual(moved.volume, SpatialParameterMapper.volume(forDepth: 0.8), accuracy: 0.001)
    }

    /// Añadir un nodo crea también su conexión con Play, pero eso fue **una**
    /// acción del usuario y debe deshacerse de una sola vez.
    @MainActor
    func testUndoRemovesNodeAndItsAutomaticConnectionTogether() {
        let state = CompositionState()
        XCTAssertFalse(state.canUndo)

        state.createNode(of: .kick)
        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.connections.count, 1)
        XCTAssertTrue(state.canUndo)

        state.undo()
        XCTAssertEqual(state.nodes.count, 0)
        XCTAssertEqual(state.connections.count, 0)
        XCTAssertFalse(state.canUndo)
    }

    @MainActor
    func testCuttingAConnectionIsUndoable() {
        let state = CompositionState()
        let source = state.createNode(of: .kick)
        // Desde Play a propósito: así la conexión que se corta es la que crea
        // esta prueba y no la que el encadenado automático ya habría puesto.
        let destination = state.createNode(of: .bass, from: .play)
        XCTAssertTrue(state.connect(sourceID: source, destinationID: destination))

        let connectionCount = state.connections.count
        guard let cut = state.connections.last?.id else { return XCTFail("Sin conexión que cortar") }
        state.removeConnection(id: cut)
        XCTAssertEqual(state.connections.count, connectionCount - 1)

        state.undo()
        XCTAssertEqual(state.connections.count, connectionCount)
        XCTAssertTrue(state.connections.contains { $0.id == cut })
    }

    @MainActor
    func testUndoRestoresTheCanvasAfterLoadingTheDemo() {
        let state = CompositionState()
        state.createNode(of: .pad)
        let ownNodes = state.nodes

        state.loadSpatialTestScene()
        XCTAssertEqual(state.nodes.count, 5)
        XCTAssertTrue(state.isSpatialTestScene)

        state.undo()
        XCTAssertEqual(state.nodes, ownNodes)
        XCTAssertFalse(state.isSpatialTestScene)
    }

    /// La colocación automática solía derivarse de `nodes.count`, así que tras
    /// borrar un nodo los siguientes reaparecían encima de los supervivientes.
    @MainActor
    func testAutomaticPlacementKeepsNodesApartAfterDeletions() {
        let state = CompositionState()
        for _ in 0..<5 { state.createNode(of: .kick) }

        state.selectedNodeID = state.nodes[2].id
        state.deleteSelectedNode()
        state.createNode(of: .snare)
        state.createNode(of: .hiHat)

        let positions = state.nodes.map { SIMD3<Float>($0.positionX, $0.positionY, $0.positionZ) }
        for (index, position) in positions.enumerated() {
            for other in positions[(index + 1)...] {
                XCTAssertGreaterThan(
                    simd_distance(position, other), 0.2,
                    "Dos organismos quedaron prácticamente encima"
                )
            }
        }
    }

    /// Tocar el nodo ya seleccionado debe soltarlo.
    @MainActor
    func testTappingTheSelectedNodeAgainDeselectsIt() {
        let state = CompositionState()
        let id = state.createNode(of: .lead)

        state.selectNode(id: id)
        XCTAssertNil(state.selectedNodeID)
        state.selectNode(id: id)
        XCTAssertEqual(state.selectedNodeID, id)
    }

    @MainActor
    func testNearestNodeHonoursRadiusAndExclusion() {
        let state = CompositionState()
        let origin = state.createNode(of: .kick, at: [0, 1.25, 0])
        let near = state.createNode(of: .bass, at: [0.25, 1.25, 0])

        XCTAssertEqual(state.nearestNode(to: [0.3, 1.25, 0], excluding: origin, within: 0.42), near)
        XCTAssertNil(state.nearestNode(to: [2.2, 1.25, 0], excluding: origin, within: 0.42))
        XCTAssertNil(state.nearestNode(to: [0.02, 1.25, 0], excluding: origin, within: 0.1))
    }

    /// El punto del candado: ordenar el espacio sin tocar la composición.
    @MainActor
    func testLockedNodeCanBeMovedWithoutChangingItsSound() {
        let state = CompositionState()
        let id = state.createNode(of: .pad, at: [0, 1.25, 0])
        guard let before = state.node(id: id) else { return XCTFail("Nodo perdido") }

        state.toggleSoundLock(id: id)
        state.moveNode(id: id, to: [1.1, 2.2, -1.4])

        guard let after = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertTrue(after.isSoundLocked)
        XCTAssertEqual(after.positionY, 2.2, accuracy: 0.001, "Debe recolocarse igualmente")
        XCTAssertEqual(after.positionX, 1.1, accuracy: 0.001)
        XCTAssertEqual(after.pitch, before.pitch, accuracy: 0.001, "El pitch no debe moverse")
        XCTAssertEqual(after.volume, before.volume, accuracy: 0.001, "El volumen no debe moverse")
    }

    /// Un extremo fijo también congela el tiempo de su conexión: si no, mover
    /// un nodo "fijo" seguiría alterando el ritmo.
    @MainActor
    func testLockingAnEndpointFreezesItsConnectionDuration() {
        let state = CompositionState()
        let source = state.createNode(of: .kick, at: [0, 1.25, 0])
        let destination = state.createNode(of: .bass, at: [0.5, 1.25, 0])
        state.connect(sourceID: source, destinationID: destination)

        guard let durationBefore = state.connections.last?.durationBeats else {
            return XCTFail("Sin conexión")
        }
        state.toggleSoundLock(id: destination)
        state.moveNode(id: destination, to: [2.0, 1.25, 0])

        XCTAssertEqual(state.connections.last?.durationBeats, durationBefore)
    }

    /// Sin candado, el comportamiento original debe seguir intacto.
    @MainActor
    func testUnlockedNodeStillRetunesWhenMoved() {
        let state = CompositionState()
        let id = state.createNode(of: .lead, at: [0, 1.25, 0])

        state.moveNode(id: id, to: [0, 2.0, 0.6])
        guard let after = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertEqual(after.pitch, SpatialParameterMapper.pitch(forHeight: 2.0), accuracy: 0.001)
        XCTAssertEqual(after.volume, SpatialParameterMapper.volume(forDepth: 0.6), accuracy: 0.001)
    }

    @MainActor
    func testSequencerStepDurationAt120BPM() {
        let sequencer = Sequencer()
        sequencer.bpm = 120
        XCTAssertEqual(sequencer.secondsPerStep, 0.125, accuracy: 0.000_001)
    }
}
