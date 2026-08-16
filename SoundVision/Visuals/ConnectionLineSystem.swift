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
        let revision = revision(nodes: nodes, connections: connections, triggeredIDs: triggeredIDs)
        guard container.components[ConnectionRevisionComponent.self]?.value != revision else { return }
        container.components.set(ConnectionRevisionComponent(value: revision))

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
                // Una hebra de 4 mm es imposible de tocar con la mirada. El
                // collider es una cápsula mucho más ancha; se escala en Y junto
                // con la línea, así que cubre toda su longitud.
                line.components.set(InputTargetComponent())
                line.components.set(HoverEffectComponent())
                line.components.set(CollisionComponent(
                    shapes: [.generateCapsule(height: 1, radius: 0.05)]
                ))
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

    /// Identifica la conexión tocada, subiendo por la jerarquía como hacen los
    /// nodos.
    static func id(from entity: Entity) -> UUID? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name.hasPrefix(prefix) {
                return UUID(uuidString: String(current.name.dropFirst(prefix.count)))
            }
            candidate = current.parent
        }
        return nil
    }

    private static func position(of node: SoundNode) -> SIMD3<Float> {
        let style = NodeVisualStyle.style(for: node.type)
        return [node.positionX, node.positionY + style.verticalOffset, node.positionZ]
    }

    private static func revision(
        nodes: [SoundNode],
        connections: [SoundConnection],
        triggeredIDs: Set<UUID>
    ) -> Int {
        var hasher = Hasher()
        for node in nodes {
            hasher.combine(node.id)
            hasher.combine(node.positionX)
            hasher.combine(node.positionY)
            hasher.combine(node.positionZ)
            hasher.combine(node.isActive)
        }
        for connection in connections {
            hasher.combine(connection.id)
            hasher.combine(connection.sourceNodeID)
            hasher.combine(connection.destinationNodeID)
        }
        for id in triggeredIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        return hasher.finalize()
    }
}

private struct ConnectionRevisionComponent: Component {
    var value: Int
}
