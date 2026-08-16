import Foundation

/// Síntesis de una voz, horneada una sola vez al preparar la reproducción.
///
/// Antes cada organismo era un seno más ruido con una envolvente de potencia, lo
/// que sonaba a prueba de concepto. Ahora hay dos familias con tratamientos
/// distintos: los percusivos son transitorios y los tonales sostienen la nota
/// tanto como diga la distancia al siguiente organismo.
enum VoiceSynthesis {
    /// Techo del horneado. Sin él, dos organismos muy separados obligarían a
    /// sintetizar decenas de segundos en el hilo principal al pulsar Play.
    static let maximumDuration: TimeInterval = 4.5

    static func isPercussive(_ type: SoundNodeType) -> Bool {
        switch type {
        case .kick, .snare, .hiHat, .clap: true
        case .bass, .pad, .lead, .fx: false
        }
    }

    /// Cuánto suena la nota. En los tonales manda la distancia horizontal: lejos
    /// sostiene, cerca queda staccato. Los percusivos son un golpe y su longitud
    /// es propia del instrumento.
    static func duration(for type: SoundNodeType, sustainSeconds: TimeInterval?) -> TimeInterval {
        guard !isPercussive(type) else { return percussiveDuration(for: type) }
        let spec = tonalSpec(for: type)
        let held = min(max(sustainSeconds ?? 1.2, 0.18), maximumDuration - spec.release)
        return held + spec.release
    }

    static func bake(
        node: SoundNode,
        sustainSeconds: TimeInterval?,
        sampleRate: Double
    ) -> [Float] {
        let total = duration(for: node.type, sustainSeconds: sustainSeconds)
        let count = max(1, Int(total * sampleRate))
        let frequency = fundamental(for: node.type) * pow(2, Double(node.pitch) / 12)

        var dry = [Float](repeating: 0, count: count)
        if isPercussive(node.type) {
            bakePercussive(&dry, node: node, frequency: frequency, sampleRate: sampleRate)
        } else {
            bakeTonal(
                &dry,
                node: node,
                frequency: frequency,
                sampleRate: sampleRate,
                held: total - tonalSpec(for: node.type).release
            )
        }

        applyDelay(&dry, node: node, sampleRate: sampleRate)
        applyDistortion(&dry, node: node)

        // Red de seguridad: los ecos suman sobre la señal seca y el ruido
        // filtrado puede acercarse a la unidad. Garantiza el rango una sola vez
        // aquí en vez de confiar en que cada instrumento se porte bien.
        for index in dry.indices {
            dry[index] = max(-1, min(dry[index], 1))
        }
        return dry
    }

    // MARK: - Tonales

    private struct TonalSpec {
        let attack: Double
        let decay: Double
        let sustainLevel: Double
        let release: Double
        let cutoff: Double
        /// Múltiplo de la fundamental y su peso.
        let partials: [(Double, Float)]
    }

    private static func tonalSpec(for type: SoundNodeType) -> TonalSpec {
        switch type {
        case .bass:
            .init(attack: 0.012, decay: 0.18, sustainLevel: 0.75, release: 0.12, cutoff: 900,
                  partials: [(1, 1.0), (2, 0.32), (3, 0.14), (4, 0.06)])
        case .pad:
            .init(attack: 0.34, decay: 0.5, sustainLevel: 0.82, release: 0.7, cutoff: 2_200,
                  partials: [(1, 1.0), (2, 0.46), (3, 0.26), (5, 0.13), (7, 0.05)])
        case .lead:
            .init(attack: 0.008, decay: 0.14, sustainLevel: 0.62, release: 0.18, cutoff: 3_600,
                  partials: [(1, 1.0), (3, 0.34), (5, 0.19), (7, 0.11)])
        case .fx:
            .init(attack: 0.05, decay: 0.35, sustainLevel: 0.55, release: 0.45, cutoff: 2_800,
                  partials: [(1, 1.0), (2.41, 0.42), (4.13, 0.26), (6.7, 0.12)])
        case .kick, .snare, .hiHat, .clap:
            .init(attack: 0.005, decay: 0.1, sustainLevel: 0.5, release: 0.1, cutoff: 1_500,
                  partials: [(1, 1.0)])
        }
    }

    private static func bakeTonal(
        _ buffer: inout [Float],
        node: SoundNode,
        frequency: Double,
        sampleRate: Double,
        held: Double
    ) {
        let spec = tonalSpec(for: node.type)
        // Normaliza para que sumar armónicos no dispare el nivel.
        let weight = spec.partials.reduce(Float(0)) { $0 + $1.1 }
        let filterCoefficient = onePole(cutoff: spec.cutoff, sampleRate: sampleRate)
        var filtered: Float = 0

        for index in buffer.indices {
            let time = Double(index) / sampleRate
            var sample: Float = 0
            for (multiple, amplitude) in spec.partials {
                sample += Float(sin(2 * .pi * frequency * multiple * time)) * amplitude
            }
            sample /= weight

            // Un polo basta para quitar la aspereza de los armónicos altos.
            filtered += filterCoefficient * (sample - filtered)
            buffer[index] = filtered * envelope(at: time, spec: spec, held: held)
        }
    }

