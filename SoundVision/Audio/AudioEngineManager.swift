import AVFAudio
import Foundation
import RealityKit

struct SpatialAudioSession: Identifiable, Sendable {
    let id: UUID
    let nodes: [SoundNode]
    let events: [GraphPlaybackEvent]
    let secondsPerBeat: Double
    let startHostTime: UInt64
    let leadInSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        nodes: [SoundNode],
        events: [GraphPlaybackEvent],
        secondsPerBeat: Double,
        // Margen suficiente para que SwiftUI propague la sesión, RealityKit
        // conecte las fuentes y la síntesis quede horneada antes del primer
        // ataque. Con 0.24 s las primeras notas caían en el pasado y se perdían
        // en silencio.
        leadInSeconds: TimeInterval = 0.55
    ) {
        self.id = id
        self.nodes = nodes
        self.events = events
        self.secondsPerBeat = secondsPerBeat
        self.leadInSeconds = leadInSeconds
        startHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: leadInSeconds)
    }
}

/// Une cada organismo visual con una fuente de RealityKit Spatial Audio.
/// RealityKit aplica el HRTF personalizado, seguimiento de cabeza, atenuación
/// física y acústica del entorno; el render handler entrega una señal mono a
/// 48 kHz para que Apple realice la espacialización final.
@MainActor
final class AudioEngineManager: ObservableObject {
    private var sessionID: UUID?
    private var controllers: [AudioGeneratorController] = []
    private var renderers: [SpatialVoiceRenderer] = []

    /// Retira las fuentes de la sesión anterior. Debe correr **antes** de que la
    /// escena elimine entidades: un `AudioGeneratorController` cuyo entity
    /// desaparece sin haberse detenido deja audio colgado.
    func retireSourcesIfNeeded(for session: SpatialAudioSession?) {
        guard session?.id != sessionID else { return }
        stopAll()
    }

    /// Adjunta las fuentes de la sesión actual. Debe correr **después** de que
    /// la escena haya creado las entidades, o los nodos nuevos quedan mudos.
    func synchronize(session: SpatialAudioSession?, in root: Entity) {
        guard session?.id != sessionID else { return }
        stopAll()
        guard let session else { return }
        sessionID = session.id

        let nodesByID = Dictionary(uniqueKeysWithValues: session.nodes.map { ($0.id, $0) })
        let eventsByNode = Dictionary(grouping: session.events, by: \.nodeID)

        for (nodeID, events) in eventsByNode {
            guard let node = nodesByID[nodeID], node.isActive,
                  let entity = root.findEntity(named: NodeEntityFactory.nodePrefix + nodeID.uuidString)
            else { continue }

            entity.spatialAudio = spatialConfiguration(for: node)
            let attackHostTimes = events.map { event in
                session.startHostTime + AVAudioTime.hostTime(
                    forSeconds: event.beat * session.secondsPerBeat
                )
            }
            let renderer = SpatialVoiceRenderer(node: node, attackHostTimes: attackHostTimes)

            do {
                let controller = try entity.prepareAudio(
                    configuration: AudioGeneratorConfiguration(layoutTag: kAudioChannelLayoutTag_Mono),
                    renderer.render
                )
                // Conserva 6 dB de headroom para bifurcaciones simultáneas y
                // evita que la primera prueba física resulte agresiva.
                controller.gain = -6
                controller.play()
                controllers.append(controller)
                renderers.append(renderer)
            } catch {
                print("SoundVision RealityKit spatial audio: \(error.localizedDescription)")
            }
        }
    }

    func stopAll() {
        controllers.forEach { $0.stop() }
        controllers = []
        renderers = []
        sessionID = nil
    }

    private func spatialConfiguration(for node: SoundNode) -> SpatialAudioComponent {
        let musicalGain = 20 * log10(max(0.05, Double(node.volume)))
        let reverbLevel = -24 + Double(node.reverb) * 23
        // Sin directividad: un organismo sonoro debe localizarse igual de bien
        // desde cualquier ángulo, incluido a la espalda de la persona.
        return SpatialAudioComponent(
            gain: max(-24, min(musicalGain, 0)),
            directLevel: .zero,
            reverbLevel: max(-24, min(reverbLevel, -1)),
            distanceAttenuation: .rolloff(factor: 0.9)
        )
    }
}

/// Renderizador sin locks ni asignaciones en el audio thread. Todas las notas
/// se evalúan contra host time, de modo que ramas distintas comparten ataques
/// sample-accurate aunque cada entidad tenga su propio generador.
private final class SpatialVoiceRenderer: @unchecked Sendable {
    private let attackSeconds: [TimeInterval]
    private let sampleRate = 48_000.0
    private let soundDuration: TimeInterval
    private let samples: [Float]

