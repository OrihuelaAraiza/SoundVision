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
        leadInSeconds: TimeInterval = 0.24
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
                controller.gain = -3
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
        return SpatialAudioComponent(
            gain: max(-24, min(musicalGain, 0)),
            directLevel: .zero,
            reverbLevel: max(-24, min(reverbLevel, -1)),
            directivity: .beam(focus: .zero),
            distanceAttenuation: .rolloff(factor: 0.9)
        )
    }
}

/// Renderizador sin locks ni asignaciones en el audio thread. Todas las notas
/// se evalúan contra host time, de modo que ramas distintas comparten ataques
/// sample-accurate aunque cada entidad tenga su propio generador.
private final class SpatialVoiceRenderer: @unchecked Sendable {
    private let node: SoundNode
    private let attackSeconds: [TimeInterval]
    private let sampleRate = 48_000.0
    private let soundDuration: TimeInterval
    private let baseFrequency: Double
    private let seed: UInt64

    init(node: SoundNode, attackHostTimes: [UInt64]) {
        self.node = node
        attackSeconds = attackHostTimes.map(AVAudioTime.seconds(forHostTime:))
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
        baseFrequency = fundamental * pow(2, Double(node.pitch) / 12)
        seed = UInt64(node.type.rawValue.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) })
    }

    var render: Audio.GeneratorRenderHandler {
        { [unowned self] _, timestamp, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let blockStart = AVAudioTime.seconds(forHostTime: timestamp.pointee.mHostTime)

            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    let absoluteTime = blockStart + Double(frame) / sampleRate
                    var mixedSample: Float = 0
                    for attack in attackSeconds {
                        let localTime = absoluteTime - attack
                        guard localTime >= 0, localTime < soundDuration else { continue }
                        mixedSample += sample(at: localTime)
                    }
                    data[frame] = tanh(mixedSample * 1.15) * 0.78
                }
            }

            return noErr
        }
    }

    private func sample(at time: TimeInterval) -> Float {
        let dry = drySample(at: time)
        let delayTime = 0.07 + Double(node.delay) * 0.48
        let firstEcho = time >= delayTime ? drySample(at: time - delayTime) * node.delay * 0.42 : 0
        let secondEcho = time >= delayTime * 2 ? drySample(at: time - delayTime * 2) * node.delay * 0.18 : 0
        let combined = dry + firstEcho + secondEcho
        let drive = 1 + node.distortion * 8
        return node.distortion > 0.001
            ? tanh(combined * drive) / max(1, tanh(drive))
            : combined
    }

    private func drySample(at time: TimeInterval) -> Float {
        guard time >= 0, time < soundDuration else { return 0 }
        let progress = time / soundDuration
        let envelopePower = node.type == .pad ? 1.15 : 3.4
        let envelope = Float(pow(max(0, 1 - progress), envelopePower))
        let sine = Float(sin(2 * .pi * sweptFrequency(at: progress) * time))
        let noise = deterministicNoise(sample: Int64(time * sampleRate))

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

    private func sweptFrequency(at progress: Double) -> Double {
        switch node.type {
        case .kick: baseFrequency * max(0.58, 1.85 - progress * 1.4)
        case .fx: baseFrequency * (1 + progress * 4)
        default: baseFrequency
        }
    }

    private func deterministicNoise(sample: Int64) -> Float {
        var value = UInt64(bitPattern: sample) &+ seed
        value ^= value >> 30
        value &*= 0xbf58_476d_1ce4_e5b9
        value ^= value >> 27
        value &*= 0x94d0_49bb_1331_11eb
        value ^= value >> 31
        return Float(Double(value) / Double(UInt64.max) * 2 - 1)
    }
}
