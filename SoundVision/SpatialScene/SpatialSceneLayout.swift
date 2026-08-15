import CoreGraphics
import Foundation
import simd

enum SpatialSceneLayout {
    /// El origen de ImmersiveSpace está a nivel del suelo. Los nodos ya guardan
    /// alturas humanas, por lo que la raíz no debe volver a bajarlos.
    static let rootPosition = SIMD3<Float>(0, 0, -1.65)

    static func dropPosition(at location: CGPoint, in viewport: CGSize) -> SIMD3<Float> {
        guard viewport.width > 0, viewport.height > 0 else {
            return [0.65, SpatialParameterMapper.neutralHeight, 0]
        }
        let normalizedX = Float(location.x / viewport.width - 0.5)
        let normalizedY = Float(1 - location.y / viewport.height)
        return [
            normalizedX * 2.8,
            0.65 + normalizedY * 1.35,
            0
        ]
    }
}
