import Combine
import Foundation
import simd

enum SoundParameter: String, CaseIterable, Sendable { case volume, reverb, delay, distortion }

enum StudioSection: Hashable { case transport, sounds, node, learn }

enum ConnectionEndpoint: Equatable {
    case play
    case node(UUID)
}

@MainActor
final class CompositionState: ObservableObject {
    // La ventana del sistema abre en el centro. Despejar ese eje evita que el
    // collider de Play capture los gestos dirigidos a la consola.
    nonisolated static let playNodePosition = SIMD3<Float>(-1.05, SpatialParameterMapper.neutralHeight, -0.15)

    @Published var nodes: [SoundNode] { didSet { contentDidChange() } }
    @Published var connections: [SoundConnection] { didSet { contentDidChange() } }
    @Published var isImmersiveSpaceOpen = false
    /// Los destellos de reproducción **no** se publican. Cada nota provocaba una
    /// reevaluación completa de SwiftUI: con música sonando, la consola se
    /// reconstruía decenas de veces por segundo y perdía pulsaciones de botón.
    /// Ahora viajan por este callback directo a las entidades de la escena.
    private(set) var soundingNodeIDs: Set<UUID> = []
    var onSoundingChanged: ((Set<UUID>) -> Void)?
    var onVisualAttack: ((UUID) -> Void)?
    /// Installed by the scene; tests and nonimmersive previews can use the transport clock.
    var scheduleAudio: ((SpatialAudioSession) -> TimeInterval?)?
    @Published private(set) var hasPendingTimingChanges = false
    @Published var studioSection: StudioSection = .transport
    @Published var selectedNodeID: UUID?
    @Published var statusMessage: String?
    @Published var spatialAudioSession: SpatialAudioSession?
    @Published var isSpatialTestScene = false
    @Published var testStep = 0
    @Published private(set) var activeLesson: MusicLesson?
    @Published private(set) var lessonHasPlayed = false
    private var learningBackup: (snapshot: CompositionEditSnapshot, history: CompositionHistory)?
    @Published private(set) var sceneContentRevision = 0
    @Published private(set) var undoLabel: String?
    @Published private(set) var redoLabel: String?
    @Published private(set) var recoveryAvailable = false
    @Published private(set) var saveStatus = "Sin cambios"
    @Published private(set) var recoveryProblem: String?
    @Published var connectionHint: String?
    @Published private(set) var onboardingProgress = 0
    private var recovery: RecoveryCoordinator?
    private var pendingRecovery: SessionRecovery?
    private var hasSessionEdits = false
    private var needsRecoveryWrite = false
    private var isRestoring = false
    /// Solo tiene valor cuando el motor de audio tiene algo que reportar.
    @Published var audioProblem: String?
    /// Estado vivo del motor en una línea, para la pestaña Reproducir.
    @Published var audioDiagnostics: String?
    let sequencer = Sequencer()
    let graphTransport = GraphTransport()
    private let storage: CompositionStorage
    private var pulseClearTasks: [UUID: Task<Void, Never>] = [:]
    private var previewClearTask: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    private var history = CompositionHistory()