    private static func envelope(at time: Double, spec: TonalSpec, held: Double) -> Float {
        if time < spec.attack {
            return Float(time / spec.attack)
        }
        let sinceAttack = time - spec.attack
        if sinceAttack < spec.decay {
            let progress = sinceAttack / spec.decay
            return Float(1 + (spec.sustainLevel - 1) * progress)
        }
        if time < held {
            return Float(spec.sustainLevel)
        }
        let releaseProgress = (time - held) / spec.release
        return Float(spec.sustainLevel * max(0, 1 - releaseProgress))
    }

    // MARK: - Percusivos

    private static func percussiveDuration(for type: SoundNodeType) -> TimeInterval {
        switch type {
        case .kick: 0.42
        case .snare: 0.26
        case .hiHat: 0.11
        case .clap: 0.32
        default: 0.3
        }
    }

    private static func bakePercussive(
        _ buffer: inout [Float],
        node: SoundNode,
        frequency: Double,
        sampleRate: Double
    ) {
        let total = Double(buffer.count) / sampleRate
        let seed = UInt64(node.type.rawValue.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) })
        var lowpass: Float = 0
        var highpassPrevious: Float = 0
        var highpassOutput: Float = 0
        let lowCoefficient = onePole(cutoff: node.type == .snare ? 6_000 : 9_000, sampleRate: sampleRate)

        for index in buffer.indices {
            let time = Double(index) / sampleRate
            let progress = time / total
            let noise = deterministicNoise(sample: Int64(index), seed: seed)

            switch node.type {
            case .kick:
                // El barrido de tono es lo que da el golpe en el pecho.
                let swept = frequency * (1 + 3.2 * exp(-time / 0.028))
                let body = Float(sin(2 * .pi * swept * time))
                buffer[index] = body * Float(exp(-time / 0.11))

            case .snare:
                let body = Float(sin(2 * .pi * frequency * time)) * 0.35
                lowpass += lowCoefficient * (noise - lowpass)
                buffer[index] = (body + lowpass * 0.6) * Float(exp(-time / 0.055))

            case .hiHat:
                // Paso alto sencillo: la diferencia entre muestras quita graves.
                highpassOutput = 0.92 * (highpassOutput + noise - highpassPrevious)
                highpassPrevious = noise
                buffer[index] = highpassOutput * 0.38 * Float(exp(-time / 0.018))

            case .clap:
                // Tres ráfagas muy juntas y una cola: así suena una palmada.
                let bursts = [0.0, 0.011, 0.023]
                var amplitude: Float = 0
                for burst in bursts where time >= burst && time < burst + 0.009 {
                    amplitude = 0.9
                }
                if time >= 0.032 {
                    amplitude = Float(exp(-(time - 0.032) / 0.07)) * 0.55
                }
                lowpass += lowCoefficient * (noise - lowpass)
                buffer[index] = lowpass * amplitude

            case .bass, .pad, .lead, .fx:
                buffer[index] = 0
            }

            // Cierre suave para que ningún golpe termine en un clic.
            if progress > 0.88 {
                buffer[index] *= Float((1 - progress) / 0.12)
            }
        }
    }

    // MARK: - Efectos

    private static func applyDelay(_ buffer: inout [Float], node: SoundNode, sampleRate: Double) {
        guard node.delay > 0.001 else { return }
        let offset = max(1, Int((0.07 + Double(node.delay) * 0.48) * sampleRate))
        // Los ecos reindexan la señal ya escrita en vez de resintetizarla.
        for index in buffer.indices {
            var value = buffer[index]
            if index >= offset { value += buffer[index - offset] * node.delay * 0.42 }
            if index >= offset * 2 { value += buffer[index - offset * 2] * node.delay * 0.18 }
            buffer[index] = value
        }
    }

    private static func applyDistortion(_ buffer: inout [Float], node: SoundNode) {
        guard node.distortion > 0.001 else { return }
        let drive = 1 + node.distortion * 8
        let normalization = max(1, tanh(drive))
        for index in buffer.indices {
            buffer[index] = tanh(buffer[index] * drive) / normalization
        }
    }

    // MARK: - Utilidades

    private static func fundamental(for type: SoundNodeType) -> Double {
        switch type {
        case .kick: 52
        case .snare: 190
        case .hiHat: 320
        case .clap: 400
        case .bass: 55
        case .pad: 220
        case .lead: 440
        case .fx: 330
        }
    }

    private static func onePole(cutoff: Double, sampleRate: Double) -> Float {
        Float(1 - exp(-2 * .pi * cutoff / sampleRate))
    }

    private static func deterministicNoise(sample: Int64, seed: UInt64) -> Float {
        var value = UInt64(bitPattern: sample) &+ seed
        value ^= value >> 30
        value &*= 0xbf58_476d_1ce4_e5b9
        value ^= value >> 27
        value &*= 0x94d0_49bb_1331_11eb
        value ^= value >> 31
        return Float(Double(value) / Double(UInt64.max) * 2 - 1)
    }
}
