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

/// Une cada organismo visual con una fuente de RealityKit Spatial Audio.
/// RealityKit aplica el HRTF personalizado, seguimiento de cabeza, atenuación
/// física y acústica del entorno; el render handler entrega una señal mono para
/// que Apple realice la espacialización final.
///
/// Las voces son **persistentes**: nacen con el organismo y mueren con él. Antes
/// se creaban al pulsar Play y se destruían al detener, de modo que cada
/// reproducción pagaba el enganche del grafo de audio justo cuando la línea de
/// tiempo ya estaba fechada, y en el dispositivo eso llegaba tarde y se comía
/// las primeras notas. Reproducir ahora es solo publicar tiempos.
@MainActor
final class AudioEngineManager: ObservableObject {
    private struct Voice {
        let renderer: SpatialVoiceRenderer
        let controller: AudioGeneratorController
        /// Débil a propósito: si la escena retira la entidad, la voz queda
        /// huérfana y hay que volver a engancharla, no mantenerla viva a la
        /// fuerza con una fuente de audio colgando de ella.
        weak var entity: Entity?
        var appliedGain: Double = .nan
        var appliedReverb: Double = .nan
        /// Una voz puede terminar de engancharse una pasada de interfaz después
        /// de que Play haya publicado la sesión. Llevar esta marca por voz evita
        /// que ese organismo se quede sin agenda solo porque sus compañeros ya
        /// la recibieron.
        var publishedSessionID: UUID?
    }

    /// Techo de fuentes espaciales simultáneas. Cada voz es una fuente de audio
    /// de RealityKit viva permanentemente; un lienzo con decenas de organismos
    /// no debe poder agotar los recursos del sistema en silencio. Si se alcanza,
    /// el diagnóstico lo dice en vez de dejar organismos mudos sin explicación.
    static let maximumVoices = 32

    private var voices: [UUID: Voice] = [:]
    private var publishedSessionID: UUID?
    private var publishedStartSeconds: Double?
    private var secondsPerBeat: Double = 0.5
    private var expectedVoiceCount = 0
    private var requestedVoiceCount = 0
    private var attachFailure: String?
    private var lastBlockCount = 0
    private var isStalled = false

    /// Prepara la salida del sistema. Idempotente y barata.
    @discardableResult
    func prepare(force: Bool = false) -> Bool {
        AudioOutputSession.activate(force: force)
    }

    // MARK: - Ciclo de vida de las voces

    /// Suelta las voces de organismos que ya no existen. Debe correr **antes**
    /// de que la escena elimine sus entidades: una fuente de audio cuya entidad
    /// desaparece sin haberse detenido deja audio colgado.
    func releaseVoices(keeping ids: Set<UUID>) {
        // No se muta un Dictionary mientras su iterador está vivo. En Swift esa
        // combinación no ofrece garantías y coincidía con cierres al cambiar de
        // demo o borrar organismos durante una cola de audio.
        let removedIDs = voices.keys.filter { !ids.contains($0) }
        for nodeID in removedIDs {
            voices[nodeID]?.controller.stop()
            voices[nodeID] = nil
        }
    }

    /// Engancha una voz a cada organismo que aún no la tenga. Debe correr
    /// **después** de que la escena haya creado las entidades.
    func attachVoices(
        for nodes: [SoundNode],
        sustainBeats: [UUID: Double],
        entityProvider: (UUID) -> Entity?
    ) {
        requestedVoiceCount = nodes.count
        expectedVoiceCount = min(nodes.count, Self.maximumVoices)
        guard !nodes.isEmpty else {
            attachFailure = nil
            return
        }
        guard prepare() else {
            attachFailure = AudioOutputSession.problem ?? "la sesión de salida no está disponible"
            return
        }

        var firstFailure: String?
        for node in nodes.prefix(Self.maximumVoices) {
            guard let entity = entityProvider(node.id) else { continue }
            // Una entidad reconstruida (deshacer, cargar, demo) deja la voz
            // apuntando al vacío: sin esto, el organismo volvía mudo para
            // siempre aunque siguiera en pantalla.
            if let existing = voices[node.id] {
                if existing.entity === entity { continue }
                existing.controller.stop()
                voices[node.id] = nil
            }

            let renderer = SpatialVoiceRenderer(
                node: node,
                sustainSeconds: sustainBeats[node.id].map { $0 * secondsPerBeat }
            )
            entity.spatialAudio = spatialConfiguration(for: node)
            do {
                let controller = try entity.prepareAudio(
                    configuration: AudioGeneratorConfiguration(layoutTag: kAudioChannelLayoutTag_Mono),
                    renderer.render
                )
                // Conserva 6 dB de headroom para bifurcaciones simultáneas y
                // evita que la primera prueba física resulte agresiva.
                controller.gain = -6
                controller.play()
                voices[node.id] = Voice(
                    renderer: renderer,
                    controller: controller,
                    entity: entity,
                    publishedSessionID: nil
                )
            } catch {
                if firstFailure == nil { firstFailure = error.localizedDescription }
                print("SoundVision RealityKit spatial audio: \(error.localizedDescription)")
            }
        }
        attachFailure = firstFailure
    }

