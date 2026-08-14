import Foundation
import RealityKit

enum NodeAnimationSystem {
    static func update(
        _ entity: Entity,
        node: SoundNode,
        isSelected: Bool,
        isTriggered: Bool,
        time: TimeInterval
    ) {
        let style = NodeVisualStyle.style(for: node.type)
        let typePhase = Double(SoundNodeType.allCases.firstIndex(of: node.type) ?? 0) * 0.73
        let idle = node.isActive ? sin(time * Double(style.idleSpeed) + typePhase) * Double(style.idleAmplitude) : 0

        entity.position = [node.positionX, node.positionY + style.verticalOffset + Float(idle), node.positionZ]
        let scale = isTriggered ? style.triggerScale : (node.isActive ? style.baseScale : style.baseScale * 0.78)
        entity.scale = SIMD3(repeating: scale)

        updateMaterials(in: entity, node: node, isTriggered: isTriggered)
        updatePersonality(in: entity, type: node.type, isTriggered: isTriggered, time: time)
        WaveformVisualizer.updateWave(in: entity, type: node.type, isTriggered: isTriggered)

        if let halo = entity.findEntity(named: "selection-halo") {
            halo.isEnabled = isSelected
            halo.scale = SIMD3(repeating: isSelected ? 1.08 + Float(sin(time * 2.4)) * 0.05 : 1)
        }
    }

    private static func updateMaterials(in root: Entity, node: SoundNode, isTriggered: Bool) {
        for child in root.children.compactMap({ $0 as? ModelEntity }) {
            if child.name.hasPrefix("node-core") {
                child.model?.materials = [SoundVisionMaterials.nodeSurface(for: node.type, isActive: node.isActive, isTriggered: isTriggered)]
            } else if child.name == "accent" || child.name.hasPrefix("fragment-") {
                child.model?.materials = [node.isActive
                    ? SoundVisionMaterials.accentGlow(for: node.type, alpha: isTriggered ? 0.95 : 0.52)
                    : SoundVisionMaterials.translucentAccent(for: node.type, alpha: 0.05)]
            }
        }
    }

    private static func updatePersonality(in root: Entity, type: SoundNodeType, isTriggered: Bool, time: TimeInterval) {
        switch type {
        case .clap:
            let gap: Float = isTriggered ? 0.035 : 0.072
            root.findEntity(named: "node-core")?.position.x = -gap
            root.findEntity(named: "node-core-secondary")?.position.x = gap
        case .snare:
            let offset: Float = isTriggered ? 0.175 : 0.145
            let accents = root.children.filter { $0.name == "accent" }
            if accents.count == 2 {
                accents[0].position.x = -offset
                accents[1].position.x = offset
            }
        case .hiHat:
            root.findEntity(named: "accent")?.position.y = isTriggered ? 0.012 : 0.035
        case .pad:
            root.orientation = simd_quatf(angle: Float(sin(time * 0.22)) * 0.08, axis: [0, 1, 0])
        case .lead:
            root.orientation = simd_quatf(angle: Float(sin(time * 0.65)) * 0.06, axis: [0, 0, 1])
        case .fx:
            root.orientation = simd_quatf(angle: Float(time * (isTriggered ? 1.8 : 0.38)), axis: [0.3, 1, 0.2])
        case .kick, .bass:
            root.orientation = simd_quatf(angle: Float(sin(time * 0.7)) * 0.018, axis: [0, 0, 1])
        }
    }
}
