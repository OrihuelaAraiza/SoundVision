import SwiftUI

/// Consola del estudio. Vive en una ventana real de visionOS en vez de en
/// attachments anclados a la cabeza: el sistema le da su propia barra de
/// movimiento, la persona la coloca donde quiera y ahí se queda mientras camina
/// o gira. Además los diálogos modales solo se presentan desde una ventana, no
/// desde dentro de un `ImmersiveSpace`.
struct StudioConsoleView: View {
    @EnvironmentObject private var state: CompositionState
    let onExit: () -> Void


    /// Todo cabía en una sola columna con scroll, pero creció hasta no caber en
    /// la ventana, y entre botones y sliders de ancho completo casi no quedaba
    /// zona neutra donde agarrar para desplazarla. En pestañas cada pantalla es
    /// corta y no depende del scroll para alcanzar nada.
    var body: some View {
        TabView {
            Tab("Reproducir", systemImage: "play.circle") {
                page { transportSection; if state.isSpatialTestScene { guideSection } }
            }
            Tab("Sonidos", systemImage: "square.grid.2x2") {
                page { instrumentSection; compositionSection }
            }
            Tab("Nodo", systemImage: "slider.horizontal.3") {
                page {
                    if state.selectedNode == nil {
                        ContentUnavailableView(
                            "Ningún organismo seleccionado",
                            systemImage: "hand.tap",
                            description: Text("Haz pinch sobre un organismo en el espacio para editarlo aquí.")
                        )
                    } else {
                        inspectorSection
                    }
                }
            }
        }
        .navigationTitle("SoundVision")
    }

    /// Encabezado común más el contenido de la pestaña. El scroll se conserva
    /// como red de seguridad, no como la vía principal para llegar a las cosas.
    @ViewBuilder
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(26)
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            // Cede el ancho antes que los botones: si algo tiene que encoger,
            // que sea el recuento y no la acción.
            .layoutPriority(0)

            Spacer(minLength: 8)
            // Siempre disponible mientras haya historial, en vez de un aviso
            // que se desvanece: si aparece y desaparece, hay que darse prisa.
            Button { state.undo() } label: {
                Label(
                    state.undoLabel.map { "Deshacer \($0.lowercased())" } ?? "Deshacer",
                    systemImage: "arrow.uturn.backward"
                )
                .lineLimit(1)
                .truncationMode(.tail)
                // Etiquetas como "Deshacer vaciar el lienzo" desbordaban la
                // fila entera y aplastaban lo que tenían al lado.
                .frame(maxWidth: 186)
            }
            .buttonStyle(.bordered)
            .disabled(!state.canUndo)
            .layoutPriority(1)

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
            .disabled(state.playEntryNodeID == nil)

            if state.playEntryNodeID == nil {
                Label(
                    state.nodes.isEmpty
                        ? "Añade el primer sonido para poder reproducir"
                        : "Play necesita una única entrada antes de reproducir",
                    systemImage: "info.circle"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                "Vueltas de ciclos internos \(state.graphTransport.loopPasses)×",
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

            // "No suena" es un síntoma con media docena de causas. Esta línea
            // dice cuántas voces hay enganchadas, de qué reloj se fían, a qué
            // tasa rinden, cuánto nivel están sacando y por dónde sale: con eso
            // una prueba con el visor puesto deja de ser adivinanza.
            if let diagnostics = state.audioDiagnostics {
                Label(diagnostics, systemImage: "waveform.badge.magnifyingglass")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
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

            if let entry = state.playEntryNode {
                Label(
                    "Play inicia únicamente \(entry.name). Los demás sonidos se unen arrastrando sus conectores.",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    "El primer sonido será la única entrada desde Play.",
                    systemImage: "play.circle"
                )
                .font(.caption)
                .foregroundStyle(.cyan)
            }

            if state.nodes.count >= AudioEngineManager.maximumVoices {
                Label(
                    "Límite de \(AudioEngineManager.maximumVoices) organismos alcanzado para conservar audio estable.",
                    systemImage: "speaker.slash"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                        .frame(minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.nodes.count >= AudioEngineManager.maximumVoices)
                }
            }
        }
    }

    /// Un organismo al que Play no llega es un organismo mudo, y el silencio no
    /// explica por qué. Este aviso lo dice y ofrece el remedio en el sitio.
    @ViewBuilder
    private func reachabilityWarning(for node: SoundNode) -> some View {
        if state.unreachableNodeIDs().contains(node.id) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Play no llega hasta aquí: este organismo no sonará.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if state.playEntryNodeID == nil {
                    Button { state.connectToPlay(id: node.id) } label: {
                        Label("Convertir en entrada de Play", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else {
                    Label(
                        "Play ya tiene su única entrada. Arrastra el conector de un organismo alcanzable hasta este.",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
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
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(.cyan)

                reachabilityWarning(for: node)
                connectionControls(for: node)

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
                    .fixedSize(horizontal: false, vertical: true)
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

    /// Alternativa precisa al gesto espacial. La persona sigue decidiendo cada
    /// enlace, pero no depende de la puntería de manos para construir o corregir
    /// una ruta compleja.
    private func connectionControls(for source: SoundNode) -> some View {
        let availableTargets = state.nodes.filter { candidate in
            candidate.id != source.id
                && !state.connections.contains {
                    $0.sourceNodeID == source.id && $0.destinationNodeID == candidate.id
                }
        }
        let outgoing = state.connections.filter { $0.sourceNodeID == source.id }
        let playConnection = state.connections.first {
            $0.sourceNodeID == nil && $0.destinationNodeID == source.id
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("CONEXIONES DESDE ESTE ORGANISMO")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            if let playConnection {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").foregroundStyle(.cyan)
                    Text("Entrada única: Play → \(source.name)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button(role: .destructive) {
                        state.removeConnection(id: playConnection.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar entrada de Play")
                }
            }

            Menu {
                ForEach(availableTargets) { target in
                    Button {
                        _ = state.connect(sourceID: source.id, destinationID: target.id)
                    } label: {
                        Label(target.name, systemImage: SoundNodeType.icon(for: target.type))
                    }
                }
            } label: {
                Label("Conectar hacia…", systemImage: "arrow.turn.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(availableTargets.isEmpty)

            if outgoing.isEmpty {
                Text("Sin salidas. Este organismo será el final de su rama.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(outgoing) { connection in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.cyan)
                        Text(state.node(id: connection.destinationNodeID)?.name ?? "Destino eliminado")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(String(format: "%.2f beats", connection.durationBeats))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            state.removeConnection(id: connection.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cortar conexión")
                    }
                }
            }
        }
        .padding(10)
        .background(.cyan.opacity(0.08), in: .rect(cornerRadius: 12))
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
                .lineLimit(1)
                // "Izquierda · Derecha" llega justo al borde de los 116 pt.
                .minimumScaleFactor(0.7)
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
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                // El valor es el dato: si algo se encoge, que sea la etiqueta.
                .layoutPriority(1)
        }
    }
}