    func stopAll() {
        tearDownVoices()
        AudioOutputSession.deactivate()
    }

    /// Una interrupción o cambio de dispositivo invalida tanto la sesión como
    /// los controladores de RealityKit. Se reconstruyen en la siguiente pasada
    /// de RealityView; intentar reutilizarlos es una fuente conocida de silencio.
    func suspendForAudioInterruption() {
        tearDownVoices()
        AudioOutputSession.invalidate()
    }

    func recoverFromAudioEnvironmentChange(resetConfiguration: Bool = false) {
        tearDownVoices()
        AudioOutputSession.invalidate(configurationToo: resetConfiguration)
        _ = prepare(force: true)
    }

    private func tearDownVoices() {
        voices.values.forEach { $0.controller.stop() }
        voices = [:]
        publishedSessionID = nil
        publishedStartSeconds = nil
        expectedVoiceCount = 0
        requestedVoiceCount = 0
        lastBlockCount = 0
        isStalled = false
        attachFailure = nil
    }

    // MARK: - Reproducción

    func updateTempo(bpm: Double) {
        let safeBPM = bpm.isFinite ? max(1, bpm) : 120
        secondsPerBeat = 60 / safeBPM
    }

    /// Reparte la línea de tiempo entre las voces vivas. Sin reenganches, sin
    /// reservas en el camino crítico: cada voz recibe sus instantes de ataque.
    func publish(session: SpatialAudioSession?) {
        guard let session else {
            guard publishedSessionID != nil else { return }
            let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            for nodeID in Array(voices.keys) {
                guard var voice = voices[nodeID] else { continue }
                voice.renderer.schedule.stop(at: now)
                voice.publishedSessionID = nil
                voices[nodeID] = voice
            }
            publishedSessionID = nil
            publishedStartSeconds = nil
            return
        }

        guard prepare() else {
            voices.values.forEach { $0.renderer.schedule.clear() }
            return
        }
        secondsPerBeat = session.secondsPerBeat

        let isNewSession = session.id != publishedSessionID
        publishedSessionID = session.id

        // Red de seguridad contra una publicación tardía. La sesión se fecha al
        // pulsar Play y llega aquí en la siguiente pasada de SwiftUI; si esa
        // pasada se retrasa más que el margen previsto, las primeras notas
        // caerían en el pasado y se perderían en silencio. Antes que sacrificar
        // el arranque de la pieza, se desplaza la línea entera: como mucho, la
        // imagen adelanta al sonido unos milisegundos.
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let start: Double
        if isNewSession || publishedStartSeconds == nil {
            start = max(AVAudioTime.seconds(forHostTime: session.startHostTime), now + 0.06)
            publishedStartSeconds = start
        } else {
            start = publishedStartSeconds ?? now + 0.06
        }
        let activeIDs = Set(session.nodes.filter(\.isActive).map(\.id))
        let attacksByNode = session.attackTimesByNode(startSeconds: start)

        for nodeID in Array(voices.keys) {
            guard var voice = voices[nodeID] else { continue }
            guard isNewSession || voice.publishedSessionID != session.id else { continue }
            guard activeIDs.contains(nodeID), let attacks = attacksByNode[nodeID] else {
                voice.renderer.schedule.clear()
                voice.publishedSessionID = session.id
                voices[nodeID] = voice
                continue
            }
            voice.renderer.schedule.publish(
                attacks,
                loopStart: start,
                repeatingEvery: session.loopDurationSeconds
            )
            voice.publishedSessionID = session.id
            voices[nodeID] = voice
        }
    }

