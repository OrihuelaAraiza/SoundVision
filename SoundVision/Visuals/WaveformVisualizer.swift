import Foundation
import RealityKit

/// Ondas que salen del organismo cuando suena.
///
/// Antes era una sola esfera que aparecía y desaparecía de golpe, lo que se leía
/// como un parpadeo y no como sonido emitido. Ahora cada ataque lanza una onda
/// que se expande y se desvanece, y varias pueden convivir: en un pasaje rápido
/// se ven salir una tras otra, que es lo que hace el sonido de verdad.
enum WaveformVisualizer {
    /// Cuántas ondas pueden estar en el aire a la vez. Con notas cortas y
    /// seguidas hacen falta varias; más allá de esto se solapan sin aportar.
    static let concurrentWaves = 4
    static let lifetime: TimeInterval = 0.75

    static func makeWaves(for type: SoundNodeType) -> [ModelEntity] {
        (0..<concurrentWaves).map { index in
            let wave = ModelEntity(
                mesh: .generateSphere(radius: 0.2),
                materials: [SoundVisionMaterials.translucentAccent(for: type, alpha: 0.42)]
            )
            wave.name = name(at: index)
            wave.isEnabled = false
            return wave
        }
    }

    static func name(at index: Int) -> String { "trigger-wave-\(index)" }

    /// Expande y desvanece cada onda viva. La opacidad se modula con
    /// `OpacityComponent`, que RealityKit resuelve sin reconstruir materiales:
    /// hacerlo cambiando el material costaría una asignación por frame y por onda.
    static func update(in root: Entity, style: NodeVisualStyle, birthTimes: SIMD4<Double>, time: TimeInterval) {
        for index in 0..<concurrentWaves {
            guard let wave = root.findEntity(named: name(at: index)) else { continue }
            let age = time - birthTimes[index]

            guard age >= 0, age < lifetime else {
                if wave.isEnabled { wave.isEnabled = false }
                continue
            }

            let progress = Float(age / lifetime)
            wave.isEnabled = true
            // Arranca pegada al cuerpo y se aleja frenando, como se dispersa
            // una onda de verdad.
            let eased = 1 - (1 - progress) * (1 - progress)
            wave.scale = SIMD3(repeating: 0.55 + eased * (style.waveScale - 0.55))
            wave.components.set(OpacityComponent(opacity: (1 - progress) * 0.9))
        }
    }
}
