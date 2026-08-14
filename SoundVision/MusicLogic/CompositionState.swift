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

    let sequencer = Sequencer()
    let graphTransport = GraphTransport()
    private let storage: CompositionStorage
    private var pulseClearTasks: [UUID: Task<Void, Never>] = [:]
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

    func stopPlayback() {
        graphTransport.stop()
        spatialAudioSession = nil
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
            statusMessage = "Composición espacial cargada."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reset() {
        stopPlayback()
        nodes = []
        connections = []
        lastTriggeredNodeIDs = []
        selectedNodeID = nil
        pendingConnectionSourceID = nil
        statusMessage = "Lienzo espacial restaurado."
    }

    var snapshot: Composition {
        Composition(title: "Anatomía del Sonido", bpm: sequencer.bpm, steps: Sequencer.totalSteps, nodes: nodes, connections: connections)
    }

    private func triggerVisualPulse(for nodeID: UUID) {
        lastTriggeredNodeIDs.insert(nodeID)
        pulseClearTasks[nodeID]?.cancel()
        pulseClearTasks[nodeID] = Task { @MainActor [weak self] in
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
            max(-1.8, min(value.z, 1.1))
        ]
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