    /// Empuja a las voces vivas lo que la mano acaba de cambiar. Es lo que hace
    /// que mover un organismo mientras suena se oiga al instante en vez de
    /// esperar a la siguiente reproducción.
    func updateLiveParameters(nodes: [SoundNode], sustainBeats: [UUID: Double]) {
        guard !voices.isEmpty else { return }
        for node in nodes {
            guard var voice = voices[node.id] else { continue }

            // Volumen y reverb los aplica RealityKit, no el sintetizador.
            // Reescribir el componente en cada pasada costaba trabajo inútil en
            // el hilo principal: solo se toca cuando el valor cambia de verdad.
            let gain = spatialGain(for: node)
            let reverb = spatialReverb(for: node)
            if voice.appliedGain != gain || voice.appliedReverb != reverb {
                voice.entity?.spatialAudio = spatialConfiguration(for: node)
                voice.appliedGain = gain
                voice.appliedReverb = reverb
                voices[node.id] = voice
            }

            voice.renderer.parameters.update(
                from: node,
                heldSeconds: heldSeconds(for: node, sustainBeats: sustainBeats)
            )
        }
    }

    // MARK: - Diagnóstico

    /// Resumen legible del estado real del motor. Devuelve `nil` cuando todo va
    /// bien: solo habla si hay algo que explicar.
    var problemSummary: String? {
        if let problem = AudioOutputSession.problem { return "Audio: \(problem)" }
        if let attachFailure { return "Audio: \(attachFailure)" }
        guard expectedVoiceCount > 0 else { return nil }
        if voices.isEmpty {
            return "Audio: ninguna voz llegó a engancharse a la escena."
        }
        if voices.count < expectedVoiceCount {
            return "Audio: \(voices.count) de \(expectedVoiceCount) organismos tienen voz."
        }
        if requestedVoiceCount > Self.maximumVoices {
            return "Audio: solo los primeros \(Self.maximumVoices) de \(requestedVoiceCount) organismos tienen voz."
        }
        if voices.values.allSatisfy({ $0.renderer.renderedBlocks == 0 }) {
            return "Audio: las voces están enganchadas pero el sistema no les pide muestras."
        }
        if isStalled {
            return "Audio: el sistema dejó de pedir muestras en plena reproducción."
        }
        if publishedSessionID != nil, voices.values.allSatisfy({ !$0.renderer.didRenderAudibleSample }) {
            return "Audio: voces conectadas y activas, pero sin muestras audibles todavía."
        }
        return nil
    }

    /// Estado vivo del motor en una línea. Es lo que convierte "no suena" en un
    /// dato accionable durante una prueba con el visor puesto.
    ///
    /// Se consulta a 1 Hz, así que aprovecha para medir si el sistema sigue
    /// pidiendo muestras: una voz enganchada que deja de rendir es un fallo
    /// completamente distinto de una voz que rinde silencio, y desde fuera los
    /// dos suenan igual de callados.
    func diagnosticsSummary() -> String {
        let blocks = voices.values.reduce(0) { $0 + $1.renderer.renderedBlocks }
        isStalled = publishedSessionID != nil && blocks > 0 && blocks == lastBlockCount
        lastBlockCount = blocks

        guard let reference = voices.values.first else {
            return "Sin voces enganchadas · \(AudioOutputSession.routeDescription)"
        }
        let peak = voices.values.map(\.renderer.peakLevel).max() ?? 0
        let level = peak > 0.0001
            ? String(format: "%.0f dB", 20 * log10(Double(peak)))
            : "silencio"
        return String(
            format: "%d voces · %@ · %.1f kHz · pico %@ · %@",
            voices.count,
            reference.renderer.clockDescription,
            reference.renderer.sampleRate / 1_000,
            level,
            AudioOutputSession.routeDescription
        )
    }

    // MARK: - Parámetros espaciales

    private func heldSeconds(for node: SoundNode, sustainBeats: [UUID: Double]) -> Double {
        let beats = sustainBeats[node.id] ?? 1.2
        let seconds = beats * secondsPerBeat
        let release = VoiceSynthesis.spec(for: node.type).release
        return min(max(seconds, 0.18), VoiceSynthesis.maximumDuration - release)
    }

    private func spatialGain(for node: SoundNode) -> Double {
        max(-24, min(20 * log10(max(0.05, Double(node.volume))), 0))
    }

    private func spatialReverb(for node: SoundNode) -> Double {
        max(-24, min(-24 + Double(node.reverb) * 23, -1))
    }

    private func spatialConfiguration(for node: SoundNode) -> SpatialAudioComponent {
        // Sin directividad: un organismo sonoro debe localizarse igual de bien
        // desde cualquier ángulo, incluido a la espalda de la persona.
        SpatialAudioComponent(
            gain: spatialGain(for: node),
            directLevel: .zero,
            reverbLevel: spatialReverb(for: node),
            distanceAttenuation: .rolloff(factor: 0.9)
        )
    }
}
