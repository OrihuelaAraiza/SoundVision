import Foundation
import RealityKit

enum ConnectionLineSystem {
    static let prefix = "connection-"

    static func makeConnections(for nodes: [SoundNode], corePosition: SIMD3<Float>) -> Entity {
        let container = Entity()
        container.name = "energy-connections"
        for node in nodes {
            let style = NodeVisualStyle.style(for: node.type)
            let start = SIMD3(node.positionX, node.positionY + style.verticalOffset, node.positionZ)
            let line = makeLine(from: start, to: corePosition, type: node.type)
            line.name = prefix + node.id.uuidString
            line.isEnabled = node.isActive
            container.addChild(line)
        }
        return container
    }

    static func update(in root: Entity, nodes: [SoundNode], triggeredIDs: Set<UUID>) {
        for node in nodes {
            guard let line = root.findEntity(named: prefix + node.id.uuidString) as? ModelEntity else { continue }
            line.isEnabled = node.isActive
            line.model?.materials = [SoundVisionMaterials.connection(for: node.type, highlighted: triggeredIDs.contains(node.id))]
            line.scale.x = triggeredIDs.contains(node.id) ? 1.8 : 1
            line.scale.z = line.scale.x
        }
    }

    private static func makeLine(from start: SIMD3<Float>, to end: SIMD3<Float>, type: SoundNodeType) -> ModelEntity {
        let vector = end - start
        let length = simd_length(vector)
        let line = ModelEntity(
            mesh: .generateCylinder(height: length, radius: 0.004),
            materials: [SoundVisionMaterials.connection(for: type, highlighted: false)]
        )
        line.position = (start + end) / 2
        line.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(vector))
        return line
    }
}
