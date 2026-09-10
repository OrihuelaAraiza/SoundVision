import RealityKit
import UIKit

struct NodeEffectHandleComponent: Component {
    let nodeID: UUID
    let parameter: SoundParameter
}

/// Un único gizmo reutilizable para el nodo seleccionado. Es hermano de los
/// organismos, de modo que sus faders no giran ni crecen al cambiar un efecto
/// o recibir un ataque. Solo los cuatro pomos tienen zonas de interacción.
@MainActor
final class NodeEffectGizmo {
    static let rootName = "node-effect-gizmo"
    static let handleRadius: Float = 0.065
    /// Recorrido vertical del pomo. El pomo **es** el indicador: sube y baja
    /// con el valor en vez de quedarse clavado en el centro de su control,
    /// así el nivel de los cuatro efectos se lee de un vistazo y desde lejos.
    static let trackHeight: Float = 0.18
    /// El pomo se adelanta un poco sobre la pista para que la pinza lo agarre
    /// a él y no al relleno que tiene detrás.
    static let handleDepth: Float = 0.014
    static let parameters: [SoundParameter] = [.reverb, .delay, .distortion, .volume]
    let root = Entity()
    private(set) var nodeID: UUID?
    private let heading = ModelEntity()
    private let digitMeshes: [MeshResource]
    private var headingText = ""
    private var controls: [SoundParameter: Dial] = [:]

    private struct Dial {
        let handle: ModelEntity
        let fill: ModelEntity
        let digits: [ModelEntity]
        let lit: UnlitMaterial
        let dim: UnlitMaterial
        var percent = -1
        var isEditing = false
    }

    init() {
        digitMeshes = (0...9).map { Self.textMesh(String($0), size: 0.034, width: 0.04) }
        root.name = Self.rootName
        root.isEnabled = false
        root.components.set(BillboardComponent())
        // Los diez glifos se comparten entre todos los porcentajes. Arrastrar
        // cambia referencias a mallas; nunca tesela texto en cada frame.
        for (index, parameter) in Self.parameters.enumerated() {
            controls[parameter] = makeDial(parameter, at: Self.center(at: index), digitMeshes: digitMeshes)
        }
        heading.name = "gizmo-heading"
        heading.position = [-0.38, 0.62, 0.12]
        root.addChild(heading)
        let hint = ModelEntity(mesh: Self.textMesh("Pinza y arrastra · lento afina", size: 0.026, width: 0.64),
                               materials: [UnlitMaterial(color: .white.withAlphaComponent(0.65))])
        hint.position = [-0.32, -0.63, 0.12]
        root.addChild(hint)
    }

    /// Ni el cuerpo más grande ni el conector inferior invaden los pomos, y
    /// tampoco lo hacen con el pomo en el extremo bajo de su recorrido: los
    /// centros están lo bastante lejos para que el fader entero quede libre.
    static func center(at index: Int) -> SIMD3<Float> {
        let positions: [SIMD3<Float>] = [
            [-0.62, 0.52, 0.16], [0.62, 0.52, 0.16],
            [0.62, -0.52, 0.16], [-0.62, -0.52, 0.16]
        ]
        return positions[index]
    }

    /// Altura del pomo y del relleno para un valor de 0 a 1.
    static func place(handle: Entity, fill: Entity, at value: Float) {
        let amount = max(0, min(value.isFinite ? value : 0, 1))
        handle.position = [0, -trackHeight / 2 + amount * trackHeight, handleDepth]
        // La barra crece desde abajo: se escala la misma malla en vez de
        // generar una nueva por cada porcentaje.
        fill.scale.y = max(amount, 0.0001)
        fill.position = [0, -trackHeight / 2 + amount * trackHeight / 2, 0.002]
    }

    func synchronize(node: SoundNode?, position: SIMD3<Float>? = nil,
                     editing: SoundParameter? = nil, pendingValue: Float? = nil) {
        guard let node else {
            root.isEnabled = false
            nodeID = nil
            return
        }
        nodeID = node.id
        root.isEnabled = true
        root.position = position ?? SIMD3(node.positionX,
            node.positionY + NodeVisualStyle.style(for: node.type).verticalOffset, node.positionZ)
        let title = String(node.name.prefix(28))
        if title != headingText {
            headingText = title
            heading.model = ModelComponent(mesh: Self.textMesh(title, size: 0.036, width: 0.76),
                                          materials: [UnlitMaterial(color: .white)])
        }
        for parameter in Self.parameters {
            let amount = parameter == editing ? pendingValue ?? parameter.value(in: node) : parameter.value(in: node)
            update(parameter, nodeID: node.id, value: amount, isEditing: parameter == editing)
        }
    }

    func move(to position: SIMD3<Float>, node: SoundNode) {
        guard nodeID == node.id else { return }
        root.position = position + [0, NodeVisualStyle.style(for: node.type).verticalOffset, 0]
    }

    /// Subir por la jerarquía permite añadir detalles al pomo sin convertir
    /// accidentalmente sus taps/arrastres en movimientos del organismo.
    static func handle(from entity: Entity) -> NodeEffectHandleComponent? {
        var current: Entity? = entity
        while let candidate = current {
            if let handle = candidate.components[NodeEffectHandleComponent.self] { return handle }
            current = candidate.parent
        }
        return nil
    }