    init(storage: CompositionStorage = CompositionStorage(), enableRecovery: Bool = false) {
        self.storage = storage
        nodes = []
        connections = []
        if enableRecovery {
            do {
                let coordinator = RecoveryCoordinator(storage: try storage.recoveryStorage())
                recovery = coordinator
                pendingRecovery = coordinator.storage.load()
                recoveryAvailable = pendingRecovery != nil
            } catch {
                recoveryProblem = "No se pudo preparar la recuperación: \(error.localizedDescription)"
            }
        }
        sequencer.objectWillChange
            .merge(with: graphTransport.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
    }

    private var editSnapshot: CompositionEditSnapshot {
        CompositionEditSnapshot(nodes: nodes, connections: connections, selectedNodeID: selectedNodeID,
            isSpatialTestScene: isSpatialTestScene, bpm: sequencer.bpm, loopPasses: graphTransport.loopPasses)
    }

    private func contentDidChange() {
        guard !isRestoring else { return }
        hasSessionEdits = true
        needsRecoveryWrite = true
        if recovery != nil { saveStatus = "Cambios pendientes" }
        recovery?.schedule { [weak self] in self?.flushRecovery() }
    }

    func flushRecovery() {
        guard hasSessionEdits, needsRecoveryWrite, let recovery else { return }
        do {
            try recovery.flush(SessionRecovery(version: 1, current: editSnapshot, history: history,
                lesson: activeLesson, original: learningBackup?.snapshot,
                originalHistory: learningBackup?.history, savedAt: Date()))
            needsRecoveryWrite = false
            saveStatus = "Sesión recuperable"
            recoveryProblem = nil
            pendingRecovery = nil
            recoveryAvailable = false
        } catch {
            recoveryProblem = "No se pudo guardar la recuperación: \(error.localizedDescription). Usa Guardar composición."
        }
    }

    func restoreRecoveredSession() {
        guard let saved = pendingRecovery else { return }
        stopPlayback()
        isRestoring = true
        apply(saved.current)
        history = saved.history
        // A process can end during a drag. Seal that transaction once, on recovery.
        history.end(at: editSnapshot)
        if let original = saved.original, let originalHistory = saved.originalHistory {
            learningBackup = (original, originalHistory)
        } else { learningBackup = nil }
        activeLesson = saved.lesson
        lessonHasPlayed = false
        refreshHistoryLabels()
        pendingRecovery = nil
        recoveryAvailable = false
        isRestoring = false
        hasSessionEdits = true
        needsRecoveryWrite = false
        onboardingProgress = nodes.isEmpty ? 0 : connections.contains { $0.sourceNodeID != nil } ? 2 : 1
        saveStatus = "Sesión recuperada"
        statusMessage = "Recuperamos tu sesión. Pulsa Reproducir cuando estés listo."
        studioSection = activeLesson == nil ? .transport : .learn
    }

    func setTempo(_ bpm: Double) {
        guard !graphTransport.isPlaying, bpm.isFinite else { return }
        let value = min(180, max(50, bpm.rounded()))
        guard value != sequencer.bpm else { return }
        recordUndo("Cambiar tempo")
        sequencer.bpm = value
        contentDidChange()
    }

    func setLoopPasses(_ count: Int) {
        guard !graphTransport.isPlaying else { return }
        let value = min(8, max(1, count))
        guard value != graphTransport.loopPasses else { return }
        recordUndo("Cambiar ciclos")
        graphTransport.loopPasses = value
        contentDidChange()
    }

    var selectedNode: SoundNode? {
        nodes.first { $0.id == selectedNodeID }
    }

    func node(id: UUID) -> SoundNode? {
        nodes.first { $0.id == id }
    }

    /// Tocar el nodo ya seleccionado lo suelta. Sin esto no había forma de
    /// quedarse sin selección desde dentro del espacio.
    func selectNode(id: UUID) {
        endParameterEdit()
        selectedNodeID = selectedNodeID == id ? nil : id
    }

    /// Selección desde un gesto que ya sabe a quién apunta (arrastrar, girar).
    /// Pasa por aquí y no por `selectedNodeID` a secas para que "seleccionado"
    /// y el inspector no puedan divergir según por dónde entres.
    func focusNode(id: UUID) {
        if selectedNodeID != id { endParameterEdit() }
        selectedNodeID = id
    }

    /// Único organismo que PLAY puede iniciar. El valor también sirve para que
    /// la UI explique el flujo sin deducirlo de una conexión cualquiera.
    var playEntryNodeID: UUID? {
        connections.first(where: { $0.sourceNodeID == nil })?.destinationNodeID
    }

    var playEntryNode: SoundNode? {
        playEntryNodeID.flatMap(node(id:))
    }

    /// Organismos a los que Play no llega por ningún camino. No suenan, y hasta
    /// ahora no había manera de darse cuenta salvo por el silencio.
    func unreachableNodeIDs() -> Set<UUID> {
        var reachable: Set<UUID> = []
        var pending = playEntryNodeID.map { [$0] } ?? []
        let outgoing = Dictionary(grouping: connections.compactMap { connection -> (UUID, UUID)? in
            guard let source = connection.sourceNodeID else { return nil }
            return (source, connection.destinationNodeID)
        }, by: { $0.0 })

        while let current = pending.popLast() {
            guard reachable.insert(current).inserted else { continue }
            pending.append(contentsOf: outgoing[current, default: []].map(\.1))
        }
        return Set(nodes.map(\.id)).subtracting(reachable)
    }

    // MARK: - Deshacer

    var canUndo: Bool {
        !history.undo.isEmpty || history.transaction.map { !$0.snapshot.hasSameContent(as: editSnapshot) } == true
    }
    var canRedo: Bool {
        !history.redo.isEmpty && history.transaction.map { $0.snapshot.hasSameContent(as: editSnapshot) } != false
    }

    private func refreshHistoryLabels() {
        undoLabel = history.transaction?.label ?? history.undo.last?.label
        redoLabel = history.redo.last?.label
    }

    private func recordUndo(_ label: String) {
        history.record(label, at: editSnapshot)
        refreshHistoryLabels()
    }

    func beginParameterEdit(_ label: String = "Ajustar sonido") {
        history.begin(label, at: editSnapshot)
        refreshHistoryLabels()
    }

    func endParameterEdit() {
        if let edit = history.transaction, !edit.snapshot.hasSameContent(as: editSnapshot) {
            needsRecoveryWrite = true
        }
        history.end(at: editSnapshot)
        refreshHistoryLabels()
        flushRecovery()
    }

    func undo() {
        guard let entry = history.takeUndo(at: editSnapshot) else { return }
        apply(entry.snapshot)
        refreshHistoryLabels()
        statusMessage = "Se deshizo: \(entry.label.lowercased())."
        flushRecovery()
    }

    func redo() {
        guard let entry = history.takeRedo(at: editSnapshot) else { return }
        apply(entry.snapshot)
        refreshHistoryLabels()
        statusMessage = "Se rehizo: \(entry.label.lowercased())."
        flushRecovery()
    }

    private func apply(_ entry: CompositionEditSnapshot) {
        let sameNodes = nodes.count == entry.nodes.count && zip(nodes, entry.nodes).allSatisfy { $0.id == $1.id && $0.type == $1.type }
        let sameEdges = connections.count == entry.connections.count && zip(connections, entry.connections).allSatisfy {
            $0.id == $1.id && $0.sourceNodeID == $1.sourceNodeID && $0.destinationNodeID == $1.destinationNodeID
        }
        if !sameNodes || !sameEdges || sequencer.bpm != entry.bpm || graphTransport.loopPasses != entry.loopPasses {
            stopPlayback()
        } else if graphTransport.isPlaying && connections != entry.connections {
            hasPendingTimingChanges = true
        }
        sequencer.bpm = entry.bpm
        graphTransport.loopPasses = entry.loopPasses
        nodes = entry.nodes
        connections = entry.connections
        selectedNodeID = entry.selectedNodeID
        isSpatialTestScene = entry.isSpatialTestScene
        sceneContentRevision &+= 1
    }

    func toggleSelectedNode() {
        guard let id = selectedNodeID else { return }
        toggleNode(id: id)
    }

    func toggleNode(id: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        recordUndo("Cambiar silencio")
        nodes[index].isActive.toggle()
    }

    func clearSelection() {
        endParameterEdit()
        selectedNodeID = nil
    }

    func deleteSelectedNode() {
        endParameterEdit()
        guard let id = selectedNodeID, let node = node(id: id) else { return }
        recordUndo("Eliminar \(node.name)")
        stopPlayback()
        nodes.removeAll { $0.id == id }
        connections.removeAll { $0.sourceNodeID == id || $0.destinationNodeID == id }
        selectedNodeID = nil
        sceneContentRevision &+= 1
        statusMessage = "\(node.name) eliminado."
    }

    func removeConnection(id: UUID) {
        endParameterEdit()
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        recordUndo("Cortar conexión")
        let destinationID = connections[index].destinationNodeID
        stopPlayback()
        connections.remove(at: index)
        recalculateDurationSummary(for: destinationID)
        statusMessage = "Conexión cortada."
    }

    @discardableResult
    func connect(sourceID: UUID?, destinationID: UUID) -> Bool {
        endParameterEdit()
        guard canConnect(sourceID: sourceID, destinationID: destinationID) else { return false }
        recordUndo("Crear conexión")
        stopPlayback()
        appendConnection(sourceID: sourceID, destinationID: destinationID)
        if sourceID != nil, activeLesson == nil, nodes.count - unreachableNodeIDs().count >= 2 { onboardingProgress = max(onboardingProgress, 2) }
        let sourceName = sourceID.flatMap { node(id: $0)?.name } ?? "Play"
        let destinationName = node(id: destinationID)?.name ?? "organismo"
        statusMessage = "Conexión creada: \(sourceName) → \(destinationName)."
        return true
    }

    /// Un hilo une una rama libre a la ruta que ya nace de Play, aunque la
    /// mano empiece por la rama libre. Entre nodos alcanzables se conserva la
    /// dirección del gesto para permitir convergencias y ciclos explícitos.
    struct ConnectionProposal {
        let sourceID: UUID?
        let destinationID: UUID?
        let isValid: Bool
        let message: String
    }

    func connectionProposal(from source: ConnectionEndpoint, to target: ConnectionEndpoint) -> ConnectionProposal {
        let sourceID: UUID?
        let destinationID: UUID
        switch (source, target) {
        case (.play, .node(let id)), (.node(let id), .play):
            sourceID = nil
            destinationID = id
            if playEntryNodeID != nil {
                return ConnectionProposal(sourceID: nil, destinationID: id, isValid: false,
                    message: "Play ya tiene una entrada. Corta esa conexión antes de elegir otra.")
            }
        case (.node(let a), .node(let b)):
            let unreachable = unreachableNodeIDs()
            let reverse = unreachable.contains(a) && !unreachable.contains(b)
            sourceID = reverse ? b : a
            destinationID = reverse ? a : b
        case (.play, .play):
            return ConnectionProposal(sourceID: nil, destinationID: nil, isValid: false,
                message: "Elige un organismo como destino.")
        }
        let route = "\(sourceID.flatMap { node(id: $0)?.name } ?? "Play") → \(node(id: destinationID)?.name ?? "Destino")"
        let valid = canConnect(sourceID: sourceID, destinationID: destinationID)
        return ConnectionProposal(sourceID: sourceID, destinationID: destinationID, isValid: valid,
            message: valid ? "Soltar para conectar: \(route)" : "Conexión no disponible o duplicada: \(route)")
    }

    @discardableResult
    func connectByDragging(from source: ConnectionEndpoint, to target: ConnectionEndpoint) -> Bool {
        let proposal = connectionProposal(from: source, to: target)
        guard proposal.isValid, let id = proposal.destinationID else {
            statusMessage = proposal.message
            return false
        }
        return connect(sourceID: proposal.sourceID, destinationID: id)
    }

    private func canConnect(sourceID: UUID?, destinationID: UUID) -> Bool {
        guard sourceID != destinationID,
              position(of: destinationID) != nil,
              !connections.contains(where: { $0.sourceNodeID == sourceID && $0.destinationNodeID == destinationID })
        else { return false }

        if let sourceID {
            return position(of: sourceID) != nil
        }
        // Invariante central del producto: PLAY tiene exactamente una salida.
        return playEntryNodeID == nil
    }

    /// Alta sin punto de retorno propio: `createNode` ya registró el suyo y una
    /// sola acción del usuario debe deshacerse de una sola vez.
    private func appendConnection(sourceID: UUID?, destinationID: UUID) {
        let sourcePosition = sourceID.flatMap(position(of:)) ?? Self.playNodePosition
        guard let destinationPosition = position(of: destinationID) else { return }
        connections.append(SoundConnection(
            sourceNodeID: sourceID,
            destinationNodeID: destinationID,
            durationBeats: SpatialParameterMapper.durationBeats(from: sourcePosition, to: destinationPosition)
        ))
        recalculateDurationSummary(for: destinationID)
    }

    /// Cuánto sostiene cada organismo: hasta que arranca el siguiente al que
    /// apunta. Con varias ramas manda la más corta, porque es la primera que
    /// releva a este nodo. Sin salidas, la nota se apaga por su cuenta.
    func sustainBeatsByNode() -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for connection in connections {
            guard let sourceID = connection.sourceNodeID else { continue }
            let beats = max(0.0625, connection.durationBeats)
            result[sourceID] = min(result[sourceID] ?? .greatestFiniteMagnitude, beats)
        }
        return result
    }

