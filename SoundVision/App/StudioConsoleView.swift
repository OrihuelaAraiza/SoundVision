import SwiftUI

struct StudioConsoleView: View {
    @EnvironmentObject private var state: CompositionState
    let onExit: () -> Void
    @State private var showsOrder = false
    @AppStorage("soundvision.guideDismissed") private var guideDismissed = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TabView(selection: $state.studioSection) {
            Tab("Estudio", systemImage: "waveform", value: StudioSection.transport) {
                page { overview; if state.isSpatialTestScene { guide } }
            }
            Tab("Sonidos", systemImage: "square.grid.2x2", value: StudioSection.sounds) {
                page { SoundLibraryView() }
            }
            Tab("Nodo", systemImage: "slider.horizontal.3", value: StudioSection.node) {
                page { inspector }
            }
            Tab("Aprender", systemImage: "graduationcap", value: StudioSection.learn) {
                page { MusicLearningView() }
            }
        }
        .background { StudioBackdrop() }
        .tint(StudioDesign.accent)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { playbackBar }
        .onChange(of: state.studioSection) { _, _ in state.endParameterEdit() }
        .sheet(isPresented: $showsOrder) { PlaybackOrderView() }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !guideDismissed && state.activeLesson == nil { quickStart }
                content()
            }
                .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 12) {
            Image(systemName: "waveform.path").font(.title2).foregroundStyle(StudioDesign.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("SOUNDVISION").font(.system(.callout, design: .rounded).weight(.heavy)).tracking(2)
                Text(state.activeLesson == nil ? "ESTUDIO ESPACIAL" : "PRÁCTICA MUSICAL")
                    .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Text(state.saveStatus).font(.caption2).foregroundStyle(.secondary)
            }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 8) {
            Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).disabled(!state.canUndo)
                .accessibilityLabel(state.undoLabel.map { "Deshacer \($0)" } ?? "Deshacer")
            Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).disabled(!state.canRedo)
                .accessibilityLabel(state.redoLabel.map { "Rehacer \($0)" } ?? "Rehacer")
            Menu {
                Button("Ver guía inicial") { guideDismissed = false; state.studioSection = .transport }
                Divider()
                Button { state.save() } label: { Label("Guardar composición", systemImage: "square.and.arrow.down") }
                    .disabled(state.activeLesson != nil)
                Button { state.load() } label: { Label("Cargar composición", systemImage: "folder") }
                Divider()
                Button { state.startNewComposition(); state.studioSection = .sounds } label: {
                    Label("Nueva composición", systemImage: "plus.rectangle.on.rectangle")
                }
                Button { state.loadSpatialTestScene(); state.studioSection = .transport } label: {
                    Label("Abrir demo espacial", systemImage: "ear.and.waveform")
                }
                Divider()
                Button("Salir del estudio", action: onExit)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("Opciones de composición")            }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(StudioDesign.ink.opacity(0.8))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    private var playbackBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                Button { state.togglePlayback() } label: {
                    Label(state.graphTransport.isPlaying ? "Detener" : "Reproducir",
                          systemImage: state.graphTransport.isPlaying ? "stop.fill" : "play.fill")
                        .font(.callout.bold()).frame(minWidth: 130, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.graphTransport.isPlaying ? .pink : StudioDesign.accent)
                .disabled(state.playEntryNodeID == nil)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(state.sequencer.bpm)) BPM").font(.callout.monospacedDigit().bold())
                    Label(state.graphTransport.isPlaying ? "EN VIVO" : "LISTO",
                          systemImage: state.graphTransport.isPlaying ? "circle.fill" : "circle")
                        .font(.caption2.bold()).foregroundStyle(state.graphTransport.isPlaying ? .green : .secondary)
                }
                if state.activeLesson != nil && state.studioSection != .learn {
                    Button { state.studioSection = .learn } label: { Image(systemName: "graduationcap") }
                        .accessibilityLabel("Volver a la práctica")
                }
            }
            if let hint = state.connectionHint {
                Label(hint, systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.cyan)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.hasPendingTimingChanges {
                Button { showsOrder = true } label: {
                    Label("Sonido en vivo · tiempos nuevos en el próximo Play", systemImage: "clock.arrow.circlepath")
                        .font(.caption2).foregroundStyle(.cyan)
                }.buttonStyle(.plain)
            }
            if let problem = state.audioProblem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = state.recoveryProblem {
                Label(problem, systemImage: "externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = state.statusMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(StudioDesign.ink.opacity(0.93))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            StudioHeading(eyebrow: "Tu sesión", title: "Dale forma al sonido",
                          detail: "Mueve, afina y transforma tus sonidos mientras la música sigue.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                metric("SONIDOS", value: "\(state.nodes.count)", icon: "waveform")
                metric("CON RUTA", value: "\(state.nodes.count - state.unreachableNodeIDs().count)", icon: "arrow.triangle.branch")
                metric("HABILITADOS", value: "\(state.nodes.filter { $0.isActive && $0.volume > 0 }.count)", icon: "speaker.wave.2")
                metric("SILENCIADOS", value: "\(state.nodes.filter { !$0.isActive || $0.volume == 0 }.count)", icon: "speaker.slash")
            }
            if state.nodes.isEmpty {
                StudioCard {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.cyan)
                    Text("Tu primera idea empieza con un sonido").font(.headline)
                    Text("Elige un timbre; será la entrada desde Play. Después conecta los demás a tu manera.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { state.studioSection = .sounds } label: {
                        Label("Explorar sonidos", systemImage: "plus").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button("Aprender con una práctica") { state.studioSection = .learn }.buttonStyle(.bordered)
                }
            } else {
                StudioCard {
                    HStack {
                        Label("Ritmo y recorrido", systemImage: "metronome").font(.headline)
                        Spacer()
                        Text("LOOP").font(.caption2.bold()).foregroundStyle(.cyan)
                    }
                    HStack {
                        Text("Tempo").font(.callout)
                        Slider(value: Binding(get: { state.sequencer.bpm }, set: { state.setTempo($0) }), in: 50...180, step: 1, onEditingChanged: { editing in
                            if editing { state.beginParameterEdit("Cambiar tempo") } else { state.endParameterEdit() }
                        })
                            .accessibilityLabel("Tempo en BPM").disabled(state.graphTransport.isPlaying)
                        Text("\(Int(state.sequencer.bpm))").font(.callout.monospacedDigit()).fixedSize()
                    }
                    if state.graphTransport.isPlaying {
                        Text("Tono, volumen y efectos responden en vivo. El tempo se ajusta con la pista detenida.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Ciclos del grafo") {
                        Stepper("Recorridos internos · \(state.graphTransport.loopPasses)×", value: Binding(
                            get: { state.graphTransport.loopPasses }, set: { state.setLoopPasses($0) }), in: 1...8)
                            .disabled(state.graphTransport.isPlaying)
                    }.font(.callout)
                    Button { showsOrder = true } label: {
                        Label("Ver orden de reproducción", systemImage: "list.number").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
                StudioCard(tint: .purple) {
                    HStack {
                        Text("En tu espacio").font(.headline)
                        Spacer()
                        Button { state.studioSection = .sounds } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Añadir sonidos")
                    }
                    let unreachable = state.unreachableNodeIDs()
                    ForEach(state.nodes) { node in
                        HStack(spacing: 12) {
                            Image(systemName: SoundNodeType.icon(for: node.type))
                                .foregroundStyle(Color(uiColor: NodeVisualStyle.style(for: node.type).color)).frame(width: 25)
                            Button {
                                state.focusNode(id: node.id); state.studioSection = .node
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name).font(.callout.bold())
                                    Text(nodeStatus(node, unreachable: unreachable))
                                        .font(.caption2).foregroundStyle(unreachable.contains(node.id) ? .orange : .secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { state.toggleNode(id: node.id) } label: {
                                Image(systemName: node.isActive ? "speaker.wave.2" : "speaker.slash")
                                    .foregroundStyle(node.isActive ? .cyan : .secondary).frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("\(node.isActive ? "Silenciar" : "Activar") \(node.name)")
                        }.padding(.vertical, 3)
                    }
                }
            }
            if let diagnostics = state.audioDiagnostics {
                DisclosureGroup("Diagnóstico de audio") { Text(diagnostics).font(.caption2.monospaced()) }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func nodeStatus(_ node: SoundNode, unreachable: Set<UUID>) -> String {
        let route = unreachable.contains(node.id) ? "Sin ruta desde Play" : node.id == state.playEntryNodeID ? "Entrada de Play" : "Con ruta desde Play"
        return route + (!node.isActive ? " · Silenciado" : node.volume == 0 ? " · Volumen 0 %" : " · Habilitado")
    }

    private var quickStart: some View {
        StudioCard {
            HStack {
                Label("Primeros pasos · \(min(state.onboardingProgress + 1, 3))/3", systemImage: "hand.draw")
                    .font(.callout.bold())
                Spacer()
                Button { guideDismissed = true } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Ocultar guía inicial")
            }
            let titles = ["Añade tu primer sonido", "Conecta una segunda idea", "Escucha tu composición", "Tu composición ya tiene vida"]
            let details = ["Abre Sonidos y elige un timbre. Será la única entrada desde Play.",
                "Añade otro sonido y une el punto luminoso del primero con él. También puedes usar Nodo → Añadir salida.",
                "Pulsa Reproducir. Mueve un sonido para cambiar su nota y usa los diales para transformarlo.",
                "Puedes seguir añadiendo ramas, editar mientras suena y deshacer tus ajustes."]
            Text(titles[state.onboardingProgress]).font(.headline)
            Text(details[state.onboardingProgress]).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(state.onboardingProgress), total: 3)
            if state.onboardingProgress == 0 {
                Button("Elegir sonido") { state.studioSection = .sounds }.buttonStyle(.bordered)
            } else if state.onboardingProgress == 3 {
                Button("Entendido") { guideDismissed = true }.buttonStyle(.bordered)
            }
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.system(.title2, design: .rounded).bold().monospacedDigit())
            Text(title).font(.caption2.bold()).tracking(0.6).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.white.opacity(0.035), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder private var inspector: some View {
        if state.nodes.isEmpty {
            StudioHeading(eyebrow: "Inspector", title: "Cada sonido, a tu medida", detail: "Añade un sonido para controlar su afinación, volumen y efectos.")
            Button("Elegir un sonido") { state.studioSection = .sounds }.buttonStyle(.borderedProminent)
        } else {
            Picker("Sonido seleccionado", selection: Binding(get: { state.selectedNodeID }, set: { id in
                if let id { state.focusNode(id: id) } else { state.clearSelection() }
            })) {
                Text("Selecciona un sonido").tag(nil as UUID?)
                ForEach(state.nodes) { node in Text(node.name).tag(Optional(node.id)) }
            }.pickerStyle(.menu)
            if let node = state.selectedNode {
                SoundMixerControls(node: node)
                if state.unreachableNodeIDs().contains(node.id) {
                    StudioCard(tint: .orange) {
                        Label("Este sonido aún no tiene ruta desde Play", systemImage: "arrow.triangle.branch").font(.callout)
                        if state.playEntryNodeID == nil {
                            Text("Usa Conectar a Play en las conexiones de abajo, o une el hilo con Play en el espacio.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Menu("Conectar desde…") {
                                ForEach(state.nodes.filter { !state.unreachableNodeIDs().contains($0.id) }) { source in
                                    Button(source.name) { _ = state.connect(sourceID: source.id, destinationID: node.id) }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                ConnectionEditorView(node: node)
                StudioCard {
                    DisclosureGroup("Posición en el espacio") {
                        axis("Izquierda / derecha", value: node.positionX, range: -2.4...2.4) {
                            state.moveNode(id: node.id, to: [$0, node.positionY, node.positionZ])
                        }
                        axis("Abajo / arriba", value: node.positionY, range: 0.35...2.5) {
                            state.moveNode(id: node.id, to: [node.positionX, $0, node.positionZ])
                        }
                        axis("Lejos / cerca", value: node.positionZ, range: -2...2.4) {
                            state.moveNode(id: node.id, to: [node.positionX, node.positionY, $0])
                        }
                    }
                }
            } else {
                ContentUnavailableView("Selecciona un sonido", systemImage: "hand.tap",
                    description: Text("Toca un organismo en el espacio o elígelo en el menú de arriba."))
            }
        }
    }

    private func axis(_ title: String, value: Float, range: ClosedRange<Float>, set: @escaping @MainActor @Sendable (Float) -> Void) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(value, specifier: "%+.2f") m").monospacedDigit() }
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { value }, set: { set($0) }), in: range, onEditingChanged: { editing in
                if editing { state.beginParameterEdit("Mover sonido") } else { state.endParameterEdit() }
            }).accessibilityLabel(title)
        }.padding(.top, 10)
    }

    private var guide: some View {
        StudioCard(tint: .purple) {
            Label("Demo espacial · \(state.testStep + 1)/\(CompositionState.spatialTestInstructions.count)", systemImage: "ear.and.waveform").font(.headline)
            Text(CompositionState.spatialTestInstructions[state.testStep]).font(.callout)
            HStack {
                Button("Anterior") { state.previousTestStep() }.disabled(state.testStep == 0)
                Button("Siguiente") { state.advanceTestStep() }.disabled(state.testStep == CompositionState.spatialTestInstructions.count - 1)
                Spacer()
                Button("Ocultar") { state.closeTestGuide() }
            }.buttonStyle(.bordered)
        }
    }
}

struct SoundMixerControls: View {
    @EnvironmentObject private var state: CompositionState
    let node: SoundNode
    private var color: Color { Color(uiColor: NodeVisualStyle.style(for: node.type).color) }

    var body: some View {
        StudioCard(tint: color) {
            HStack(spacing: 14) {
                Image(systemName: SoundNodeType.icon(for: node.type)).font(.title).foregroundStyle(color)
                    .frame(width: 52, height: 52).background(color.opacity(0.12), in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).font(.system(.title2, design: .rounded).bold())
                    Text(node.type.character).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { state.toggleNode(id: node.id) } label: {
                    Image(systemName: node.isActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 44, height: 44)
                }.buttonStyle(.borderless).accessibilityLabel(node.isActive ? "Silenciar sonido" : "Activar sonido")
            }
            InstrumentGlyph(type: node.type).frame(height: 44)
            Toggle(isOn: Binding(get: { node.isSoundLocked }, set: { _ in state.toggleSoundLock(id: node.id) })) {
                Label(node.isSoundLocked ? "Movimiento libre · sonido fijo" : "La posición transforma el sonido",
                      systemImage: node.isSoundLocked ? "lock.fill" : "move.3d")
                    .font(.caption)
            }
            Stepper(value: Binding(get: { Double(node.pitch) }, set: { state.setPitch(id: node.id, semitones: Float($0)) }), in: -24...24, step: 1) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Afinación · \(SpatialParameterMapper.noteName(for: node))").font(.callout.bold())
                    Text("\(Int(node.pitch)) semitonos").font(.caption2).foregroundStyle(.secondary)
                }
            }
            control("Volumen", icon: "speaker.wave.2", parameter: .volume, value: node.volume)
            Divider().overlay(.white.opacity(0.08))
            HStack { Text("EFECTOS").font(.caption2.bold()).tracking(1.5); Spacer(); Text("EDICIÓN EN VIVO").font(.caption2.bold()).foregroundStyle(.cyan) }
                .foregroundStyle(.secondary)
            control("Reverb", icon: "sparkles", parameter: .reverb, value: node.reverb)
            control("Delay", icon: "repeat", parameter: .delay, value: node.delay)
            control("Distorsión", icon: "waveform.path", parameter: .distortion, value: node.distortion)
            HStack {
                Button { state.previewSelectedNode() } label: { Label("Escuchar solo", systemImage: "play.circle") }
                    .disabled(!node.isActive || state.graphTransport.isPlaying)
                Spacer()
                Button(role: .destructive) { state.deleteSelectedNode() } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Eliminar \(node.name)")
            }.buttonStyle(.bordered)
        }
    }

    private func control(_ title: String, icon: String, parameter: SoundParameter, value: Float) -> some View {
        VStack(spacing: 2) {
            HStack {
                Label(title, systemImage: icon).font(.caption)
                Spacer()
                // Redondear, no truncar: `Int(0.34 * 100)` en Float da 33, así
                // que la consola enseñaba un porcentaje menos que el fader
                // espacial sobre el mismo valor.
                Text("\(Int((value * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            // Mismo paso de 1 % que el fader del nodo: los dos controles llegan
            // exactamente a los mismos valores y muestran el mismo número.
            Slider(value: Binding(get: { value }, set: { state.setSoundParameter(id: node.id, parameter: parameter, value: $0) }),
                   in: 0...1, step: Float(SpatialEffectDrag.step),
                   onEditingChanged: { if $0 { state.beginParameterEdit("Ajustar \(title)") } else { state.endParameterEdit() } })
                .accessibilityLabel(title)
        }
    }
}
