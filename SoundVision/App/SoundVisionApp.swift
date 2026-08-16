import RealityKit
import SwiftUI

@main
struct SoundVisionApp: App {
    @StateObject private var compositionState = CompositionState()

    init() {
        // Los sistemas animan la escultura a la tasa de refresco de RealityKit.
        SoundNodeVisualComponent.registerComponent()
        TransportVisualComponent.registerComponent()
        NodeAnimationSystem.registerSystem()
        TransportAnimationSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(compositionState)
        }
        .defaultSize(width: 520, height: 760)

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
