import simd
import XCTest
@testable import SoundVision

/// Cubre de dónde nace cada organismo nuevo.
///
/// PLAY es una entrada única. El resto del grafo solo cambia cuando la persona
/// conecta organismos explícitamente.
@MainActor
final class ConnectionGraphTests: XCTestCase {
    func testFirstSoundHangsFromPlayBecauseThereIsNothingElse() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)

        XCTAssertEqual(state.connections.count, 1)
        XCTAssertNil(state.connections.first?.sourceNodeID)
        XCTAssertEqual(state.connections.first?.destinationNodeID, kick)
        XCTAssertEqual(state.playEntryNodeID, kick)
    }

    func testNewSoundsStayUnconnectedUntilTheUserDecides() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        let bass = state.createNode(of: .bass)
        let pad = state.createNode(of: .pad)

        XCTAssertEqual(state.connections.count, 1)
        XCTAssertEqual(state.playEntryNodeID, kick)
        XCTAssertEqual(state.unreachableNodeIDs(), [bass, pad])
    }

    func testUserConnectionsBuildTheChain() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        let bass = state.createNode(of: .bass)
        let hat = state.createNode(of: .hiHat)

        XCTAssertTrue(state.connect(sourceID: kick, destinationID: bass))
        XCTAssertTrue(state.connect(sourceID: bass, destinationID: hat))
        XCTAssertTrue(state.unreachableNodeIDs().isEmpty)
    }

    func testPlayRejectsASecondOutgoingConnection() {
        let state = CompositionState()
        state.createNode(of: .kick)
        let clap = state.createNode(of: .clap)

        XCTAssertFalse(state.connect(sourceID: nil, destinationID: clap))
        XCTAssertEqual(state.connections.filter { $0.sourceNodeID == nil }.count, 1)
    }

    func testAdditionalNodesNeverCreateAnotherPlayExit() {
        let state = CompositionState()
        state.createNode(of: .kick)

        let additional = state.createNextNode(at: [0.8, 1.3, 0.4])
        XCTAssertFalse(state.connections.contains { $0.sourceNodeID == nil && $0.destinationNodeID == additional })
        XCTAssertEqual(state.connections.filter { $0.sourceNodeID == nil }.count, 1)
    }

    func testSelectingANodeDoesNotCreateConnections() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        state.createNode(of: .bass)

        state.selectNode(id: kick)
        state.createNode(of: .lead)
        XCTAssertEqual(state.connections.count, 1)
    }

    func testDeletingThePlayEntryLetsTheNextNodeBecomeTheEntry() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        state.selectedNodeID = kick
        state.deleteSelectedNode()

        XCTAssertNil(state.playEntryNodeID)
        let bass = state.createNode(of: .bass)
        XCTAssertTrue(state.connections.contains { $0.sourceNodeID == nil && $0.destinationNodeID == bass })
    }

    // MARK: - Alcance desde Play

    /// Cortar la conexión que sostiene una rama la deja muda. El silencio no
    /// explica por qué, así que el estado tiene que poder señalarlo.
    func testNodesCutOffFromPlayAreReported() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        let bass = state.createNode(of: .bass)
        state.connect(sourceID: kick, destinationID: bass)
        XCTAssertTrue(state.unreachableNodeIDs().isEmpty)

        guard let root = state.connections.first(where: { $0.sourceNodeID == nil })?.id else {
            return XCTFail("Sin conexión raíz")
        }
        state.removeConnection(id: root)

        XCTAssertEqual(state.unreachableNodeIDs(), [kick, bass], "Toda la rama queda incomunicada")

        state.connectToPlay(id: kick)
        XCTAssertTrue(state.unreachableNodeIDs().isEmpty, "Reconectar la raíz rescata la rama entera")
    }

    /// Un ciclo cerrado que no toca Play tampoco suena, y el recorrido no debe
    /// quedarse dando vueltas dentro de él.
    func testCyclesAwayFromPlayAreStillUnreachable() {
        let state = CompositionState()
        let first = state.createNode(of: .kick)
        let second = state.createNode(of: .bass)
        state.connect(sourceID: first, destinationID: second)
        state.connect(sourceID: second, destinationID: first)

        guard let root = state.connections.first(where: { $0.sourceNodeID == nil })?.id else {
            return XCTFail("Sin conexión raíz")
        }
        state.removeConnection(id: root)

        XCTAssertEqual(state.unreachableNodeIDs(), [first, second])
    }

    // MARK: - Datos de entrada hostiles

    /// Un archivo guardado puede venir de otra versión o editado a mano. Nada de
    /// eso debe poder tumbar la app.
    func testSanitizingDropsDuplicatesAndDanglingConnections() {
        let kick = SoundNode(name: "Kick", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0)
        let ghost = UUID()
        let composition = Composition(
            title: "Roto",
            bpm: .nan,
            steps: 16,
            nodes: [kick, kick],
            connections: [
                SoundConnection(sourceNodeID: nil, destinationNodeID: kick.id),
                SoundConnection(sourceNodeID: ghost, destinationNodeID: kick.id),
                SoundConnection(sourceNodeID: nil, destinationNodeID: ghost)
            ]
        ).sanitized()

        XCTAssertEqual(composition.nodes.count, 1, "Los identificadores repetidos hacían caer un Dictionary")
        XCTAssertEqual(composition.connections.count, 1)
        XCTAssertEqual(composition.bpm, 120)
    }

    func testSanitizingKeepsOnlyOnePlayEntry() {
        let kick = SoundNode(name: "Kick", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0)
        let bass = SoundNode(name: "Bass", type: .bass, positionX: 0.8, positionY: 1.25, positionZ: 0)
        let clean = Composition(
            title: "Abanico antiguo",
            bpm: 120,
            steps: 16,
            nodes: [kick, bass],
            connections: [
                SoundConnection(sourceNodeID: nil, destinationNodeID: kick.id),
                SoundConnection(sourceNodeID: nil, destinationNodeID: bass.id)
            ]
        ).sanitized()

        XCTAssertEqual(clean.connections.filter { $0.sourceNodeID == nil }.count, 1)
        XCTAssertEqual(clean.connections.first?.destinationNodeID, kick.id)
    }

    func testSanitizingGraphWithoutEntryRescuesOnlyTheFirstNode() {
        let kick = SoundNode(name: "Kick", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0)
        let bass = SoundNode(name: "Bass", type: .bass, positionX: 0.8, positionY: 1.25, positionZ: 0)
        let clean = Composition(
            title: "Sin entrada",
            bpm: 120,
            steps: 16,
            nodes: [kick, bass],
            connections: []
        ).sanitized()

        XCTAssertEqual(clean.connections.count, 1)
        XCTAssertNil(clean.connections[0].sourceNodeID)
        XCTAssertEqual(clean.connections[0].destinationNodeID, kick.id)
    }

    func testTransportDefensivelyIgnoresAdditionalPlayEntries() {
        let kick = SoundNode(name: "Kick", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0)
        let bass = SoundNode(name: "Bass", type: .bass, positionX: 0.8, positionY: 1.25, positionZ: 0)
        let schedule = GraphTransport.makeSchedule(
            nodes: [kick, bass],
            connections: [
                SoundConnection(sourceNodeID: nil, destinationNodeID: kick.id),
                SoundConnection(sourceNodeID: nil, destinationNodeID: bass.id)
            ],
            loopPasses: 1
        )

        XCTAssertEqual(schedule, [GraphPlaybackEvent(nodeID: kick.id, beat: 0)])
    }

    /// Un NaN en una posición acaba dentro de una transformada de RealityKit y,
    /// antes de eso, dentro de un `Int(...)` que aborta el proceso.
    func testNonFiniteValuesNeverReachTheComposition() {
        let broken = SoundNode(
            name: "Roto",
            type: .pad,
            volume: .nan,
            pitch: .infinity,
            positionX: .nan,
            positionY: .infinity,
            positionZ: -.infinity
        ).sanitized()

        XCTAssertTrue(broken.positionX.isFinite)
        XCTAssertTrue(broken.positionY.isFinite)
        XCTAssertTrue(broken.positionZ.isFinite)
        XCTAssertTrue(broken.pitch.isFinite)
        XCTAssertTrue(broken.volume.isFinite)
    }

    func testMovingANodeToANonFinitePositionIsClamped() {
        let state = CompositionState()
        let id = state.createNode(of: .lead, at: [0, 1.25, 0])
        state.moveNode(id: id, to: [.nan, .infinity, 0.3])

        guard let node = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertTrue(node.positionX.isFinite)
        XCTAssertTrue(node.positionY.isFinite)
        XCTAssertTrue(node.pitch.isFinite)
        XCTAssertTrue(node.volume.isFinite)
    }

    func testNonFiniteRotationCannotPoisonVisualOrAudioParameters() {
        let state = CompositionState()
        let id = state.createNode(of: .fx)
        state.rotateNode(id: id, addingTo: .zero, delta: [.nan, .infinity, -.infinity])

        guard let node = state.node(id: id) else { return XCTFail("Nodo perdido") }
        XCTAssertTrue(node.rotationX.isFinite)
        XCTAssertTrue(node.rotationY.isFinite)
        XCTAssertTrue(node.rotationZ.isFinite)
        XCTAssertTrue(node.reverb.isFinite)
        XCTAssertTrue(node.delay.isFinite)
        XCTAssertTrue(node.distortion.isFinite)
    }

    /// Un organismo justo encima del núcleo produce un vector nulo, y de ahí
    /// sale un cuaternión con NaN que RealityKit no sobrevive.
    func testDegenerateSegmentsGetANeutralOrientation() {
        let point = SIMD3<Float>(0, 1.25, 0)
        let orientation = SpatialSceneLayout.segmentOrientation(from: point, to: point)

        XCTAssertTrue(orientation.vector.x.isFinite)
        XCTAssertTrue(orientation.vector.y.isFinite)
        XCTAssertTrue(orientation.vector.z.isFinite)
        XCTAssertTrue(orientation.vector.w.isFinite)
        XCTAssertGreaterThan(SpatialSceneLayout.segmentLength(from: point, to: point), 0)
    }
}
