import Foundation
import RealityKit

enum NodeEntityFactory {
    static let nodePrefix = "sound-node-"

    static func makeNode(_ node: SoundNode) -> Entity {
        let root = Entity()
        root.name = nodePrefix + node.id.uuidString
        root.position = SIMD3(node.positionX, node.positionY, node.positionZ)

        let surface = SoundVisionMaterials.nodeSurface(for: node.type, isActive: node.isActive)
        for part in visualParts(for: node.type, surface: surface) {
            part.components.set(InputTargetComponent())
            part.components.set(HoverEffectComponent())
            part.generateCollisionShapes(recursive: false)
            root.addChild(part)
        }

        root.addChild(WaveformVisualizer.makeWave(for: node.type))
        root.addChild(makeSelectionHalo(for: node.type))
        return root
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
