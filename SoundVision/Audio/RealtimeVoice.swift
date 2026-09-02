import AVFAudio
import Foundation
import RealityKit
import Synchronization

/// Parámetros que la mano puede cambiar mientras la música suena.
///
/// El hilo principal escribe; el de audio lee. No hay locks porque en el hilo de
/// audio no puede haberlos, y no hacen falta: son escalares alineados
/// independientes entre sí, sin ninguna invariante que los relacione. Lo peor
/// que puede pasar es que un bloque mezcle valores de dos instantes contiguos,
/// diferencia inaudible. Cada campo se lee **una vez por bloque** y se desliza
/// hacia su destino, de modo que ni siquiera un salto brusco produce un clic.
final class LiveVoiceParameters: @unchecked Sendable {
    struct Snapshot {
        let frequency: Double
        let heldSeconds: Double
        let delayAmount: Float
        let distortionAmount: Float
        let isMuted: Bool
    }

    private let frequencyBits = Atomic<UInt64>(Double(440).bitPattern)
    private let heldSecondsBits = Atomic<UInt64>(Double(1).bitPattern)
    private let delayBits = Atomic<UInt32>(Float(0).bitPattern)
    private let distortionBits = Atomic<UInt32>(Float(0).bitPattern)
    /// Un organismo muteado conserva su voz enganchada, pero no suena. Quitarle
    /// la voz obligaría a volver a engancharla al desmutear, que es justo el
    /// trabajo que ya no queremos tener en el camino de Play.
    private let mutedValue = Atomic<UInt32>(0)

    init(node: SoundNode, heldSeconds: Double) {
        update(from: node, heldSeconds: heldSeconds)
    }

    func update(from node: SoundNode, heldSeconds: Double) {
        frequencyBits.store(VoiceSynthesis.frequency(for: node.type, pitch: node.pitch).bitPattern, ordering: .releasing)
        heldSecondsBits.store(heldSeconds.bitPattern, ordering: .releasing)
        delayBits.store(node.delay.bitPattern, ordering: .releasing)
        distortionBits.store(node.distortion.bitPattern, ordering: .releasing)
        mutedValue.store(node.isActive ? 0 : 1, ordering: .releasing)
    }

    /// El render toma una sola fotografía por bloque. Además de eliminar carreras
    /// de datos, evita mezclar cinco lecturas de instantes distintos.
    @inline(__always)
    func snapshot() -> Snapshot {
        Snapshot(
            frequency: Double(bitPattern: frequencyBits.load(ordering: .acquiring)),
            heldSeconds: Double(bitPattern: heldSecondsBits.load(ordering: .acquiring)),
            delayAmount: Float(bitPattern: delayBits.load(ordering: .acquiring)),
            distortionAmount: Float(bitPattern: distortionBits.load(ordering: .acquiring)),
            isMuted: mutedValue.load(ordering: .acquiring) != 0
        )
    }
}

/// Sintetiza en el hilo de audio a partir de parámetros vivos.
///
/// La voz vive mientras vive su organismo: se engancha a la entidad en cuanto el
/// nodo existe y a partir de ahí siempre está rindiendo, aunque sea silencio.
/// Reproducir es únicamente publicar tiempos de ataque en su `VoiceSchedule`.
///
/// Reglas del hilo de audio que este tipo respeta: ninguna asignación, ningún
/// lock, ninguna llamada transcendental por muestra. Fases, línea de delay y
/// agenda viven en memoria reservada una sola vez al construirlo.
final class SpatialVoiceRenderer: @unchecked Sendable {
    private let type: SoundNodeType
    private let spec: InstrumentSpec
    private let seed: UInt64
    let parameters: LiveVoiceParameters
    let schedule = VoiceSchedule()

    /// Desvanecido al detener. Suficiente para que no se oiga el corte y lo
    /// bastante corto para que Detener siga siendo instantáneo.
    static let stopFadeSeconds = 0.012

    // Memoria propia: los `Array` de Swift pueden copiarse al leerse y eso no
    // tiene cabida en el hilo de audio.
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
    private var silentFrames = 0
    private var lastGeneration: UInt64 = .max

