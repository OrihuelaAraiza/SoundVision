import Combine
import Foundation
import simd

enum SoundParameter { case volume, reverb, delay, distortion }

enum StudioSection: Hashable { case transport, sounds, node, learn }

@MainActor
final class CompositionState: ObservableObject {
    nonisolated static let playNodePosition = SIMD3<Float>(0, SpatialParameterMapper.neutralHeight, 0)

    @Published var nodes: [SoundNode]
    @Published var connections: [SoundConnection]
    @Published var isImmersiveSpaceOpen = false
    /// Los destellos de reproducción **no** se publican. Cada nota provocaba una
    /// reevaluación completa de SwiftUI: con música sonando, la consola se
    /// reconstruía decenas de veces por segundo y perdía pulsaciones de botón.
    /// Ahora viajan por este callback directo a las entidades de la escena.
    private(set) var soundingNodeIDs: Set<UUID> = []
    var onSoundingChanged: ((Set<UUID>) -> Void)?
    @Published private(set) var hasPendingTimingChanges = false
    @Published var studioSection: StudioSection = .transport
    @Published var selectedNodeID: UUID?
    @Published var statusMessage: String?
    @Published var spatialAudioSession: SpatialAudioSession?
    @Published var isSpatialTestScene = false
    @Published var testStep = 0
    @Published private(set) var activeLesson: MusicLesson?
    @Published private(set) var lessonHasPlayed = false
    private var learningBackup: (composition: Composition, selectedID: UUID?, undo: [UndoEntry], isDemo: Bool)?
    @Published private(set) var sceneContentRevision = 0
    @Published private(set) var undoLabel: String?
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
    private var undoStack: [UndoEntry] = []

    private struct UndoEntry {
        let label: String
        let nodes: [SoundNode]
        let connections: [SoundConnection]
        let selectedNodeID: UUID?
        let isSpatialTestScene: Bool
        let bpm: Double
        let loopPasses: Int
    }

    init(storage: CompositionStorage = CompositionStorage()) {
        self.storage = storage
        nodes = []
        connections = []

        sequencer.objectWillChange
            .merge(with: graphTransport.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
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
        selectedNodeID = selectedNodeID == id ? nil : id
    }

    /// Selección desde un gesto que ya sabe a quién apunta (arrastrar, girar).
    /// Pasa por aquí y no por `selectedNodeID` a secas para que "seleccionado"
    /// y el inspector no puedan divergir según por dónde entres.
    func focusNode(id: UUID) {
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

    var canUndo: Bool { !undoStack.isEmpty }

    /// Toda acción que destruye o crea estructura deja un punto de retorno, de
    /// modo que ningún borrado necesita un diálogo de confirmación previo.
    private func recordUndo(_ label: String) {
        undoStack.append(UndoEntry(
            label: label,
            nodes: nodes,
            connections: connections,
            selectedNodeID: selectedNodeID,
            isSpatialTestScene: isSpatialTestScene,
            bpm: sequencer.bpm, loopPasses: graphTransport.loopPasses
        ))
        if undoStack.count > 24 { undoStack.removeFirst() }
        undoLabel = label
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
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
        undoLabel = undoStack.last?.label
        sceneContentRevision &+= 1
        statusMessage = "Se deshizo: \(entry.label.lowercased())."
    }

    func toggleSelectedNode() {
        guard let id = selectedNodeID else { return }
        toggleNode(id: id)
    }

    func toggleNode(id: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].isActive.toggle()
    }

    func clearSelection() {
        selectedNodeID = nil
    }

    func deleteSelectedNode() {
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
        guard canConnect(sourceID: sourceID, destinationID: destinationID) else { return false }
        recordUndo("Crear conexión")
        stopPlayback()
        appendConnection(sourceID: sourceID, destinationID: destinationID)
        let sourceName = sourceID.flatMap { node(id: $0)?.name } ?? "Play"
        let destinationName = node(id: destinationID)?.name ?? "organismo"
        statusMessage = "Conexión creada: \(sourceName) → \(destinationName)."
        return true
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
        guard nodes.count < SoundNode.maximumCount else {
            statusMessage = "Límite de 32 sonidos alcanzado. Elimina uno para añadir otro."
            return selectedNodeID ?? nodes.last!.id
        }
        let finalPosition = clamped(position ?? freeSpawnPosition())
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
        nodes[index] = updated
        if !updated.isSoundLocked { recalculateConnections(touching: id) }
    }

    func toggleSoundLock(id: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].isSoundLocked.toggle()
        statusMessage = nodes[index].isSoundLocked
            ? "\(nodes[index].name): sonido fijo. Muévelo libremente para ordenar."
            : "\(nodes[index].name): la posición vuelve a controlar su sonido."
    }

