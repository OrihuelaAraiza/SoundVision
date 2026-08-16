import RealityKit
import Spatial
import SwiftUI

/// El espacio inmersivo contiene únicamente la escultura sonora y sus gestos.
/// Todos los controles viven en `StudioConsoleView`, una ventana del sistema:
/// anclar paneles a la cabeza los volvía imposibles de mirar, porque seguían el
/// giro de la persona en lugar de esperarla.
struct SoundSculptureView: View {
    @EnvironmentObject private var state: CompositionState
    @StateObject private var audioEngine = AudioEngineManager()
    @State private var dragOrigins: [UUID: SIMD3<Float>] = [:]
    @State private var rotationOrigins: [UUID: SIMD3<Float>] = [:]
    @State private var connectionDrag: ConnectionDrag?

    /// Hilo en curso entre el conector de un organismo y el punto donde está la
    /// mano. Vive en la vista porque solo existe mientras dura el gesto.
    private struct ConnectionDrag {
        let sourceID: UUID
        var endPoint: SIMD3<Float>
        var candidateID: UUID?
    }

    var body: some View {
        RealityView { content in
            content.add(makeSculpture())
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "sound-sculpture" }) else { return }
            // El orden importa en ambos extremos: las fuentes viejas se detienen
            // antes de que sus entidades desaparezcan, y las nuevas se adjuntan
            // solo después de que la escena las haya creado.
            audioEngine.retireSourcesIfNeeded(for: state.spatialAudioSession)
            reconcileNodes(in: root)
            audioEngine.synchronize(session: state.spatialAudioSession, in: root)
            syncVisualState(in: root)
        }
        .gesture(tapGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(rotationGesture)
        .onDisappear {
            // El espacio también puede cerrarse desde el sistema (corona
            // digital). Sin esto la ventana seguía mostrando la consola de un
            // estudio que ya no existía.
            audioEngine.stopAll()
            state.stopPlayback()
            state.isImmersiveSpaceOpen = false
        }
    }

    // MARK: - Gestos

    /// Los gestos mutan el estado directamente. Antes encolaban una petición que
    /// el closure `update` reaplicaba en cada frame sin limpiarla nunca: eso
    /// modificaba estado observado durante el ciclo de actualización de SwiftUI
    /// y dejaba la CPU recalculando el mismo movimiento para siempre.
    private var tapGesture: some Gesture {
        TapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if TransportNodeFactory.isTransportEntity(value.entity) {
                    state.togglePlayback()
                } else if let connectionID = ConnectionLineSystem.id(from: value.entity) {
                    // Cortar es inmediato: el historial de deshacer lo respalda.
                    state.removeConnection(id: connectionID)
                } else if let id = NodeEntityFactory.id(from: value.entity) {
                    state.selectNode(id: id)
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = NodeEntityFactory.id(from: value.entity),
                      let node = state.node(id: id),
                      let root = sculptureRoot(from: value.entity)
                else { return }

                // Tirar del conector traza un hilo; tirar del cuerpo mueve el
                // organismo. Un mismo gesto, dos intenciones, sin ningún modo.
                if connectionDrag?.sourceID == id || NodeEntityFactory.isConnector(value.entity) {
                    let point = value.convert(value.location3D, from: .local, to: root)
                    connectionDrag = ConnectionDrag(
                        sourceID: id,
                        endPoint: point,
                        candidateID: state.nearestNode(to: point, excluding: id, within: connectionSnapRadius)
                    )
                    return
                }

                // Conserva el punto de agarre para que el nodo no salte al dedo.
                let origin: SIMD3<Float>
                if let stored = dragOrigins[id] {
                    origin = stored
                } else {
                    origin = [node.positionX, node.positionY, node.positionZ]
                    dragOrigins[id] = origin
                    state.selectedNodeID = id
                }

                let start = value.convert(value.startLocation3D, from: .local, to: root)
                let current = value.convert(value.location3D, from: .local, to: root)
                state.moveNode(id: id, to: origin + (current - start))
            }
            .onEnded { value in
                if let drag = connectionDrag {
                    connectionDrag = nil
                    guard let targetID = drag.candidateID else {
                        state.statusMessage = "Suelta el hilo sobre otro organismo para conectarlo."
                        return
                    }
                    // Nunca dejes el gesto sin respuesta: soltar sobre un
                    // destino ya conectado debe decirlo, no quedarse callado.
                    if !state.connect(sourceID: drag.sourceID, destinationID: targetID) {
                        state.statusMessage = "Esos organismos ya estaban conectados."
                    }
                } else if let id = NodeEntityFactory.id(from: value.entity) {
                    dragOrigins[id] = nil
                } else if TransportNodeFactory.isTransportEntity(value.entity),
                          let root = sculptureRoot(from: value.entity) {
                    // Extraer un organismo nuevo tirando del núcleo Play.
                    state.createNextNode(at: value.convert(value.location3D, from: .local, to: root))
                }
            }
    }

    /// Radio de enganche del hilo. Generoso a propósito: acertar a un objeto
    /// pequeño a un metro con la mano cansa.
    private var connectionSnapRadius: Float { 0.42 }

    private var rotationGesture: some Gesture {
        RotateGesture3D()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = NodeEntityFactory.id(from: value.entity),
                      let node = state.node(id: id)
                else { return }

                let origin: SIMD3<Float>
                if let stored = rotationOrigins[id] {
                    origin = stored
                } else {
                    origin = [node.rotationX, node.rotationY, node.rotationZ]
                    rotationOrigins[id] = origin
                    state.selectedNodeID = id
                }

                let rotation = simd_quatf(value.rotation)
                state.rotateNode(id: id, addingTo: origin, delta: rotation.axis * rotation.angle)
            }
            .onEnded { value in
                if let id = NodeEntityFactory.id(from: value.entity) {
                    rotationOrigins[id] = nil
                }
            }
    }

    private func sculptureRoot(from entity: Entity) -> Entity? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name == "sound-sculpture" { return current }
            candidate = current.parent
        }
        return nil
    }

    // MARK: - Escena

    private func makeSculpture() -> Entity {
        let root = Entity()
        root.name = "sound-sculpture"
        // Las coordenadas musicales ya expresan alturas humanas (neutral = 1.25 m).
        root.position = SpatialSceneLayout.rootPosition
        root.addChild(ConnectionLineSystem.makeContainer())
        root.addChild(TransportNodeFactory.make())
        state.nodes.forEach { root.addChild(NodeEntityFactory.makeNode($0)) }
        root.components.set(SceneMembershipRevisionComponent(value: state.sceneContentRevision))
        Task { await ParticleEffectSystem.prepareAssets(in: root) }
        return root
    }

    private func reconcileNodes(in root: Entity) {
        guard root.components[SceneMembershipRevisionComponent.self]?.value != state.sceneContentRevision else { return }
        let expectedNames = Set(state.nodes.map { NodeEntityFactory.nodePrefix + $0.id.uuidString })
        for stale in root.children where stale.name.hasPrefix(NodeEntityFactory.nodePrefix) && !expectedNames.contains(stale.name) {
            stale.isEnabled = false
            stale.removeFromParent()
        }
        for node in state.nodes where root.findEntity(named: NodeEntityFactory.nodePrefix + node.id.uuidString) == nil {
            root.addChild(NodeEntityFactory.makeNode(node))
        }
        root.components.set(SceneMembershipRevisionComponent(value: state.sceneContentRevision))
    }

    /// Empuja el estado musical a los componentes. A partir de aquí la animación
    /// continua es responsabilidad de `NodeAnimationSystem`, que corre a la tasa
    /// de refresco de RealityKit en vez de a los 12–20 Hz de un `TimelineView`.
    private func syncVisualState(in root: Entity) {
        let soundingIDs = state.lastTriggeredNodeIDs.union(state.graphTransport.activeNodeIDs)

        ConnectionLineSystem.synchronize(
            in: root,
            nodes: state.nodes,
            connections: state.connections,
            triggeredIDs: soundingIDs
        )

        if let transport = root.findEntity(named: TransportNodeFactory.rootName) {
            transport.components.set(TransportVisualComponent(
                isPlaying: state.graphTransport.isPlaying,
                activeCount: state.nodes.filter(\.isActive).count,
                triggeredCount: soundingIDs.count
            ))
        }

        for node in state.nodes {
            guard let entity = root.findEntity(named: NodeEntityFactory.nodePrefix + node.id.uuidString) else { continue }
            NodeEntityFactory.updateSpatialReadout(in: entity, node: node)
            entity.components.set(SoundNodeVisualComponent(
                node: node,
                // El candidato a destino se ilumina como si estuviera
                // seleccionado: dice "suelta aquí" sin necesidad de texto.
                isSelected: state.selectedNodeID == node.id || connectionDrag?.candidateID == node.id,
                isTriggered: soundingIDs.contains(node.id),
                isConnectionSource: connectionDrag?.sourceID == node.id
            ))
        }

        updateTendril(in: root)
    }

    /// Hilo que sigue la mano mientras se traza una conexión.
    private func updateTendril(in root: Entity) {
        let name = "connection-tendril"
        guard let drag = connectionDrag, let source = state.node(id: drag.sourceID) else {
            root.findEntity(named: name)?.removeFromParent()
            return
        }

        let tendril: ModelEntity
        if let existing = root.findEntity(named: name) as? ModelEntity {
            tendril = existing
        } else {
            tendril = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.006),
                materials: [SoundVisionMaterials.accentGlow(for: source.type, alpha: 0.85)]
            )
            tendril.name = name
            root.addChild(tendril)
        }

        // Mismo desplazamiento vertical que aplica la animación al organismo,
        // para que el hilo nazca del conector y no del aire.
        let verticalOffset = NodeVisualStyle.style(for: source.type).verticalOffset
        let from = SIMD3<Float>(
            source.positionX,
            source.positionY + verticalOffset - 0.26,
            source.positionZ
        )
        let vector = drag.endPoint - from
        let length = max(simd_length(vector), 0.001)
        tendril.position = (from + drag.endPoint) / 2
        tendril.orientation = simd_quatf(from: [0, 1, 0], to: vector / length)
        tendril.scale = [drag.candidateID == nil ? 1 : 1.9, length, drag.candidateID == nil ? 1 : 1.9]
    }
}

private struct SceneMembershipRevisionComponent: Component {
    var value: Int
}
