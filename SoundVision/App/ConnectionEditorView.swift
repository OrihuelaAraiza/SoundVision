import SwiftUI

struct ConnectionEditorView: View {
    @EnvironmentObject private var state: CompositionState
    let node: SoundNode

    private var outgoing: [SoundConnection] {
        state.connections.filter { $0.sourceNodeID == node.id }.sorted {
            if $0.durationBeats != $1.durationBeats { return $0.durationBeats < $1.durationBeats }
            return (state.node(id: $0.destinationNodeID)?.name ?? "") < (state.node(id: $1.destinationNodeID)?.name ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Conexiones", systemImage: "arrow.triangle.branch").font(.headline)
            Text("Cada salida cuenta desde este nodo. Mismo tiempo: juntas. Tiempos distintos: primero el menor.")
                .font(.caption).foregroundStyle(.secondary)

            let incoming = state.connections.filter { $0.destinationNodeID == node.id }
            if !incoming.isEmpty {
                DisclosureGroup("Entradas · \(incoming.count)") {
                    ForEach(incoming) { edge in
                        HStack {
                            Text(edge.sourceNodeID.flatMap { state.node(id: $0)?.name } ?? "Play")
                            Spacer()
                            if edge.sourceNodeID != nil {
                                Text("+\(edge.durationBeats, specifier: "%.2f") beats")
                                    .foregroundStyle(.secondary)
                            }
                            cutButton(edge)
                        }
                        .font(.caption).padding(.vertical, 4)
                    }
                    Text("Si varias rutas llegan aquí a la vez, suena una vez. En momentos distintos, vuelve a sonar.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            let targets = state.nodes.filter { candidate in
                candidate.id != node.id && !outgoing.contains { $0.destinationNodeID == candidate.id }
            }
            Menu {
                ForEach(targets) { target in
                    Button(target.name) { _ = state.connect(sourceID: node.id, destinationID: target.id) }
                }
            } label: {
                Label("Añadir salida", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered).disabled(targets.isEmpty)

            if outgoing.isEmpty {
                Text("Esta rama termina aquí. Añade otro sonido para continuarla.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(outgoing) { edge in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.right").foregroundStyle(.cyan)
                        Button(state.node(id: edge.destinationNodeID)?.name ?? "Destino") {
                            state.focusNode(id: edge.destinationNodeID)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        cutButton(edge)
                    }
                    HStack {
                        Menu {
                            ForEach([0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 8, 16, 32], id: \.self) { beats in
                                Button("\(beats, specifier: "%g") beats") {
                                    state.setConnectionBeats(id: edge.id, beats: beats)
                                }
                            }
                            Divider()
                            Button("Según distancia") { state.useSpatialTiming(id: edge.id) }
                        } label: {
                            Label("+\(edge.durationBeats, specifier: "%.2f") beats", systemImage: "clock")
                        }
                        .buttonStyle(.bordered)
                        Text(edge.usesSpatialTiming ? "Espacial" : "Fijo")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(10)
                .background(.white.opacity(0.04), in: .rect(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(.cyan.opacity(0.07), in: .rect(cornerRadius: 16))
    }

    private func cutButton(_ edge: SoundConnection) -> some View {
        Button(role: .destructive) { state.removeConnection(id: edge.id) } label: {
            Image(systemName: "minus.circle").frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Quitar conexión hacia \(state.node(id: edge.destinationNodeID)?.name ?? node.name)")
    }
}

struct PlaybackOrderView: View {
    @EnvironmentObject private var state: CompositionState
    @Environment(\.dismiss) private var dismiss
    @State private var plan = GraphPlaybackPlan(events: [], isTruncated: false)
    @State private var showsDraft = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if state.graphTransport.isPlaying {
                        Picker("Recorrido", selection: $showsDraft) {
                            Text("En reproducción").tag(false)
                            Text("Próximo Play").tag(true)
                        }.pickerStyle(.segmented)
                    }
                    Text("Beat 0 es el inicio. Los sonidos con el mismo beat empiezan juntos. La vuelta se repite un beat después del último ataque, hasta pulsar Detener.")
                        .font(.callout).foregroundStyle(.secondary)
                    if plan.isTruncated {
                        Label("Ruta demasiado compleja: reduce los ciclos internos. Esta vista es parcial y Play no reproducirá una ruta recortada.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(Array(plan.events.enumerated()), id: \.offset) { _, event in
                    HStack {
                        Text("\(event.beat, specifier: "%.2f")")
                            .font(.body.monospacedDigit()).foregroundStyle(.cyan).frame(width: 64, alignment: .leading)
                        if let node = state.node(id: event.nodeID) {
                            Label(node.name, systemImage: SoundNodeType.icon(for: node.type))
                            Spacer()
                            if !node.isActive { Text("Silencio").foregroundStyle(.secondary) }
                        }
                    }
                }
                if plan.events.isEmpty { Text("Añade un sonido y conéctalo a Play.") }
            }
            .navigationTitle("Orden de reproducción")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .task(id: showsDraft) {
            if !showsDraft, state.graphTransport.isPlaying, let session = state.spatialAudioSession {
                plan = GraphPlaybackPlan(events: session.events, isTruncated: false)
                return
            }
            plan = GraphSchedule.makePlan(nodes: state.nodes, connections: state.connections,
                                          loopPasses: state.graphTransport.loopPasses)
        }
    }
}
