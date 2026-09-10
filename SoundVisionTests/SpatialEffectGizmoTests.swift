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

    /// El mismo pomo tiene que servir para buscar un 1 % y para ir de 0 a
    /// 100 %. Con ganancia fija había que elegir: a 240 puntos por rango, la
    /// mano en el aire movía el valor de tres en tres por ciento.
    func testSlowDragIsFinerThanASweepAndBothLandOnWholePercents() throws {
        var fine = SpatialEffectDrag(value: 0.5, translationY: 0)
        // Doce eventos de un punto: una mano quieta corrigiendo a 90 Hz.
        for step in 1...12 { fine.update(translationY: Double(-step)) }
        var sweep = SpatialEffectDrag(value: 0.5, translationY: 0)
        sweep.update(translationY: -12)

        XCTAssertEqual(fine.value, 0.52, accuracy: 0.0001)
        XCTAssertEqual(sweep.value, 0.55, accuracy: 0.0001)
        XCTAssertLessThan(fine.value, sweep.value, "El mismo recorrido despacio debe afinar más")

        // Todo lo que se publica cae en un porcentaje entero: soltar aterriza
        // sobre el número que enseña el fader, no sobre un 0.6374 invisible.
        var stepper = SpatialEffectDrag(value: 0.5, translationY: 0)
        for step in 1...40 {
            stepper.update(translationY: Double(-step) * 1.7)
            XCTAssertEqual(Double(stepper.value) * 100, (Double(stepper.value) * 100).rounded(), accuracy: 0.001)
        }
        XCTAssertGreaterThan(stepper.value, 0.5)
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

    /// El pomo y su relleno suben y bajan con el valor. Antes el pomo se
    /// quedaba clavado en el centro del control y el nivel solo se leía en el
    /// número, que a dos metros no se lee.
    func testHandleAndFillRideTheValueInsteadOfStayingStill() throws {
        let gizmo = NodeEffectGizmo()
        var node = SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0)
        let travel = NodeEffectGizmo.trackHeight
        gizmo.synchronize(node: node)
        let handle = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-handle-reverb"))
        let fill = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-fill-reverb"))
        XCTAssertEqual(handle.position.y, -travel / 2, accuracy: 0.0001)
        XCTAssertLessThan(fill.scale.y, 0.01, "Sin efecto, la barra está vacía")

        node.reverb = 0.5
        gizmo.synchronize(node: node)
        XCTAssertEqual(handle.position.y, 0, accuracy: 0.0001)
        XCTAssertEqual(fill.scale.y, 0.5, accuracy: 0.0001)

        node.reverb = 1
        gizmo.synchronize(node: node)
        XCTAssertEqual(handle.position.y, travel / 2, accuracy: 0.0001)
        XCTAssertEqual(fill.scale.y, 1, accuracy: 0.0001)

        // Cada efecto tiene su propio recorrido: subir reverb no mueve delay.
        let delayHandle = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-handle-delay"))
        XCTAssertEqual(delayHandle.position.y, -travel / 2, accuracy: 0.0001)
        // Y durante el arrastre el pomo sigue el valor pendiente, que va por
        // delante del modelo hasta que se confirma.
        gizmo.synchronize(node: node, editing: .delay, pendingValue: 0.25)
        XCTAssertEqual(delayHandle.position.y, -travel / 2 + 0.25 * travel, accuracy: 0.0001)
    }

    /// Cada efecto tiene su barra sobre el cuerpo, y esa barra no hereda ni el
    /// giro ni el pulso del organismo: se queda quieta y legible donde está.
    func testBodyBarsAppearWithTheEffectAndIgnoreTheBodyTransform() throws {
        var node = SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0)
        let body = NodeEntityFactory.makeNode(node)
        let parts = try XCTUnwrap(body.components[NodePartsComponent.self])
        XCTAssertEqual(parts.effectBars.count, 3)
        let reverbBar = try XCTUnwrap(parts.effectBars.first { $0.parameter == .reverb })
        let delayBar = try XCTUnwrap(parts.effectBars.first { $0.parameter == .delay })

        NodeAnimationSystem.apply(to: body, node: visual(node), time: 1)
        XCTAssertFalse(reverbBar.group.isEnabled, "Un organismo seco no enseña ninguna barra")

        node.reverb = 0.6
        NodeAnimationSystem.apply(to: body, node: visual(node), time: 1.05)
        XCTAssertTrue(reverbBar.group.isEnabled, "Subir el efecto hace aparecer su indicador")
        XCTAssertEqual(reverbBar.fill.scale.y, 0.6, accuracy: 0.0001)
        XCTAssertEqual(reverbBar.fill.position.y, -NodeEffectMeter.barHeight / 2 + 0.6 * NodeEffectMeter.barHeight / 2,
                       accuracy: 0.0001, "La barra crece desde abajo")
        XCTAssertFalse(delayBar.group.isEnabled, "El efecto que nadie ha tocado sigue oculto")

        node.rotationY = .pi / 2
        node.rotationX = .pi / 3
        NodeAnimationSystem.apply(to: body, node: visual(node, isTriggered: true), time: 1.1)
        let meter = try XCTUnwrap(parts.effectMeter)
        let offset = meter.position(relativeTo: nil) - body.position(relativeTo: nil)
        XCTAssertEqual(offset.x, 0, accuracy: 0.002)
        XCTAssertEqual(offset.y, NodeEffectMeter.elevation, accuracy: 0.002)
        XCTAssertEqual(offset.z, 0, accuracy: 0.002)
        XCTAssertEqual(meter.scale(relativeTo: nil).x, 1, accuracy: 0.002,
                       "El ataque agranda el cuerpo, no su lectura")
    }

    private func visual(_ node: SoundNode, isTriggered: Bool = false) -> SoundNodeVisualComponent {
        SoundNodeVisualComponent(node: node, isSelected: false, isTriggered: isTriggered)
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
                // Ahora el pomo recorre su pista, así que el despeje hay que
                // comprobarlo en todo el trayecto y no solo en el centro: el
                // extremo bajo de los faders de arriba es el punto crítico.
                for value: Float in [0, 0.5, 1] {
                    gizmo.synchronize(node: node, editing: parameter, pendingValue: value)
                    let handle = try XCTUnwrap(gizmo.root.findEntity(named: "gizmo-handle-\(parameter.rawValue)"))
                    let distance = simd_length(handle.position(relativeTo: gizmo.root))
                    XCTAssertGreaterThan(distance - NodeEffectGizmo.handleRadius * handle.scale.x, reach + 0.02,
                                         "\(type) debe conservar espacio entre \(parameter) al \(value) y su conector")
                }
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
