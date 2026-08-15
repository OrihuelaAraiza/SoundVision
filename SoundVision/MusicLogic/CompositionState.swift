import Combine
import Foundation
import simd

@MainActor
final class CompositionState: ObservableObject {
    nonisolated static let playNodePosition = SIMD3<Float>(0, SpatialParameterMapper.neutralHeight, 0)

    @Published var nodes: [SoundNode]
    @Published var connections: [SoundConnection]
    @Published var isImmersiveSpaceOpen = false
    @Published var lastTriggeredNodeIDs: Set<UUID> = []
    @Published var selectedNodeID: UUID?
    @Published var pendingConnectionSourceID: UUID?
    @Published var statusMessage: String?
    @Published var spatialAudioSession: SpatialAudioSession?
    @Published var isSpatialTestScene = false
    @Published var testStep = 0
    @Published private(set) var sceneContentRevision = 0

    let sequencer = Sequencer()
    let graphTransport = GraphTransport()
    private let storage: CompositionStorage
    private var pulseClearTasks: [UUID: Task<Void, Never>] = [:]
    private var previewClearTask: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()

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

    func selectNode(id: UUID) {
        if let sourceID = pendingConnectionSourceID, sourceID != id {
            connect(sourceID: sourceID, destinationID: id)
            pendingConnectionSourceID = nil
        }
        selectedNodeID = id
    }

