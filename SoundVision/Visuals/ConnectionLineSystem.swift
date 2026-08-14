import Foundation
import RealityKit

enum ConnectionLineSystem {
    static let containerName = "energy-connections"
    static let prefix = "connection-"

    static func makeContainer() -> Entity {
        let container = Entity()
        container.name = containerName
        return container
    }

    static func synchronize(
        in root: Entity,
        nodes: [SoundNode],
        connections: [SoundConnection],
        triggeredIDs: Set<UUID>
    ) {
        guard let container = root.findEntity(named: containerName) else { return }
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let validNames = Set(connections.map { prefix + $0.id.uuidString })

        for stale in container.children where stale.name.hasPrefix(prefix) && !validNames.contains(stale.name) {
            stale.removeFromParent()
        }

        for connection in connections {
            guard let destination = nodeMap[connection.destinationNodeID] else { continue }
            let sourcePosition = connection.sourceNodeID
                .flatMap { nodeMap[$0] }
                .map(position(of:)) ?? CompositionState.playNodePosition
            let destinationPosition = position(of: destination)
            let lineName = prefix + connection.id.uuidString
            let line: ModelEntity

            if let existing = container.findEntity(named: lineName) as? ModelEntity {
                line = existing
            } else {
                line = ModelEntity(
                    mesh: .generateCylinder(height: 1, radius: 0.004),
                    materials: [SoundVisionMaterials.connection(for: destination.type, highlighted: false)]
                )
                line.name = lineName
                container.addChild(line)
            }

            let vector = destinationPosition - sourcePosition
            let length = max(simd_length(vector), 0.001)
            line.position = (sourcePosition + destinationPosition) / 2
            line.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(vector))
            let highlighted = triggeredIDs.contains(destination.id)
            line.scale = [highlighted ? 1.8 : 1, length, highlighted ? 1.8 : 1]
            line.model?.materials = [SoundVisionMaterials.connection(for: destination.type, highlighted: highlighted)]
            line.isEnabled = destination.isActive
        }
    }

    private static func position(of node: SoundNode) -> SIMD3<Float> {
        let style = NodeVisualStyle.style(for: node.type)
        return [node.positionX, node.positionY + style.verticalOffset, node.positionZ]
    }
}
