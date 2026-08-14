import RealityKit
import Spatial
import SwiftUI

struct SoundSculptureView: View {
    @EnvironmentObject private var state: CompositionState
    @State private var spatialRequest: SpatialRequest?
    @State private var processedSpawnToken: UUID?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            RealityView { content in
                content.add(makeSculpture())
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == "sound-sculpture" }) else { return }
                processSpatialRequest(using: content, root: root)
                reconcileNodes(in: root)
                updateScene(root, at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .gesture(tapGesture)
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(rotationGesture)
            .overlay(alignment: .bottom) {
                transportPanel.padding(.bottom, 30)
            }
            .overlay(alignment: .trailing) {
                inspectorPanel.padding(.trailing, 28)
            }
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
                spatialRequest = .rotate(token: UUID(), nodeID: id, rotation: value.rotation)
            }
    }

    private var transportPanel: some View {
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

            Button { state.createNextNode() } label: {
                Label("Extraer nodo", systemImage: "plus.circle.fill")
            }

            Divider().frame(height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("GRAFO SONORO")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.cyan)
                Text(state.nodes.isEmpty
                     ? "Arrastra desde Play para crear el primer nodo"
                     : "\(state.nodes.count) nodos · \(state.connections.count) conexiones")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(get: { state.sequencer.bpm }, set: { state.sequencer.bpm = $0 }),
                in: 50...180,
                step: 1
            )
            .frame(width: 120)

            Text("\(Int(state.sequencer.bpm)) BPM")
                .font(.caption.monospacedDigit())

            Button { state.save() } label: { Image(systemName: "square.and.arrow.down") }
            Button { state.reset() } label: { Image(systemName: "arrow.counterclockwise") }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect(in: .rect(cornerRadius: 22))
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
                }

                parameter("Altura · Pitch", value: String(format: "%+.1f st", node.pitch))
                parameter("Profundidad · Volumen", value: "\(Int(node.volume * 100)) %")
                parameter("Distancia · Duración", value: String(format: "%.2f beats", node.durationBeats))
                Divider()
                parameter("Rotación X · Reverb", value: "\(Int(node.reverb * 100)) %")
                parameter("Rotación Y · Delay", value: "\(Int(node.delay * 100)) %")
                parameter("Rotación Z · Distorsión", value: "\(Int(node.distortion * 100)) %")

                HStack {
                    Button(node.isActive ? "Mutear" : "Activar") { state.toggleSelectedNode() }
                    Button(state.pendingConnectionSourceID == node.id ? "Elige destino" : "Conectar") {
                        state.beginConnection()
                    }
                    .disabled(state.pendingConnectionSourceID == node.id)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 260)
            .padding(18)
            .glassBackgroundEffect(in: .rect(cornerRadius: 22))
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
        root.position = [0, -1.15, -1.8]
        root.addChild(ConnectionLineSystem.makeContainer())
        root.addChild(TransportNodeFactory.make())
        state.nodes.forEach { root.addChild(NodeEntityFactory.makeNode($0)) }
        return root
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
        var soundingIDs = state.lastTriggeredNodeIDs
        if let currentNodeID = state.graphTransport.currentNodeID {
            soundingIDs.insert(currentNodeID)
        }
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
            transport.scale = SIMD3(repeating: state.graphTransport.isPlaying ? 1.12 : 1)
        }

        for node in state.nodes {
            guard let entity = root.findEntity(named: NodeEntityFactory.nodePrefix + node.id.uuidString) else { continue }
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
