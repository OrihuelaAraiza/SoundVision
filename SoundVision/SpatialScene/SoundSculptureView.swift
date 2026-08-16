import QuartzCore
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
    /// Referencia, no valor: mutar sus campos durante un gesto no invalida la
    /// vista. Guardar el origen del arrastre en `@State` provocaba una pasada de
    /// SwiftUI por cada frame de movimiento.
    @State private var scene = SculptureBridge()

    var body: some View {
        RealityView { content in
            let sculpture = makeSculpture()
            scene.adopt(root: sculpture)
            content.add(sculpture)
        } update: { content in
            guard let root = scene.root else { return }
            // El orden importa en ambos extremos: las fuentes viejas se detienen
            // antes de que sus entidades desaparezcan, y las nuevas se adjuntan
            // solo después de que la escena las haya creado.
            audioEngine.retireSourcesIfNeeded(for: state.spatialAudioSession)
            reconcileNodes(in: root)
            audioEngine.synchronize(session: state.spatialAudioSession, in: root)
            syncVisualState(in: root)
            reportAudioProblem()
        }
        .gesture(tapGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(rotationGesture)
        .onAppear {
            // Los destellos van directo a las entidades. Publicarlos obligaba a
            // reconstruir toda la interfaz en cada nota, y la consola perdía
            // pulsaciones mientras sonaba la música.
            state.onSoundingChanged = { ids in applySounding(ids) }
        }
        .onDisappear {
            // El espacio también puede cerrarse desde el sistema (corona
            // digital). Sin esto la ventana seguía mostrando la consola de un
            // estudio que ya no existía.
            state.onSoundingChanged = nil
            audioEngine.stopAll()
            state.stopPlayback()
            state.isImmersiveSpaceOpen = false
        }
    }

    // MARK: - Gestos

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
                guard let root = scene.root,
                      let id = NodeEntityFactory.id(from: value.entity),
                      let node = state.node(id: id)
                else { return }

                let current = value.convert(value.location3D, from: .local, to: root)

                // Tirar del conector traza un hilo; tirar del cuerpo mueve el
                // organismo. Un mismo gesto, dos intenciones, sin ningún modo.
                if scene.connectionSourceID == id || NodeEntityFactory.isConnector(value.entity) {
                    scene.connectionSourceID = id
                    let candidate = state.nearestNode(to: current, excluding: id, within: connectionSnapRadius)
                    updateTendril(from: node, to: current, candidate: candidate, in: root)
                    return
                }

                // Conserva el punto de agarre para que el nodo no salte al dedo.
                let origin = scene.dragOrigins[id] ?? [node.positionX, node.positionY, node.positionZ]
                if scene.dragOrigins[id] == nil {
                    scene.dragOrigins[id] = origin
                    state.selectedNodeID = id
                }
                let start = value.convert(value.startLocation3D, from: .local, to: root)
                state.moveNode(id: id, to: origin + (current - start))
            }
            .onEnded { value in
                if let sourceID = scene.connectionSourceID {
                    let candidate = scene.tendrilCandidateID
                    scene.connectionSourceID = nil
                    scene.tendrilCandidateID = nil
                    clearTendril()

                    guard let targetID = candidate else {
                        state.statusMessage = "Suelta el hilo sobre otro organismo para conectarlo."
                        return
                    }
                    // Nunca dejes el gesto sin respuesta: soltar sobre un
                    // destino ya conectado debe decirlo, no quedarse callado.
                    if !state.connect(sourceID: sourceID, destinationID: targetID) {
                        state.statusMessage = "Esos organismos ya estaban conectados."
                    }
                } else if let id = NodeEntityFactory.id(from: value.entity) {
                    scene.dragOrigins[id] = nil
                } else if TransportNodeFactory.isTransportEntity(value.entity), let root = scene.root {
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

                let origin = scene.rotationOrigins[id] ?? [node.rotationX, node.rotationY, node.rotationZ]
                if scene.rotationOrigins[id] == nil {
                    scene.rotationOrigins[id] = origin
                    state.selectedNodeID = id
                }

                let rotation = simd_quatf(value.rotation)
                state.rotateNode(id: id, addingTo: origin, delta: rotation.axis * rotation.angle)
            }
            .onEnded { value in
                if let id = NodeEntityFactory.id(from: value.entity) {
                    scene.rotationOrigins[id] = nil
                }
            }
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
        scene.rebuildNodeIndex(from: root)
    }

    /// Empuja el estado musical a los componentes. A partir de aquí la animación
    /// continua es responsabilidad de `NodeAnimationSystem`, que corre a la tasa
    /// de refresco de RealityKit.
    private func syncVisualState(in root: Entity) {
        let sounding = state.soundingNodeIDs
        let now = CACurrentMediaTime()

        ConnectionLineSystem.synchronize(
            in: root,
            nodes: state.nodes,
            connections: state.connections,
            triggeredIDs: sounding
        )

        if let transport = scene.transport {
            transport.components.set(TransportVisualComponent(
                isPlaying: state.graphTransport.isPlaying,
                activeCount: state.nodes.filter(\.isActive).count,
                triggeredCount: sounding.count
            ))
        }

        for node in state.nodes {
            // Búsqueda en diccionario, no recorrido recursivo del árbol: esto
            // corría por cada nodo en cada pasada de actualización.
            guard let entity = scene.nodeEntities[node.id] else { continue }
            NodeEntityFactory.updateSpatialReadout(in: entity, node: node, at: now)
            entity.components.set(SoundNodeVisualComponent(
                node: node,
                // El candidato a destino se ilumina como si estuviera
                // seleccionado: dice "suelta aquí" sin necesidad de texto.
                isSelected: state.selectedNodeID == node.id || scene.tendrilCandidateID == node.id,
                isTriggered: sounding.contains(node.id),
                isConnectionSource: scene.connectionSourceID == node.id
            ))
        }
    }

    /// Aplica los destellos directamente sobre las entidades afectadas.
    private func applySounding(_ ids: Set<UUID>) {
        let changed = scene.soundingIDs.symmetricDifference(ids)
        scene.soundingIDs = ids

        for id in changed {
            guard let entity = scene.nodeEntities[id],
                  var component = entity.components[SoundNodeVisualComponent.self]
            else { continue }
            component.isTriggered = ids.contains(id)
            entity.components.set(component)
        }

        if let transport = scene.transport,
           var component = transport.components[TransportVisualComponent.self] {
            component.triggeredCount = ids.count
            transport.components.set(component)
        }

        if let root = scene.root {
            ConnectionLineSystem.applyTriggerHighlights(in: root, triggeredIDs: ids)
        }
    }

    /// Publica el diagnóstico del motor **fuera** del ciclo de actualización:
    /// escribir estado observado desde dentro de `update` es justamente lo que
    /// antes dejaba a SwiftUI recalculando sin parar.
    private func reportAudioProblem() {
        let problem = audioEngine.problemSummary
        guard problem != state.audioProblem else { return }
        Task { @MainActor in state.audioProblem = problem }
    }

    /// Hilo que sigue la mano mientras se traza una conexión. Se dibuja desde el
    /// gesto, no desde el ciclo de actualización, para responder a frame rate.
    private func updateTendril(
        from source: SoundNode,
        to endPoint: SIMD3<Float>,
        candidate: UUID?,
        in root: Entity
    ) {
        let previousCandidate = scene.tendrilCandidateID
        scene.tendrilCandidateID = candidate

        let tendril: ModelEntity
        if let existing = scene.tendril {
            tendril = existing
        } else {
            tendril = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.006),
                materials: [SoundVisionMaterials.accentGlow(for: source.type, alpha: 0.85)]
            )
            tendril.name = "connection-tendril"
            root.addChild(tendril)
            scene.tendril = tendril
        }

        // Mismo desplazamiento vertical que aplica la animación al organismo,
        // para que el hilo nazca del conector y no del aire.
        let verticalOffset = NodeVisualStyle.style(for: source.type).verticalOffset
        let from = SIMD3<Float>(
            source.positionX,
            source.positionY + verticalOffset - 0.34,
            source.positionZ
        )
        let vector = endPoint - from
        let length = max(simd_length(vector), 0.001)
        tendril.position = (from + endPoint) / 2
        tendril.orientation = simd_quatf(from: [0, 1, 0], to: vector / length)
        tendril.scale = [candidate == nil ? 1 : 1.9, length, candidate == nil ? 1 : 1.9]

        // Ilumina el destino candidato en cuanto cambia, sin esperar a SwiftUI.
        if previousCandidate != candidate {
            for id in [previousCandidate, candidate].compactMap({ $0 }) {
                guard let entity = scene.nodeEntities[id],
                      var component = entity.components[SoundNodeVisualComponent.self]
                else { continue }
                component.isSelected = state.selectedNodeID == id || candidate == id
                entity.components.set(component)
            }
        }

        if let entity = scene.nodeEntities[source.id],
           var component = entity.components[SoundNodeVisualComponent.self],
           !component.isConnectionSource {
            component.isConnectionSource = true
            entity.components.set(component)
        }
    }

    private func clearTendril() {
        scene.tendril?.removeFromParent()
        scene.tendril = nil
        for (_, entity) in scene.nodeEntities {
            guard var component = entity.components[SoundNodeVisualComponent.self],
                  component.isConnectionSource
            else { continue }
            component.isConnectionSource = false
            entity.components.set(component)
        }
    }
}

