import AVFAudio
import Foundation
import RealityKit

struct SpatialAudioSession: Identifiable, Sendable {
    let id: UUID
    let nodes: [SoundNode]
    let events: [GraphPlaybackEvent]
    /// Cuánto sostiene cada organismo antes de que arranque el siguiente. Es la
    /// distancia horizontal traducida a tiempo: lejos sostiene, cerca es staccato.
    let sustainBeats: [UUID: Double]
    let secondsPerBeat: Double
    let startHostTime: UInt64
    let leadInSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        nodes: [SoundNode],
        events: [GraphPlaybackEvent],
        sustainBeats: [UUID: Double] = [:],
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
        self.sustainBeats = sustainBeats
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
    private var attachFailure: String?

    /// Resumen legible del estado real del motor. Devuelve `nil` cuando todo va
    /// bien: solo habla si hay algo que explicar.
    var problemSummary: String? {
        if let attachFailure { return "Audio: \(attachFailure)" }
        guard sessionID != nil else { return nil }
        if controllers.isEmpty {
            return "Audio: ninguna voz llegó a engancharse a la escena."
        }
        if renderers.allSatisfy({ !$0.didRenderAudibleSample }) {
            return "Audio: \(controllers.count) voces conectadas pero sin muestras audibles todavía."
        }
        return nil
    }

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
        attachFailure = nil

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
            let renderer = SpatialVoiceRenderer(
                node: node,
                sustainSeconds: session.sustainBeats[nodeID].map { $0 * session.secondsPerBeat },
                attackHostTimes: attackHostTimes
            )

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
                attachFailure = error.localizedDescription
                print("SoundVision RealityKit spatial audio: \(error.localizedDescription)")
            }
        }
    }

    func stopAll() {
        controllers.forEach { $0.stop() }
        controllers = []
        renderers = []
        sessionID = nil
        attachFailure = nil
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
final class SpatialVoiceRenderer: @unchecked Sendable {
    private let attackSeconds: [TimeInterval]
    private let sampleRate = 48_000.0
    private let soundDuration: TimeInterval
    private let samples: [Float]

    /// Reloj propio, usado cuando el timestamp del host no sirve. Solo lo toca
    /// el hilo de audio, un bloque después de otro.
    private var anchorSeconds: TimeInterval = -1
    private var renderedFrames: Double = 0
    private var resolvedClock: Clock = .undecided

    enum Clock { case undecided, hostTimestamp, internalCounter }

    /// Diagnóstico para la UI: sin esto, "no suena" es indistinguible de "las
    /// voces nunca llegaron a engancharse".
    private(set) var didRenderAudibleSample = false

    init(node: SoundNode, sustainSeconds: TimeInterval? = nil, attackHostTimes: [UInt64]) {
        // Ordenados para poder acotar por búsqueda binaria qué ataques pueden
        // sonar en un bloque concreto, en vez de recorrerlos todos por frame.
        attackSeconds = attackHostTimes.map(AVAudioTime.seconds(forHostTime:)).sorted()
        soundDuration = VoiceSynthesis.duration(for: node.type, sustainSeconds: sustainSeconds)
        samples = VoiceSynthesis.bake(
            node: node,
            sustainSeconds: sustainSeconds,
            sampleRate: 48_000
        )
    }

    var render: Audio.GeneratorRenderHandler {
        // `isSilence` es parte del contrato, no un parámetro ignorable: quien
        // consume el buffer puede descartarlo si queda marcado como silencio.
        // El código anterior nunca lo tocaba.
        { [unowned self] isSilence, timestamp, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let blockStart = self.blockStartSeconds(from: timestamp.pointee)
            let blockEnd = blockStart + Double(frameCount) / sampleRate
            defer { renderedFrames += Double(frameCount) }

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
                isSilence.pointee = true
                return noErr
            }
            isSilence.pointee = false

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
                    if mixedSample != 0 { didRenderAudibleSample = true }
                    data[frame] = max(-0.78, min(mixedSample * 0.9, 0.78))
                }
            }

            return noErr
        }
    }

    /// Decide una sola vez de qué reloj fiarse y se mantiene en él.
    ///
    /// El diseño original daba por hecho que `mHostTime` venía poblado y en el
    /// mismo reloj `mach_absolute_time()` que los ataques. Cuando no es así, los
    /// ataques quedan fuera de toda ventana y la salida es silencio total, sin
    /// error ni pista alguna. Ahora se verifica y, si no cuadra, se lleva un
    /// contador de muestras propio anclado al reloj mach.
    private func blockStartSeconds(from stamp: AudioTimeStamp) -> TimeInterval {
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())

        if resolvedClock == .undecided {
            let hostSeconds = AVAudioTime.seconds(forHostTime: stamp.mHostTime)
            let isValid = stamp.mFlags.contains(.hostTimeValid)
                && stamp.mHostTime != 0
                // Mismo epoch: un timestamp del reloj de audio o a cero se
                // delataría por estar a años de distancia del reloj mach.
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

    var usesFallbackClock: Bool { resolvedClock == .internalCounter }

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

}
