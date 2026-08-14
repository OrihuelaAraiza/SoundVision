import RealityKit

struct SequencerRingConfig {
    let radius: Float
    let height: Float
    let totalSteps: Int
    let markerSize: Float

    static let soundVision = SequencerRingConfig(radius: 0.79, height: 1.25, totalSteps: 16, markerSize: 0.035)
}

enum SequencerRing {
    static func make(config: SequencerRingConfig = .soundVision) -> Entity {
        let root = Entity()
        root.name = "sequencer-ring"

        // Segmentos finos dan volumen al aro sin depender de un mesh o textura.
        for segment in 0..<64 {
            let angle = Float(segment) / 64 * 2 * .pi
            let piece = ModelEntity(
                mesh: .generateBox(width: 0.012, height: 0.01, depth: 0.085, cornerRadius: 0.006),
                materials: [SoundVisionMaterials.ring()]
            )
            piece.position = [cos(angle) * config.radius, config.height, sin(angle) * config.radius]
            piece.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            root.addChild(piece)
        }

        for step in 0..<config.totalSteps {
            let isMajor = step.isMultiple(of: 4)
            let angle = Float(step) / Float(config.totalSteps) * 2 * .pi
            let marker = ModelEntity(
                mesh: .generateBox(
                    width: isMajor ? config.markerSize * 1.8 : config.markerSize,
                    height: isMajor ? 0.052 : 0.032,
                    depth: isMajor ? 0.18 : 0.13,
                    cornerRadius: 0.012
                ),
                materials: [SoundVisionMaterials.ring(isMajor: isMajor)]
            )
            marker.name = "step-marker-\(step)"
            marker.position = [cos(angle) * config.radius, config.height, sin(angle) * config.radius]
            marker.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            root.addChild(marker)
        }
        return root
    }
}
