import Foundation

/// Descripción de un instrumento: envolvente, armónicos y color. Son datos
/// puros, compartidos por el sintetizador en tiempo real.
struct InstrumentSpec {
    let isPercussive: Bool
    let fundamental: Double
    let attack: Double
    let decay: Double
    let sustainLevel: Double
    let release: Double
    let cutoff: Double
    /// Múltiplos de la fundamental y su peso relativo.
    let partials: [(multiple: Double, amplitude: Float)]

    var partialWeight: Float {
        partials.reduce(0) { $0 + $1.amplitude }
    }
}

enum VoiceSynthesis {
    /// Techo del sostenido de una nota tonal.
    static let maximumDuration: TimeInterval = 4.5

    static func isPercussive(_ type: SoundNodeType) -> Bool {
        spec(for: type).isPercussive
    }

    /// Cuánto suena la nota. En los tonales manda la distancia horizontal: lejos
    /// sostiene, cerca queda staccato. Los percusivos son un golpe y su longitud
    /// es propia del instrumento.
    static func duration(for type: SoundNodeType, sustainSeconds: TimeInterval?) -> TimeInterval {
        let spec = spec(for: type)
        guard !spec.isPercussive else { return percussiveDuration(for: type) }
        let held = min(max(sustainSeconds ?? 1.2, 0.18), maximumDuration - spec.release)
        return held + spec.release
    }

    static func percussiveDuration(for type: SoundNodeType) -> TimeInterval {
        switch type {
        case .kick: 0.42
        case .snare: 0.26
        case .hiHat: 0.11
        case .clap: 0.32
        case .tom: 0.55
        case .shaker: 0.16
        default: 0.3
        }
    }

    static func spec(for type: SoundNodeType) -> InstrumentSpec {
        switch type {
        case .kick:
            .init(isPercussive: true, fundamental: 52, attack: 0, decay: 0, sustainLevel: 0,
                  release: 0, cutoff: 9_000, partials: [(1, 1)])
        case .snare:
            .init(isPercussive: true, fundamental: 190, attack: 0, decay: 0, sustainLevel: 0,
                  release: 0, cutoff: 6_000, partials: [(1, 1)])
        case .hiHat:
            .init(isPercussive: true, fundamental: 320, attack: 0, decay: 0, sustainLevel: 0,
                  release: 0, cutoff: 9_000, partials: [(1, 1)])
        case .clap:
            .init(isPercussive: true, fundamental: 400, attack: 0, decay: 0, sustainLevel: 0,
                  release: 0, cutoff: 9_000, partials: [(1, 1)])
        case .tom:
            .init(isPercussive: true, fundamental: 110, attack: 0, decay: 0, sustainLevel: 0,
                  release: 0, cutoff: 4_000, partials: [(1, 1)])
        case .shaker:
            .init(isPercussive: true, fundamental: 800, attack: 0, decay: 0, sustainLevel: 0,
                  release: 0, cutoff: 8_000, partials: [(1, 1)])
        case .bell:
            .init(isPercussive: false, fundamental: 440, attack: 0.003, decay: 0.65,
                  sustainLevel: 0.08, release: 0.55, cutoff: 7_000,
                  partials: [(1, 1), (2.76, 0.42), (5.4, 0.2), (8.93, 0.08)])
        case .marimba:
            .init(isPercussive: false, fundamental: 220, attack: 0.002, decay: 0.3,
                  sustainLevel: 0.03, release: 0.18, cutoff: 3_000,
                  partials: [(1, 1), (4, 0.24), (10, 0.06)])
        case .pluck:
            .init(isPercussive: false, fundamental: 220, attack: 0.003, decay: 0.22,
                  sustainLevel: 0.12, release: 0.2, cutoff: 4_800,
                  partials: [(1, 1), (2, 0.5), (3, 0.28), (4, 0.15), (6, 0.07)])
        case .organ:
            .init(isPercussive: false, fundamental: 220, attack: 0.025, decay: 0.08,
                  sustainLevel: 0.9, release: 0.16, cutoff: 5_000,
                  partials: [(1, 1), (2, 0.7), (3, 0.4), (4, 0.32), (8, 0.12)])
        case .bass:
            .init(isPercussive: false, fundamental: 55, attack: 0.012, decay: 0.18,
                  sustainLevel: 0.75, release: 0.12, cutoff: 900,
                  partials: [(1, 1.0), (2, 0.32), (3, 0.14), (4, 0.06)])
        case .pad:
            .init(isPercussive: false, fundamental: 220, attack: 0.34, decay: 0.5,
                  sustainLevel: 0.82, release: 0.7, cutoff: 2_200,
                  partials: [(1, 1.0), (2, 0.46), (3, 0.26), (5, 0.13), (7, 0.05)])
        case .lead:
            .init(isPercussive: false, fundamental: 440, attack: 0.008, decay: 0.14,
                  sustainLevel: 0.62, release: 0.18, cutoff: 3_600,
                  partials: [(1, 1.0), (3, 0.34), (5, 0.19), (7, 0.11)])
        case .fx:
            .init(isPercussive: false, fundamental: 330, attack: 0.05, decay: 0.35,
                  sustainLevel: 0.55, release: 0.45, cutoff: 2_800,
                  partials: [(1, 1.0), (2.41, 0.42), (4.13, 0.26), (6.7, 0.12)])
        }
    }

    static func frequency(for type: SoundNodeType, pitch: Float) -> Double {
        spec(for: type).fundamental * pow(2, Double(pitch) / 12)
    }

    // MARK: - Primitivas aptas para el hilo de audio