    /// La rotación se acumula sobre el valor que el nodo tenía al empezar el
    /// gesto, para que soltar y volver a girar continúe en vez de reiniciar.
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
        let effects = SpatialParameterMapper.effects(from: vector)
        updated.reverb = effects.reverb
        updated.delay = effects.delay
        updated.distortion = effects.distortion
        if updated != nodes[index] { nodes[index] = updated }
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
                return session.leadInSeconds
            },
            onVisualTrigger: { [weak self] node in
                guard self?.node(id: node.id)?.isActive == true else { return }
                self?.triggerVisualPulse(for: node.id)
            }
        )
        if didStart {
            if activeLesson != nil { lessonHasPlayed = true }
            statusMessage = "Loop activo desde \(playEntryNode?.name ?? "la entrada"). Pulsa Detener para terminar."
        } else {
            spatialAudioSession = nil
            statusMessage = "La ruta es demasiado compleja. Reduce las vueltas internas o corta un ciclo antes de reproducir."
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
        triggerVisualPulse(for: node.id, delay: session.leadInSeconds)
        statusMessage = "Preview espacial: mueve la cabeza para localizar \(node.name)."

        previewClearTask?.cancel()
        previewClearTask = Task { @MainActor [weak self] in
            let held = (session.sustainBeats[node.id] ?? 1.2) * session.secondsPerBeat
            let duration = VoiceSynthesis.duration(for: node.type, sustainSeconds: held)
            let delayTail = node.delay > 0 ? 2 * (0.07 + Double(node.delay) * 0.48) : 0
            try? await Task.sleep(for: .seconds(session.leadInSeconds + duration + max(0.4, delayTail)))
            guard let self, !Task.isCancelled, self.spatialAudioSession?.id == session.id else { return }
            self.spatialAudioSession = nil
        }
    }

    func loadSpatialTestScene() {
        finishLesson()
        recordUndo("Abrir demo")
        stopPlayback()
        sequencer.bpm = 92
        graphTransport.loopPasses = 2

        let kick = testNode("Kick frontal", .kick, position: [0, 1.18, 0.78])
        let bass = testNode("Bass izquierdo", .bass, position: [-1.15, 1.0, -0.18])
        let hat = testNode("Hi-hat derecho", .hiHat, position: [1.12, 1.62, 0.12])
        let pad = testNode("Pad alto y lejano", .pad, position: [0.12, 2.15, -1.35], rotation: [.pi * 0.62, 0, 0])
        let fx = testNode("FX posterior", .fx, position: [0, 1.32, 2.28], rotation: [0, .pi * 0.48, .pi * 0.22])
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
        "Rota Pad o FX y escucha reverb, delay y distorsión.",
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
            statusMessage = "Composición espacial guardada."
        } catch {
            statusMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    func load() {
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
        recordUndo("Afinar sonido")
        nodes[index].pitch = max(-24, min(semitones.rounded(), 24))
    }

    /// Un solo punto de deshacer por arrastre de slider, no uno por muestra.
    func beginParameterEdit() { recordUndo("Ajustar sonido") }

    func setSoundParameter(id: UUID, parameter: SoundParameter, value: Float) {
        guard value.isFinite, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let amount = max(0, min(value, 1))
        var updated = nodes[index]
        switch parameter {
        case .volume: updated.volume = amount
        case .reverb:
            updated.reverb = amount
            updated.rotationX = amount * .pi
        case .delay:
            updated.delay = amount
            updated.rotationY = amount * .pi
        case .distortion:
            updated.distortion = amount
            updated.rotationZ = amount * .pi
        }
        if updated != nodes[index] { nodes[index] = updated }
    }

    func beginLesson(_ lesson: MusicLesson) {
        if learningBackup == nil {
            learningBackup = (snapshot, selectedNodeID, undoStack, isSpatialTestScene)
        }
        stopPlayback()
        let practice = lesson.composition()
        nodes = practice.nodes
        connections = practice.connections
        sequencer.bpm = practice.bpm
        graphTransport.loopPasses = practice.loopPasses
        selectedNodeID = nodes.first?.id
        isSpatialTestScene = false
        undoStack = []
        undoLabel = nil
        activeLesson = lesson
        lessonHasPlayed = false
        sceneContentRevision &+= 1
        statusMessage = "Práctica lista. Tu composición está reservada hasta que termines."
    }

    func finishLesson() {
        guard let backup = learningBackup else { return }
        stopPlayback()
        nodes = backup.composition.nodes
        connections = backup.composition.connections
        sequencer.bpm = backup.composition.bpm
        graphTransport.loopPasses = backup.composition.loopPasses
        selectedNodeID = backup.selectedID
        isSpatialTestScene = backup.isDemo
        undoStack = backup.undo
        undoLabel = undoStack.last?.label
        learningBackup = nil
        activeLesson = nil
        lessonHasPlayed = false
        sceneContentRevision &+= 1
        statusMessage = "De vuelta en tu composición."
    }

    private func position(of nodeID: UUID) -> SIMD3<Float>? {
        nodes.first(where: { $0.id == nodeID }).map { [$0.positionX, $0.positionY, $0.positionZ] }
    }

    /// Busca el hueco más despejado en un anillo alrededor del núcleo. La
    /// versión anterior derivaba la posición de `nodes.count`, así que tras
    /// borrar un nodo los siguientes reaparecían encima de los que quedaban.
    private func freeSpawnPosition() -> SIMD3<Float> {
        let radius: Float = 0.95
        let heights: [Float] = [0.24, 0, -0.22]
        var best = SIMD3<Float>(0, SpatialParameterMapper.neutralHeight, radius * 0.6)
        var bestClearance = -Float.infinity

        for step in 0..<18 {
            let angle = Float(step) / 18 * 2 * .pi
            let candidate = SIMD3<Float>(
                sin(angle) * radius,
                SpatialParameterMapper.neutralHeight + heights[step % heights.count],
                cos(angle) * radius * 0.6
            )
            let clearance = nodes
                .map { simd_distance(candidate, [$0.positionX, $0.positionY, $0.positionZ]) }
                .min() ?? .greatestFiniteMagnitude
            if clearance > bestClearance {
                bestClearance = clearance
                best = candidate
            }
        }
        return best
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
        rotation: SIMD3<Float> = .zero
    ) -> SoundNode {
        let effects = SpatialParameterMapper.effects(from: rotation)
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
