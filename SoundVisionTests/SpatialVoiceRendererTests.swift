import AVFAudio
import RealityKit
import XCTest
@testable import SoundVision

/// Prueba el renderizador contra su propio callback de audio. Sirve para
/// separar dos causas de "no suena": un fallo en la síntesis y el scheduling
/// (que estas pruebas cubren) o un fallo en cómo RealityKit entrega el reloj y
/// conecta las fuentes (que solo se ve en dispositivo).
final class SpatialVoiceRendererTests: XCTestCase {
    private let frameCount: AUAudioFrameCount = 512
    private var lastBlockWasMarkedSilent = true

    func testRendersAudioWhenHostTimestampIsValid() {
        let attack = mach_absolute_time()
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Kick", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0),
            attackHostTimes: [attack]
        )

        let output = render(renderer, hostTime: attack, hostTimeValid: true)
        XCTAssertTrue(output.contains { $0 != 0 }, "El ataque debe producir muestras audibles")
        XCTAssertFalse(lastBlockWasMarkedSilent, "Un bloque con audio no debe marcarse como silencio")
        XCTAssertTrue(renderer.didRenderAudibleSample)
        XCTAssertFalse(renderer.usesFallbackClock)
    }

    /// El caso que provocaba silencio absoluto: si el timestamp no trae host
    /// time utilizable, el renderizador debe recurrir a su propio reloj en vez
    /// de dejar todos los ataques fuera de ventana.
    func testRendersAudioWhenHostTimestampIsUnusable() {
        let attack = mach_absolute_time()
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Snare", type: .snare, positionX: 0, positionY: 1.25, positionZ: 0),
            attackHostTimes: [attack]
        )

        let output = render(renderer, hostTime: 0, hostTimeValid: false)
        XCTAssertTrue(renderer.usesFallbackClock, "Debe detectar que el host time no sirve")
        XCTAssertTrue(output.contains { $0 != 0 }, "Con el reloj propio también debe sonar")
    }

    /// Un timestamp válido pero de otro epoch (por ejemplo el reloj del
    /// hardware de audio) también debe detectarse, no creerse a ciegas.
    func testRejectsTimestampFromAnotherEpoch() {
        let attack = mach_absolute_time()
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Bass", type: .bass, positionX: 0, positionY: 1.25, positionZ: 0),
            attackHostTimes: [attack]
        )

        // Marcado como válido, pero a años del reloj mach.
        let output = render(renderer, hostTime: 12_345, hostTimeValid: true)
        XCTAssertTrue(renderer.usesFallbackClock)
        XCTAssertTrue(output.contains { $0 != 0 })
    }

    func testStaysSilentLongBeforeTheAttack() {
        let attack = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 30)
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0),
            attackHostTimes: [attack]
        )

        let output = render(renderer, hostTime: mach_absolute_time(), hostTimeValid: true)
        XCTAssertFalse(output.contains { $0 != 0 }, "Nada debe sonar 30 s antes del ataque")
        XCTAssertTrue(lastBlockWasMarkedSilent, "Un bloque vacío sí debe marcarse como silencio")
    }

    /// El handler tiene que mantener viva a su voz. Con una captura `unowned`,
    /// soltar la voz al detener la reproducción la destruía —liberando de paso
    /// su memoria manual— mientras el grafo de audio aún podía invocarla, y el
    /// motor quedaba corrupto tras la primera reproducción.
    func testHandlerKeepsItsVoiceAliveAfterTheEngineDropsIt() {
        var handler: Audio.GeneratorRenderHandler?
        weak var weakVoice: SpatialVoiceRenderer?

        autoreleasepool {
            let voice = SpatialVoiceRenderer(
                node: SoundNode(name: "Bass", type: .bass, positionX: 0, positionY: 1.25, positionZ: 0),
                attackHostTimes: [mach_absolute_time()]
            )
            weakVoice = voice
            handler = voice.render
        }

        XCTAssertNotNil(handler)
        XCTAssertNotNil(weakVoice, "El handler debe retener a su voz mientras el motor lo conserve")

        handler = nil
        XCTAssertNil(weakVoice, "Al soltar el handler, la voz debe liberarse sin fugas")
    }

    // MARK: - Agenda publicada en caliente

    /// La regresión que dejaba Play mudo: la voz ya estaba rindiendo cuando
    /// llegó la agenda. Antes las voces nacían *con* su agenda y se enganchaban
    /// al pulsar Play, así que si el enganche llegaba tarde los ataques
    /// quedaban en el pasado y no sonaba absolutamente nada.
    func testVoiceSoundsWhenTheScheduleArrivesAfterItStartedRendering() {
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Kick", type: .kick, positionX: 0, positionY: 1.25, positionZ: 0)
        )

        let idle = render(renderer, hostTime: mach_absolute_time(), hostTimeValid: true)
        XCTAssertFalse(idle.contains { $0 != 0 }, "Sin agenda, la voz debe estar en silencio")
        XCTAssertTrue(lastBlockWasMarkedSilent)

        let attack = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05)
        renderer.schedule.publish([AVAudioTime.seconds(forHostTime: attack)])

        let output = render(renderer, hostTime: attack, hostTimeValid: true)
        XCTAssertTrue(output.contains { $0 != 0 }, "Publicar la agenda debe bastar para que suene")
        XCTAssertFalse(lastBlockWasMarkedSilent)
    }

    /// Reproducir dos veces seguidas con la misma voz: el segundo Play publica
    /// una agenda nueva y debe sonar igual que el primero.
    func testVoiceSoundsAgainOnASecondSchedule() {
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Snare", type: .snare, positionX: 0, positionY: 1.25, positionZ: 0)
        )

        let first = mach_absolute_time()
        renderer.schedule.publish([AVAudioTime.seconds(forHostTime: first)])
        XCTAssertTrue(render(renderer, hostTime: first, hostTimeValid: true).contains { $0 != 0 })

        let second = first + AVAudioTime.hostTime(forSeconds: 4)
        renderer.schedule.publish([AVAudioTime.seconds(forHostTime: second)])
        XCTAssertTrue(
            render(renderer, hostTime: second, hostTimeValid: true).contains { $0 != 0 },
            "La segunda reproducción debe sonar sin volver a crear la voz"
        )
    }

    /// Detener no vacía la agenda: deja que la cola se apague en unos
    /// milisegundos. Cortar la onda a mitad de ciclo se oye como un chasquido.
    func testStoppingFadesTheTailAndThenGoesSilent() {
        let renderer = SpatialVoiceRenderer(
            node: SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0),
            sustainSeconds: 2
        )
        let attack = mach_absolute_time()
        let attackSeconds = AVAudioTime.seconds(forHostTime: attack)
        renderer.schedule.publish([attackSeconds])

        let sounding = render(
            renderer,
            hostTime: attack + AVAudioTime.hostTime(forSeconds: 0.4),
            hostTimeValid: true
        )
        XCTAssertTrue(sounding.contains { $0 != 0 }, "El pad debe estar sonando a los 0,4 s")

        renderer.schedule.stop(at: attackSeconds + 0.41)
        let afterFade = render(
            renderer,
            hostTime: attack + AVAudioTime.hostTime(forSeconds: 0.45),
            hostTimeValid: true
        )
        XCTAssertFalse(afterFade.contains { $0 != 0 }, "Pasado el desvanecido no debe quedar señal")
    }

    /// Un organismo muteado conserva su voz enganchada y no suena.
    func testMutedNodeStaysSilentEvenWithNotesScheduled() {
        var node = SoundNode(name: "Bass", type: .bass, positionX: 0, positionY: 1.25, positionZ: 0)
        let renderer = SpatialVoiceRenderer(node: node)
        node.isActive = false
        renderer.parameters.update(from: node, heldSeconds: 1)

        let attack = mach_absolute_time()
        renderer.schedule.publish([AVAudioTime.seconds(forHostTime: attack)])

        let output = render(
            renderer,
            hostTime: attack + AVAudioTime.hostTime(forSeconds: 0.1),
            hostTimeValid: true
        )
        XCTAssertFalse(output.contains { $0 != 0 })
    }

    /// Cada familia sonora debe producir su propia señal: si una quedara muda,
    /// la composición perdería un instrumento sin avisar.
    func testEveryInstrumentProducesSound() {
        for type in SoundNodeType.allCases {
            let renderer = SpatialVoiceRenderer(
                node: SoundNode(
                    name: SoundNodeType.displayName(for: type),
                    type: type,
                    positionX: 0,
                    positionY: 1.25,
                    positionZ: 0
                ),
                sustainSeconds: 1
            )
            let attack = mach_absolute_time()
            renderer.schedule.publish([AVAudioTime.seconds(forHostTime: attack)])

            // Un poco después del ataque: los tonales tienen envolvente de
            // entrada y en la primera muestra todavía valen cero.
            let output = render(
                renderer,
                hostTime: attack + AVAudioTime.hostTime(forSeconds: 0.05),
                hostTimeValid: true
            )
            XCTAssertTrue(
                output.contains { $0 != 0 },
                "\(SoundNodeType.displayName(for: type)) no produjo ninguna muestra"
            )
        }
    }

    /// La agenda se publica desde el hilo principal mientras el de audio lee.
    /// Las losas alternas son lo que impide que una lectura en vuelo vea una
    /// agenda a medio escribir.
    func testScheduleAlternatesSlabsBetweenPublications() {
        let schedule = VoiceSchedule()
        schedule.publish([1, 2, 3])
        let first = schedule.snapshot()
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.attacks[0], 1)

        schedule.publish([9])
        let second = schedule.snapshot()
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.attacks[0], 9)
        XCTAssertNotEqual(second.generation, first.generation)
        // La agenda anterior sigue intacta: quien la estuviera leyendo no ve
        // datos rotos a mitad de bloque.
        XCTAssertEqual(first.attacks[0], 1)
        XCTAssertNotEqual(UnsafeRawPointer(first.attacks), UnsafeRawPointer(second.attacks))
    }

    /// Los ataques llegan en el orden en que los produce el grafo, no ordenados.
    /// La búsqueda binaria del render da por hecho que están ordenados.
    func testScheduleSortsWhatItPublishes() {
        let schedule = VoiceSchedule()
        schedule.publish([3, 1, 2])
        let plan = schedule.snapshot()
        XCTAssertEqual([plan.attacks[0], plan.attacks[1], plan.attacks[2]], [1, 2, 3])
    }

    func testOneVoiceCanKeepTheWholeBoundedGraphSchedule() {
        let schedule = VoiceSchedule()
        schedule.publish((0..<512).map(Double.init))
        let plan = schedule.snapshot()

        XCTAssertEqual(plan.count, 512)
        XCTAssertEqual(plan.attacks[0], 0)
        XCTAssertEqual(plan.attacks[511], 511)
    }

    /// Ejecuta un bloque del callback real y devuelve las muestras producidas.
    private func render(
        _ renderer: SpatialVoiceRenderer,
        hostTime: UInt64,
        hostTimeValid: Bool
    ) -> [Float] {
        let count = Int(frameCount)
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: count)
        samples.initialize(repeating: 0, count: count)
        defer { samples.deallocate() }

        let bufferList = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(bufferList.unsafeMutablePointer) }
        bufferList[0] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: frameCount * UInt32(MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(samples)
        )

        var stamp = AudioTimeStamp()
        stamp.mHostTime = hostTime
        stamp.mFlags = hostTimeValid ? .hostTimeValid : AudioTimeStampFlags()

        var isSilence = ObjCBool(true)
        let status = withUnsafePointer(to: &stamp) { stampPointer in
            renderer.render(&isSilence, stampPointer, frameCount, bufferList.unsafeMutablePointer)
        }
        XCTAssertEqual(status, noErr)
        lastBlockWasMarkedSilent = isSilence.boolValue

        return Array(UnsafeBufferPointer(start: samples, count: count))
    }
}
