import AVFAudio
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
            content.add(makeSculpture())
        } update: { content in
            // Derivada del contenido, no guardada al construir: si el estado de
            // la vista se reinicia, una raíz nula dejaba todos los gestos
            // muertos y la escena sin actualizar.
            guard let root = content.entities.first(where: { $0.name == sculptureName }) else { return }
            scene.adopt(root: root)
            // El orden importa en ambos extremos: las voces de organismos que se
            // van se detienen antes de que sus entidades desaparezcan, y las
            // nuevas se enganchan solo después de que la escena las haya creado.
            let sustainBeats = state.sustainBeatsByNode()
            audioEngine.updateTempo(bpm: state.sequencer.bpm)
            audioEngine.releaseVoices(keeping: Set(state.nodes.map(\.id)))
            reconcileNodes(in: root)
            audioEngine.attachVoices(for: state.nodes, sustainBeats: sustainBeats) { id in
                scene.entity(for: id, in: root)
            }
            // Lo que la mano acaba de cambiar llega a las voces que ya suenan:
            // con la síntesis en tiempo real, mover un organismo se oye ya.
            audioEngine.updateLiveParameters(nodes: state.nodes, sustainBeats: sustainBeats)
            // Publicar la agenda va al final: para entonces todas las voces
            // existen y tienen sus parámetros al día, así que la primera nota
            // suena con la afinación y el volumen correctos.
            audioEngine.publish(session: state.spatialAudioSession)
            syncVisualState(in: root)
            reportAudioProblem()
        }
        .gesture(tapGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(rotationGesture)
        .onAppear {
            audioEngine.prepare()
            // Los destellos van directo a las entidades. Publicarlos obligaba a
            // reconstruir toda la interfaz en cada nota, y la consola perdía
            // pulsaciones mientras sonaba la música.
            //
            // El closure captura el puente, no la vista: guardar `self` en un
            // callback que vive fuera del ciclo de SwiftUI significaba leer
            // `@State` y `@EnvironmentObject` fuera de `body` en cada nota, que
            // es territorio sin garantías y una de las vías por las que la app
            // podía caerse en pleno pasaje rápido.
            let bridge = scene
            state.onSoundingChanged = { [bridge] ids in bridge.applySounding(ids) }
        }
        .task {
            // Un latido de 1 Hz basta para que la consola cuente qué está
            // haciendo el motor sin volver a caer en el error de publicar
            // estado por nota, que era lo que dejaba la interfaz sin respuesta.
            // En reposo el pico cae a cero y la cadena se estabiliza sola, así
            // que esto no genera pasadas de SwiftUI mientras nadie toca nada.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let summary = audioEngine.diagnosticsSummary()
                if summary != state.audioDiagnostics { state.audioDiagnostics = summary }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
            handleAudioInterruption($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) {
            handleAudioRouteChange($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
            state.stopPlayback()
            audioEngine.recoverFromAudioEnvironmentChange(resetConfiguration: true)
            state.statusMessage = "El sistema de audio se reinició. Las voces se reconstruyeron; pulsa Reproducir."
        }
        .onDisappear {
            // El espacio también puede cerrarse desde el sistema (corona
            // digital). Sin esto la ventana seguía mostrando la consola de un
            // estudio que ya no existía.
            state.onSoundingChanged = nil
            audioEngine.stopAll()
            state.stopPlayback()
            state.audioDiagnostics = nil
            state.isImmersiveSpaceOpen = false
        }
    }

    // MARK: - Gestos

    private func handleAudioInterruption(_ notification: Notification) {
        guard let raw = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            state.stopPlayback()
            audioEngine.suspendForAudioInterruption()
            state.statusMessage = "Audio interrumpido por el sistema. La composición quedó detenida de forma segura."
        case .ended:
            audioEngine.recoverFromAudioEnvironmentChange()
            state.statusMessage = "Salida de audio recuperada. Pulsa Reproducir para iniciar desde Play."
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let raw = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .noSuitableRouteForCategory:
            state.stopPlayback()
            audioEngine.recoverFromAudioEnvironmentChange()
            state.statusMessage = "Cambió la salida de audio. Las voces se reconectaron; pulsa Reproducir."
        default:
            // Activar nuestra propia categoría también genera una notificación;
            // ignorarla evita un ciclo de reactivación sin fin.
            break
        }
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                // Tras arrastrar, SwiftUI puede entregar también el tap. Como
                // tocar el nodo ya seleccionado lo suelta, mover un organismo
                // acababa deseleccionándolo y vaciando la pestaña Nodo.
                guard !scene.isSettlingAfterDrag(at: CACurrentMediaTime()) else { return }

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
                guard let root = sculptureRoot(from: value.entity),
                      let id = NodeEntityFactory.id(from: value.entity),
                      let node = state.node(id: id)
                else { return }

                // El seguimiento puede entregar una coordenada no finita durante
                // un frame al perder una mano. Nunca debe llegar a una transformada
                // de RealityKit, tampoco mientras solo dibujamos el hilo temporal.
                let current = state.clampedPosition(
                    value.convert(value.location3D, from: .local, to: root)
                )

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
                    // Referencia tomada aquí, no en `startLocation3D`: el gesto
                    // no engancha hasta recorrer la distancia mínima, así que
                    // medir desde el inicio real hacía saltar el nodo esa
                    // distancia de golpe en cuanto empezaba a moverse.
                    scene.dragReferences[id] = current
                    state.focusNode(id: id)
                }
                let reference = scene.dragReferences[id] ?? current
                let target = state.clampedPosition(origin + (current - reference))

                // La entidad sigue la mano en cada frame, pero el estado
                // observado solo se confirma 20 veces por segundo: publicar a
                // 90 Hz reconstruía la consola entera (con sus sliders) tantas
                // veces por segundo que dejaba de responder y de hacer scroll.
                scene.setLivePosition(target, for: id, in: root)
                ConnectionLineSystem.updateGeometry(
                    in: root,
                    movedNodeID: id,
                    livePosition: target,
                    nodes: state.nodes,
                    connections: state.connections
                )
                if scene.shouldCommitDrag(at: CACurrentMediaTime()) {
                    state.moveNode(id: id, to: target)
                }
                scene.pendingDragTarget = target
            }
            .onEnded { value in
                if let sourceID = scene.connectionSourceID {
                    let candidate = scene.tendrilCandidateID
                    scene.connectionSourceID = nil
                    scene.tendrilCandidateID = nil
                    scene.noteDragEnded(at: CACurrentMediaTime())
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
                    // Confirma la posición final aunque el acelerador se la
                    // hubiera saltado.
                    if let target = scene.pendingDragTarget {
                        state.moveNode(id: id, to: target)
                        // Solo un desplazamiento real suprime el tap posterior.
                        // Suprimirlo siempre haría que un toque con un temblor
                        // de mano dejara de seleccionar el organismo.
                        if let origin = scene.dragOrigins[id], simd_distance(origin, target) > 0.02 {
                            scene.noteDragEnded(at: CACurrentMediaTime())
                        }
                    }
                    scene.dragOrigins[id] = nil
                    scene.dragReferences[id] = nil
                    scene.pendingDragTarget = nil
                } else if TransportNodeFactory.isTransportEntity(value.entity),
                          let root = sculptureRoot(from: value.entity) {
                    // Extraer un organismo exige un tirón deliberado. Antes
                    // bastaban los 8 puntos mínimos del gesto, así que rozar el
                    // núcleo al intentar cualquier otra cosa hacía brotar
                    // organismos que nadie había pedido.
                    let drop = value.convert(value.location3D, from: .local, to: root)
                    if simd_distance(drop, CompositionState.playNodePosition) > 0.45 {
                        if state.playEntryNodeID == nil {
                            state.createNextNode(at: drop)
                        } else {
                            state.statusMessage = "Play ya tiene su única salida. Añade otro sonido y conéctalo entre organismos."
                        }
                    }
                }
            }
    }

    private var sculptureName: String { "sound-sculpture" }

    /// Sube por la jerarquía hasta la raíz de la escultura. Derivarla de la
    /// entidad tocada no puede fallar, a diferencia de guardarla al construir.
    private func sculptureRoot(from entity: Entity) -> Entity? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name == sculptureName { return current }
            candidate = current.parent
        }
        return nil
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
                    state.focusNode(id: id)
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
        root.name = sculptureName
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
            guard let entity = scene.entity(for: node.id, in: root) else { continue }
            NodeEntityFactory.updateSpatialReadout(
                in: entity,
                node: node,
                isVisible: state.selectedNodeID == node.id,
                at: now
            )
            var component = SoundNodeVisualComponent(
                node: node,
                // El candidato a destino se ilumina como si estuviera
                // seleccionado: dice "suelta aquí" sin necesidad de texto.
                isSelected: state.selectedNodeID == node.id || scene.tendrilCandidateID == node.id,
                isTriggered: sounding.contains(node.id),
                isConnectionSource: scene.connectionSourceID == node.id
            )
            // Un nodo en pleno arrastre manda sobre el estado: su posición la
            // escribe el gesto a frame rate y el estado va detrás.
            if scene.dragOrigins[node.id] != nil,
               let live = entity.components[SoundNodeVisualComponent.self] {
                component.position = live.position
            }
            entity.components.set(component)
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
        let length = SpatialSceneLayout.segmentLength(from: from, to: endPoint)
        tendril.position = (from + endPoint) / 2
        tendril.orientation = SpatialSceneLayout.segmentOrientation(from: from, to: endPoint)
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
    var pendingDragTarget: SIMD3<Float>?
    var dragReferences: [UUID: SIMD3<Float>] = [:]
    private var lastDragCommit: TimeInterval = -.infinity
    private var lastDragEnd: TimeInterval = -.infinity

    func adopt(root: Entity) {
        guard self.root !== root else { return }
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

    /// Caché que se repara sola. Una entrada perdida antes dejaba al nodo sin
    /// actualizarse en absoluto; ahora se vuelve a buscar y se guarda.
    func entity(for id: UUID, in root: Entity) -> Entity? {
        if let cached = nodeEntities[id], cached.parent != nil { return cached }
        guard let found = root.findEntity(named: NodeEntityFactory.nodePrefix + id.uuidString) else { return nil }
        nodeEntities[id] = found
        return found
    }

    /// Mueve la entidad ya, sin esperar a que el estado observado se ponga al día.
    func setLivePosition(_ position: SIMD3<Float>, for id: UUID, in root: Entity) {
        guard let entity = entity(for: id, in: root),
              var component = entity.components[SoundNodeVisualComponent.self]
        else { return }
        component.position = position
        entity.components.set(component)
    }

    /// Aplica los destellos directamente sobre las entidades afectadas.
    /// Vive aquí, y no en la vista, porque se invoca desde el reloj de la
    /// reproducción: fuera de una pasada de SwiftUI no hay `@State` que leer.
    func applySounding(_ ids: Set<UUID>) {
        let changed = soundingIDs.symmetricDifference(ids)
        soundingIDs = ids

        for id in changed {
            guard let entity = nodeEntities[id],
                  var component = entity.components[SoundNodeVisualComponent.self]
            else { continue }
            component.isTriggered = ids.contains(id)
            entity.components.set(component)
        }

        if let transport, var component = transport.components[TransportVisualComponent.self] {
            component.triggeredCount = ids.count
            transport.components.set(component)
        }

        if let root {
            ConnectionLineSystem.applyTriggerHighlights(in: root, triggeredIDs: ids)
        }
    }

    func noteDragEnded(at time: TimeInterval) {
        lastDragEnd = time
    }

    /// Ventana corta tras soltar en la que se ignoran los taps.
    func isSettlingAfterDrag(at time: TimeInterval) -> Bool {
        time - lastDragEnd < 0.3
    }

    /// Limita a 20 Hz la publicación del arrastre hacia SwiftUI.
    func shouldCommitDrag(at time: TimeInterval) -> Bool {
        guard time - lastDragCommit >= 0.05 else { return false }
        lastDragCommit = time
        return true
    }
}

private struct SceneMembershipRevisionComponent: Component {
    var value: Int
}
