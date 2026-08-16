import Foundation
import simd

enum SpatialSceneLayout {
    /// El origen de ImmersiveSpace está a nivel del suelo. Los nodos ya guardan
    /// alturas humanas, por lo que la raíz no debe volver a bajarlos.
    static let rootPosition = SIMD3<Float>(0, 0, -1.65)
}
