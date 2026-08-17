import Foundation
import RealityKit
import UIKit

enum NodeEntityFactory {
    static let nodePrefix = "sound-node-"
    static let connectorName = "node-connector"
    static let soundLockName = "node-sound-lock"

    static func makeNode(_ node: SoundNode) -> Entity {
        let root = Entity()
        root.name = nodePrefix + node.id.uuidString
        root.position = SIMD3(node.positionX, node.positionY, node.positionZ)

        let surface = SoundVisionMaterials.nodeSurface(for: node.type, isActive: node.isActive)
        let highlight = NodeVisualStyle.style(for: node.type).color
        for part in visualParts(for: node.type, surface: surface) {
            part.components.set(InputTargetComponent())
            // Resaltado con el color del propio instrumento en vez del genérico
            // del sistema: al mirar un organismo, se enciende como él mismo.
            // visionOS nunca dice a la app hacia dónde miras —es una garantía de
            // privacidad—, así que este efecto lo dibuja el sistema por su cuenta.
            part.components.set(HoverEffectComponent(.highlight(
                .init(color: highlight, strength: 0.75)
            )))
            part.generateCollisionShapes(recursive: false)
            root.addChild(part)
        }

        let waves = WaveformVisualizer.makeWaves(for: node.type)
        waves.forEach { root.addChild($0) }
        let halo = makeSelectionHalo(for: node.type)
        let connector = makeConnector(for: node.type)
        let plinth = makeSoundLockPlinth()

        root.addChild(ParticleEffectSystem.makeNodeEmitter(for: node.type))
        root.addChild(halo)
        root.addChild(makeConnectorStem(for: node.type))
        root.addChild(connector)
        root.addChild(plinth)
        root.addChild(makeSpatialReadout(for: node))
        root.components.set(readoutState(for: node))
        // Resueltas aquí, no buscadas por nombre en cada frame.
        root.components.set(NodePartsComponent(
            waves: waves,
            halo: halo,
            connector: connector,
            soundLockPlinth: plinth
        ))
        return root
    }

