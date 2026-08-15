import RealityKit
import Spatial
import SwiftUI

struct SoundSculptureView: View {
    @EnvironmentObject private var state: CompositionState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var audioEngine = AudioEngineManager()
    @State private var spatialRequest: SpatialRequest?
    @State private var processedSpawnToken: UUID?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingNewTrackConfirmation = false
    @State private var isShowingDemoConfirmation = false
    @State private var isInstrumentDrawerExpanded = true
    @State private var transportPanelOffset = CGSize.zero
    @State private var drawerPanelOffset = CGSize.zero
    @State private var inspectorPanelOffset = CGSize.zero
    @State private var guidePanelOffset = CGSize.zero
    @State private var panelDistance: Float = 0.72
    @State private var isChangingComposition = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(
                minimumInterval: state.graphTransport.isPlaying ? 1.0 / 20.0 : (state.nodes.isEmpty ? 0.25 : 1.0 / 12.0),
                paused: false
            )) { timeline in
                RealityView { content, attachments in
                    let sculpture = makeSculpture()
                    content.add(sculpture)
                    installPanelAttachments(in: content, attachments: attachments)
                    await ParticleEffectSystem.prepareAssets(in: sculpture)
                } update: { content, _ in
                    guard let root = content.entities.first(where: { $0.name == "sound-sculpture" }) else { return }
                    processSpatialRequest(using: content, root: root)
                    // Detén las fuentes antes de retirar las entidades que las contienen.
                    audioEngine.synchronize(session: state.spatialAudioSession, in: root)
                    reconcileNodes(in: root)
                    updateScene(root, at: timeline.date.timeIntervalSinceReferenceDate)
                    updatePanelAttachmentPositions(in: content)
                } attachments: {
                    Attachment(id: PanelAttachmentID.transport) { transportPanel }
                    Attachment(id: PanelAttachmentID.drawer) { instrumentDrawer }
                    Attachment(id: PanelAttachmentID.inspector) { inspectorPanel }
                    Attachment(id: PanelAttachmentID.guide) { testGuide }
                    Attachment(id: PanelAttachmentID.status) { statusBanner }
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
                MenuDragHandle(label: "Mover controles", offset: $transportPanelOffset)

                Button { state.togglePlayback() } label: {
                    Label(
                        state.graphTransport.isPlaying ? "Detener" : "Reproducir",
                        systemImage: state.graphTransport.isPlaying ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(state.graphTransport.isPlaying ? .pink : .cyan)
                .disabled(state.connections.isEmpty || isChangingComposition)

                Button { isInstrumentDrawerExpanded.toggle() } label: {
                    Label("Sonidos", systemImage: "square.grid.2x2.fill")
                }

                Button { requestDemo() } label: {
                    Label("Demo espacial", systemImage: "ear.and.waveform")
                }
                .tint(.purple)
                .disabled(isChangingComposition)

                Button { requestNewTrack() } label: {
                    Label("Nueva pista", systemImage: "doc.badge.plus")
                }
                .disabled(isChangingComposition)

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

                Spacer()
            }

            HStack(spacing: 12) {
                Text("MENÚS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Button { adjustPanelDistance(by: -0.08) } label: {
                    Label("Más cerca", systemImage: "plus.magnifyingglass")
                }
                .help("Acerca todos los menús")

                Button { adjustPanelDistance(by: 0.08) } label: {
                    Label("Más lejos", systemImage: "minus.magnifyingglass")
                }
                .help("Aleja todos los menús")

                Button { resetMenuPositions() } label: {
                    Label("Recentrar", systemImage: "scope")
                }
                .accessibilityLabel("Recentrar menús")
                .help("Devuelve todos los paneles a su posición inicial")

                Button { openWindow(id: StudioWindowID.controls) } label: {
                    Label("Ventana movible", systemImage: "macwindow.on.rectangle")
                }
                .accessibilityLabel("Abrir controles movibles")
                .help("Abre una ventana espacial que puedes acomodar con la barra del sistema")

                Spacer()
                Button { state.save() } label: { Label("Guardar", systemImage: "square.and.arrow.down") }
                Button {
                    performCompositionTransition {
                        state.reset()
                        isInstrumentDrawerExpanded = true
                    }
                } label: {
                    Label("Limpiar", systemImage: "arrow.counterclockwise")
                }
                .disabled(isChangingComposition)
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
                        Text("Toca/arrastra sonidos · usa MOVER para acomodar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    MenuDragHandle(label: "Mover cajón", offset: $drawerPanelOffset)
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
            HStack(spacing: 8) {
                MenuDragHandle(label: "Mover cajón", offset: $drawerPanelOffset)
                Button { isInstrumentDrawerExpanded = true } label: {
                    Label("Sonidos", systemImage: "square.grid.2x2.fill")
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding(8)
            .glassBackgroundEffect(in: .capsule)
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
                    MenuDragHandle(label: "Mover inspector", offset: $inspectorPanelOffset)
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
                    MenuDragHandle(label: "Mover guía", offset: $guidePanelOffset)
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
        if isChangingComposition {
            Label("Actualizando el espacio…", systemImage: "waveform.path")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassBackgroundEffect(in: .capsule)
        } else if let message = state.statusMessage {
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
        root.components.set(SceneMembershipRevisionComponent(value: state.sceneContentRevision))
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
        performCompositionTransition {
            state.startNewComposition()
            isInstrumentDrawerExpanded = true
        }
    }

    private func requestDemo() {
        if state.nodes.isEmpty || state.isSpatialTestScene {
            loadDemo()
        } else {
            isShowingDemoConfirmation = true
        }
    }

    private func loadDemo() {
        performCompositionTransition {
            state.loadSpatialTestScene()
            isInstrumentDrawerExpanded = false
        }
    }

    private func performCompositionTransition(_ update: @escaping @MainActor () -> Void) {
        guard !isChangingComposition else { return }
        isChangingComposition = true
        audioEngine.stopAll()
        state.stopPlayback()

        Task { @MainActor in
            // Cede un frame para retirar audio y mostrar feedback antes de
            // reemplazar de una sola vez las entidades del grafo.
            await Task.yield()
            update()
            await Task.yield()
            isChangingComposition = false
        }
    }

    private func resetMenuPositions() {
        withAnimation(.snappy(duration: 0.32)) {
            transportPanelOffset = .zero
            drawerPanelOffset = .zero
            inspectorPanelOffset = .zero
            guidePanelOffset = .zero
            panelDistance = 0.72
        }
        state.statusMessage = "Menús recentrados y listos para acomodarse de nuevo."
    }

    private func adjustPanelDistance(by delta: Float) {
        withAnimation(.snappy(duration: 0.2)) {
            panelDistance = min(0.95, max(0.52, panelDistance + delta))
        }
        state.statusMessage = String(format: "Menús a %.0f cm.", panelDistance * 100)
    }

    private func installPanelAttachments(
        in content: RealityViewContent,
        attachments: RealityViewAttachments
    ) {
        let headAnchor = AnchorEntity(.head, trackingMode: .continuous)
        headAnchor.name = PanelAttachmentID.headAnchor

        for id in PanelAttachmentID.all {
            guard let entity = attachments.entity(for: id) else { continue }
            entity.name = id
            headAnchor.addChild(entity)
        }
        content.add(headAnchor)
        updatePanelAttachmentPositions(in: content)
    }

    private func updatePanelAttachmentPositions(in content: RealityViewContent) {
        guard let anchor = content.entities.first(where: { $0.name == PanelAttachmentID.headAnchor }) else { return }
        setPanelPosition(PanelAttachmentID.transport, base: [0, -0.31], offset: transportPanelOffset, in: anchor)
        setPanelPosition(PanelAttachmentID.drawer, base: [-0.40, 0.01], offset: drawerPanelOffset, in: anchor)
        setPanelPosition(PanelAttachmentID.inspector, base: [0.40, 0.01], offset: inspectorPanelOffset, in: anchor)
        setPanelPosition(PanelAttachmentID.guide, base: [0, 0.29], offset: guidePanelOffset, in: anchor)
        anchor.findEntity(named: PanelAttachmentID.status)?.position = [0, 0.42, -panelDistance]
    }

    private func setPanelPosition(
        _ name: String,
        base: SIMD2<Float>,
        offset: CGSize,
        in anchor: Entity
    ) {
        anchor.findEntity(named: name)?.position = [
            base.x + Float(offset.width) / 1_000,
            base.y - Float(offset.height) / 1_000,
            -panelDistance
        ]
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

private struct MenuDragHandle: View {
    let label: String
    @Binding var offset: CGSize
    @State private var origin: CGSize?

    var body: some View {
        Label("MOVER", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.thinMaterial, in: .capsule)
            .contentShape(.capsule)
            .hoverEffect()
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = origin ?? offset
                        if origin == nil { origin = start }
                        offset = Self.clamped(
                            CGSize(
                                width: start.width + value.translation.width,
                                height: start.height + value.translation.height
                            )
                        )
                    }
                    .onEnded { _ in origin = nil }
            )
            .accessibilityLabel(label)
            .accessibilityHint("Mantén el pinch y mueve la mano para acomodar el panel")
    }

    private static func clamped(_ value: CGSize) -> CGSize {
        CGSize(
            width: min(360, max(-360, value.width)),
            height: min(220, max(-220, value.height))
        )
    }
}

private enum PanelAttachmentID {
    static let headAnchor = "studio-panels-head-anchor"
    static let transport = "studio-panel-transport"
    static let drawer = "studio-panel-drawer"
    static let inspector = "studio-panel-inspector"
    static let guide = "studio-panel-guide"
    static let status = "studio-panel-status"
    static let all = [transport, drawer, inspector, guide, status]
}

private struct SceneMembershipRevisionComponent: Component {
    var value: Int
}

private enum SpatialRequest {
    case move(token: UUID, nodeID: UUID, point: Point3D)
    case spawn(token: UUID, point: Point3D)
    case rotate(token: UUID, nodeID: UUID, rotation: Rotation3D)
}
