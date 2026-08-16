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

    var body: some View {
        Group {
            if state.isImmersiveSpaceOpen {
                StudioConsoleView { Task { await closeStudio() } }
            } else {
                launcher
            }
        }
        .animation(.snappy(duration: 0.25), value: state.isImmersiveSpaceOpen)
    }

    private var launcher: some View {
        VStack(spacing: 26) {
            Spacer()

            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 64, weight: .thin))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.cyan, .purple)

            VStack(spacing: 8) {
                Text("SOUNDVISION")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(6)
                Text("Surgery of Sound")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.cyan)
                Text("Construye música conectando organismos sonoros en el espacio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await start { state.startNewComposition() } }
                } label: {
                    Label("Nueva pista", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button {
                    Task { await start { state.loadSpatialTestScene() } }
                } label: {
                    Label("Abrir demo espacial", systemImage: "ear.and.waveform")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button {
                    Task { await start { state.load() } }
                } label: {
                    Label("Cargar composición guardada", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
            }
            .disabled(isTransitioning)
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
        .padding(40)
    }

    @MainActor
    private func start(_ prepare: () -> Void) async {
        prepare()
        guard !state.isImmersiveSpaceOpen else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        switch await openImmersiveSpace(id: ImmersiveSpaceID.soundLab) {
        case .opened:
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
