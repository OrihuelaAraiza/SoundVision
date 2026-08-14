import Foundation
import RealityKit

enum PulseIndicator {
    static func make() -> Entity {
        let root = Entity()
        root.name = "pulse-indicator"

        let core = ModelEntity(mesh: .generateSphere(radius: 0.052), materials: [SoundVisionMaterials.pulse(isOnActiveStep: false)])
        core.name = "pulse-core"
        root.addChild(core)

        for index in 1...3 {
            let trail = ModelEntity(
                mesh: .generateSphere(radius: 0.038 - Float(index) * 0.006),
                materials: [SoundVisionMaterials.translucentAccent(for: .pad, alpha: CGFloat(0.2 / Double(index)))]
            )
            trail.name = "pulse-trail-\(index)"
            root.addChild(trail)
        }
        return root
    }

    static func update(
        _ pulse: Entity,
        currentStep: Int,
        progress: Float,
        radius: Float,
        height: Float,
        activeSteps: Set<Int>
    ) {
        let nextStep = (currentStep + 1) % Sequencer.totalSteps
        let fromAngle = Float(currentStep) / Float(Sequencer.totalSteps) * 2 * .pi
        let toAngle = Float(nextStep) / Float(Sequencer.totalSteps) * 2 * .pi
        let angle = fromAngle + shortestAngle(from: fromAngle, to: toAngle) * progress
        pulse.position = [cos(angle) * radius, height + 0.065, sin(angle) * radius]

        if let core = pulse.findEntity(named: "pulse-core") as? ModelEntity {
            core.model?.materials = [SoundVisionMaterials.pulse(isOnActiveStep: activeSteps.contains(currentStep))]
            core.scale = SIMD3(repeating: activeSteps.contains(currentStep) ? 1.3 : 1)
        }

        for index in 1...3 {
            guard let trail = pulse.findEntity(named: "pulse-trail-\(index)") else { continue }
            let trailAngle = angle - Float(index) * 0.055
            trail.position = [cos(trailAngle) * radius - pulse.position.x, 0, sin(trailAngle) * radius - pulse.position.z]
        }
    }

    private static func shortestAngle(from: Float, to: Float) -> Float {
        var difference = to - from
        if difference < -.pi { difference += 2 * .pi }
        if difference > .pi { difference -= 2 * .pi }
        return difference
    }
}