    /// Punto de salida del que se tira para conectar. Es una pieza propia con su
    /// collider para poder distinguir "arrastrar el organismo" de "tirar un hilo
    /// hacia otro organismo" sin modos ni botones.
    private static func makeConnector(for type: SoundNodeType) -> ModelEntity {
        let connector = part(
            connectorName,
            mesh: .generateSphere(radius: 0.042),
            material: SoundVisionMaterials.accentGlow(for: type, alpha: 0.9),
            // Bien despejado del cuerpo. A -0.26 el collider invadía el Pad
            // (atmósfera de 0.22) y el Lead (haz de 0.44), así que al intentar
            // mover esos organismos se agarraba el conector y salía un hilo.
            position: [0, -0.34, 0]
        )
        connector.components.set(InputTargetComponent())
        connector.components.set(HoverEffectComponent())
        connector.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.075)]))
        return connector
    }

    /// Tallo hasta el conector. Separarlo del cuerpo resolvió los agarres
    /// equivocados, pero a esa distancia un punto suelto ya no se lee como parte
    /// del organismo; el tallo restituye esa relación. Sin collider, para no
    /// volver a competir con el cuerpo.
    private static func makeConnectorStem(for type: SoundNodeType) -> ModelEntity {
        let stem = ModelEntity(
            mesh: .generateCylinder(height: 0.17, radius: 0.005),
            materials: [SoundVisionMaterials.accentGlow(for: type, alpha: 0.45)]
        )
        stem.name = "node-connector-stem"
        stem.position = [0, -0.25, 0]
        return stem
    }

    /// Pedestal que aparece bajo el organismo cuando su sonido está fijo. La
    /// metáfora es la del objeto asentado: puedes moverlo sin que cambie.
    private static func makeSoundLockPlinth() -> ModelEntity {
        let plinth = ModelEntity(
            mesh: .generateCylinder(height: 0.007, radius: 0.23),
            materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.34))]
        )
        plinth.name = soundLockName
        plinth.position = [0, -0.44, 0]
        plinth.isEnabled = false
        return plinth
    }

    /// Distingue el conector del resto del organismo. Se detiene al llegar a la
    /// raíz del nodo para no confundirlo con piezas de un nodo padre.
    static func isConnector(_ entity: Entity) -> Bool {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name == connectorName { return true }
            if current.name.hasPrefix(nodePrefix) { return false }
            candidate = current.parent
        }
        return false
    }

    /// Regenerar la etiqueta cuesta un teselado de fuente en el hilo principal.
    /// Antes se disparaba con cada 1 % de volumen, es decir prácticamente en
    /// cada frame de un arrastre: era la causa principal de que la app se
    /// trabara y de que la consola perdiera pulsaciones. Ahora el valor va en
    /// pasos gruesos y además no se reconstruye más de ~8 veces por segundo.
    static func updateSpatialReadout(
        in root: Entity,
        node: SoundNode,
        isVisible: Bool,
        at time: TimeInterval
    ) {
        // Esta función corre cuando cambia el estado, no en cada frame, así que
        // aquí sí sale a cuenta recorrer los hijos.
        for child in root.children where child.name.hasPrefix("node-readout-") {
            child.isEnabled = isVisible
        }
        // Oculta, no hay nada que teselar. Antes se reconstruía la etiqueta de
        // los ocho organismos aunque nadie estuviera leyendo ninguna.
        guard isVisible else { return }

        let expectedState = readoutState(for: node)
        let previous = root.components[NodeReadoutStateComponent.self]
        guard previous != expectedState else { return }
        guard time - (previous?.renderedAt ?? -.infinity) >= 0.125 else { return }

        for child in root.children where child.name.hasPrefix("node-readout-") {
            child.removeFromParent()
        }
        let readout = makeSpatialReadout(for: node)
        readout.isEnabled = true
        root.addChild(readout)
        var stamped = expectedState
        stamped.renderedAt = time
        root.components.set(stamped)
    }

    private static func visualParts(for type: SoundNodeType, surface: RealityKit.Material) -> [ModelEntity] {
        let glow = SoundVisionMaterials.accentGlow(for: type, alpha: 0.58)
        switch type {
        case .kick:
            let core = part("node-core", mesh: .generateSphere(radius: 0.14), material: surface)
            let lowRing = part("accent", mesh: .generateCylinder(height: 0.018, radius: 0.2), material: glow, position: [0, -0.13, 0])
            return [core, lowRing]
        case .snare:
            let core = part("node-core", mesh: .generateBox(size: 0.22, cornerRadius: 0.045), material: surface)
            let left = part("accent", mesh: .generateBox(width: 0.028, height: 0.18, depth: 0.27, cornerRadius: 0.01), material: glow, position: [-0.145, 0, 0])
            let right = part("accent", mesh: .generateBox(width: 0.028, height: 0.18, depth: 0.27, cornerRadius: 0.01), material: glow, position: [0.145, 0, 0])
            return [core, left, right]
        case .hiHat:
            let lower = part("node-core", mesh: .generateCylinder(height: 0.018, radius: 0.17), material: surface, position: [0, -0.025, 0])
            let upper = part("accent", mesh: .generateCylinder(height: 0.012, radius: 0.14), material: glow, position: [0, 0.035, 0])
            return [lower, upper]
        case .clap:
            let left = part("node-core", mesh: .generateBox(width: 0.095, height: 0.2, depth: 0.055, cornerRadius: 0.018), material: surface, position: [-0.072, 0, 0])
            let right = part("node-core-secondary", mesh: .generateBox(width: 0.095, height: 0.2, depth: 0.055, cornerRadius: 0.018), material: surface, position: [0.072, 0, 0])
            let center = part("accent", mesh: .generateSphere(radius: 0.035), material: glow)
            return [left, right, center]
        case .bass:
            let core = part("node-core", mesh: .generateBox(width: 0.19, height: 0.3, depth: 0.19, cornerRadius: 0.035), material: surface)
            let heart = part("accent", mesh: .generateBox(width: 0.1, height: 0.2, depth: 0.205, cornerRadius: 0.02), material: glow)
            return [core, heart]
        case .pad:
            let core = part("node-core", mesh: .generateSphere(radius: 0.17), material: surface)
            let atmosphere = part("accent", mesh: .generateSphere(radius: 0.22), material: SoundVisionMaterials.translucentAccent(for: type, alpha: 0.08))
            return [atmosphere, core]
        case .lead:
            let crystal = part("node-core", mesh: .generateCone(height: 0.36, radius: 0.12), material: surface)
            let beam = part("accent", mesh: .generateCylinder(height: 0.44, radius: 0.012), material: glow)
            crystal.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
            return [crystal, beam]
        case .fx:
            let core = part("node-core", mesh: .generateBox(size: 0.18, cornerRadius: 0.055), material: surface)
            core.orientation = simd_quatf(angle: .pi / 4, axis: [1, 1, 0])
            let offsets: [SIMD3<Float>] = [[-0.17, 0.08, 0], [0.15, 0.11, 0.04], [0.04, -0.16, -0.07], [-0.06, 0.16, 0.1]]
            let fragments = offsets.enumerated().map { index, offset in
                let fragment = part("fragment-\(index)", mesh: .generateBox(size: 0.045, cornerRadius: 0.008), material: glow, position: offset)
                fragment.orientation = simd_quatf(angle: Float(index + 1) * 0.58, axis: [1, 0.7, 0.3])
                return fragment
            }
            return [core] + fragments
        }
    }

    private static func part(_ name: String, mesh: MeshResource, material: RealityKit.Material, position: SIMD3<Float> = .zero) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.position = position
        return entity
    }

    private static func makeSelectionHalo(for type: SoundNodeType) -> ModelEntity {
        let halo = part(
            "selection-halo",
            mesh: .generateSphere(radius: 0.245),
            material: SoundVisionMaterials.translucentAccent(for: type, alpha: 0.12)
        )
        halo.isEnabled = false
        return halo
    }

    /// Etiqueta espacial deliberadamente breve. visionOS aplica el hover sin
    /// revelar a la app qué estaba mirando la persona; el inspector detallado
    /// continúa abriéndose con pinch.
    private static func makeSpatialReadout(for node: SoundNode) -> Entity {
        let container = Entity()
        container.name = readoutName(for: node)
        container.position = [-0.16, 0.27, 0.02]
        // Solo el organismo seleccionado enseña su lectura; ocho etiquetas a la
        // vez llenaban el espacio de texto que nadie estaba leyendo.
        container.isEnabled = false

        let text = String(
            format: "%@   %+.0f st   %d%%",
            node.name,
            node.pitch,
            Int(node.volume * 100)
        )
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.0008,
            font: .monospacedSystemFont(ofSize: 0.034, weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: 0.5, height: 0.07),
            alignment: .left,
            lineBreakMode: .byClipping
        )
        let label = ModelEntity(
            mesh: mesh,
            materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.72))]
        )
        label.name = "spatial-readout-label"
        container.addChild(label)
        return container
    }

    private static func readoutName(for node: SoundNode) -> String {
        "node-readout-\(Int(node.pitch.rounded()))-\(Int((node.volume * 100).rounded()))-\(node.isActive)"
    }

    private static func readoutState(for node: SoundNode) -> NodeReadoutStateComponent {
        NodeReadoutStateComponent(
            pitch: Int(node.pitch.rounded()),
            // Pasos de 5 %: la etiqueta es informativa, no un instrumento de
            // medida, y cada escalón cuesta reconstruir la malla de texto.
            volume: Int((node.volume * 20).rounded()) * 5,
            isActive: node.isActive
        )
    }

    static func id(from entity: Entity) -> UUID? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name.hasPrefix(nodePrefix) {
                return UUID(uuidString: String(current.name.dropFirst(nodePrefix.count)))
            }
            candidate = current.parent
        }
        return nil
    }
}

private struct NodeReadoutStateComponent: Component, Equatable {
    var pitch: Int
    var volume: Int
    var isActive: Bool
    /// Cuándo se tesela por última vez. Fuera de `==` a propósito: marca el
    /// ritmo de reconstrucción, no forma parte de la identidad del contenido.
    var renderedAt: TimeInterval = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pitch == rhs.pitch && lhs.volume == rhs.volume && lhs.isActive == rhs.isActive
    }
}
