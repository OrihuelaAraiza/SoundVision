import RealityKit

enum TransportNodeFactory {
    static let rootName = "transport-play-node"

    @MainActor
    static func make() -> Entity {
        let root = Entity()
        root.name = rootName
        root.position = CompositionState.playNodePosition

        let core = CentralCoreSystem.make()
        core.position = .zero
        root.addChild(core)

        root.addChild(MetalEnergyFieldSystem.make())

        let playGlyph = ModelEntity(
            mesh: .generateCone(height: 0.12, radius: 0.075),
            materials: [UnlitMaterial(color: .white)]
        )
        playGlyph.name = "play-glyph"
        playGlyph.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        playGlyph.position.z = 0.145
        root.addChild(playGlyph)

        let hitTarget = ModelEntity(
            mesh: .generateSphere(radius: 0.22),
            materials: [SoundVisionMaterials.translucentAccent(for: .pad, alpha: 0.035)]
        )
        hitTarget.name = "play-hit-target"
        hitTarget.components.set(InputTargetComponent())
        hitTarget.components.set(HoverEffectComponent())
        hitTarget.generateCollisionShapes(recursive: false)
        root.addChild(hitTarget)
        return root
    }

    static func isTransportEntity(_ entity: Entity) -> Bool {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name == rootName { return true }
            candidate = current.parent
        }
        return false
    }
}
