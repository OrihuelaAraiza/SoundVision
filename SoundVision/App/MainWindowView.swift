import SwiftUI

/// Una sola ventana que alterna entre lanzador y consola. Al estar montada
/// sobre el chrome estándar de visionOS, la persona puede recolocarla con la
/// barra del sistema y siempre puede recuperarla; no hace falta ningún
/// mecanismo propio de "recentrar menús".
struct MainWindowView: View {
    @EnvironmentObject private var state: CompositionState
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isTransitioning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if state.isImmersiveSpaceOpen {
                StudioConsoleView { Task { await closeStudio() } }
            } else {
                launcher
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: state.isImmersiveSpaceOpen)
    }

    private var launcher: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("SOUNDVISION").font(.system(.callout, design: .rounded).weight(.heavy)).tracking(3)
                    Spacer()
                    Text("Surgery of Sound").font(.caption).foregroundStyle(.cyan)
                }
                StudioEmblem().frame(height: 170).frame(maxWidth: .infinity)
                StudioHeading(eyebrow: "Música que puedes tocar", title: "Tu espacio. Tu sonido.",
                              detail: "Construye música con las manos. Conecta ideas y transfórmalas mientras suenan.")
                HStack(spacing: 18) {
                    Label("24 timbres", systemImage: "waveform")
                    Label("4 prácticas", systemImage: "graduationcap")
                }.font(.caption).foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    if !state.nodes.isEmpty {
                        Button { Task { await start {} } } label: {
                            Label("Continuar mi composición", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 38)
                        }.buttonStyle(.borderedProminent).tint(StudioDesign.accent)
                    }
                    Button {
                        Task { await start { state.startNewComposition(); state.studioSection = .sounds } }
                    } label: {
                        Label("Crear una composición", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 38)
                    }.buttonStyle(.borderedProminent).tint(state.nodes.isEmpty ? StudioDesign.accent : .purple)

                    HStack(spacing: 12) {
                        Button { Task { await start { state.studioSection = .learn } } } label: {
                            Label("Aprender", systemImage: "graduationcap").frame(maxWidth: .infinity, minHeight: 34)
                        }
                        Button { Task { await start { state.loadSpatialTestScene(); state.studioSection = .transport } } } label: {
                            Label("Explorar demo", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 34)
                        }
                    }.buttonStyle(.bordered)
                    Button { Task { await start { state.load(); state.studioSection = .transport } } } label: {
                        Label("Abrir composición guardada", systemImage: "folder").frame(maxWidth: .infinity, minHeight: 28)
                    }.buttonStyle(.borderless)
                }
                .disabled(isTransitioning)
                .lineLimit(1).minimumScaleFactor(0.8)
                if isTransitioning {
                    ProgressView("Preparando tu espacio…").font(.caption)
                } else if let message = state.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("Sintetizado en tu dispositivo · Hecho para el espacio")
                    .font(.caption2).foregroundStyle(.tertiary)
            }.padding(32)
        }
        .background { StudioBackdrop() }
    }

    @MainActor
    private func start(_ prepare: () -> Void) async {
        guard !isTransitioning, !state.isImmersiveSpaceOpen else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        switch await openImmersiveSpace(id: ImmersiveSpaceID.soundLab) {
        case .opened:
            prepare()
            state.isImmersiveSpaceOpen = true
        case .error:
            state.statusMessage = "No se pudo abrir el espacio inmersivo."
        case .userCancelled:
            state.statusMessage = "Apertura cancelada."
        @unknown default:
            state.statusMessage = "Resultado inesperado al abrir el espacio."
        }
    }

    @MainActor
    private func closeStudio() async {
        state.stopPlayback()
        await dismissImmersiveSpace()
        state.isImmersiveSpaceOpen = false
    }
}
