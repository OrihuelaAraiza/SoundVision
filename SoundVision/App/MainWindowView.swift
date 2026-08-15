import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var state: CompositionState
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var isTransitioning = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.035, blue: 0.08), Color(red: 0.08, green: 0.025, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 68, weight: .thin))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.cyan, .purple)
                    .shadow(color: .cyan.opacity(0.7), radius: 24)

                VStack(spacing: 8) {
                    Text("SOUNDVISION")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .tracking(8)
                    Text("Surgery of Sound")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.cyan)
                    Text("Construye música conectando organismos sonoros en el espacio.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Button {
                        Task { await startNewTrack() }
                    } label: {
                        Label("Nueva pista", systemImage: "plus.rectangle.on.rectangle")
                            .frame(minWidth: 190)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(isTransitioning)

                    Button {
                        Task { await startSpatialTest() }
                    } label: {
                        Label("Abrir demo", systemImage: "ear.and.waveform")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isTransitioning)

                    Button {
                        Task { await toggleImmersiveSpace() }
                    } label: {
                        Label(
                            state.isImmersiveSpaceOpen ? "Cerrar estudio" : "Entrar al estudio",
                            systemImage: state.isImmersiveSpaceOpen ? "xmark" : "visionpro"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTransitioning)
                }

                Button {
                    Task {
                        state.load()
                        await openStudioIfNeeded()
                    }
                } label: {
                    Label("Cargar composición guardada", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)

                if state.isImmersiveSpaceOpen {
                    Button {
                        openWindow(id: StudioWindowID.controls)
                    } label: {
                        Label("Abrir controles movibles", systemImage: "macwindow.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                }

                Divider().opacity(0.35)

                HStack(spacing: 32) {
                    metric(title: "TEMPO", value: "\(Int(state.sequencer.bpm)) BPM")
                    metric(title: "NODOS", value: "\(state.nodes.count)")
                    metric(title: "CONEXIONES", value: "\(state.connections.count)")
                }

                if let message = state.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(52)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
    }

    @MainActor
    private func startSpatialTest() async {
        state.loadSpatialTestScene()
        await openStudioIfNeeded()
    }

    @MainActor
    private func startNewTrack() async {
        state.startNewComposition()
        await openStudioIfNeeded()
    }

    @MainActor
    private func openStudioIfNeeded() async {
        guard !state.isImmersiveSpaceOpen else { return }
        await toggleImmersiveSpace()
    }

    @MainActor
    private func toggleImmersiveSpace() async {
        isTransitioning = true
        defer { isTransitioning = false }

        if state.isImmersiveSpaceOpen {
            await dismissImmersiveSpace()
            state.isImmersiveSpaceOpen = false
            state.stopPlayback()
        } else {
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
    }
}
