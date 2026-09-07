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
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 64, weight: .thin))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.cyan, .purple)

            VStack(spacing: 8) {
                Text("SOUNDVISION")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(6)
                    // Con el tracking, el título roza los 366 pt: si la ventana
                    // se estrecha debe encoger, no recortarse.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Surgery of Sound")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.cyan)
                Text("Construye música conectando organismos sonoros en el espacio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                if !state.nodes.isEmpty {
                    Button { Task { await start {} } } label: {
                        Label("Continuar composición", systemImage: "arrow.uturn.forward")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    Task { await start { state.studioSection = .learn } }
                } label: {
                    Label("Aprender música", systemImage: "graduationcap")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await start { state.startNewComposition(); state.studioSection = .sounds } }
                } label: {
                    Label("Nueva pista", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button {
                    Task { await start { state.loadSpatialTestScene(); state.studioSection = .transport } }
                } label: {
                    Label("Abrir demo espacial", systemImage: "ear.and.waveform")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button {
                    Task { await start { state.load(); state.studioSection = .transport } }
                } label: {
                    Label("Cargar composición guardada", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
            }
            .disabled(isTransitioning)
            // "Cargar composición guardada" es la etiqueta más larga: dentro de
            // 340 pt entra, pero que encoja antes que recortarse.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: 340)

            if let message = state.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text("Los controles aparecen en esta misma ventana al entrar al estudio.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        }
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
