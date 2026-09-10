import Foundation
import simd

enum SpatialNodePlacement {
    // Conservative bounds include the largest animated body and its idle offset.
    // Interaction handles are tested separately against the rendered geometry.
    static func radius(for type: SoundNodeType) -> Float {
        switch type {
        case .pad, .strings, .organ, .brass, .fx: 0.44
        case .kick, .lead, .flute, .bell, .cowbell: 0.50
        case .hiHat, .openHat: 0.46
        case .shaker: 0.44
        case .bass, .subBass: 0.40
        default: 0.36
        }
    }

    static func position(for type: SoundNodeType, among nodes: [SoundNode], play: SIMD3<Float>) -> SIMD3<Float> {
        let center = SIMD3<Float>(0, 1.25, -0.25)
        // Forty coarse slots retain a full body diameter plus 10 cm of clearance.
        // Keep these slots ahead of the dense fallback: greedy insertion into a
        // fine grid can leave unusable pockets before reaching the 32-node limit.
        var slots: [SIMD3<Float>] = []
        for y in 0...1 {
            for z in 0...3 {
                for x in 0...4 {
                    slots.append([-2.2 + Float(x) * 1.1, 0.65 + Float(y) * 1.1, -1.7 + Float(z) * 1.1])
                }
            }
        }
        var fallback: [SIMD3<Float>] = []
        for y in 0...7 {
            for z in 0...16 {
                for x in 0...18 {
                    fallback.append([-2.25 + Float(x) * 0.25, 0.55 + Float(y) * 0.25, -1.9 + Float(z) * 0.25])
                }
            }
        }
        func nearer(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
            let da = simd_distance_squared(a, center), db = simd_distance_squared(b, center)
            if abs(da - db) > 0.0001 { return da < db }
            if a.y != b.y { return a.y < b.y }
            if a.z != b.z { return a.z < b.z }
            return a.x < b.x
        }
        let candidates = slots.sorted(by: nearer) + fallback.sorted(by: nearer)
        var best = candidates[0]
        var bestGap = -Float.infinity
        for candidate in candidates {
            var gap = simd_distance(candidate, play) - radius(for: type) - 0.5
            for node in nodes {
                gap = min(gap, simd_distance(candidate, [node.positionX, node.positionY, node.positionZ])
                    - radius(for: type) - radius(for: node.type))
            }
            if gap >= 0.08 { return candidate }
            if gap > bestGap { best = candidate; bestGap = gap }
        }
        return best
    }
}
