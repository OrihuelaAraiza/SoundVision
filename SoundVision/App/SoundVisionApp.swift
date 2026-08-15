import SwiftUI

@main
struct SoundVisionApp: App {
    @StateObject private var compositionState = CompositionState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(compositionState)
        }
        .windowStyle(.plain)
        .defaultSize(width: 760, height: 620)

        WindowGroup(id: StudioWindowID.controls) {
            FloatingStudioControlsView()
                .environmentObject(compositionState)
        }
        .defaultSize(width: 430, height: 590)

        ImmersiveSpace(id: ImmersiveSpaceID.soundLab) {
            SoundSculptureView()
                .environmentObject(compositionState)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

enum ImmersiveSpaceID {
    static let soundLab = "sound-lab"
}

enum StudioWindowID {
    static let controls = "soundvision-controls"
}
