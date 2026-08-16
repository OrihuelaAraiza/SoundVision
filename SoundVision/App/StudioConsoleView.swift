import SwiftUI

/// Consola del estudio. Vive en una ventana real de visionOS en vez de en
/// attachments anclados a la cabeza: el sistema le da su propia barra de
/// movimiento, la persona la coloca donde quiera y ahí se queda mientras camina
/// o gira. Además los diálogos modales solo se presentan desde una ventana, no
/// desde dentro de un `ImmersiveSpace`.
struct StudioConsoleView: View {
    @EnvironmentObject private var state: CompositionState
    let onExit: () -> Void


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
            // Siempre disponible mientras haya historial, en vez de un aviso
            // que se desvanece: si aparece y desaparece, hay que darse prisa.
            Button { state.undo() } label: {
                Label(
                    state.undoLabel.map { "Deshacer \($0.lowercased())" } ?? "Deshacer",
                    systemImage: "arrow.uturn.backward"
                )
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .disabled(!state.canUndo)

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

            if let problem = state.audioProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

                Toggle(isOn: Binding(
                    get: { node.isSoundLocked },
                    set: { _ in state.toggleSoundLock(id: node.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Sonido fijo", systemImage: node.isSoundLocked ? "lock.fill" : "lock.open")
                            .font(.callout.weight(.medium))
                        Text(node.isSoundLocked
                             ? "Muévelo para ordenar: no cambiará de sonido."
                             : "Al moverlo, la posición ajusta pitch y volumen.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.cyan)

                positionControls(for: node)

                parameter(
                    "Altura · Nota",
                    value: "\(SpatialParameterMapper.noteName(forSemitones: node.pitch))  (\(String(format: "%+.0f", node.pitch)) st)"
                )
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
                    Spacer()
                    Button(role: .destructive) { state.deleteSelectedNode() } label: {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)

                Label("Tira del punto bajo el organismo para conectarlo con otro.", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Button { state.startNewComposition() } label: {
                    Label("Nueva pista", systemImage: "doc.badge.plus")
                }
                Button { state.loadSpatialTestScene() } label: {
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

    /// Colocación exacta desde la ventana. El arrastre con la mano sigue siendo
    /// la vía principal, pero a un metro de distancia la puntería fina cansa y
    /// para *ordenar* el grafo hace falta poder afinar la posición sin pelearse.
    private func positionControls(for node: SoundNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POSICIÓN")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            axisSlider("Izquierda · Derecha", value: node.positionX, range: -2.4...2.4) {
                state.moveNode(id: node.id, to: [$0, node.positionY, node.positionZ])
            }
            axisSlider("Abajo · Arriba", value: node.positionY, range: 0.35...2.5) {
                state.moveNode(id: node.id, to: [node.positionX, $0, node.positionZ])
            }
            axisSlider("Lejos · Cerca", value: node.positionZ, range: -2.0...2.4) {
                state.moveNode(id: node.id, to: [node.positionX, node.positionY, $0])
            }
        }
    }

    private func axisSlider(
        _ title: String,
        value: Float,
        range: ClosedRange<Float>,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range
            )
            Text(String(format: "%+.2f", value))
                .font(.caption2.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
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
