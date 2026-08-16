import Foundation
import RealityKit

enum CentralCoreSystem {
    static func make() -> Entity {
        let root = Entity()
        root.name = "mix-core"
        root.position.y = 1.25

        let outer = ModelEntity(
            mesh: .generateSphere(radius: 0.19),
            materials: [SoundVisionMaterials.translucentAccent(for: .pad, alpha: 0.08)]
        )
        outer.name = "core-outer"
        root.addChild(outer)

        let shell = ModelEntity(
            mesh: .generateSphere(radius: 0.135),
            materials: [SoundVisionMaterials.core(intensity: 0.65)]
        )
        shell.name = "core-shell"
        root.addChild(shell)

        let heart = ModelEntity(
            mesh: .generateSphere(radius: 0.055),
            materials: [UnlitMaterial(color: .white)]
        )
        heart.name = "core-heart"
        root.addChild(heart)
        root.addChild(ParticleEffectSystem.makeCoreEmitter())
        return root
    }

}
