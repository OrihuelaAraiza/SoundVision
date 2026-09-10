import RealityKit
import XCTest
@testable import SoundVision

@MainActor
final class SpatialEffectGizmoTests: XCTestCase {
    func testGrabbingDoesNotJumpAndVerticalDragClampsWithoutADeadZone() throws {
        var drag = SpatialEffectDrag(value: 0.4, translationY: -12)
        XCTAssertNil(drag.update(translationY: -12))
        XCTAssertEqual(try XCTUnwrap(drag.update(translationY: -132)), 0.9, accuracy: 0.0001)
        XCTAssertEqual(drag.update(translationY: -1000), 1)
        XCTAssertEqual(try XCTUnwrap(drag.update(translationY: -976)), 0.9, accuracy: 0.0001,
                       "Volver desde el límite debe responder inmediatamente")
        XCTAssertEqual(drag.update(translationY: 1000), 0)
        XCTAssertNil(drag.update(translationY: .nan))
        XCTAssertNil(drag.update(translationY: .infinity))
        XCTAssertEqual(drag.value, 0)
    }

    func testEachGizmoControlEditsOnlyItsParameterAndKeepsPlayback() throws {
        for parameter in SoundParameter.allCases {
            let state = CompositionState()
            let id = state.createNode(of: .pad, at: [0, 1.25, 0])
            state.setSoundParameter(id: id, parameter: parameter, value: 0.25)
            state.togglePlayback()
            defer { state.stopPlayback() }
            let before = try XCTUnwrap(state.node(id: id))
            let session = try XCTUnwrap(state.spatialAudioSession)
            let connections = state.connections
            let edit = SpatialEffectEditingSession(node: before, parameter: parameter, translationY: 0)
            edit.update(translationY: -48, at: 0, state: state)
            edit.update(translationY: -72, at: 0.01, state: state)
            edit.update(translationY: -96, at: 0.02, state: state, finish: true)
            let after = try XCTUnwrap(state.node(id: id))
            XCTAssertEqual(parameter.value(in: after), 0.65, accuracy: 0.0001)
            for other in SoundParameter.allCases where other != parameter {
                XCTAssertEqual(other.value(in: after), other.value(in: before))
            }
            XCTAssertEqual(after.positionX, before.positionX)
            XCTAssertEqual(after.positionY, before.positionY)
            XCTAssertEqual(after.positionZ, before.positionZ)
            XCTAssertEqual(after.pitch, before.pitch)
            XCTAssertEqual(state.connections, connections)
            XCTAssertEqual(state.spatialAudioSession?.id, session.id)
            XCTAssertEqual(state.spatialAudioSession?.events, session.events)
            XCTAssertTrue(state.graphTransport.isPlaying)
            XCTAssertFalse(state.hasPendingTimingChanges)
            state.undo()
            XCTAssertEqual(state.node(id: id), before, "Un solo Deshacer revierte todo el arrastre")
            XCTAssertTrue(state.graphTransport.isPlaying)
        }
    }

    func testOldGestureCannotEditANewSelectionOrADeletedNode() throws {
        let state = CompositionState()
        let a = state.createNode(of: .bass)
        let before = try XCTUnwrap(state.node(id: a))
        let edit = SpatialEffectEditingSession(node: before, parameter: .delay, translationY: 0)
        let b = state.createNode(of: .bell)
        edit.update(translationY: -120, at: 0, state: state, finish: true)
        XCTAssertEqual(state.node(id: a), before)
        XCTAssertEqual(state.node(id: b)?.delay, 0)
        state.focusNode(id: a)
        state.deleteSelectedNode()
        edit.update(translationY: -200, at: 1, state: state, finish: true)
        XCTAssertNil(state.node(id: a))
        XCTAssertEqual(state.node(id: b)?.delay, 0)
    }

