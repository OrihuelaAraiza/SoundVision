import Foundation
import RealityKit

/// Datos que la línea necesita para poder resaltarse sin volver a consultar la
/// composición. Permite que los destellos de reproducción se apliquen directo a
/// las entidades, sin pasar por SwiftUI.
struct ConnectionLineComponent: Component {
    var destinationID: UUID
    var type: SoundNodeType
    var isHighlighted: Bool
}

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
        let revision = revision(nodes: nodes, connections: connections)
        guard container.components[ConnectionRevisionComponent.self]?.value != revision else { return }
        container.components.set(ConnectionRevisionComponent(value: revision))

        let nodeMap = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

            let length = SpatialSceneLayout.segmentLength(from: sourcePosition, to: destinationPosition)
            line.position = (sourcePosition + destinationPosition) / 2
            line.orientation = SpatialSceneLayout.segmentOrientation(from: sourcePosition, to: destinationPosition)
            line.scale = [1, length, 1]
            line.isEnabled = destination.isActive
            line.components.set(ConnectionLineComponent(
                destinationID: destination.id,
                type: destination.type,
                isHighlighted: false
            ))
            setHighlight(triggeredIDs.contains(destination.id), on: line)
        }
    }

    /// Recoloca en vivo las líneas que tocan un organismo en pleno arrastre.
    /// El estado observado solo se confirma 20 veces por segundo; sin esto, las
    /// conexiones irían visiblemente por detrás de la mano.
    static func updateGeometry(
        in root: Entity,
        movedNodeID: UUID,
        livePosition: SIMD3<Float>,
        nodes: [SoundNode],
        connections: [SoundConnection]
    ) {
        guard let container = root.findEntity(named: containerName) else { return }
        let nodeMap = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func endpoint(_ id: UUID) -> SIMD3<Float>? {
            guard let node = nodeMap[id] else { return nil }
            let base = id == movedNodeID
                ? livePosition
                : SIMD3<Float>(node.positionX, node.positionY, node.positionZ)
            return [base.x, base.y + NodeVisualStyle.style(for: node.type).verticalOffset, base.z]
        }

        for connection in connections
        where connection.sourceNodeID == movedNodeID || connection.destinationNodeID == movedNodeID {
            guard let line = container.findEntity(named: prefix + connection.id.uuidString) as? ModelEntity,
                  let destination = endpoint(connection.destinationNodeID)
            else { continue }
            let source = connection.sourceNodeID.flatMap(endpoint) ?? CompositionState.playNodePosition
            let length = SpatialSceneLayout.segmentLength(from: source, to: destination)
            let thickness = line.components[ConnectionLineComponent.self]?.isHighlighted == true ? Float(1.8) : 1

            line.position = (source + destination) / 2
            line.orientation = SpatialSceneLayout.segmentOrientation(from: source, to: destination)
            line.scale = [thickness, length, thickness]
        }
    }

    /// Resalta las líneas de los nodos que suenan sin reconstruir geometría ni
    /// tocar el estado observado: cada nota redibujaba antes toda la interfaz.
    static func applyTriggerHighlights(in root: Entity, triggeredIDs: Set<UUID>) {
        guard let container = root.findEntity(named: containerName) else { return }
        for child in container.children {
            guard let line = child as? ModelEntity,
                  let info = line.components[ConnectionLineComponent.self]
            else { continue }
            setHighlight(triggeredIDs.contains(info.destinationID), on: line)
        }
    }

    private static func setHighlight(_ highlighted: Bool, on line: ModelEntity) {
        guard var info = line.components[ConnectionLineComponent.self],
              info.isHighlighted != highlighted
        else { return }
        info.isHighlighted = highlighted
        line.components.set(info)

        let thickness: Float = highlighted ? 1.8 : 1
        line.scale = [thickness, line.scale.y, thickness]
        line.model?.materials = [SoundVisionMaterials.connection(for: info.type, highlighted: highlighted)]
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

    /// Solo geometría y pertenencia. Los destellos quedan fuera a propósito:
    /// entraban en el hash y obligaban a rehacer este cálculo en cada nota.
    private static func revision(nodes: [SoundNode], connections: [SoundConnection]) -> Int {
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
        return hasher.finalize()
    }
}

private struct ConnectionRevisionComponent: Component {
    var value: Int
}