/// Estado vivo de la escena. Es una clase a propósito: los gestos la mutan
/// decenas de veces por segundo y nada de eso debe invalidar la vista.
/// Deliberadamente **no** es `ObservableObject`: observarla anularía el motivo
/// de su existencia.
@MainActor
private final class SculptureBridge {
    private(set) var root: Entity?
    private(set) var transport: Entity?
    private(set) var nodeEntities: [UUID: Entity] = [:]

    var dragOrigins: [UUID: SIMD3<Float>] = [:]
    var rotationOrigins: [UUID: SIMD3<Float>] = [:]
    var connectionSourceID: UUID?
    var tendrilCandidateID: UUID?
    var tendril: ModelEntity?
    var soundingIDs: Set<UUID> = []

    func adopt(root: Entity) {
        self.root = root
        transport = root.findEntity(named: TransportNodeFactory.rootName)
        rebuildNodeIndex(from: root)
    }

    func rebuildNodeIndex(from root: Entity) {
        nodeEntities = [:]
        for child in root.children where child.name.hasPrefix(NodeEntityFactory.nodePrefix) {
            let raw = String(child.name.dropFirst(NodeEntityFactory.nodePrefix.count))
            guard let id = UUID(uuidString: raw) else { continue }
            nodeEntities[id] = child
        }
    }
}

private struct SceneMembershipRevisionComponent: Component {
    var value: Int
}