    /// Destino más cercano al punto donde se soltó el hilo. El radio generoso
    /// evita exigir puntería fina con las manos a un metro de distancia.
    func nearestNode(to point: SIMD3<Float>, excluding excludedID: UUID?, within radius: Float) -> UUID? {
        nodes
            .filter { $0.id != excludedID }
            .map { ($0.id, simd_distance(point, [$0.positionX, $0.positionY, $0.positionZ])) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?
            .0
    }

    @discardableResult
    func createNextNode(at position: SIMD3<Float>? = nil) -> UUID {
        let type = SoundNodeType.allCases[nodes.count % SoundNodeType.allCases.count]
        return createNode(of: type, at: position)
    }

    /// Alta de un organismo.
    ///
    /// PLAY conecta automáticamente el primer organismo y solo el primero. Los
    /// siguientes nacen libres: conectarlos es una decisión explícita mediante
    /// el hilo que se arrastra entre organismos.
    @discardableResult
    func createNode(
        of type: SoundNodeType,
        at position: SIMD3<Float>? = nil
    ) -> UUID {
        endParameterEdit()
        guard nodes.count < SoundNode.maximumCount else {
            statusMessage = "Límite de 32 sonidos alcanzado. Elimina uno para añadir otro."
            return selectedNodeID ?? nodes.last!.id
        }
        let finalPosition = clamped(position ?? SpatialNodePlacement.position(for: type, among: nodes, play: Self.playNodePosition))
        recordUndo("Añadir \(SoundNodeType.displayName(for: type))")
        let name = uniqueName(for: type)
        let node = SoundNode(
            name: name,
            type: type,
            volume: SpatialParameterMapper.volume(forDepth: finalPosition.z),
            pitch: SpatialParameterMapper.pitch(forHeight: finalPosition.y),
            positionX: finalPosition.x,
            positionY: finalPosition.y,
            positionZ: finalPosition.z
        )
        nodes.append(node)
        if activeLesson == nil { onboardingProgress = max(onboardingProgress, 1) }
        let startsFromPlay = playEntryNodeID == nil
        if startsFromPlay, canConnect(sourceID: nil, destinationID: node.id) {
            appendConnection(sourceID: nil, destinationID: node.id)
        }
        selectedNodeID = node.id
        sceneContentRevision &+= 1
        statusMessage = startsFromPlay
            ? "\(name) es la única entrada desde Play."
            : "\(name) agregado sin conexión. Une organismos arrastrando el punto luminoso."
        return node.id
    }

    /// Tres organismos llamados "Kick" son indistinguibles en el selector de
    /// origen y en el inspector, que es justo donde hay que poder elegir uno.
    private func uniqueName(for type: SoundNodeType) -> String {
        let base = SoundNodeType.displayName(for: type)
        guard nodes.contains(where: { $0.name == base }) else { return base }
        var index = 2
        while nodes.contains(where: { $0.name == "\(base) \(index)" }) { index += 1 }
        return "\(base) \(index)"
    }

    /// Rescata un organismo únicamente cuando PLAY se quedó sin entrada. Si ya
    /// existe una, la rama debe unirse desde otro organismo.
    func connectToPlay(id: UUID) {
        guard node(id: id) != nil else { return }
        guard playEntryNodeID == nil else {
            statusMessage = "Play ya inicia un organismo. Conecta esta rama desde otro organismo."
            return
        }
        _ = connect(sourceID: nil, destinationID: id)
    }

    func moveNode(id: UUID, to position: SIMD3<Float>) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let value = clamped(position)
        var updated = nodes[index]
        updated.positionX = value.x
        updated.positionY = value.y
        updated.positionZ = value.z
        if !updated.isSoundLocked {
            updated.pitch = SpatialParameterMapper.pitch(forHeight: value.y)
            updated.volume = SpatialParameterMapper.volume(forDepth: value.z)
        }
        guard updated != nodes[index] else { return }
        recordUndo("Mover sonido")
        nodes[index] = updated
        if !updated.isSoundLocked { recalculateConnections(touching: id) }
    }