    private func update(_ parameter: SoundParameter, nodeID: UUID, value: Float, isEditing: Bool) {
        guard var dial = controls[parameter] else { return }
        if dial.handle.components[NodeEffectHandleComponent.self]?.nodeID != nodeID {
            dial.handle.components.set(NodeEffectHandleComponent(nodeID: nodeID, parameter: parameter))
        }
        let amount = max(0, min(value.isFinite ? value : 0, 1))
        let percent = Int((amount * 100).rounded())
        if percent != dial.percent {
            dial.percent = percent
            // El pomo y la barra se mueven con el mismo número que enseñan los
            // dígitos: apuntar, leer y oír coinciden al 1 %.
            Self.place(handle: dial.handle, fill: dial.fill, at: Float(percent) / 100)
            // Reutilizar las mallas de los diez dígitos también mantiene el
            // porcentaje exacto al soltar, sin esperar a regenerar texto.
            for (index, digit) in dial.digits.enumerated() {
                let number = index == 0 ? percent / 100 : index == 1 ? (percent / 10) % 10 : percent % 10
                digit.isEnabled = index == 0 ? percent >= 100 : index == 1 ? percent >= 10 : true
                digit.model?.mesh = digitMeshes[number]
            }
            var accessibility = AccessibilityComponent()
            accessibility.label = "\(parameter.title)"
            accessibility.value = "\(percent) por ciento"
            accessibility.isAccessibilityElement = true
            dial.handle.components.set(accessibility)
        }
        if isEditing != dial.isEditing {
            dial.isEditing = isEditing
            dial.handle.scale = SIMD3(repeating: isEditing ? 1.18 : 1)
        }
        controls[parameter] = dial
    }

    private func makeDial(_ parameter: SoundParameter, at center: SIMD3<Float>, digitMeshes: [MeshResource]) -> Dial {
        let group = Entity()
        group.name = "gizmo-dial-\(parameter.rawValue)"
        group.position = center
        root.addChild(group)
        let color = EffectIndicatorStyle.color(for: parameter)
        let lit = UnlitMaterial(color: color)
        let dim = UnlitMaterial(color: color.withAlphaComponent(0.18))
        // Pista, relleno y pomo comparten eje: donde apuntas es donde lees.
        let track = ModelEntity(mesh: .generateBox(width: 0.017, height: Self.trackHeight, depth: 0.005),
                                materials: [dim])
        track.name = "gizmo-track-\(parameter.rawValue)"
        group.addChild(track)
        let fill = ModelEntity(mesh: .generateBox(width: 0.017, height: Self.trackHeight, depth: 0.006),
                               materials: [lit])
        fill.name = "gizmo-fill-\(parameter.rawValue)"
        group.addChild(fill)
        // Graduaciones fijas cada 25 %: dan una referencia estable contra la
        // que juzgar la altura del pomo sin tener que leer el número.
        for step in 0...4 {
            let mark = ModelEntity(mesh: .generateBox(width: 0.013, height: 0.003, depth: 0.003), materials: [dim])
            mark.position = [-0.023, -Self.trackHeight / 2 + Float(step) / 4 * Self.trackHeight, 0]
            group.addChild(mark)
        }
        let handle = ModelEntity(mesh: .generateSphere(radius: 0.036), materials: [lit])
        handle.name = "gizmo-handle-\(parameter.rawValue)"
        handle.components.set(InputTargetComponent())
        handle.components.set(HoverEffectComponent(.highlight(.init(color: color, strength: 0.9))))
        handle.components.set(CollisionComponent(shapes: [.generateSphere(radius: Self.handleRadius)]))
        group.addChild(handle)
        Self.place(handle: handle, fill: fill, at: 0)
        let title = ModelEntity(mesh: Self.textMesh(parameter.title, size: 0.03, width: 0.27), materials: [lit])
        title.position = [-0.135, 0.15, 0]
        group.addChild(title)
        let digits = (0..<3).map { index in
            let cell = ModelEntity(mesh: digitMeshes[0], materials: [UnlitMaterial(color: .white)])
            cell.position = [-0.065 + Float(index) * 0.023, -0.2, 0]
            group.addChild(cell)
            return cell
        }
        let percent = ModelEntity(mesh: Self.textMesh("%", size: 0.03, width: 0.05),
                                  materials: [UnlitMaterial(color: .white.withAlphaComponent(0.65))])
        percent.position = [0.012, -0.2, 0]
        group.addChild(percent)
        // Une visualmente el fader con el nodo sin añadir otra zona de captura.
        let direction = SIMD3<Float>(center.x, center.y, 0)
        let inner = simd_normalize(direction) * 0.30
        let outer = simd_normalize(direction) * (simd_length(direction) - 0.17)
        let line = ModelEntity(mesh: .generateCylinder(height: 1, radius: 0.002), materials: [dim])
        line.position = (inner + outer) / 2 + [0, 0, center.z]
        line.orientation = SpatialSceneLayout.segmentOrientation(from: inner, to: outer)
        line.scale.y = simd_distance(inner, outer)
        root.addChild(line)
        return Dial(handle: handle, fill: fill, digits: digits, lit: lit, dim: dim)
    }

    private static func textMesh(_ text: String, size: CGFloat, width: CGFloat) -> MeshResource {
        .generateText(text, extrusionDepth: 0.0005,
                      font: .monospacedSystemFont(ofSize: size, weight: .semibold),
                      containerFrame: CGRect(x: 0, y: 0, width: width, height: size * 1.7),
                      alignment: .center, lineBreakMode: .byTruncatingTail)
    }
}
