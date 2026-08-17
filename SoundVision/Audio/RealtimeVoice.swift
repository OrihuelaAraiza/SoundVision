import AVFAudio
import Foundation
import RealityKit

/// Parámetros que la mano puede cambiar mientras la música suena.
///
/// El hilo principal escribe; el de audio lee. No hay locks porque en el hilo de
/// audio no puede haberlos, y no hacen falta: son escalares alineados
/// independientes entre sí, sin ninguna invariante que los relacione. Lo peor
/// que puede pasar es que un bloque mezcle valores de dos instantes contiguos,
/// diferencia inaudible. Cada campo se lee **una vez por bloque** y se desliza
/// hacia su destino, de modo que ni siquiera un salto brusco produce un clic.
final class LiveVoiceParameters: @unchecked Sendable {
    var frequency: Double = 440
    var heldSeconds: Double = 1
    var delayAmount: Float = 0
    var distortionAmount: Float = 0

    init(node: SoundNode, heldSeconds: Double) {
        update(from: node, heldSeconds: heldSeconds)
    }

    func update(from node: SoundNode, heldSeconds: Double) {
        frequency = VoiceSynthesis.frequency(for: node.type, pitch: node.pitch)
        self.heldSeconds = heldSeconds
        delayAmount = node.delay
        distortionAmount = node.distortion
    }
}

/// Sintetiza en el hilo de audio a partir de parámetros vivos.
///
/// La versión anterior horneaba cada nota entera al pulsar Play, así que mover
/// un organismo mientras sonaba no podía cambiar su afinación: el sonido ya
/// estaba escrito. Aquí cada muestra se genera en el momento, de modo que la
/// posición de la mano se oye de inmediato.
///
/// Reglas del hilo de audio que este tipo respeta: ninguna asignación, ningún
/// lock, ninguna llamada transcendental por muestra. Fases, línea de delay y
/// tiempos de ataque viven en memoria reservada una sola vez al construirlo.
final class SpatialVoiceRenderer: @unchecked Sendable {
    private let type: SoundNodeType
    private let spec: InstrumentSpec
    private let seed: UInt64
    private let sampleRate = 48_000.0
    let parameters: LiveVoiceParameters

    // Memoria propia: los `Array` de Swift pueden copiarse al leerse y eso no
    // tiene cabida en el hilo de audio.
    private let attacks: UnsafeMutablePointer<Double>
    private let attackCount: Int
    private let phases: UnsafeMutablePointer<Double>
    private let partialMultiples: UnsafeMutablePointer<Double>
    private let partialAmplitudes: UnsafeMutablePointer<Float>
    private let partialCount: Int
    private let delayLine: UnsafeMutablePointer<Float>
    private let delayCapacity: Int

    private var delayWriteIndex = 0
    private var filterState: Float = 0
    private var smoothedFrequency: Double
    private var smoothedDelay: Float = 0
    private var smoothedDrive: Float = 1

    /// Reloj propio, usado cuando el timestamp del host no sirve.
    private var anchorSeconds: TimeInterval = -1
    private var renderedFrames: Double = 0
    private var resolvedClock: Clock = .undecided

    enum Clock { case undecided, hostTimestamp, internalCounter }

    /// Diagnóstico para la UI: sin esto, "no suena" es indistinguible de "las
    /// voces nunca llegaron a engancharse".
    private(set) var didRenderAudibleSample = false
    var usesFallbackClock: Bool { resolvedClock == .internalCounter }

    init(node: SoundNode, sustainSeconds: TimeInterval? = nil, attackHostTimes: [UInt64]) {
        type = node.type
        spec = VoiceSynthesis.spec(for: node.type)
        seed = VoiceSynthesis.seed(for: node.type)

        let held = min(
            max(sustainSeconds ?? 1.2, 0.18),
            VoiceSynthesis.maximumDuration - spec.release
        )
        parameters = LiveVoiceParameters(node: node, heldSeconds: held)
        smoothedFrequency = parameters.frequency

        // Ordenados para poder acotar por búsqueda binaria qué ataques pueden
        // sonar en un bloque concreto, en vez de recorrerlos todos por frame.
        let sorted = attackHostTimes.map(AVAudioTime.seconds(forHostTime:)).sorted()
        attackCount = sorted.count
        attacks = .allocate(capacity: max(1, sorted.count))
        for (index, value) in sorted.enumerated() { attacks[index] = value }

        partialCount = spec.partials.count
        partialMultiples = .allocate(capacity: partialCount)
        partialAmplitudes = .allocate(capacity: partialCount)
        phases = .allocate(capacity: partialCount)
        for (index, partial) in spec.partials.enumerated() {
            partialMultiples[index] = partial.multiple
            partialAmplitudes[index] = partial.amplitude / max(spec.partialWeight, 0.0001)
            phases[index] = 0
        }

        // Espacio para los dos ecos del delay más largo posible.
        delayCapacity = Int(1.2 * sampleRate)
        delayLine = .allocate(capacity: delayCapacity)
        delayLine.initialize(repeating: 0, count: delayCapacity)
    }

