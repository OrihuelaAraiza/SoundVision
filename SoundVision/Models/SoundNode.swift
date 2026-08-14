import Foundation

enum SoundNodeType: String, Codable, CaseIterable, Sendable {
    case kick, snare, hiHat, clap, bass, pad, lead, fx
}

struct SoundNode: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var type: SoundNodeType
    var isActive: Bool
    var volume: Float
    var pitch: Float
    var stepIndex: Int
    var positionX: Float
    var positionY: Float
    var positionZ: Float

    static func starterPattern(radius: Float = 1.15) -> [SoundNode] {
        let definitions: [(String, SoundNodeType, Int, Bool)] = [
            ("Kick", .kick, 0, true), ("Snare", .snare, 2, true),
            ("Hi-hat", .hiHat, 4, true), ("Clap", .clap, 6, false),
            ("Bass", .bass, 8, true), ("Pad", .pad, 10, true),
            ("Lead", .lead, 12, false), ("FX", .fx, 14, true)
        ]

        return definitions.enumerated().map { index, definition in
            let angle = Float(index) / Float(definitions.count) * 2 * .pi
            return SoundNode(
                id: UUID(), name: definition.0, type: definition.1,
                isActive: definition.3, volume: 0.78, pitch: 0,
                stepIndex: definition.2,
                positionX: cos(angle) * radius,
                positionY: 1.25 + sin(Float(index) * 1.7) * 0.12,
                positionZ: sin(angle) * radius
            )
        }
    }
}

struct Composition: Codable, Equatable, Sendable {
    var title: String
    var bpm: Double
    var steps: Int
    var nodes: [SoundNode]
}