    /// Reloj propio, usado cuando el timestamp del host no sirve.
    private var anchorSeconds: TimeInterval = -1
    private var renderedFrames: Double = 0
    private var resolvedClock: Clock = .undecided
    private var previousBlockStart: TimeInterval = -1
    private var rateEstimate: Double = 0
    private var rateSamples = 0

    enum Clock { case undecided, hostTimestamp, internalCounter }

    /// Diagnóstico para la UI. Se escriben desde el hilo de audio y se leen
    /// desde el principal: son escalares alineados e independientes, sin
    /// ninguna invariante entre ellos, y sirven para *informar*, no para
    /// decidir nada dentro del render.
    private let audibleValue = Atomic<UInt32>(0)
    private let renderedBlockValue = Atomic<UInt64>(0)
    private let peakBits = Atomic<UInt32>(Float(0).bitPattern)
    private let sampleRateBits = Atomic<UInt64>(Double(48_000).bitPattern)
    private let clockValue = Atomic<UInt32>(0)
    private var audioRenderedBlocks: UInt64 = 0
    private var audioDidRenderAudibleSample = false
    private var renderSampleRate = 48_000.0

    var didRenderAudibleSample: Bool { audibleValue.load(ordering: .acquiring) != 0 }
    var renderedBlocks: Int { Int(renderedBlockValue.load(ordering: .acquiring)) }
    var peakLevel: Float { Float(bitPattern: peakBits.load(ordering: .acquiring)) }
    var sampleRate: Double { Double(bitPattern: sampleRateBits.load(ordering: .acquiring)) }
    var usesFallbackClock: Bool { clockValue.load(ordering: .acquiring) == 2 }

    var clockDescription: String {
        switch clockValue.load(ordering: .acquiring) {
        case 1: "reloj del host"
        case 2: "reloj propio"
        default: "sin arrancar"
        }
    }

    init(node: SoundNode, sustainSeconds: TimeInterval? = nil) {
        type = node.type
        spec = VoiceSynthesis.spec(for: node.type)
        seed = VoiceSynthesis.seed(for: node.type)

        let held = min(
            max(sustainSeconds ?? 1.2, 0.18),
            VoiceSynthesis.maximumDuration - spec.release
        )
        parameters = LiveVoiceParameters(node: node, heldSeconds: held)
        smoothedFrequency = parameters.snapshot().frequency

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
        delayCapacity = Int(1.2 * renderSampleRate)
        delayLine = .allocate(capacity: delayCapacity)
        delayLine.initialize(repeating: 0, count: delayCapacity)
    }

    /// Atajo para pruebas y para el preview: construye la voz con su agenda ya
    /// publicada, en tiempos del reloj mach.
    convenience init(node: SoundNode, sustainSeconds: TimeInterval? = nil, attackHostTimes: [UInt64]) {
        self.init(node: node, sustainSeconds: sustainSeconds)
        schedule.publish(attackHostTimes.map(AVAudioTime.seconds(forHostTime:)))
    }

    deinit {
        phases.deallocate()
        partialMultiples.deallocate()
        partialAmplitudes.deallocate()
        delayLine.deallocate()
    }

