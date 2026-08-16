import SwiftUI

/// Consola del estudio. Vive en una ventana real de visionOS en vez de en
/// attachments anclados a la cabeza: el sistema le da su propia barra de
/// movimiento, la persona la coloca donde quiera y ahí se queda mientras camina
/// o gira. Además los diálogos modales solo se presentan desde una ventana, no
/// desde dentro de un `ImmersiveSpace`.
struct StudioConsoleView: View {
    @EnvironmentObject private var state: CompositionState
    let onExit: () -> Void

    @State private var isConfirmingDelete = false
    @State private var isConfirmingNewTrack = false
    @State private var isConfirmingDemo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                transportSection
                if state.isSpatialTestScene { guideSection }
                instrumentSection
                if state.selectedNode != nil { inspectorSection }
                compositionSection
            }
            .padding(26)
        }
        .navigationTitle("SoundVision")
        .confirmationDialog(
            "¿Eliminar este nodo?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar nodo", role: .destructive) { state.deleteSelectedNode() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("También se eliminarán todas sus conexiones.")
        }
        .confirmationDialog(
            "¿Comenzar una pista nueva?",
            isPresented: $isConfirmingNewTrack,
            titleVisibility: .visible
        ) {
            Button("Crear pista nueva", role: .destructive) { state.startNewComposition() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La composición actual se quitará del lienzo. Guárdala antes si quieres conservarla.")
        }
        .confirmationDialog(
            "¿Abrir la demo espacial?",
            isPresented: $isConfirmingDemo,
            titleVisibility: .visible
        ) {
            Button("Abrir demo") { state.loadSpatialTestScene() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La demo sustituirá los nodos del lienzo actual.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ESTUDIO")
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(.cyan)
                Text("\(state.nodes.count) nodos · \(state.connections.count) conexiones")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .cancel) { onExit() } label: {
                Label("Salir", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
        }
    }

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { state.togglePlayback() } label: {
                Label(
                    state.graphTransport.isPlaying ? "Detener" : "Reproducir",
                    systemImage: state.graphTransport.isPlaying ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.graphTransport.isPlaying ? .pink : .cyan)
            .disabled(state.connections.isEmpty)

            if state.connections.isEmpty {
                Label("Añade un sonido para poder reproducir", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("TEMPO").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { state.sequencer.bpm }, set: { state.sequencer.bpm = $0 }),
                    in: 50...180,
                    step: 1
                )
                .disabled(state.graphTransport.isPlaying)
                Text("\(Int(state.sequencer.bpm))")
                    .font(.callout.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }

            Stepper(
                "Loops \(state.graphTransport.loopPasses)×",
                value: Binding(
                    get: { state.graphTransport.loopPasses },
                    set: { state.graphTransport.loopPasses = $0 }
                ),
                in: 1...8
            )
            .font(.callout.monospacedDigit())
            .disabled(state.graphTransport.isPlaying)

            if let message = state.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guideSection: some View {
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
                Button("Ocultar") { state.closeTestGuide() }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.purple.opacity(0.12), in: .rect(cornerRadius: 18))
    }

    private var instrumentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AÑADIR SONIDO")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SoundNodeType.allCases, id: \.self) { type in
                    let style = NodeVisualStyle.style(for: type)
                    Button {
                        state.createNode(of: type)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: SoundNodeType.icon(for: type))
                                .foregroundStyle(Color(uiColor: style.color))
                            Text(SoundNodeType.displayName(for: type))
                                .font(.callout.weight(.medium))
                            Spacer()
                        }
                        .frame(minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var inspectorSection: some View {
        if let node = state.selectedNode {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color(uiColor: NodeVisualStyle.style(for: node.type).color))
                        .frame(width: 11, height: 11)
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

                parameter("Altura · Pitch", value: String(format: "%+.1f st", node.pitch))
                parameter("Profundidad · Volumen", value: "\(Int(node.volume * 100)) %")
                parameter("Distancia · Duración", value: String(format: "%.2f beats", node.durationBeats))
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
                    Spacer()
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(.thinMaterial, in: .rect(cornerRadius: 18))
        }
    }

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPOSICIÓN")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            HStack {
                Button { isConfirmingNewTrack = true } label: {
                    Label("Nueva pista", systemImage: "doc.badge.plus")
                }
                Button { isConfirmingDemo = true } label: {
                    Label("Demo", systemImage: "ear.and.waveform")
                }
                .tint(.purple)
            }
            .buttonStyle(.bordered)

            HStack {
                Button { state.save() } label: {
                    Label("Guardar", systemImage: "square.and.arrow.down")
                }
                Button { state.load() } label: {
                    Label("Cargar", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func parameter(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}
