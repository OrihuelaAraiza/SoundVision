import AVFAudio
import Foundation

struct SpatialAudioSession: Identifiable, Sendable {
    let id: UUID
    let nodes: [SoundNode]
    let events: [GraphPlaybackEvent]
    /// Cuánto sostiene cada organismo antes de que arranque el siguiente. Es la
    /// distancia horizontal traducida a tiempo: lejos sostiene, cerca es staccato.
    let sustainBeats: [UUID: Double]
    let secondsPerBeat: Double
    /// Duración del patrón que vuelve a empezar hasta recibir Stop. `nil` deja
    /// una sesión de una sola toma, como el preview de un organismo.
    let loopDurationBeats: Double?
    let startHostTime: UInt64
    let leadInSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        nodes: [SoundNode],
        events: [GraphPlaybackEvent],
        sustainBeats: [UUID: Double] = [:],
        secondsPerBeat: Double,
        loopDurationBeats: Double? = nil,
        // Margen para que SwiftUI propague la sesión y las voces reciban su
        // agenda antes del primer ataque. Ya no incluye el enganche del audio:
        // las voces están vivas desde que existe el organismo, así que aquí solo
        // se paga una pasada de interfaz.
        leadInSeconds: TimeInterval = 0.45
    ) {
        self.id = id
        self.nodes = nodes
        self.events = events
        self.sustainBeats = sustainBeats
        self.secondsPerBeat = secondsPerBeat
        self.loopDurationBeats = loopDurationBeats
        self.leadInSeconds = leadInSeconds
        startHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: leadInSeconds)
    }

    var loopDurationSeconds: TimeInterval? {
        guard let loopDurationBeats,
              loopDurationBeats.isFinite,
              loopDurationBeats > 0,
              secondsPerBeat.isFinite,
              secondsPerBeat > 0
        else { return nil }
        return loopDurationBeats * secondsPerBeat
    }

    /// Conserva cada bifurcación como una agenda independiente. Agrupar aquí,
    /// antes de tocar las voces de RealityKit, evita que una salida simultánea
    /// pueda reemplazar a otra al publicar el patrón.
    func attackTimesByNode(startSeconds: TimeInterval) -> [UUID: [TimeInterval]] {
        Dictionary(grouping: events, by: \.nodeID).mapValues { events in
            events.map { startSeconds + $0.beat * secondsPerBeat }
        }
    }
}

