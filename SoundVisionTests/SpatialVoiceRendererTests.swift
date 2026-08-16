import AVFAudio
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
