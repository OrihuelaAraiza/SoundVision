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

    static func update(_ core: Entity, activeCount: Int, triggeredCount: Int, time: TimeInterval) {
        let activity = Float(activeCount) / 8
        let breathing = Float(sin(time * 1.35)) * 0.035
        core.findEntity(named: "core-outer")?.scale = SIMD3(repeating: 1 + activity * 0.28 + breathing)
        core.findEntity(named: "core-heart")?.scale = SIMD3(repeating: 0.9 + activity * 0.42 + Float(triggeredCount) * 0.16)

        if let shell = core.findEntity(named: "core-shell") as? ModelEntity {
            shell.scale = SIMD3(repeating: 1 + activity * 0.12 + (triggeredCount > 0 ? 0.16 : 0))
            let materialBand = min(4, activeCount / 2) + (triggeredCount > 0 ? 10 : 0)
            if core.components[CoreRenderedStateComponent.self]?.materialBand != materialBand {
                shell.model?.materials = [SoundVisionMaterials.core(intensity: 0.5 + activity * 0.5)]
                core.components.set(CoreRenderedStateComponent(materialBand: materialBand))
            }
            shell.orientation = simd_quatf(angle: Float(time * 0.16), axis: [0.3, 1, 0.2])
        }
    }
}

private struct CoreRenderedStateComponent: Component {
    var materialBand: Int
}