    func toggleSelectedNode() {
        guard let id = selectedNodeID, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].isActive.toggle()
    }

    func clearSelection() {
        selectedNodeID = nil
        pendingConnectionSourceID = nil
    }

    func cancelConnection() {
        pendingConnectionSourceID = nil
        statusMessage = "Conexión cancelada."
    }

    func deleteSelectedNode() {
        guard let id = selectedNodeID else { return }
        stopPlayback()
        nodes.removeAll { $0.id == id }
        connections.removeAll { $0.sourceNodeID == id || $0.destinationNodeID == id }
        selectedNodeID = nil
        pendingConnectionSourceID = nil
        sceneContentRevision &+= 1
        statusMessage = "Nodo eliminado."
    }

    func beginConnection() {
        pendingConnectionSourceID = selectedNodeID
        statusMessage = selectedNodeID == nil ? "Selecciona primero un nodo." : "Selecciona el nodo destino."
    }

    func connect(sourceID: UUID?, destinationID: UUID) {
        guard sourceID != destinationID,
              !connections.contains(where: { $0.sourceNodeID == sourceID && $0.destinationNodeID == destinationID })
        else { return }

        let sourcePosition = sourceID.flatMap(position(of:)) ?? Self.playNodePosition
        guard let destinationPosition = position(of: destinationID) else { return }
        connections.append(SoundConnection(
            sourceNodeID: sourceID,
            destinationNodeID: destinationID,
            durationBeats: SpatialParameterMapper.durationBeats(from: sourcePosition, to: destinationPosition)
        ))
        recalculateDurationSummary(for: destinationID)
        statusMessage = "Conexión creada."
    }

    @discardableResult
    func createNextNode(at position: SIMD3<Float>? = nil, connectedFrom sourceID: UUID? = nil) -> UUID {
        let type = SoundNodeType.allCases[nodes.count % SoundNodeType.allCases.count]
        return createNode(of: type, at: position, connectedFrom: sourceID)
    }

    @discardableResult
    func createNode(
        of type: SoundNodeType,
        at position: SIMD3<Float>? = nil,
        connectedFrom sourceID: UUID? = nil
    ) -> UUID {
        let spawnIndex = Float(nodes.count)
        let defaultPosition = SIMD3<Float>(
            0.48 + cos(spawnIndex * 1.4) * 0.5,
            SpatialParameterMapper.neutralHeight + sin(spawnIndex * 0.8) * 0.15,
            sin(spawnIndex * 1.4) * 0.42
        )
        let finalPosition = clamped(position ?? defaultPosition)
        let node = SoundNode(
            name: displayName(for: type),
            type: type,
            volume: SpatialParameterMapper.volume(forDepth: finalPosition.z),
            pitch: SpatialParameterMapper.pitch(forHeight: finalPosition.y),
            positionX: finalPosition.x,
            positionY: finalPosition.y,
            positionZ: finalPosition.z
        )
        nodes.append(node)
        connect(sourceID: sourceID, destinationID: node.id)
        selectedNodeID = node.id
        sceneContentRevision &+= 1
        statusMessage = "\(displayName(for: type)) agregado. Arrástralo para cambiar pitch, volumen y duración."
        return node.id
    }

    func moveNode(id: UUID, to position: SIMD3<Float>) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let value = clamped(position)
        nodes[index].positionX = value.x
        nodes[index].positionY = value.y
        nodes[index].positionZ = value.z
        nodes[index].pitch = SpatialParameterMapper.pitch(forHeight: value.y)
        nodes[index].volume = SpatialParameterMapper.volume(forDepth: value.z)
        recalculateConnections(touching: id)
    }

    func rotateNode(id: UUID, quaternion: simd_quatf) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let vector = quaternion.axis * quaternion.angle
        nodes[index].rotationX = vector.x
        nodes[index].rotationY = vector.y
        nodes[index].rotationZ = vector.z
        let effects = SpatialParameterMapper.effects(from: vector)
        nodes[index].reverb = effects.reverb
        nodes[index].delay = effects.delay
        nodes[index].distortion = effects.distortion
    }

    func togglePlayback() {
        if graphTransport.isPlaying {
            stopPlayback()
            return
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        graphTransport.start(
            nodes: nodes,
            connections: connections,
            bpm: sequencer.bpm,
            onSchedule: { [weak self] timeline, secondsPerBeat in
                guard let self else { return nil }
                let session = SpatialAudioSession(
                    nodes: Array(nodesByID.values),
                    events: timeline,
                    secondsPerBeat: secondsPerBeat
                )
                self.spatialAudioSession = session
                return session.leadInSeconds
            },
            onVisualTrigger: { [weak self] node in
                self?.triggerVisualPulse(for: node.id)
            },
            onCompletion: { [weak self] in
                self?.spatialAudioSession = nil
            }
        )
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
            secondsPerBeat: 1,
            leadInSeconds: 0.14
        )
        spatialAudioSession = session
        triggerVisualPulse(for: node.id, delay: session.leadInSeconds)
        statusMessage = "Preview espacial: mueve la cabeza para localizar \(node.name)."

        previewClearTask?.cancel()
        previewClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.35))
            guard let self, !Task.isCancelled, self.spatialAudioSession?.id == session.id else { return }
            self.spatialAudioSession = nil
        }
    }

    func loadSpatialTestScene() {
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
            testConnection(from: nil, to: fx),
            testConnection(from: kick, to: bass),
            testConnection(from: kick, to: hat),
            testConnection(from: bass, to: pad),
            testConnection(from: hat, to: pad),
            testConnection(from: pad, to: fx)
        ]
        recalculateAllConnections()
        selectedNodeID = kick.id
        pendingConnectionSourceID = nil
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
        "Rota Pad o FX y escucha reverb, delay y distorsión. Después crea una conexión nueva entre dos nodos.",
        "Detén, vuelve a reproducir y comprueba que controles, ondas y audio permanecen sincronizados."
    ]

    func stopPlayback() {
        graphTransport.stop()
        spatialAudioSession = nil
        previewClearTask?.cancel()
        previewClearTask = nil
        pulseClearTasks.values.forEach { $0.cancel() }
        pulseClearTasks = [:]
        lastTriggeredNodeIDs = []
    }

    func save() {
        do {
            try storage.save(snapshot)
            statusMessage = "Composición espacial guardada."
        } catch {
            statusMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    func load() {
        do {
            let composition = try storage.load()
            stopPlayback()
            sequencer.bpm = composition.bpm
            nodes = composition.nodes
            connections = composition.connections.isEmpty
                ? composition.nodes.map { SoundConnection(sourceNodeID: nil, destinationNodeID: $0.id) }
                : composition.connections
            selectedNodeID = nil
            pendingConnectionSourceID = nil
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
        stopPlayback()
        nodes = []
        connections = []
        lastTriggeredNodeIDs = []
        selectedNodeID = nil
        pendingConnectionSourceID = nil
        statusMessage = message
        isSpatialTestScene = false
        testStep = 0
        sceneContentRevision &+= 1
    }

    var snapshot: Composition {
        Composition(title: "Anatomía del Sonido", bpm: sequencer.bpm, steps: Sequencer.totalSteps, nodes: nodes, connections: connections)
    }

    private func triggerVisualPulse(for nodeID: UUID, delay: TimeInterval = 0) {
        pulseClearTasks[nodeID]?.cancel()
        pulseClearTasks[nodeID] = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.lastTriggeredNodeIDs.insert(nodeID)
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.lastTriggeredNodeIDs.remove(nodeID)
            self?.pulseClearTasks[nodeID] = nil
        }
    }

    private func recalculateAllConnections() {
        for index in connections.indices { recalculateConnection(at: index) }
        nodes.forEach { recalculateDurationSummary(for: $0.id) }
    }

    private func recalculateConnections(touching nodeID: UUID) {
        for index in connections.indices where connections[index].sourceNodeID == nodeID || connections[index].destinationNodeID == nodeID {
            recalculateConnection(at: index)
        }
        let affected = connections
            .filter { $0.sourceNodeID == nodeID || $0.destinationNodeID == nodeID }
            .map(\.destinationNodeID)
        Set(affected).forEach(recalculateDurationSummary)
    }

    private func recalculateConnection(at index: Int) {
        let connection = connections[index]
        let source = connection.sourceNodeID.flatMap(position(of:)) ?? Self.playNodePosition
        guard let destination = position(of: connection.destinationNodeID) else { return }
        connections[index].durationBeats = SpatialParameterMapper.durationBeats(from: source, to: destination)
    }

    private func recalculateDurationSummary(for nodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].durationBeats = connections.first(where: { $0.destinationNodeID == nodeID })?.durationBeats ?? 1
    }

    private func position(of nodeID: UUID) -> SIMD3<Float>? {
        nodes.first(where: { $0.id == nodeID }).map { [$0.positionX, $0.positionY, $0.positionZ] }
    }

    private func clamped(_ value: SIMD3<Float>) -> SIMD3<Float> {
        [
            max(-2.4, min(value.x, 2.4)),
            max(0.35, min(value.y, 2.5)),
            max(-2.0, min(value.z, 2.4))
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

    private func displayName(for type: SoundNodeType) -> String {
        switch type {
        case .kick: "Kick"
        case .snare: "Snare"
        case .hiHat: "Hi-hat"
        case .clap: "Clap"
        case .bass: "Bass"
        case .pad: "Pad"
        case .lead: "Lead"
        case .fx: "FX"
        }
    }
}
