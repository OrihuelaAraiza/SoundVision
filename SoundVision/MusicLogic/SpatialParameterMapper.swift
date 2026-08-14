import Foundation
import simd

enum SpatialParameterMapper {
    static let neutralHeight: Float = 1.25

    static func pitch(forHeight height: Float) -> Float {
        clamp((height - neutralHeight) * 18, min: -24, max: 24)
    }

    /// En coordenadas locales, un Z mayor está más cerca del usuario.
    static func volume(forDepth depth: Float) -> Float {
        clamp(0.72 + depth * 0.22, min: 0.12, max: 1)
    }

    static func durationBeats(from source: SIMD3<Float>, to destination: SIMD3<Float>) -> Double {
        let horizontal = simd_distance(SIMD2(source.x, source.z), SIMD2(destination.x, destination.z))
        return Double(clamp(horizontal * 2, min: 0.25, max: 8))
    }

    static func effects(from rotation: SIMD3<Float>) -> (reverb: Float, delay: Float, distortion: Float) {
        (
            normalizedAngle(rotation.x),
            normalizedAngle(rotation.y),
            normalizedAngle(rotation.z)
        )
    }

    private static func normalizedAngle(_ angle: Float) -> Float {
        clamp(abs(angle) / .pi, min: 0, max: 1)
    }

    private static func clamp<T: Comparable>(_ value: T, min minimum: T, max maximum: T) -> T {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}
