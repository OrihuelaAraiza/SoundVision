import RealityKit
import UIKit

/// Partículas de bajo costo que refuerzan estados musicales concretos.
/// El atlas usa fondo negro y mezcla aditiva, por lo que no necesita un canal
/// alpha perfecto para conservar el halo luminoso en un entorno inmersivo.
enum ParticleEffectSystem {
    static let nodeEmitterName = "node-energy-particles"
    static let coreEmitterName = "core-energy-particles"

    private static var atlas: TextureResource?

    static func prepareAssets(in root: Entity) async {
        if atlas == nil, let image = UIImage(named: "EnergyParticleAtlas")?.cgImage {
            atlas = try? await TextureResource(
                image: image,
                withName: "EnergyParticleAtlas",
                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
            )
        }
        guard let atlas else { return }
        apply(atlas: atlas, to: root)
    }

    static func makeNodeEmitter(for type: SoundNodeType) -> Entity {
        let entity = Entity()
        entity.name = nodeEmitterName

        var component = baseComponent()
        component.emitterShape = .sphere
        component.birthLocation = .surface
        component.emitterShapeSize = SIMD3(repeating: emitterRadius(for: type))
        component.speed = 0.025
        component.speedVariation = 0.018
        component.radialAmount = 0.82
        component.mainEmitter.birthRate = 0
        component.mainEmitter.lifeSpan = 0.72
        component.mainEmitter.lifeSpanVariation = 0.18
        component.mainEmitter.size = 0.048
        component.mainEmitter.sizeVariation = 0.022
        component.mainEmitter.noiseStrength = 0.22
        component.mainEmitter.noiseScale = 0.8
        component.mainEmitter.noiseAnimationSpeed = 0.55
        component.mainEmitter.vortexStrength = type == .fx ? 0.38 : 0.12
        component.mainEmitter.vortexDirection = [0, 1, 0]
        entity.components.set(component)
        return entity
    }

    static func makeCoreEmitter() -> Entity {
        let entity = Entity()
        entity.name = coreEmitterName

        var component = baseComponent()
        component.emitterShape = .torus
        component.birthLocation = .volume
        component.emitterShapeSize = [0.48, 0.075, 0.48]
        component.torusInnerRadius = 0.76
        component.speed = 0.018
        component.speedVariation = 0.012
        component.radialAmount = 0.28
        component.mainEmitter.birthRate = 3
        component.mainEmitter.lifeSpan = 1.15
        component.mainEmitter.lifeSpanVariation = 0.35
        component.mainEmitter.size = 0.06
        component.mainEmitter.sizeVariation = 0.025
        component.mainEmitter.noiseStrength = 0.3
        component.mainEmitter.noiseScale = 0.72
        component.mainEmitter.noiseAnimationSpeed = 0.32
        component.mainEmitter.vortexStrength = 0.48
        component.mainEmitter.vortexDirection = [0, 1, 0]
        entity.components.set(component)
        return entity
    }

    static func updateNode(in root: Entity, isSelected: Bool, isTriggered: Bool, isActive: Bool) {
        guard let emitter = root.findEntity(named: nodeEmitterName),
              var component = emitter.components[ParticleEmitterComponent.self] else { return }
        let isEmitting = isActive && (isSelected || isTriggered)
        let birthRate: Float = isTriggered ? 10 : (isSelected ? 2 : 0)
        let size: Float = isTriggered ? 0.064 : 0.04
        let angularSpeed: Float = isTriggered ? 1.7 : 0.55
        guard component.isEmitting != isEmitting
                || component.mainEmitter.birthRate != birthRate
                || component.mainEmitter.size != size
                || component.mainEmitter.angularSpeed != angularSpeed else { return }
        component.isEmitting = isEmitting
        component.mainEmitter.birthRate = birthRate
        component.mainEmitter.size = size
        component.mainEmitter.angularSpeed = angularSpeed
        emitter.components.set(component)
    }

    static func updateCore(in root: Entity, isPlaying: Bool, triggeredCount: Int) {
        guard let emitter = root.findEntity(named: coreEmitterName),
              var component = emitter.components[ParticleEmitterComponent.self] else { return }
        let birthRate: Float = isPlaying ? min(14, 6 + Float(triggeredCount * 2)) : 1.5
        let size: Float = isPlaying ? 0.064 : 0.045
        let angularSpeed: Float = isPlaying ? 0.9 : 0.24
        guard component.mainEmitter.birthRate != birthRate
                || component.mainEmitter.size != size
                || component.mainEmitter.angularSpeed != angularSpeed else { return }
        component.isEmitting = true
        component.mainEmitter.birthRate = birthRate
        component.mainEmitter.size = size
        component.mainEmitter.angularSpeed = angularSpeed
        emitter.components.set(component)
    }

    private static func baseComponent() -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent()
        component.birthDirection = .local
        component.fieldSimulationSpace = .local
        component.particlesInheritTransform = true
        component.simulationState = .play
        component.isEmitting = true
        component.mainEmitter.blendMode = .additive
        component.mainEmitter.billboardMode = .billboard
        component.mainEmitter.opacityCurve = .quickFadeInOut
        component.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.35
        component.mainEmitter.sortOrder = .decreasingAge
        component.mainEmitter.image = atlas

        var sequence = ParticleEmitterComponent.ParticleEmitter.ImageSequence()
        sequence.rowCount = 4
        sequence.columnCount = 4
        sequence.initialFrame = 0
        sequence.initialFrameVariation = 0
        sequence.frameRate = 22
        sequence.frameRateVariation = 2
        sequence.animationMode = .playOnce
        component.mainEmitter.imageSequence = sequence
        return component
    }

    private static func emitterRadius(for type: SoundNodeType) -> Float {
        switch type {
        case .pad: 0.22
        case .lead, .bass: 0.19
        case .kick, .snare, .hiHat, .clap, .fx: 0.17
        }
    }

    private static func apply(atlas: TextureResource, to root: Entity) {
        if var component = root.components[ParticleEmitterComponent.self] {
            component.mainEmitter.image = atlas
            root.components.set(component)
        }
        for child in root.children {
            apply(atlas: atlas, to: child)
        }
    }
}
