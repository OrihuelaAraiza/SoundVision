import SwiftUI

/// Respaldo recuperable para el espacio inmersivo. visionOS proporciona la
/// barra de movimiento de esta ventana, por lo que puede colocarse nuevamente
/// frente a la persona aunque los overlays del estudio hayan quedado detrás.
struct FloatingStudioControlsView: View {
    @EnvironmentObject private var state: CompositionState
    @State private var isConfirmingNewTrack = false
    @State private var isConfirmingDemo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONTROLES FLOTANTES")
                        .font(.caption.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(.cyan)
                    Text("Mueve esta ventana con la barra de visionOS")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button { state.togglePlayback() } label: {
                        Label(
                            state.graphTransport.isPlaying ? "Detener" : "Reproducir",
                            systemImage: state.graphTransport.isPlaying ? "stop.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(state.graphTransport.isPlaying ? .pink : .cyan)
                    .disabled(state.connections.isEmpty)

                    Button { isConfirmingNewTrack = true } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .accessibilityLabel("Nueva pista")

                    Button { isConfirmingDemo = true } label: {
                        Image(systemName: "ear.and.waveform")
                    }
                    .accessibilityLabel("Abrir demo")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("AÑADIR SONIDO")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(SoundNodeType.allCases, id: \.self) { type in
                            Button {
                                state.createNode(of: type)
                            } label: {
                                Label(name(for: type), systemImage: icon(for: type))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color(uiColor: NodeVisualStyle.style(for: type).color))
                        }
                    }
                }

                if let node = state.selectedNode {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(node.name).font(.headline)
                        Text(String(format: "Pitch %+.1f st · Volumen %d%%", node.pitch, Int(node.volume * 100)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Escuchar") { state.previewSelectedNode() }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                            Button(node.isActive ? "Mutear" : "Activar") { state.toggleSelectedNode() }
                            Button("Conectar") { state.beginConnection() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("\(state.nodes.count) nodos · \(state.connections.count) conexiones")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .confirmationDialog("¿Comenzar una pista nueva?", isPresented: $isConfirmingNewTrack) {
            Button("Crear pista nueva", role: .destructive) { state.startNewComposition() }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Abrir la demo espacial?", isPresented: $isConfirmingDemo) {
            Button("Abrir demo") { state.loadSpatialTestScene() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func name(for type: SoundNodeType) -> String {
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

    private func icon(for type: SoundNodeType) -> String {
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
}