    private static let tableSize = 4_096
    private static let tableMask = tableSize - 1

    /// Tabla de seno con interpolación lineal. En tiempo real hay que producir
    /// una muestra por armónico y por frame: llamar a `sin()` ahí sería
    /// gratuitamente caro.
    static let sineTable: [Float] = (0..<tableSize).map {
        Float(sin(2 * .pi * Double($0) / Double(tableSize)))
    }

    /// `cycles` va en vueltas completas, no en radianes.
    @inline(__always)
    static func sine(cycles: Double) -> Float {
        let wrapped = cycles - floor(cycles)
        let position = wrapped * Double(tableSize)
        let index = Int(position)
        let fraction = Float(position - Double(index))
        let current = sineTable[index & tableMask]
        let next = sineTable[(index + 1) & tableMask]
        return current + (next - current) * fraction
    }

    /// Ruido reproducible y sin estado: la misma muestra da siempre el mismo
    /// valor, lo que permite sintetizar percusión sin guardar nada entre notas.
    @inline(__always)
    static func noise(sample: Int64, seed: UInt64) -> Float {
        var value = UInt64(bitPattern: sample) &+ seed
        value ^= value >> 30
        value &*= 0xbf58_476d_1ce4_e5b9
        value ^= value >> 27
        value &*= 0x94d0_49bb_1331_11eb
        value ^= value >> 31
        return Float(Double(value) / Double(UInt64.max) * 2 - 1)
    }

    static func seed(for type: SoundNodeType) -> UInt64 {
        UInt64(type.rawValue.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) })
    }

    @inline(__always)
    static func onePoleCoefficient(cutoff: Double, sampleRate: Double) -> Float {
        Float(1 - exp(-2 * .pi * cutoff / sampleRate))
    }

    /// Saturación suave. Aproximación de `tanh` sin transcendentales, porque
    /// esto corre por muestra y `tanh` no tiene sitio en el hilo de audio.
    @inline(__always)
    static func softClip(_ value: Float, drive: Float) -> Float {
        let x = max(-3, min(value * drive, 3))
        let shaped = x * (27 + x * x) / (27 + 9 * x * x)
        return shaped
    }

    /// Envolvente ADSR evaluada desde el inicio de la nota.
    @inline(__always)
    static func envelope(at time: Double, spec: InstrumentSpec, held: Double) -> Float {
        if time < 0 { return 0 }
        if time < spec.attack {
            return Float(time / spec.attack)
        }
        let sinceAttack = time - spec.attack
        if sinceAttack < spec.decay {
            return Float(1 + (spec.sustainLevel - 1) * (sinceAttack / spec.decay))
        }
        if time < held {
            return Float(spec.sustainLevel)
        }
        let releaseProgress = (time - held) / spec.release
        return releaseProgress >= 1 ? 0 : Float(spec.sustainLevel * (1 - releaseProgress))
    }

    /// Forma de onda percusiva, cerrada en el tiempo desde el ataque. Al no
    /// guardar estado, varios golpes solapados se suman sin reservar voces.
    @inline(__always)
    static func percussiveSample(
        type: SoundNodeType,
        localTime: Double,
        frequency: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> Float {
        let index = Int64(localTime * sampleRate)
        let total = percussiveDuration(for: type)
        guard localTime >= 0, localTime < total else { return 0 }

        var value: Float
        switch type {
        case .kick:
            // El barrido de tono es lo que da el golpe en el pecho.
            let swept = frequency * (1 + 3.2 * exp(-localTime / 0.028))
            value = sine(cycles: swept * localTime) * Float(exp(-localTime / 0.11))

        case .snare:
            // Media de muestras vecinas en lugar de un filtro con estado:
            // suaviza el ruido sin tener que recordar nada entre bloques.
            let smoothed = (noise(sample: index, seed: seed)
                + noise(sample: index - 1, seed: seed)
                + noise(sample: index - 2, seed: seed)) / 3
            let body = sine(cycles: frequency * localTime) * 0.35
            value = (body + smoothed * 0.6) * Float(exp(-localTime / 0.055))

        case .hiHat:
            // La diferencia entre muestras vecinas actúa como paso alto.
            let bright = noise(sample: index, seed: seed) - noise(sample: index - 1, seed: seed)
            value = bright * 0.34 * Float(exp(-localTime / 0.018))

        case .clap:
            var amplitude: Float = 0
            for burst in [0.0, 0.011, 0.023] where localTime >= burst && localTime < burst + 0.009 {
                amplitude = 0.9
            }
            if localTime >= 0.032 {
                amplitude = Float(exp(-(localTime - 0.032) / 0.07)) * 0.55
            }
            let smoothed = (noise(sample: index, seed: seed) + noise(sample: index - 1, seed: seed)) / 2
            value = smoothed * amplitude

        case .tom:
            let phase = frequency * (localTime + 0.018 * (1 - exp(-localTime / 0.045)))
            value = (sine(cycles: phase) + 0.2 * sine(cycles: phase * 1.6))
                * Float(exp(-localTime / 0.14)) * 0.75
        case .shaker:
            let bright = noise(sample: index, seed: seed) - noise(sample: index - 1, seed: seed)
            let swell = min(localTime / 0.018, 1) * exp(-localTime / 0.04)
            value = bright * Float(swell) * 0.48
        case .bass, .pad, .lead, .fx, .bell, .marimba, .pluck, .organ:
            return 0
        }

        // Cierre suave para que ningún golpe termine en un clic.
        let progress = localTime / total
        if progress > 0.88 {
            value *= Float((1 - progress) / 0.12)
        }
        return value
    }
}
