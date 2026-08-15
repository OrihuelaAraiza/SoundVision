import RealityKit
import Spatial
import SwiftUI

struct SoundSculptureView: View {
    @EnvironmentObject private var state: CompositionState
    @StateObject private var audioEngine = AudioEngineManager()
    @State private var spatialRequest: SpatialRequest?
    @State private var processedSpawnToken: UUID?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingNewTrackConfirmation = false
    @State private var isShowingDemoConfirmation = false
    @State private var isInstrumentDrawerExpanded = true

    var body: some View {
        GeometryReader { geometry in
            TimelineView(
                .animation(
                    minimumInterval: state.graphTransport.isPlaying ? 1.0 / 20.0 : 1.0 / 12.0,
                    paused: state.nodes.isEmpty
                )
            ) { timeline in
                RealityView { content in
                    let sculpture = makeSculpture()
                    content.add(sculpture)
                    await ParticleEffectSystem.prepareAssets(in: sculpture)
                } update: { content in
                    guard let root = content.entities.first(where: { $0.name == "sound-sculpture" }) else { return }
                    processSpatialRequest(using: content, root: root)
                    reconcileNodes(in: root)
                    audioEngine.synchronize(session: state.spatialAudioSession, in: root)
                    updateScene(root, at: timeline.date.timeIntervalSinceReferenceDate)
                }
                .dropDestination(for: String.self) { items, location in
                    guard let rawType = items.first,
                          let type = SoundNodeType(rawValue: rawType) else { return false }
                    addInstrument(type, at: location, viewport: geometry.size)
                    return true
                }
                .gesture(tapGesture)
                .simultaneousGesture(dragGesture)
                .simultaneousGesture(rotationGesture)
            }
            .overlay(alignment: .bottom) {
                transportPanel.padding(.bottom, 24)
            }
            .overlay(alignment: .trailing) {
                inspectorPanel.padding(.trailing, 24)
            }
            .overlay(alignment: .leading) {
                instrumentDrawer.padding(.leading, 24)
            }
            .overlay(alignment: .topLeading) {
                testGuide.padding(.top, 24).padding(.leading, 24)
            }
            .overlay(alignment: .top) {
                statusBanner.padding(.top, 24)
            }
        }
        .onDisappear { audioEngine.stopAll() }
        .confirmationDialog(
            "¿Eliminar este nodo?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar nodo", role: .destructive) { state.deleteSelectedNode() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("También se eliminarán todas sus conexiones.")
        }
        .confirmationDialog(
            "¿Comenzar una pista nueva?",
            isPresented: $isShowingNewTrackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Crear pista nueva", role: .destructive) { startNewTrack() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La composición actual se quitará del lienzo. Guárdala antes si quieres conservarla.")
        }
        .confirmationDialog(
            "¿Abrir la demo espacial?",
            isPresented: $isShowingDemoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Abrir demo") { loadDemo() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La demo sustituirá temporalmente los nodos del lienzo actual.")
        }
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if TransportNodeFactory.isTransportEntity(value.entity) {
                    state.togglePlayback()
                } else if let id = NodeEntityFactory.id(from: value.entity) {
                    state.selectNode(id: id)
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = NodeEntityFactory.id(from: value.entity) else { return }
                state.selectedNodeID = id
                spatialRequest = .move(token: UUID(), nodeID: id, point: value.location3D)
            }
            .onEnded { value in
                if TransportNodeFactory.isTransportEntity(value.entity) {
                    spatialRequest = .spawn(token: UUID(), point: value.location3D)
                } else if let id = NodeEntityFactory.id(from: value.entity) {
                    spatialRequest = .move(token: UUID(), nodeID: id, point: value.location3D)
                }
            }
    }

    private var rotationGesture: some Gesture {
        RotateGesture3D()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = NodeEntityFactory.id(from: value.entity) else { return }
                state.selectedNodeID = id
                spatialRequest = .rotate(token: UUID(), nodeID: id, rotation: value.rotation)
            }
    }

    private var transportPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button { state.togglePlayback() } label: {
                    Label(
                        state.graphTransport.isPlaying ? "Detener" : "Reproducir",
                        systemImage: state.graphTransport.isPlaying ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(state.graphTransport.isPlaying ? .pink : .cyan)
                .disabled(state.connections.isEmpty)

                Button { isInstrumentDrawerExpanded.toggle() } label: {
                    Label("Sonidos", systemImage: "square.grid.2x2.fill")
                }

                Button { requestDemo() } label: {
                    Label("Demo espacial", systemImage: "ear.and.waveform")
                }
                .tint(.purple)

                Button { requestNewTrack() } label: {
                    Label("Nueva pista", systemImage: "doc.badge.plus")
                }

                Divider().frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("REALITYKIT SPATIAL AUDIO")
                        .font(.caption2.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(.cyan)
                    Text(state.nodes.isEmpty
                         ? "Abre Sonidos y arrastra un nodo al espacio"
                         : "\(state.nodes.count) nodos · \(state.connections.count) conexiones")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Text("TEMPO").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { state.sequencer.bpm }, set: { state.sequencer.bpm = $0 }),
                    in: 50...180,
                    step: 1
                )
                .frame(width: 160)
                .disabled(state.graphTransport.isPlaying)

                Text("\(Int(state.sequencer.bpm)) BPM")
                    .font(.caption.monospacedDigit())

                Stepper(
                    "Loops \(state.graphTransport.loopPasses)×",
                    value: Binding(
                        get: { state.graphTransport.loopPasses },
                        set: { state.graphTransport.loopPasses = $0 }
                    ),
                    in: 1...8
                )
                .font(.caption.monospacedDigit())
                .frame(width: 116)
                .disabled(state.graphTransport.isPlaying)
                .help("Máximo de recorridos por conexión cíclica")

                Spacer(minLength: 10)
                Button { state.save() } label: { Label("Guardar", systemImage: "square.and.arrow.down") }
                Button { state.reset() } label: { Label("Limpiar", systemImage: "arrow.counterclockwise") }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 760)
        .glassBackgroundEffect(in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private var instrumentDrawer: some View {
        if isInstrumentDrawerExpanded {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CAJÓN DE SONIDOS")
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                        Text("Toca para añadir · arrastra para colocar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { isInstrumentDrawerExpanded = false } label: {
                        Image(systemName: "chevron.left.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(SoundNodeType.allCases, id: \.self) { type in
                        instrumentCard(for: type)
                    }
                }

                if state.nodes.isEmpty {
                    Label("Empieza con Kick, Bass o Pad", systemImage: "hand.draw.fill")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
            }
            .padding(16)
            .frame(width: 286)
            .glassBackgroundEffect(in: .rect(cornerRadius: 22))
        } else {
            Button { isInstrumentDrawerExpanded = true } label: {
                Label("Sonidos", systemImage: "square.grid.2x2.fill")
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
    }

    private func instrumentCard(for type: SoundNodeType) -> some View {
        let style = NodeVisualStyle.style(for: type)
        return Button {
            addInstrument(type)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: instrumentIcon(for: type))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: style.color))
                Text(instrumentName(for: type))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: style.color).opacity(0.12), in: .rect(cornerRadius: 13))
        .hoverEffect()
        .draggable(type.rawValue) {
            Label(instrumentName(for: type), systemImage: instrumentIcon(for: type))
                .padding(12)
                .background(.regularMaterial, in: .capsule)
        }
        .accessibilityHint("Toca para añadirlo al centro o arrástralo al lugar deseado")
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if let node = state.selectedNode {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color(uiColor: NodeVisualStyle.style(for: node.type).color))
                        .frame(width: 10, height: 10)
                    Text(node.name).font(.headline)
                    Spacer()
                    Text(node.isActive ? "ACTIVO" : "MUTE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(node.isActive ? .green : .secondary)
                    Button { state.clearSelection() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                parameter("Motor", value: "Spatial · 48 kHz")
                parameter("Altura · Pitch", value: String(format: "%+.1f st", node.pitch))
                parameter("Profundidad · Volumen", value: "\(Int(node.volume * 100)) %")
                parameter("Distancia · Duración", value: String(format: "%.2f beats", node.durationBeats))
                Divider()
                parameter("Rotación X · Reverb", value: "\(Int(node.reverb * 100)) %")
                parameter("Rotación Y · Delay", value: "\(Int(node.delay * 100)) %")
                parameter("Rotación Z · Distorsión", value: "\(Int(node.distortion * 100)) %")

                Button { state.previewSelectedNode() } label: {
                    Label("Escuchar desde aquí", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(!node.isActive)

                HStack {
                    Button(node.isActive ? "Mutear" : "Activar") { state.toggleSelectedNode() }
                    if state.pendingConnectionSourceID == node.id {
                        Button("Cancelar conexión") { state.cancelConnection() }
                    } else {
                        Button("Conectar") { state.beginConnection() }
                    }
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) { isShowingDeleteConfirmation = true } label: {
                    Label("Eliminar nodo", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 292)
            .padding(18)
            .glassBackgroundEffect(in: .rect(cornerRadius: 22))
        }
    }

    @ViewBuilder
    private var testGuide: some View {
        if state.isSpatialTestScene {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("PRUEBA EN VISION PRO", systemImage: "checklist")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.purple)
                    Spacer()
                    Text("\(state.testStep + 1)/\(CompositionState.spatialTestInstructions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(CompositionState.spatialTestInstructions[state.testStep])
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { state.previousTestStep() } label: { Image(systemName: "chevron.left") }
                        .disabled(state.testStep == 0)
                    Button { state.advanceTestStep() } label: {
                        Label("Siguiente", systemImage: "chevron.right")
                    }
                    .disabled(state.testStep == CompositionState.spatialTestInstructions.count - 1)
                    Spacer()
                    Button("Crear mi pista") { startNewTrack() }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    Button("Ocultar") { state.closeTestGuide() }
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 340)
            .padding(18)
            .glassBackgroundEffect(in: .rect(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let message = state.statusMessage {
            Text(message)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassBackgroundEffect(in: .capsule)
        }
    }

    private func parameter(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    private func makeSculpture() -> Entity {
        let root = Entity()
        root.name = "sound-sculpture"
        // Las coordenadas musicales ya expresan alturas humanas (neutral = 1.25 m).
        // No se resta nuevamente esa altura: en Vision Pro eso colocaba el grafo en el suelo.
        root.position = SpatialSceneLayout.rootPosition
        root.addChild(ConnectionLineSystem.makeContainer())
        root.addChild(TransportNodeFactory.make())
        state.nodes.forEach { root.addChild(NodeEntityFactory.makeNode($0)) }
        return root
    }

    private func addInstrument(_ type: SoundNodeType) {
        state.createNode(of: type)
    }

    private func addInstrument(_ type: SoundNodeType, at location: CGPoint, viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0 else {
            addInstrument(type)
            return
        }
        let position = SpatialSceneLayout.dropPosition(at: location, in: viewport)
        state.createNode(of: type, at: position)
    }

    private func requestNewTrack() {
        if state.nodes.isEmpty || state.isSpatialTestScene {
            startNewTrack()
        } else {
            isShowingNewTrackConfirmation = true
        }
    }

    private func startNewTrack() {
        state.startNewComposition()
        isInstrumentDrawerExpanded = true
    }

    private func requestDemo() {
        if state.nodes.isEmpty || state.isSpatialTestScene {
            loadDemo()
        } else {
            isShowingDemoConfirmation = true
        }
    }

    private func loadDemo() {
        state.loadSpatialTestScene()
        isInstrumentDrawerExpanded = false
    }

    private func instrumentName(for type: SoundNodeType) -> String {
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

    private func instrumentIcon(for type: SoundNodeType) -> String {
        switch type {
        case .kick: "circle.fill"
        case .snare: "square.fill"
        case .hiHat: "triangle.fill"
        case .clap: "hands.clap.fill"
        case .bass: "waveform.path"
        case .pad: "cloud.fill"
        case .lead: "bolt.fill"
        case .fx: "sparkles"
        }
    }

    private func processSpatialRequest(using content: RealityViewContent, root: Entity) {
        guard let request = spatialRequest else { return }
        switch request {
        case let .move(_, nodeID, point):
            let position = content.convert(point, from: .local, to: root)
            state.moveNode(id: nodeID, to: position)
        case let .spawn(token, point):
            guard processedSpawnToken != token else { return }
            processedSpawnToken = token
            let position = content.convert(point, from: .local, to: root)
            state.createNextNode(at: position)
        case let .rotate(_, nodeID, rotation):
            let quaternion = content.convert(rotation, from: .local, to: root)
            state.rotateNode(id: nodeID, quaternion: quaternion)
        }
    }

    private func reconcileNodes(in root: Entity) {
        let expectedNames = Set(state.nodes.map { NodeEntityFactory.nodePrefix + $0.id.uuidString })
        for stale in root.children where stale.name.hasPrefix(NodeEntityFactory.nodePrefix) && !expectedNames.contains(stale.name) {
            stale.removeFromParent()
        }
        for node in state.nodes where root.findEntity(named: NodeEntityFactory.nodePrefix + node.id.uuidString) == nil {
            root.addChild(NodeEntityFactory.makeNode(node))
        }
    }

    private func updateScene(_ root: Entity, at time: TimeInterval) {
        let soundingIDs = state.lastTriggeredNodeIDs.union(state.graphTransport.activeNodeIDs)
        ConnectionLineSystem.synchronize(
            in: root,
            nodes: state.nodes,
            connections: state.connections,
            triggeredIDs: soundingIDs
        )

        if let transport = root.findEntity(named: TransportNodeFactory.rootName),
           let core = transport.findEntity(named: "mix-core") {
            CentralCoreSystem.update(
                core,
                activeCount: state.nodes.filter(\.isActive).count,
                triggeredCount: soundingIDs.count,
                time: time
            )
            ParticleEffectSystem.updateCore(
                in: core,
                isPlaying: state.graphTransport.isPlaying,
                triggeredCount: soundingIDs.count
            )
            MetalEnergyFieldSystem.update(
                in: transport,
                time: time,
                isPlaying: state.graphTransport.isPlaying,
                triggeredCount: soundingIDs.count
            )
            transport.scale = SIMD3(repeating: state.graphTransport.isPlaying ? 1.12 : 1)
        }

        for node in state.nodes {
            guard let entity = root.findEntity(named: NodeEntityFactory.nodePrefix + node.id.uuidString) else { continue }
            NodeEntityFactory.updateSpatialReadout(in: entity, node: node)
            NodeAnimationSystem.update(
                entity,
                node: node,
                isSelected: state.selectedNodeID == node.id,
                isTriggered: soundingIDs.contains(node.id),
                time: time
            )
        }
    }
}

private enum SpatialRequest {
    case move(token: UUID, nodeID: UUID, point: Point3D)
    case spawn(token: UUID, point: Point3D)
    case rotate(token: UUID, nodeID: UUID, rotation: Rotation3D)
}
