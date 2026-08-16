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
    /// Índices para poder empujar parámetros vivos a la voz de cada organismo.
    private var voicesByNode: [UUID: SpatialVoiceRenderer] = [:]
    private var entitiesByNode: [UUID: Entity] = [:]
    private var secondsPerBeat: Double = 0.5
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
        secondsPerBeat = session.secondsPerBeat

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
                voicesByNode[nodeID] = renderer
                entitiesByNode[nodeID] = entity
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
        voicesByNode = [:]
        entitiesByNode = [:]
        sessionID = nil
        attachFailure = nil
    }

    /// Empuja a las voces vivas lo que la mano acaba de cambiar. Es lo que hace
    /// que mover un organismo mientras suena se oiga al instante en vez de
    /// esperar a la siguiente reproducción.
    func updateLiveParameters(nodes: [SoundNode], sustainBeats: [UUID: Double]) {
        guard !voicesByNode.isEmpty else { return }
        for node in nodes {
            if let entity = entitiesByNode[node.id] {
                // Volumen y reverb los aplica RealityKit, no el sintetizador.
                entity.spatialAudio = spatialConfiguration(for: node)
            }
            guard let voice = voicesByNode[node.id] else { continue }
            voice.parameters.update(
                from: node,
                heldSeconds: heldSeconds(for: node, sustainBeats: sustainBeats)
            )
        }
    }

    private func heldSeconds(for node: SoundNode, sustainBeats: [UUID: Double]) -> Double {
        let beats = sustainBeats[node.id] ?? 1.2
        let seconds = beats * secondsPerBeat
        let release = VoiceSynthesis.spec(for: node.type).release
        return min(max(seconds, 0.18), VoiceSynthesis.maximumDuration - release)
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