    /// Duración total de una nota con los parámetros actuales.
    private func noteDuration(heldSeconds: Double) -> Double {
        spec.isPercussive
            ? VoiceSynthesis.percussiveDuration(for: type)
            : heldSeconds + spec.release
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
            let frames = Int(frameCount)
            let blockStart = self.blockStartSeconds(from: timestamp.pointee, frames: frames)
            audioRenderedBlocks &+= 1
            renderedBlockValue.store(audioRenderedBlocks, ordering: .releasing)
            defer { renderedFrames += Double(frames) }

            let plan = schedule.snapshot()
            // Una agenda nueva reinicia el deslizado: si no, la primera nota
            // entraría barriendo desde la altura que tenía la anterior.
            if plan.generation != lastGeneration {
                lastGeneration = plan.generation
                smoothedFrequency = parameters.snapshot().frequency
            }

            // Los parámetros vivos se leen una vez por bloque y se deslizan
            // hacia su destino muestra a muestra: así un cambio brusco de
            // altura se oye como un glissando corto y no como un clic.
            let live = parameters.snapshot()
            let targetFrequency = live.frequency
            let targetDelay = live.isMuted ? 0 : live.delayAmount
            let targetDrive = 1 + live.distortionAmount * 8
            let duration = noteDuration(heldSeconds: live.heldSeconds)
            let blockEnd = blockStart + Double(frames) / renderSampleRate
            let fadeEnd = plan.stopTime + Self.stopFadeSeconds

            // Ventana de ataques que pueden sonar en este bloque. Nada que haya
            // sido cortado por Detener entra aquí.
            let lower = playbackIndex(atOrAfter: blockStart - duration, in: plan)
            let upper = playbackIndex(atOrAfter: min(blockEnd, plan.stopTime), in: plan)
            let hasNotes = lower < upper && !live.isMuted && blockStart < fadeEnd
            let hasDelayTail = smoothedDelay > 0.001 && silentFrames < delayCapacity

            if !hasNotes && !hasDelayTail {
                renderSilence(buffers: buffers, frames: frames)
                smoothedFrequency = targetFrequency
                smoothedDelay = targetDelay
                smoothedDrive = targetDrive
                isSilence.pointee = ObjCBool(true)
                return noErr
            }

            // Medido por bloque. `didRenderAudibleSample` es un flag pegajoso de
            // diagnóstico y no sirve para decidir si *este* bloque calla.
            var blockHadSignal = false
            var blockPeak: Float = 0

            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<frames {
                    let absoluteTime = blockStart + Double(frame) / renderSampleRate

                    smoothedFrequency += (targetFrequency - smoothedFrequency) * 0.002
                    smoothedDelay += (targetDelay - smoothedDelay) * 0.002
                    smoothedDrive += (targetDrive - smoothedDrive) * 0.002

                    var dry: Float = 0
                    if hasNotes {
                        dry = spec.isPercussive
                            ? percussiveSample(at: absoluteTime, lower: lower, upper: upper, plan: plan)
                            : tonalSample(
                                at: absoluteTime,
                                lower: lower,
                                upper: upper,
                                duration: duration,
                                heldSeconds: live.heldSeconds,
                                plan: plan
                            )
                        dry *= stopGain(at: absoluteTime, stopTime: plan.stopTime)
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
                        blockHadSignal = true
                        blockPeak = max(blockPeak, abs(out))
                    }
                    data[frame] = out
                }
            }