    func toggleSoundLock(id: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        recordUndo("Fijar sonido")
        nodes[index].isSoundLocked.toggle()
        statusMessage = nodes[index].isSoundLocked
            ? "\(nodes[index].name): sonido fijo. Muévelo libremente para ordenar."
            : "\(nodes[index].name): la posición vuelve a controlar su sonido."
    }

    /// La rotación se acumula sobre el valor que el nodo tenía al empezar el
    /// gesto, para que soltar y volver a girar continúe en vez de reiniciar.
    /// Orienta el organismo y nada más: los efectos se ajustan con los faders
    /// del gizmo o con la consola, así que colocar un cuerpo como uno quiera
    /// ya no borra un reverb ajustado al 1 %.
    func rotationEditBegan(id: UUID) {
        focusNode(id: id)
        beginParameterEdit("Girar organismo")
    }

    func rotateNode(id: UUID, addingTo origin: SIMD3<Float>, delta: SIMD3<Float>) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        func safeAngle(_ value: Float, fallback: Float) -> Float {
            guard value.isFinite else { return fallback.isFinite ? fallback : 0 }
            return value.truncatingRemainder(dividingBy: 2 * .pi)
        }
        let vector = SIMD3<Float>(
            safeAngle(origin.x + delta.x, fallback: origin.x),
            safeAngle(origin.y + delta.y, fallback: origin.y),
            safeAngle(origin.z + delta.z, fallback: origin.z)
        )
        var updated = nodes[index]
        updated.rotationX = vector.x
        updated.rotationY = vector.y
        updated.rotationZ = vector.z
        if updated != nodes[index] {
            recordUndo("Girar organismo")
            nodes[index] = updated
        }
    }

    func togglePlayback() {
        if graphTransport.isPlaying {
            stopPlayback()
            statusMessage = "Reproducción detenida."
            return
        }

        guard playEntryNodeID != nil else {
            statusMessage = nodes.isEmpty
                ? "Añade el primer sonido: será la única entrada desde Play."
                : "Play no tiene entrada. Elige un organismo y conéctalo con Play."
            return
        }
        let reachable = Set(nodes.map(\.id)).subtracting(unreachableNodeIDs())
        guard nodes.contains(where: { reachable.contains($0.id) && $0.isActive }) else {
            statusMessage = "La ruta que nace de Play no contiene organismos activos."
            return
        }

        // Tolerante a repetidos: un archivo cargado a mano con dos nodos del
        // mismo identificador hacía caer la app en el acto, y con Play.
        let nodesByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let didStart = graphTransport.start(
            nodes: nodes,
            connections: connections,
            bpm: sequencer.bpm,
            scheduleUsesHostClock: true,
            onSchedule: { [weak self] timeline, secondsPerBeat, loopDurationBeats in
                guard let self else { return nil }
                let session = SpatialAudioSession(
                    nodes: Array(nodesByID.values),
                    events: timeline,
                    sustainBeats: self.sustainBeatsByNode(),
                    secondsPerBeat: secondsPerBeat,
                    loopDurationBeats: loopDurationBeats
                )
                self.spatialAudioSession = session
                if let scheduleAudio = self.scheduleAudio {
                    guard let start = scheduleAudio(session) else { return nil }
                    return start
                }
                return PlaybackClock.seconds(forHostTime: session.startHostTime)
            },
            onVisualTrigger: { [weak self] node in
                guard self?.node(id: node.id)?.isActive == true else { return }
                self?.triggerVisualPulse(for: node.id)
            }
        )
        if didStart {
            if activeLesson != nil { lessonHasPlayed = true }
            else if onboardingProgress >= 2 { onboardingProgress = 3 }
            statusMessage = "Loop activo desde \(playEntryNode?.name ?? "la entrada"). Pulsa Detener para terminar."
        } else {
            spatialAudioSession = nil
            statusMessage = audioProblem == nil
                ? "La ruta es demasiado compleja. Reduce las vueltas internas o corta un ciclo antes de reproducir."
                : "La salida de audio aún no está lista. Vuelve a pulsar Reproducir."
        }
    }

    func previewSelectedNode() {
        guard let node = selectedNode, node.isActive else {
            statusMessage = "Selecciona un nodo activo para escucharlo."
            return
        }
        stopPlayback()
        let session = SpatialAudioSession(
            nodes: [node],
            events: [GraphPlaybackEvent(nodeID: node.id, beat: 0)],
            // El preview usa el mismo sostenido que tendría al reproducirse.
            sustainBeats: sustainBeatsByNode().filter { $0.key == node.id },
            secondsPerBeat: 60 / max(sequencer.bpm, 1),
            leadInSeconds: 0.2
        )
        spatialAudioSession = session
        let effectiveStart: TimeInterval
        if let scheduleAudio {
            guard let start = scheduleAudio(session) else {
                spatialAudioSession = nil
                statusMessage = "La salida de audio aún no está lista. Vuelve a pulsar Escuchar."
                return
            }
            effectiveStart = start
        } else { effectiveStart = PlaybackClock.seconds(forHostTime: session.startHostTime) }
        let visualDelay = max(0, effectiveStart - PlaybackClock.now)
        triggerVisualPulse(for: node.id, delay: visualDelay)
        statusMessage = "Preview espacial: mueve la cabeza para localizar \(node.name)."

        previewClearTask?.cancel()
        previewClearTask = Task { @MainActor [weak self] in
            let held = (session.sustainBeats[node.id] ?? 1.2) * session.secondsPerBeat
            let duration = VoiceSynthesis.duration(for: node.type, sustainSeconds: held)
            let delayTail = node.delay > 0 ? 2 * (0.07 + Double(node.delay) * 0.48) : 0
            try? await Task.sleep(for: .seconds(visualDelay + duration + max(0.4, delayTail)))
            guard let self, !Task.isCancelled, self.spatialAudioSession?.id == session.id else { return }
            self.spatialAudioSession = nil
        }
    }

    func loadSpatialTestScene() {
        endParameterEdit()
        finishLesson()
        recordUndo("Abrir demo")
        stopPlayback()
        sequencer.bpm = 92
        graphTransport.loopPasses = 2

        let kick = testNode("Kick frontal", .kick, position: [0, 1.18, 0.78])
        let bass = testNode("Bass izquierdo", .bass, position: [-1.15, 1.0, -0.18])
        let hat = testNode("Hi-hat derecho", .hiHat, position: [1.12, 1.62, 0.12])
        let pad = testNode("Pad alto y lejano", .pad, position: [0.12, 2.15, -1.35],
                           rotation: [.pi * 0.62, 0, 0], effects: (reverb: 0.62, delay: 0, distortion: 0))
        let fx = testNode("FX posterior", .fx, position: [0, 1.32, 2.28],
                          rotation: [0, .pi * 0.48, .pi * 0.22], effects: (reverb: 0, delay: 0.48, distortion: 0.22))
        nodes = [kick, bass, hat, pad, fx]

        connections = [
            testConnection(from: nil, to: kick),
            testConnection(from: kick, to: bass),
            testConnection(from: kick, to: hat),
            testConnection(from: bass, to: pad),
            testConnection(from: hat, to: pad),
            testConnection(from: pad, to: fx)
        ]
        recalculateAllConnections()
        selectedNodeID = kick.id
        isSpatialTestScene = true
        testStep = 0
        sceneContentRevision &+= 1
        statusMessage = "Prueba lista: pulsa Play y localiza el FX detrás de ti."
    }

    func advanceTestStep() {
        testStep = min(testStep + 1, Self.spatialTestInstructions.count - 1)
    }

    func previousTestStep() {
        testStep = max(testStep - 1, 0)
    }

    func closeTestGuide() {
        isSpatialTestScene = false
    }

    static let spatialTestInstructions = [
        "Pulsa Play. Debes oír Kick al frente y FX detrás; gira la cabeza para confirmar la localización.",
        "Selecciona Bass o Hi-hat y pulsa Escuchar. Compara izquierda y derecha sin mover el nodo.",
        "Arrastra un nodo arriba/abajo y cerca/lejos. Repite Escuchar para comprobar pitch, volumen y distancia.",
        "Selecciona Pad o FX y sube sus faders de reverb, delay y distorsión: la barra sobre el cuerpo confirma el nivel.",
        "Tira del punto luminoso bajo un organismo y suelta el hilo sobre otro para conectarlos. Toca una conexión para cortarla.",
        "Detén, vuelve a reproducir y comprueba que controles, ondas y audio permanecen sincronizados."
    ]

    func stopPlayback() {
        hasPendingTimingChanges = false
        graphTransport.stop()
        spatialAudioSession = nil
        previewClearTask?.cancel()
        previewClearTask = nil
        pulseClearTasks.values.forEach { $0.cancel() }
        pulseClearTasks = [:]
        clearSounding()
    }

    func save() {
        guard activeLesson == nil else {
            statusMessage = "Termina la práctica para volver a guardar tu composición."
            return
        }
        do {
            try storage.save(snapshot)
            flushRecovery()
            saveStatus = "Composición guardada"
            statusMessage = "Composición espacial guardada."
        } catch {
            statusMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    func load() {
        endParameterEdit()
        do {
            let composition = try storage.load().sanitized()
            finishLesson()
            recordUndo("Cargar composición")
            stopPlayback()
            sequencer.bpm = composition.bpm
            graphTransport.loopPasses = composition.loopPasses
            nodes = composition.nodes
            connections = composition.connections
            selectedNodeID = nil
            recalculateAllConnections()
            sceneContentRevision &+= 1
            statusMessage = "Composición espacial cargada."
            isSpatialTestScene = false
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reset() {
        startNewComposition(message: "Lienzo espacial restaurado.")
    }

    func startNewComposition(message: String = "Nueva pista lista. Elige un sonido del cajón para comenzar.") {
        endParameterEdit()
        finishLesson()
        if !nodes.isEmpty { recordUndo("Vaciar el lienzo") }
        stopPlayback()
        nodes = []
        connections = []
        selectedNodeID = nil
        statusMessage = message
        isSpatialTestScene = false
        testStep = 0
        sceneContentRevision &+= 1
    }

    var snapshot: Composition {
        Composition(title: "Anatomía del Sonido", bpm: sequencer.bpm, steps: Sequencer.totalSteps, nodes: nodes, connections: connections, loopPasses: graphTransport.loopPasses)
    }

    private func triggerVisualPulse(for nodeID: UUID, delay: TimeInterval = 0) {
        pulseClearTasks[nodeID]?.cancel()
        pulseClearTasks[nodeID] = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.onVisualAttack?(nodeID)
            self?.setSounding(nodeID, isSounding: true)
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.setSounding(nodeID, isSounding: false)
            self?.pulseClearTasks[nodeID] = nil
        }
    }

    private func setSounding(_ nodeID: UUID, isSounding: Bool) {
        let changed = isSounding
            ? soundingNodeIDs.insert(nodeID).inserted
            : soundingNodeIDs.remove(nodeID) != nil
        guard changed else { return }
        onSoundingChanged?(soundingNodeIDs)
    }

    private func clearSounding() {
        guard !soundingNodeIDs.isEmpty else { return }
        soundingNodeIDs = []
        onSoundingChanged?(soundingNodeIDs)
    }

    private func recalculateAllConnections() { updateConnectionTimings(touching: nil) }

    private func recalculateConnections(touching nodeID: UUID) { updateConnectionTimings(touching: nodeID) }

    /// Cada gesto publica como máximo una colección de conexiones y una de
    /// resúmenes. Antes enviaba una invalidación de toda la UI por cada arista.
    private func updateConnectionTimings(touching nodeID: UUID?) {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var updatedConnections = connections
        var rhythmChanged = false
        for index in updatedConnections.indices {
            let edge = updatedConnections[index]
            if let nodeID, edge.sourceNodeID != nodeID && edge.destinationNodeID != nodeID { continue }
            guard edge.usesSpatialTiming,
                  let destination = byID[edge.destinationNodeID], !destination.isSoundLocked,
                  edge.sourceNodeID.flatMap({ byID[$0] })?.isSoundLocked != true else { continue }
            let source = edge.sourceNodeID.flatMap { byID[$0] }
            let origin = source.map { SIMD3<Float>($0.positionX, $0.positionY, $0.positionZ) } ?? Self.playNodePosition
            let beats = SpatialParameterMapper.durationBeats(from: origin,
                to: [destination.positionX, destination.positionY, destination.positionZ])
            if abs(beats - edge.durationBeats) > 0.0001 {
                updatedConnections[index].durationBeats = beats
                if edge.sourceNodeID != nil { rhythmChanged = true }
            }
        }
        if updatedConnections != connections { connections = updatedConnections }
        if rhythmChanged && graphTransport.isPlaying && !hasPendingTimingChanges { hasPendingTimingChanges = true }
        let incoming = Dictionary(grouping: connections, by: \.destinationNodeID)
        var updatedNodes = nodes
        for index in updatedNodes.indices {
            updatedNodes[index].durationBeats = incoming[updatedNodes[index].id]?.map(\.durationBeats).min() ?? 1
        }
        if updatedNodes != nodes { nodes = updatedNodes }
    }

    /// La duración nace de la distancia entre extremos, así que un extremo con
    /// el sonido fijo también congela el tiempo de su conexión. De otro modo,
    /// recolocar un nodo "fijo" seguiría alterando el ritmo.
    private func recalculateConnection(at index: Int) {
        let connection = connections[index]
        let endpointIsLocked = [connection.sourceNodeID, connection.destinationNodeID]
            .compactMap { $0 }
            .contains { node(id: $0)?.isSoundLocked == true }
        guard !endpointIsLocked, connection.usesSpatialTiming else { return }

        let source = connection.sourceNodeID.flatMap(position(of:)) ?? Self.playNodePosition
        guard let destination = position(of: connection.destinationNodeID) else { return }
        let beats = SpatialParameterMapper.durationBeats(from: source, to: destination)
        if abs(connections[index].durationBeats - beats) > 0.0001 {
            if graphTransport.isPlaying && !hasPendingTimingChanges {
                hasPendingTimingChanges = true
            }
            connections[index].durationBeats = beats
        }
    }

    private func recalculateDurationSummary(for nodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].durationBeats = connections.filter { $0.destinationNodeID == nodeID }.map(\.durationBeats).min() ?? 1
    }

    func setConnectionBeats(id: UUID, beats: Double) {
        guard beats.isFinite, let index = connections.firstIndex(where: { $0.id == id }),
              connections[index].sourceNodeID != nil else { return }
        let value = max(0.0625, min(beats, 32))
        guard connections[index].usesSpatialTiming || connections[index].durationBeats != value else { return }
        recordUndo("Ajustar tiempo")
        if graphTransport.isPlaying { hasPendingTimingChanges = true }
        connections[index].usesSpatialTiming = false
        connections[index].durationBeats = value
        recalculateDurationSummary(for: connections[index].destinationNodeID)
        statusMessage = graphTransport.isPlaying
            ? "Tiempo preparado: \(String(format: "%.2f", value)) beats para el próximo Play."
            : "Tiempo fijo: \(String(format: "%.2f", value)) beats."
    }

    func useSpatialTiming(id: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        recordUndo("Usar tiempo espacial")
        if graphTransport.isPlaying { hasPendingTimingChanges = true }
        connections[index].usesSpatialTiming = true
        recalculateConnection(at: index)
        recalculateDurationSummary(for: connections[index].destinationNodeID)
        statusMessage = "La distancia controla el tiempo; un extremo con sonido fijo lo mantiene congelado."
    }

    func setPitch(id: UUID, semitones: Float) {
        guard semitones.isFinite, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        guard nodes[index].pitch != max(-24, min(semitones.rounded(), 24)) else { return }
        recordUndo("Afinar sonido")
        nodes[index].pitch = max(-24, min(semitones.rounded(), 24))
    }

    func setSoundParameter(id: UUID, parameter: SoundParameter, value: Float) {
        guard value.isFinite, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let amount = max(0, min(value, 1))
        var updated = nodes[index]
        // Subir un efecto ya no tumba el organismo. La orientación es del
        // espacio —la elige la persona y ahí se queda— y el nivel del efecto
        // lo enseña su barra sobre el cuerpo y su fader en el gizmo, que
        // además distinguen los tres efectos entre sí. Con el giro como
        // indicador, 60 % de reverb y 60 % de delay dejaban el mismo cuerpo
        // torcido y no había forma de saber cuál estaba sonando.
        switch parameter {
        case .volume: updated.volume = amount
        case .reverb: updated.reverb = amount
        case .delay: updated.delay = amount
        case .distortion: updated.distortion = amount
        }
        if updated != nodes[index] {
            recordUndo("Ajustar \(parameter.title)")
            nodes[index] = updated
        }
    }

    func beginLesson(_ lesson: MusicLesson) {
        endParameterEdit()
        if learningBackup == nil {
            learningBackup = (editSnapshot, history)
        }
        stopPlayback()
        let practice = lesson.composition()
        nodes = practice.nodes
        connections = practice.connections
        sequencer.bpm = practice.bpm
        graphTransport.loopPasses = practice.loopPasses
        selectedNodeID = nodes.first?.id
        isSpatialTestScene = false
        history = CompositionHistory()
        refreshHistoryLabels()
        activeLesson = lesson
        lessonHasPlayed = false
        sceneContentRevision &+= 1
        statusMessage = "Práctica lista. Tu composición está reservada hasta que termines."
        flushRecovery()
    }

    func finishLesson() {
        guard let backup = learningBackup else { return }
        stopPlayback()
        apply(backup.snapshot)
        history = backup.history
        refreshHistoryLabels()
        learningBackup = nil
        activeLesson = nil
        lessonHasPlayed = false
        sceneContentRevision &+= 1
        statusMessage = "De vuelta en tu composición."
        flushRecovery()
    }

    private func position(of nodeID: UUID) -> SIMD3<Float>? {
        nodes.first(where: { $0.id == nodeID }).map { [$0.positionX, $0.positionY, $0.positionZ] }
    }

    /// Mismos límites que aplica `moveNode`, expuestos para que un arrastre
    /// pueda mover la entidad a frame rate sin desviarse de donde acabará.
    func clampedPosition(_ value: SIMD3<Float>) -> SIMD3<Float> {
        clamped(value)
    }

    private func clamped(_ value: SIMD3<Float>) -> SIMD3<Float> {
        // `min`/`max` propagan NaN en vez de descartarlo, y un NaN aquí llega
        // hasta `Int(pitch)`, que aborta el proceso. Un gesto en el límite del
        // seguimiento de manos basta para producirlo.
        func axis(_ value: Float, _ lower: Float, _ upper: Float, fallback: Float) -> Float {
            guard value.isFinite else { return fallback }
            return max(lower, min(value, upper))
        }
        return [
            axis(value.x, -2.4, 2.4, fallback: 0),
            axis(value.y, 0.35, 2.5, fallback: SpatialParameterMapper.neutralHeight),
            axis(value.z, -2.0, 2.4, fallback: 0)
        ]
    }

    private func testNode(
        _ name: String,
        _ type: SoundNodeType,
        position: SIMD3<Float>,
        rotation: SIMD3<Float> = .zero,
        effects: (reverb: Float, delay: Float, distortion: Float) = (0, 0, 0)
    ) -> SoundNode {
        return SoundNode(
            name: name,
            type: type,
            volume: SpatialParameterMapper.volume(forDepth: position.z),
            pitch: SpatialParameterMapper.pitch(forHeight: position.y),
            positionX: position.x,
            positionY: position.y,
            positionZ: position.z,
            rotationX: rotation.x,
            rotationY: rotation.y,
            rotationZ: rotation.z,
            reverb: effects.reverb,
            delay: effects.delay,
            distortion: effects.distortion
        )
    }

    private func testConnection(from source: SoundNode?, to destination: SoundNode) -> SoundConnection {
        let sourcePosition = source.map { SIMD3<Float>($0.positionX, $0.positionY, $0.positionZ) } ?? Self.playNodePosition
        let destinationPosition = SIMD3<Float>(destination.positionX, destination.positionY, destination.positionZ)
        return SoundConnection(
            sourceNodeID: source?.id,
            destinationNodeID: destination.id,
            durationBeats: SpatialParameterMapper.durationBeats(from: sourcePosition, to: destinationPosition)
        )
    }
}