    init(node: SoundNode, attackHostTimes: [UInt64]) {
        // Ordenados para poder acotar por búsqueda binaria qué ataques pueden
        // sonar en un bloque concreto, en vez de recorrerlos todos por frame.
        attackSeconds = attackHostTimes.map(AVAudioTime.seconds(forHostTime:)).sorted()
        soundDuration = node.type == .pad || node.type == .fx ? 0.9 : 0.38
        let fundamental: Double = switch node.type {
        case .kick: 62
        case .snare: 185
        case .hiHat: 1_400
        case .clap: 520
        case .bass: 92
        case .pad: 220
        case .lead: 660
        case .fx: 310
        }
        let baseFrequency = fundamental * pow(2, Double(node.pitch) / 12)
        let seed = UInt64(node.type.rawValue.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) })
        samples = Self.renderSamples(
            node: node,
            sampleRate: sampleRate,
            duration: soundDuration,
            baseFrequency: baseFrequency,
            seed: seed
        )
    }

    var render: Audio.GeneratorRenderHandler {
        { [unowned self] _, timestamp, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let blockStart = AVAudioTime.seconds(forHostTime: timestamp.pointee.mHostTime)
            let blockEnd = blockStart + Double(frameCount) / sampleRate

            // Solo los ataques cuya cola alcanza este bloque pueden aportar
            // muestras. Recorrer la línea de tiempo completa por frame costaba
            // cientos de miles de iteraciones por bloque y provocaba cortes.
            let lower = lowerBound(for: blockStart - soundDuration)
            let upper = lowerBound(for: blockEnd)
            guard lower < upper else {
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }

            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    let absoluteTime = blockStart + Double(frame) / sampleRate
                    var mixedSample: Float = 0
                    for index in lower..<upper {
                        let localTime = absoluteTime - attackSeconds[index]
                        guard localTime >= 0, localTime < soundDuration else { continue }
                        let sampleIndex = min(samples.count - 1, Int(localTime * sampleRate))
                        mixedSample += samples[sampleIndex]
                    }
                    data[frame] = max(-0.78, min(mixedSample * 0.9, 0.78))
                }
            }

            return noErr
        }
    }

    /// Primer índice cuyo ataque es >= `time`. Sin asignaciones ni locks, apto
    /// para el hilo de audio.
    private func lowerBound(for time: TimeInterval) -> Int {
        var low = 0
        var high = attackSeconds.count
        while low < high {
            let middle = (low + high) / 2
            if attackSeconds[middle] < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// Hornea síntesis y efectos al preparar la voz. El callback de audio solo
    /// mezcla muestras y no calcula seno, potencia, ruido ni ecos en tiempo real.
    private static func renderSamples(
        node: SoundNode,
        sampleRate: Double,
        duration: TimeInterval,
        baseFrequency: Double,
        seed: UInt64
    ) -> [Float] {
        let count = max(1, Int(duration * sampleRate))
        // La señal seca se calcula una sola vez y los ecos la reindexan. Antes
        // cada muestra evaluaba `drySample` tres veces, triplicando el trabajo
        // trigonométrico justo en el momento de pulsar Play.
        let dry = (0..<count).map { index in
            drySample(
                at: Double(index) / sampleRate,
                node: node,
                duration: duration,
                sampleRate: sampleRate,
                baseFrequency: baseFrequency,
                seed: seed
            )
        }

        let delayOffset = max(1, Int((0.07 + Double(node.delay) * 0.48) * sampleRate))
        let drive = 1 + node.distortion * 8
        let normalization = max(1, tanh(drive))

        return (0..<count).map { index in
            var combined = dry[index]
            if index >= delayOffset {
                combined += dry[index - delayOffset] * node.delay * 0.42
            }
            if index >= delayOffset * 2 {
                combined += dry[index - delayOffset * 2] * node.delay * 0.18
            }
            return node.distortion > 0.001 ? tanh(combined * drive) / normalization : combined
        }
    }

    private static func drySample(
        at time: TimeInterval,
        node: SoundNode,
        duration: TimeInterval,
        sampleRate: Double,
        baseFrequency: Double,
        seed: UInt64
    ) -> Float {
        guard time >= 0, time < duration else { return 0 }
        let progress = time / duration
        let envelopePower = node.type == .pad ? 1.15 : 3.4
        let envelope = Float(pow(max(0, 1 - progress), envelopePower))
        let sine = Float(sin(2 * .pi * sweptFrequency(for: node.type, baseFrequency: baseFrequency, progress: progress) * time))
        let noise = deterministicNoise(sample: Int64(time * sampleRate), seed: seed)

        let timbre: Float = switch node.type {
        case .kick: sine * Float(1 - progress * 0.55)
        case .snare: sine * 0.24 + noise * 0.62
        case .hiHat: noise * 0.4 + Float(sin(2 * .pi * 6_200 * time)) * 0.16
        case .clap: noise * (Int(time * sampleRate) % 1_050 < 330 ? 0.52 : 0.11)
        case .bass: (sine + Float(sin(2 * .pi * baseFrequency * 2 * time)) * 0.24) * 0.66
        case .pad: (sine + Float(sin(2 * .pi * baseFrequency * 1.5 * time)) * 0.34) * 0.4
        case .lead: sine > 0 ? 0.4 : -0.4
        case .fx: sine * 0.3 + noise * 0.1
        }
        return envelope * timbre
    }

    private static func sweptFrequency(
        for type: SoundNodeType,
        baseFrequency: Double,
        progress: Double
    ) -> Double {
        switch type {
        case .kick: baseFrequency * max(0.58, 1.85 - progress * 1.4)
        case .fx: baseFrequency * (1 + progress * 4)
        default: baseFrequency
        }
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
