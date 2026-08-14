import AVFAudio
import Foundation

/// Reproduce ocho timbres sintetizados localmente. Así el prototipo tiene audio
/// funcional sin incorporar samples con licencias o atribuciones desconocidas.
@MainActor
final class AudioEngineManager {
    private let engine = AVAudioEngine()
    private var players: [SoundNodeType: AVAudioPlayerNode] = [:]
    private var buffers: [SoundNodeType: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        for type in SoundNodeType.allCases {
            let player = AVAudioPlayerNode()
            players[type] = player
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            buffers[type] = Self.makeBuffer(for: type, format: format)
        }
    }

    func play(_ node: SoundNode) {
        guard let player = players[node.type], let buffer = buffers[node.type] else { return }
        startEngineIfNeeded()
        player.volume = max(0, min(node.volume, 1))
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("SoundVision audio engine: \(error.localizedDescription)")
        }
    }

    private static func makeBuffer(for type: SoundNodeType, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = type == .pad || type == .fx ? 0.65 : 0.24
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return buffer }

        let frequency: Double = switch type {
        case .kick: 62
        case .snare: 185
        case .hiHat: 1_400
        case .clap: 520
        case .bass: 92
        case .pad: 220
        case .lead: 660
        case .fx: 310
        }

        var random = UInt64(type.rawValue.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) })
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let progress = time / duration
            let envelope = Float(pow(max(0, 1 - progress), type == .pad ? 1.2 : 3.4))
            random = random &* 6_364_136_223_846_793_005 &+ 1
            let noise = Float(Double(Int64(bitPattern: random)) / Double(Int64.max))
            let sweep = frequency * (type == .fx ? 1 + progress * 4 : 1)
            let sine = Float(sin(2 * .pi * sweep * time))

            let timbre: Float = switch type {
            case .kick: sine * Float(1 - progress * 0.5)
            case .snare: sine * 0.25 + noise * 0.65
            case .hiHat: noise * 0.42 + Float(sin(2 * .pi * 6_200 * time)) * 0.18
            case .clap: noise * (frame % 900 < 300 ? 0.55 : 0.12)
            case .bass: (sine + Float(sin(2 * .pi * frequency * 2 * time)) * 0.25) * 0.65
            case .pad: (sine + Float(sin(2 * .pi * frequency * 1.5 * time)) * 0.35) * 0.38
            case .lead: (sine > 0 ? 0.42 : -0.42)
            case .fx: sine * 0.28 + noise * 0.12
            }
            samples[frame] = envelope * timbre
        }
        return buffer
    }
}