            silentFrames = blockHadSignal ? 0 : silentFrames &+ frames
            // Caída lenta para que la consola muestre un pico legible y no un
            // valor que parpadea con cada bloque.
            let nextPeak = max(blockPeak, peakLevel * 0.86)
            peakBits.store(nextPeak.bitPattern, ordering: .releasing)
            if blockHadSignal, !audioDidRenderAudibleSample {
                audioDidRenderAudibleSample = true
                audibleValue.store(1, ordering: .releasing)
            }
            isSilence.pointee = ObjCBool(!blockHadSignal)
            return noErr
        }
    }

    // MARK: - Generación

    /// Camino rápido de la voz en reposo. Con ocho organismos enganchados
    /// permanentemente, recorrer la síntesis completa para producir ceros sería
    /// trabajo puro de relleno en el hilo más sensible de la app.
    @inline(__always)
    private func renderSilence(buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            data.update(repeating: 0, count: frames)
        }
        // La línea de delay avanza en silencio: si se quedara parada, la
        // siguiente nota leería ecos de hace minutos.
        for _ in 0..<frames {
            delayLine[delayWriteIndex] = 0
            delayWriteIndex = (delayWriteIndex + 1) % delayCapacity
        }
        for partial in 0..<partialCount {
            phases[partial] += smoothedFrequency * partialMultiples[partial] * Double(frames) / renderSampleRate
            phases[partial] -= floor(phases[partial])
        }
        silentFrames &+= frames
        filterState = 0
        // El pico también decae aquí. Si no, al detener se congelaba el último
        // valor y el diagnóstico seguía diciendo que salía nivel.
        var nextPeak = peakLevel * 0.86
        if nextPeak < 0.0001 { nextPeak = 0 }
        peakBits.store(nextPeak.bitPattern, ordering: .releasing)
    }

    /// Desvanecido de Detener. Antes del corte deja pasar todo; después baja en
    /// línea recta hasta cero en unos milisegundos.
    @inline(__always)
    private func stopGain(at time: Double, stopTime: Double) -> Float {
        guard time >= stopTime else { return 1 }
        let progress = (time - stopTime) / Self.stopFadeSeconds
        return progress >= 1 ? 0 : Float(1 - progress)
    }

    /// Un solo banco de osciladores con fase continua, escalado por la suma de
    /// envolventes de las notas activas. Dos notas del mismo organismo comparten
    /// timbre y altura, así que sumar envolventes equivale a sumar osciladores
    /// y ahorra reservar una voz por nota.
    @inline(__always)
    private func tonalSample(
        at time: Double,
        lower: Int64,
        upper: Int64,
        duration: Double,
        heldSeconds: Double,
        plan: VoiceSchedule.Snapshot
    ) -> Float {
        var envelopeSum: Float = 0
        for index in lower..<upper {
            let local = time - attackTime(at: index, in: plan)
            guard local >= 0, local < duration else { continue }
            envelopeSum += VoiceSynthesis.envelope(
                at: local,
                spec: spec,
                held: heldSeconds
            )
        }

        var oscillator: Float = 0
        for partial in 0..<partialCount {
            phases[partial] += smoothedFrequency * partialMultiples[partial] / renderSampleRate
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
            phases[partial] += smoothedFrequency * partialMultiples[partial] / renderSampleRate
            if phases[partial] > 1 { phases[partial] -= floor(phases[partial]) }
        }
    }

    @inline(__always)
    private func percussiveSample(
        at time: Double,
        lower: Int64,
        upper: Int64,
        plan: VoiceSchedule.Snapshot
    ) -> Float {
        var total: Float = 0
        for index in lower..<upper {
            total += VoiceSynthesis.percussiveSample(
                type: type,
                localTime: time - attackTime(at: index, in: plan),
                frequency: smoothedFrequency,
                sampleRate: renderSampleRate,
                seed: seed
            )
        }
        return total
    }

    private var filterCoefficient: Float {
        VoiceSynthesis.onePoleCoefficient(cutoff: spec.cutoff, sampleRate: renderSampleRate)
    }

    /// Línea circular con dos tomas. El retardo se desliza con el parámetro, así
    /// que girar el organismo mientras suena barre el eco en vez de saltarlo.
    @inline(__always)
    private func applyDelay(to dry: Float) -> Float {
        delayLine[delayWriteIndex] = dry
        defer { delayWriteIndex = (delayWriteIndex + 1) % delayCapacity }

        guard smoothedDelay > 0.001 else { return dry }
        let offset = min(Int((0.07 + Double(smoothedDelay) * 0.48) * renderSampleRate), delayCapacity / 2 - 1)
        let first = delayLine[(delayWriteIndex - offset + delayCapacity * 2) % delayCapacity]
        let second = delayLine[(delayWriteIndex - offset * 2 + delayCapacity * 2) % delayCapacity]
        return dry + first * smoothedDelay * 0.42 + second * smoothedDelay * 0.18
    }

    // MARK: - Reloj

    /// Decide una sola vez de qué reloj fiarse y se mantiene en él.
    ///
    /// Dar por hecho que `mHostTime` viene poblado y en el mismo reloj mach que
    /// los ataques produce silencio total cuando no es así, sin error ni pista.
    private func blockStartSeconds(from stamp: AudioTimeStamp, frames: Int) -> TimeInterval {
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())

        if resolvedClock == .undecided {
            let hostSeconds = AVAudioTime.seconds(forHostTime: stamp.mHostTime)
            let isValid = stamp.mFlags.contains(.hostTimeValid)
                && stamp.mHostTime != 0
                && abs(hostSeconds - now) < 1.0
            resolvedClock = isValid ? .hostTimestamp : .internalCounter
            clockValue.store(resolvedClock == .hostTimestamp ? 1 : 2, ordering: .releasing)
            if resolvedClock == .internalCounter {
                anchorSeconds = now
                renderedFrames = 0
            }
        }

        switch resolvedClock {
        case .hostTimestamp:
            let start = AVAudioTime.seconds(forHostTime: stamp.mHostTime)
            calibrateSampleRate(blockStart: start, frames: frames)
            return start
        case .internalCounter, .undecided:
            let estimate = anchorSeconds + renderedFrames / renderSampleRate
            // Si la tasa real no es la asumida, este reloj se separaría del
            // mundo sin remedio. Un cuarto de segundo de desvío ya es mucho más
            // de lo que explica el adelanto normal del buffer: reanclamos.
            if abs(estimate - now) > 0.25 {
                anchorSeconds = now
                renderedFrames = 0
                return now
            }
            return estimate
        }
    }

    /// La tasa real sale de los propios timestamps: cuántas muestras caben entre
    /// el inicio de dos bloques consecutivos. Asumir 48 kHz a ciegas desafinaba
    /// toda la pieza si el grafo entregaba otra cosa.
    private func calibrateSampleRate(blockStart: TimeInterval, frames: Int) {
        defer { previousBlockStart = blockStart }
        guard rateSamples < 12, previousBlockStart > 0 else { return }
        let elapsed = blockStart - previousBlockStart
        let measured = Double(frames) / elapsed
        guard elapsed > 0, measured > 8_000, measured < 192_000 else { return }

        rateEstimate += measured
        rateSamples += 1
        guard rateSamples == 12 else { return }

        let average = rateEstimate / 12
        // Las tasas reales son valores conocidos; quedarse con el número medido
        // en crudo introduciría una desafinación pequeña y permanente.
        let standard = [44_100.0, 48_000.0, 88_200.0, 96_000.0]
            .min { abs($0 - average) < abs($1 - average) } ?? 48_000
        if abs(standard - average) / average < 0.05 {
            renderSampleRate = standard
            sampleRateBits.store(standard.bitPattern, ordering: .releasing)
        }
    }

    /// Primer índice virtual cuyo ataque es >= `time`. Para un preview coincide
    /// con el índice de la losa; para Play avanza por vueltas sin almacenar una
    /// agenda infinita ni volver a publicar desde el hilo principal.
    @inline(__always)
    private func playbackIndex(atOrAfter time: TimeInterval, in plan: VoiceSchedule.Snapshot) -> Int64 {
        guard plan.count > 0 else { return 0 }
        guard plan.repeatInterval.isFinite,
              plan.repeatInterval > 0,
              plan.loopStart.isFinite,
              time > plan.loopStart
        else { return Int64(lowerBoundInFirstLoop(for: time, in: plan)) }

        let count = Int64(plan.count)
        let rawCycle = floor((time - plan.loopStart) / plan.repeatInterval)
        let maximumCycle = Double(Int64.max / count - 1)
        let cycle = Int64(max(0, min(rawCycle, maximumCycle)))
        let timeInFirstLoop = time - Double(cycle) * plan.repeatInterval
        let baseIndex = lowerBoundInFirstLoop(for: timeInFirstLoop, in: plan)
        if baseIndex < plan.count {
            return cycle * count + Int64(baseIndex)
        }
        return (cycle + 1) * count
    }

    @inline(__always)
    private func attackTime(at playbackIndex: Int64, in plan: VoiceSchedule.Snapshot) -> TimeInterval {
        guard plan.repeatInterval > 0 else { return plan.attacks[Int(playbackIndex)] }
        let count = Int64(plan.count)
        let loop = playbackIndex / count
        let baseIndex = Int(playbackIndex % count)
        return plan.attacks[baseIndex] + Double(loop) * plan.repeatInterval
    }

    /// Búsqueda binaria dentro de la primera vuelta publicada.
    @inline(__always)
    private func lowerBoundInFirstLoop(for time: TimeInterval, in plan: VoiceSchedule.Snapshot) -> Int {
        var low = 0
        var high = plan.count
        while low < high {
            let middle = (low + high) / 2
            if plan.attacks[middle] < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
