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
