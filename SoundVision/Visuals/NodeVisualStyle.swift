import Foundation
import UIKit

/// Define la personalidad visual y cinética de cada familia sonora.
struct NodeVisualStyle {
    let color: UIColor
    let baseScale: Float
    let triggerScale: Float
    let waveScale: Float
    let idleAmplitude: Float
    let idleSpeed: Float
    let verticalOffset: Float

    static func style(for type: SoundNodeType) -> NodeVisualStyle {
        switch type {
        case .kick:
            .init(color: UIColor(red: 0.94, green: 0.22, blue: 0.08, alpha: 1), baseScale: 1.05, triggerScale: 1.34, waveScale: 1.9, idleAmplitude: 0.012, idleSpeed: 0.75, verticalOffset: -0.12)
        case .snare:
            .init(color: UIColor(red: 1, green: 0.12, blue: 0.48, alpha: 1), baseScale: 1, triggerScale: 1.22, waveScale: 1.55, idleAmplitude: 0.018, idleSpeed: 1.3, verticalOffset: 0)
        case .hiHat:
            .init(color: UIColor(red: 1, green: 0.84, blue: 0.35, alpha: 1), baseScale: 0.94, triggerScale: 1.12, waveScale: 1.35, idleAmplitude: 0.025, idleSpeed: 2.1, verticalOffset: 0.13)
        case .clap:
            .init(color: UIColor(red: 1, green: 0.38, blue: 0.24, alpha: 1), baseScale: 1, triggerScale: 1.18, waveScale: 1.5, idleAmplitude: 0.016, idleSpeed: 1.45, verticalOffset: 0.02)
        case .bass:
            .init(color: UIColor(red: 0.19, green: 0.24, blue: 0.95, alpha: 1), baseScale: 1.08, triggerScale: 1.3, waveScale: 1.85, idleAmplitude: 0.01, idleSpeed: 0.55, verticalOffset: -0.08)
        case .pad:
            .init(color: UIColor(red: 0.14, green: 0.82, blue: 0.94, alpha: 1), baseScale: 1.06, triggerScale: 1.2, waveScale: 2.1, idleAmplitude: 0.04, idleSpeed: 0.42, verticalOffset: 0.1)
        case .lead:
            .init(color: UIColor(red: 0.12, green: 1, blue: 0.62, alpha: 1), baseScale: 1, triggerScale: 1.24, waveScale: 1.65, idleAmplitude: 0.03, idleSpeed: 1.05, verticalOffset: 0.14)
        case .fx:
            .init(color: UIColor(red: 0.65, green: 0.24, blue: 1, alpha: 1), baseScale: 1, triggerScale: 1.27, waveScale: 1.75, idleAmplitude: 0.035, idleSpeed: 1.8, verticalOffset: 0.06)
        }
    }
}
