import Foundation
import Synchronization

/// Agenda de ataques de una voz. La escribe el hilo principal y la lee el de
/// audio, sin locks y sin reservar memoria.
///
/// El motivo de que exista: antes cada Play creaba voces nuevas y las enganchaba
/// a la escena en ese momento, pero la línea de tiempo ya se había fechado con
/// el reloj del sistema *antes* de engancharlas. Si el enganche tardaba más que
/// el margen previsto —cosa normal en el dispositivo, con el grafo de audio aún
/// frío— los primeros ataques quedaban en el pasado y no sonaba nada. Ahora las
/// voces viven mientras vive su organismo y Play solo publica aquí sus tiempos,
/// así que entre pulsar y sonar no queda ningún trabajo pesado.
///
/// Dos losas fijas y un estado atómico: el hilo principal escribe siempre en la
/// losa que *no* está publicada y luego publica índice y número de ataques de
/// una sola vez. Una lectura en vuelo nunca ve una agenda a medio escribir.
final class VoiceSchedule: @unchecked Sendable {
    /// Techo de ataques por voz y reproducción. El grafo entero está limitado a
    /// 512 eventos, repartidos entre todos los organismos.
    static let capacity = 128

    /// Fotografía coherente de la agenda, tomada una vez por bloque de audio.
    struct Snapshot {
        let attacks: UnsafePointer<Double>
        let count: Int
        let generation: UInt64
        /// Instante a partir del cual no se atacan notas nuevas y lo que suena
        /// se desvanece. `infinity` mientras la reproducción sigue viva.
        let stopTime: Double
    }

    private let attacks: UnsafeMutablePointer<Double>
    /// generación (31 bits) · losa (1 bit) · número de ataques (32 bits).
    private let published = Atomic<UInt64>(0)
    private let stopBits = Atomic<UInt64>(Double.infinity.bitPattern)
    private var writeSlab = 1
    private var generation: UInt64 = 0

    init() {
        attacks = .allocate(capacity: Self.capacity * 2)
        attacks.initialize(repeating: 0, count: Self.capacity * 2)
    }

    deinit {
        attacks.deallocate()
    }

    /// Publica una agenda nueva, en segundos del reloj mach. Solo hilo principal.
    func publish(_ times: [Double]) {
        let sorted = times.sorted()
        let count = min(sorted.count, Self.capacity)
        let base = attacks + writeSlab * Self.capacity
        for index in 0..<count { base[index] = sorted[index] }

        stopBits.store(Double.infinity.bitPattern, ordering: .releasing)
        generation = (generation &+ 1) & 0x7FFF_FFFF
        published.store(
            (generation &<< 33) | (UInt64(writeSlab) &<< 32) | UInt64(count),
            ordering: .releasing
        )
        writeSlab = 1 - writeSlab
    }

    /// Corta la reproducción sin vaciar la agenda: lo que ya está sonando
    /// conserva su cola y se desvanece en unos milisegundos. Vaciarla de golpe
    /// truncaba la onda a mitad de ciclo y eso se oye como un chasquido.
    func stop(at time: Double) {
        stopBits.store(time.bitPattern, ordering: .releasing)
    }

    func clear() {
        publish([])
    }

    /// Lectura para el hilo de audio: dos cargas atómicas por bloque.
    @inline(__always)
    func snapshot() -> Snapshot {
        let state = published.load(ordering: .acquiring)
        let slab = Int((state &>> 32) & 1)
        return Snapshot(
            attacks: UnsafePointer(attacks + slab * Self.capacity),
            count: Int(state & 0xFFFF_FFFF),
            generation: state &>> 33,
            stopTime: Double(bitPattern: stopBits.load(ordering: .acquiring))
        )
    }
}
