import RealityKit

enum WaveformVisualizer {
    static func makeWave(for type: SoundNodeType) -> ModelEntity {
        let wave = ModelEntity(
            mesh: .generateSphere(radius: 0.205),
            materials: [SoundVisionMaterials.translucentAccent(for: type, alpha: 0.08)]
        )
        wave.name = "trigger-wave"
        wave.isEnabled = false
        return wave
    }

    static func updateWave(in root: Entity, type: SoundNodeType, isTriggered: Bool) {
        guard let wave = root.findEntity(named: "trigger-wave") as? ModelEntity else { return }
        let style = NodeVisualStyle.style(for: type)
        wave.isEnabled = isTriggered
        wave.scale = SIMD3(repeating: isTriggered ? style.waveScale : 0.75)
        wave.model?.materials = [SoundVisionMaterials.translucentAccent(for: type, alpha: isTriggered ? 0.16 : 0.04)]
    }
}
