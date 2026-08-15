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

        let renderedState = NodeRenderedStateComponent(isActive: node.isActive, isTriggered: isTriggered)
        if entity.components[NodeRenderedStateComponent.self] != renderedState {
            updateMaterials(in: entity, node: node, isTriggered: isTriggered)
            WaveformVisualizer.updateWave(in: entity, type: node.type, isTriggered: isTriggered)
            entity.components.set(renderedState)
        }
        updatePersonality(in: entity, node: node, isTriggered: isTriggered, time: time)
        ParticleEffectSystem.updateNode(
            in: entity,
            isSelected: isSelected,
            isTriggered: isTriggered,
            isActive: node.isActive
        )

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

    private static func updatePersonality(in root: Entity, node: SoundNode, isTriggered: Bool, time: TimeInterval) {
        let userRotation = simd_quatf(angle: node.rotationY, axis: [0, 1, 0])
            * simd_quatf(angle: node.rotationX, axis: [1, 0, 0])
            * simd_quatf(angle: node.rotationZ, axis: [0, 0, 1])
        let idleAngle: Float = switch node.type {
        case .pad: Float(sin(time * 0.22)) * 0.06
        case .lead: Float(sin(time * 0.65)) * 0.045
        case .fx: Float(time * (isTriggered ? 0.7 : 0.12)).truncatingRemainder(dividingBy: .pi * 2)
        case .kick, .bass: Float(sin(time * 0.7)) * 0.014
        case .snare, .hiHat, .clap: 0
        }
        root.orientation = userRotation * simd_quatf(angle: idleAngle, axis: [0.25, 1, 0.15])

        switch node.type {
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
        case .pad, .lead, .fx, .kick, .bass:
            break
        }
    }
}

private struct NodeRenderedStateComponent: Component, Equatable {
    var isActive: Bool
    var isTriggered: Bool
}
