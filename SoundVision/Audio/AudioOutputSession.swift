import AVFAudio
import Foundation

/// Sesión de audio del sistema.
///
/// RealityKit espacializa, pero quien decide si la app tiene derecho a sonar y
/// por qué ruta sale es `AVAudioSession`. La app no la configuraba en absoluto y
/// se quedaba con la categoría por defecto: en el simulador eso suena, pero en
/// el dispositivo es una de las explicaciones clásicas de "pulso Play, veo la
/// animación y no oigo nada". Se activa una vez al arrancar y se vuelve a
/// asegurar antes de cada reproducción, que es barato e idempotente.
@MainActor
enum AudioOutputSession {
    /// Solo tiene valor si el sistema rechazó algo. La consola lo enseña.
    private(set) static var problem: String?
    private static var isActive = false

    @discardableResult
    static func activate() -> Bool {
        guard !isActive else { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            // `.playback` con modo `.default` es la configuración canónica para
            // reproducir contenido espacial: esto es un instrumento, no un
            // efecto de interfaz, y debe sonar aunque el resto del sistema
            // calle. Sin opciones a propósito —`.mixWithOthers` sería más
            // cortés con lo que ya estuviera sonando, pero altera cómo se mezcla
            // la salida y no vale la pena arriesgar la espacialización por
            // educación. La sesión se activa al entrar al estudio, no al
            // arrancar la app, así que nada se interrumpe antes de tiempo.
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isActive = true
            problem = nil
            return true
        } catch {
            problem = "el sistema no concedió la sesión de audio (\(error.localizedDescription))"
            return false
        }
    }

    /// Tasa de muestreo de la ruta actual. Solo informativa: la voz mide la suya
    /// a partir de los timestamps reales del render.
    static var sampleRate: Double {
        AVAudioSession.sharedInstance().sampleRate
    }

    static var routeDescription: String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let first = outputs.first else { return "sin salida" }
        return first.portName
    }
}
