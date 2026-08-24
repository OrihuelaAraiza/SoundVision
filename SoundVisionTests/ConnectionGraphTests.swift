import simd
import XCTest
@testable import SoundVision

/// Cubre de dónde nace cada organismo nuevo.
///
/// Hasta ahora todo lo que se añadía colgaba del núcleo Play sin excepción, de
/// modo que la composición solo podía crecer en abanico: ocho organismos
/// disparando a la vez desde el mismo instante. Encadenar es lo que convierte el
/// grafo en una frase.
@MainActor
final class ConnectionGraphTests: XCTestCase {
    func testFirstSoundHangsFromPlayBecauseThereIsNothingElse() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)

        XCTAssertEqual(state.connections.count, 1)
        XCTAssertNil(state.connections.first?.sourceNodeID)
        XCTAssertEqual(state.connections.first?.destinationNodeID, kick)
        XCTAssertEqual(state.connectionOriginID, kick, "El recién nacido pasa a ser el origen")
    }

    func testEachNewSoundChainsFromThePreviousOne() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        let bass = state.createNode(of: .bass)
        let pad = state.createNode(of: .pad)

        XCTAssertEqual(state.connections.count, 3)
        XCTAssertEqual(state.connections[1].sourceNodeID, kick)
        XCTAssertEqual(state.connections[1].destinationNodeID, bass)
        XCTAssertEqual(state.connections[2].sourceNodeID, bass)
        XCTAssertEqual(state.connections[2].destinationNodeID, pad)
        XCTAssertTrue(state.unreachableNodeIDs().isEmpty, "La cadena entera cuelga de Play")
    }

    func testChosenOriginDecidesWhereTheNextSoundHangs() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        let bass = state.createNode(of: .bass)

        state.setConnectionOrigin(kick)
        let hat = state.createNode(of: .hiHat)

        XCTAssertEqual(state.connections.last?.sourceNodeID, kick)
        XCTAssertEqual(state.connections.last?.destinationNodeID, hat)
        XCTAssertNotEqual(state.connections.last?.sourceNodeID, bass)
    }

    func testPlayCanBeChosenAgainAsTheOrigin() {
        let state = CompositionState()
        state.createNode(of: .kick)
        state.setConnectionOrigin(nil)
        let clap = state.createNode(of: .clap)

        XCTAssertTrue(state.connections.contains { $0.sourceNodeID == nil && $0.destinationNodeID == clap })
    }

    /// Tirar del núcleo dice por sí mismo de dónde nace, sin importar lo que
    /// esté elegido en la consola.
    func testPullingFromTheCoreAlwaysHangsFromPlay() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        XCTAssertEqual(state.connectionOriginID, kick)

        let pulled = state.createNextNode(at: [0.8, 1.3, 0.4], from: .play)
        XCTAssertTrue(state.connections.contains { $0.sourceNodeID == nil && $0.destinationNodeID == pulled })
    }

    /// Seleccionar un organismo es también decir "lo siguiente nace de aquí".
    func testSelectingANodeMakesItTheOrigin() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        state.createNode(of: .bass)

        state.selectNode(id: kick)
        XCTAssertEqual(state.connectionOriginID, kick)

        let lead = state.createNode(of: .lead)
        XCTAssertEqual(state.connections.last?.sourceNodeID, kick)
        XCTAssertEqual(state.connections.last?.destinationNodeID, lead)
    }

    /// Un origen borrado no puede dejar huérfano al siguiente organismo.
    func testDeletingTheOriginFallsBackToPlay() {
        let state = CompositionState()
        let kick = state.createNode(of: .kick)
        state.selectedNodeID = kick
        state.deleteSelectedNode()

        XCTAssertNil(state.connectionOriginID)
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