    deinit {
        attacks.deallocate()
        phases.deallocate()
        partialMultiples.deallocate()
        partialAmplitudes.deallocate()
        delayLine.deallocate()
    }

    /// Duración total de una nota con los parámetros actuales.
    private var noteDuration: Double {
        spec.isPercussive
            ? VoiceSynthesis.percussiveDuration(for: type)
            : parameters.heldSeconds + spec.release
    }

    var render: Audio.GeneratorRenderHandler {
        // `isSilence` es parte del contrato, no un parámetro ignorable: quien
        // consume el buffer puede descartarlo si queda marcado como silencio.
        // Captura fuerte a propósito. El handler debe mantener viva a su voz
        // mientras RealityKit conserve la referencia: con `unowned`, soltar la
        // voz al detener la reproducción la destruía —liberando de paso su
        // memoria manual— mientras el grafo de audio aún podía invocarla. Eso
        // dejaba el motor corrupto después de la primera reproducción. Cuando
        // RealityKit suelta el generador, suelta el closure y la voz muere bien.
        { [self] isSilence, timestamp, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let blockStart = self.blockStartSeconds(from: timestamp.pointee)
            let frames = Int(frameCount)
            defer { renderedFrames += Double(frames) }

            // Los parámetros vivos se leen una vez por bloque y se deslizan
            // hacia su destino muestra a muestra: así un cambio brusco de
            // altura se oye como un glissando corto y no como un clic.
            let targetFrequency = parameters.frequency
            let targetDelay = parameters.delayAmount
            let targetDrive = 1 + parameters.distortionAmount * 8
            let duration = noteDuration

            let lower = lowerBound(for: blockStart - duration)
            let upper = lowerBound(for: blockStart + Double(frames) / sampleRate)
            let hasNotes = lower < upper
            // Medido por bloque. `didRenderAudibleSample` es un flag pegajoso de
            // diagnóstico y no sirve para decidir si *este* bloque calla.
            var blockHadSignal = false

            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<frames {
                    let absoluteTime = blockStart + Double(frame) / sampleRate

                    smoothedFrequency += (targetFrequency - smoothedFrequency) * 0.002
                    smoothedDelay += (targetDelay - smoothedDelay) * 0.002
                    smoothedDrive += (targetDrive - smoothedDrive) * 0.002

                    var dry: Float = 0
                    if hasNotes {
                        dry = spec.isPercussive
                            ? percussiveSample(at: absoluteTime, lower: lower, upper: upper)
                            : tonalSample(at: absoluteTime, lower: lower, upper: upper, duration: duration)
                    } else if !spec.isPercussive {
                        // Mantén las fases avanzando aunque no suene nada, para
                        // que la siguiente nota entre en fase continua.
                        advancePhases()
                    }

                    let wet = applyDelay(to: dry)
                    // `softClip` es unitario con señal pequeña y satura en ±1,
                    // así que hace de saturador y de limitador a la vez. La
                    // compensación de ganancia evita que subir la distorsión se
                    // perciba solo como subir el volumen.
                    let shaped = VoiceSynthesis.softClip(wet, drive: smoothedDrive)
                    let out = max(-0.85, min(shaped / (1 + (smoothedDrive - 1) * 0.35), 0.85))

                    if out != 0 {
                        didRenderAudibleSample = true
                        blockHadSignal = true
                    }
                    data[frame] = out
                }
            }

            isSilence.pointee = ObjCBool(!blockHadSignal)
            return noErr
        }
    }

    // MARK: - Generación

    /// Un solo banco de osciladores con fase continua, escalado por la suma de
    /// envolventes de las notas activas. Dos notas del mismo organismo comparten
    /// timbre y altura, así que sumar envolventes equivale a sumar osciladores
    /// y ahorra reservar una voz por nota.
    @inline(__always)
    private func tonalSample(at time: Double, lower: Int, upper: Int, duration: Double) -> Float {
        var envelopeSum: Float = 0
        for index in lower..<upper {
            let local = time - attacks[index]
            guard local >= 0, local < duration else { continue }
            envelopeSum += VoiceSynthesis.envelope(
                at: local,
                spec: spec,
                held: parameters.heldSeconds
            )
        }

        var oscillator: Float = 0
        for partial in 0..<partialCount {
            phases[partial] += smoothedFrequency * partialMultiples[partial] / sampleRate
            if phases[partial] > 1 { phases[partial] -= floor(phases[partial]) }
            oscillator += VoiceSynthesis.sine(cycles: phases[partial]) * partialAmplitudes[partial]
        }

        guard envelopeSum > 0 else {
            filterState += filterCoefficient * (0 - filterState)
            return 0
        }

        filterState += filterCoefficient * (oscillator - filterState)
        return filterState * min(envelopeSum, 2)
    }

    @inline(__always)
    private func advancePhases() {
        for partial in 0..<partialCount {
            phases[partial] += smoothedFrequency * partialMultiples[partial] / sampleRate
            if phases[partial] > 1 { phases[partial] -= floor(phases[partial]) }
        }
    }

    @inline(__always)
    private func percussiveSample(at time: Double, lower: Int, upper: Int) -> Float {
        var total: Float = 0
        for index in lower..<upper {
            total += VoiceSynthesis.percussiveSample(
                type: type,
                localTime: time - attacks[index],
                frequency: smoothedFrequency,
                sampleRate: sampleRate,
                seed: seed
            )
        }
        return total
    }

    private var filterCoefficient: Float {
        VoiceSynthesis.onePoleCoefficient(cutoff: spec.cutoff, sampleRate: sampleRate)
    }

    /// Línea circular con dos tomas. El retardo se desliza con el parámetro, así
    /// que girar el organismo mientras suena barre el eco en vez de saltarlo.
    @inline(__always)
    private func applyDelay(to dry: Float) -> Float {
        delayLine[delayWriteIndex] = dry
        defer { delayWriteIndex = (delayWriteIndex + 1) % delayCapacity }

        guard smoothedDelay > 0.001 else { return dry }
        let offset = Int((0.07 + Double(smoothedDelay) * 0.48) * sampleRate)
        let first = delayLine[(delayWriteIndex - offset + delayCapacity * 2) % delayCapacity]
        let second = delayLine[(delayWriteIndex - offset * 2 + delayCapacity * 2) % delayCapacity]
        return dry + first * smoothedDelay * 0.42 + second * smoothedDelay * 0.18
    }

    // MARK: - Reloj

    /// Decide una sola vez de qué reloj fiarse y se mantiene en él.
    ///
    /// Dar por hecho que `mHostTime` viene poblado y en el mismo reloj mach que
    /// los ataques produce silencio total cuando no es así, sin error ni pista.
    private func blockStartSeconds(from stamp: AudioTimeStamp) -> TimeInterval {
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())

        if resolvedClock == .undecided {
            let hostSeconds = AVAudioTime.seconds(forHostTime: stamp.mHostTime)
            let isValid = stamp.mFlags.contains(.hostTimeValid)
                && stamp.mHostTime != 0
                && abs(hostSeconds - now) < 1.0
            resolvedClock = isValid ? .hostTimestamp : .internalCounter
            if resolvedClock == .internalCounter {
                anchorSeconds = now
                renderedFrames = 0
            }
        }

        switch resolvedClock {
        case .hostTimestamp:
            return AVAudioTime.seconds(forHostTime: stamp.mHostTime)
        case .internalCounter, .undecided:
            return anchorSeconds + renderedFrames / sampleRate
        }
    }

    /// Primer índice cuyo ataque es >= `time`. Sin asignaciones ni locks.
    private func lowerBound(for time: TimeInterval) -> Int {
        var low = 0
        var high = attackCount
        while low < high {
            let middle = (low + high) / 2
            if attacks[middle] < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