    func testGizmoIsContextualHasFourHandlesAndDoesNotCaptureBodyGestures() throws {
        let gizmo = NodeEffectGizmo()
        XCTAssertFalse(gizmo.root.isEnabled)
        let node = SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0)
        let sculpture = Entity()
        let body = NodeEntityFactory.makeNode(node)
        sculpture.addChild(body)
        sculpture.addChild(gizmo.root)
        gizmo.synchronize(node: node)
        XCTAssertTrue(gizmo.root.isEnabled)
        XCTAssertNotNil(gizmo.root.components[BillboardComponent.self])
        for parameter in SoundParameter.allCases {
            let handle = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-handle-\(parameter.rawValue)"))
            let target = try XCTUnwrap(NodeEffectGizmo.handle(from: handle))
            XCTAssertEqual(target.nodeID, node.id)
            XCTAssertEqual(target.parameter, parameter)
            XCTAssertNotNil(handle.components[CollisionComponent.self])
            XCTAssertNil(NodeEntityFactory.id(from: handle))
            XCTAssertFalse(NodeEntityFactory.isConnector(handle))
            XCTAssertFalse(TransportNodeFactory.isTransportEntity(handle))
        }
        XCTAssertNil(NodeEffectGizmo.handle(from: body))
        XCTAssertNil(NodeEffectGizmo.handle(from: try XCTUnwrap(body.findEntity(named: NodeEntityFactory.connectorName))))
        let before = gizmo.root.transform
        body.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        body.scale = [1.4, 1.4, 1.4]
        XCTAssertEqual(gizmo.root.transform, before, "El efecto no gira ni agranda sus propios controles")
        gizmo.synchronize(node: nil)
        XCTAssertFalse(gizmo.root.isEnabled)
        XCTAssertNil(gizmo.nodeID)
    }

    func testHandlesClearTheConnectorAtItsLargestAnimatedSize() throws {
        let gizmo = NodeEffectGizmo()
        for type in SoundNodeType.allCases {
            let node = SoundNode(name: "Prueba", type: type, positionX: 0, positionY: 1.25, positionZ: 0)
            let body = NodeEntityFactory.makeNode(node)
            let connector = try XCTUnwrap(body.findEntity(named: NodeEntityFactory.connectorName))
            let style = NodeVisualStyle.style(for: type)
            // Envolvente de cualquier giro, incluyendo el collider de 7.5 cm,
            // el énfasis al conectar y el desplazamiento de respiración.
            let reach = (simd_length(connector.position) + 0.075 * 1.55)
                * max(style.baseScale, style.triggerScale) + style.idleAmplitude
            for parameter in SoundParameter.allCases {
                gizmo.synchronize(node: node, editing: parameter)
                let handle = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-handle-\(parameter.rawValue)"))
                let distance = simd_length(handle.position(relativeTo: gizmo.root))
                XCTAssertGreaterThan(distance - NodeEffectGizmo.handleRadius * handle.scale.x, reach + 0.02,
                                     "\(type) debe conservar espacio entre \(parameter) y su conector")
            }
        }
    }

    func testGizmoFollowsMovedNodeAndRetargetsHandlesWithoutAddingControls() throws {
        let gizmo = NodeEffectGizmo()
        let a = SoundNode(name: "A", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0)
        let b = SoundNode(name: "B", type: .bass, positionX: 1, positionY: 1.5, positionZ: -0.5)
        gizmo.synchronize(node: a)
        let count = gizmo.root.children.count
        gizmo.move(to: [0.8, 1.8, 0.4], node: a)
        XCTAssertEqual(gizmo.root.position.x, 0.8)
        XCTAssertEqual(gizmo.root.position.z, 0.4)
        gizmo.synchronize(node: b)
        XCTAssertEqual(gizmo.root.position.x, 1)
        XCTAssertEqual(gizmo.root.children.count, count)
        let handle = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-handle-reverb"))
        XCTAssertEqual(NodeEffectGizmo.handle(from: handle)?.nodeID, b.id)
    }
}
