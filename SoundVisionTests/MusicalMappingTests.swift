import AVFAudio
import XCTest
@testable import SoundVision

/// La afinación es la diferencia entre "suena a prototipo" y "suena a música":
/// mientras la altura devolvía semitonos continuos, cualquier pieza quedaba
/// microtonal por muy buena que fuese la síntesis.
final class MusicalMappingTests: XCTestCase {
    func testEveryHeightLandsOnTheScale() {
        let scale = Set(SpatialParameterMapper.scaleSemitones)
        for step in 0...220 {
            let height = 0.35 + Float(step) * 0.01
            let pitch = SpatialParameterMapper.pitch(forHeight: height)

            XCTAssertEqual(pitch, pitch.rounded(), "El pitch debe caer en semitonos enteros")
            let pitchClass = ((Int(pitch) % 12) + 12) % 12
            XCTAssertTrue(
                scale.contains(pitchClass),
                "Altura \(height) produjo \(pitch), fuera de la pentatónica"
            )
        }
    }

    func testHeightStillRaisesAndLowersPitch() {
        XCTAssertGreaterThan(SpatialParameterMapper.pitch(forHeight: 1.8), 0)
        XCTAssertLessThan(SpatialParameterMapper.pitch(forHeight: 0.7), 0)
        XCTAssertEqual(SpatialParameterMapper.pitch(forHeight: SpatialParameterMapper.neutralHeight), 0)
    }

    /// Subir debe subir siempre: la cuantización no puede invertir el gesto.
    func testPitchNeverDecreasesAsHeightRises() {
        var previous = -Float.infinity
        for step in 0...200 {
            let pitch = SpatialParameterMapper.pitch(forHeight: 0.4 + Float(step) * 0.01)
            XCTAssertGreaterThanOrEqual(pitch, previous)
            previous = pitch
        }
    }

    func testDegreesWalkOctavesInBothDirections() {
        XCTAssertEqual(SpatialParameterMapper.semitones(forDegree: 0), 0)
        XCTAssertEqual(SpatialParameterMapper.semitones(forDegree: 5), 12)
        XCTAssertEqual(SpatialParameterMapper.semitones(forDegree: -5), -12)
        XCTAssertEqual(SpatialParameterMapper.semitones(forDegree: 1), 3)
        XCTAssertEqual(SpatialParameterMapper.semitones(forDegree: -1), -2)
    }

    // MARK: - Duración

    /// Lo que pidió el diseño: lejos sostiene, cerca queda staccato.
    func testDistanceStretchesTonalNotes() {
        let near = VoiceSynthesis.duration(for: .pad, sustainSeconds: 0.3)
        let far = VoiceSynthesis.duration(for: .pad, sustainSeconds: 3.0)
        XCTAssertGreaterThan(far, near)
    }

    /// Un golpe es un golpe: separarlo no lo convierte en un sonido sostenido.
    func testPercussionIgnoresDistance() {
        let near = VoiceSynthesis.duration(for: .kick, sustainSeconds: 0.3)
        let far = VoiceSynthesis.duration(for: .kick, sustainSeconds: 4.0)
        XCTAssertEqual(near, far)
    }

    func testSustainIsCappedForVeryDistantNodes() {
        XCTAssertLessThanOrEqual(
            VoiceSynthesis.duration(for: .pad, sustainSeconds: 60),
            VoiceSynthesis.maximumDuration
        )
    }

    // MARK: - Síntesis en tiempo real

    func testEveryInstrumentProducesSound() {
        for type in SoundNodeType.allCases {
            let output = AudioProbe.render(node: node(type), blocks: 12)
            XCTAssertTrue(output.contains { $0 != 0 }, "\(type) salió en silencio")
            XCTAssertTrue(
                output.allSatisfy { $0.isFinite && abs($0) <= 0.9 },
                "\(type) produjo muestras fuera de rango o no finitas"
            )
        }
    }

    /// Ninguna nota debe cortarse de golpe. Un percusivo *tiene* que entrar de
    /// golpe, así que solo los tonales suben por su envolvente de ataque.
    func testNotesEndSilentlyAndTonalOnesFadeIn() {
        for type in SoundNodeType.allCases {
            let output = AudioProbe.render(node: node(type), heldSeconds: 0.3, blocks: 90)
            XCTAssertLessThan(abs(output[output.count - 1]), 0.05, "\(type) corta de golpe")
            if !VoiceSynthesis.isPercussive(type) {
                XCTAssertLessThan(abs(output[0]), 0.05, "\(type) arranca con un salto")
            }
        }
    }

    func testHigherPitchProducesFasterOscillation() {
        let low = AudioProbe.render(node: node(.lead, pitch: -12), blocks: 20)
        let high = AudioProbe.render(node: node(.lead, pitch: 12), blocks: 20)
        XCTAssertGreaterThan(zeroCrossings(high), zeroCrossings(low))
    }

    // MARK: - Lo que justifica el motor en tiempo real

    /// El punto de todo el rediseño: mover un organismo mientras suena debe
    /// cambiar su altura ya, no en la siguiente reproducción. Con la síntesis
    /// horneada esto era imposible por construcción.
    func testMovingANodeChangesPitchWhileItIsStillSounding() {
        let renderer = AudioProbe.renderer(node: node(.pad, pitch: 0), heldSeconds: 4)
        let before = AudioProbe.drain(renderer, blocks: 24)

        var moved = node(.pad, pitch: 24)
        moved.positionY = 2.2
        renderer.parameters.update(from: moved, heldSeconds: 4)

        // Deja pasar el deslizamiento antes de medir el resultado.
        _ = AudioProbe.drain(renderer, blocks: 40)
        let after = AudioProbe.drain(renderer, blocks: 24)

        XCTAssertGreaterThan(
            zeroCrossings(after), zeroCrossings(before) * 2,
            "Subir dos octavas debe oírse de inmediato"
        )
    }

    /// Ese cambio tiene que deslizarse, no saltar: un salto de fase se oye como
    /// un chasquido en mitad de la nota.
    func testLivePitchChangeDoesNotClick() {
        let renderer = AudioProbe.renderer(node: node(.bass, pitch: 0), heldSeconds: 4)
        _ = AudioProbe.drain(renderer, blocks: 30)

        renderer.parameters.update(from: node(.bass, pitch: 24), heldSeconds: 4)
        let during = AudioProbe.drain(renderer, blocks: 20)

        let biggestJump = zip(during, during.dropFirst())
            .map { abs($1 - $0) }
            .max() ?? 0
        XCTAssertLessThan(biggestJump, 0.25, "La transición de altura produjo un salto audible")
    }

    func testLiveDistortionChangesTheWaveformWithoutBlowingUp() {
        let renderer = AudioProbe.renderer(node: node(.lead, pitch: 0), heldSeconds: 4)
        _ = AudioProbe.drain(renderer, blocks: 20)

        var distorted = node(.lead, pitch: 0)
        distorted.distortion = 1
        renderer.parameters.update(from: distorted, heldSeconds: 4)
        let after = AudioProbe.drain(renderer, blocks: 60)

        XCTAssertTrue(after.allSatisfy { $0.isFinite && abs($0) <= 0.9 })
        XCTAssertTrue(after.contains { $0 != 0 })
    }

    /// El hilo de audio no puede permitirse el coste de la versión horneada.
    func testRenderingIsFastEnoughForRealtime() {
        let renderer = AudioProbe.renderer(node: node(.pad, pitch: 0), heldSeconds: 4)
        let blocks = 400
        let start = Date()
        _ = AudioProbe.drain(renderer, blocks: blocks)
        let elapsed = Date().timeIntervalSince(start)

        // 400 bloques de 512 frames son ~4.3 s de audio: generarlos debe costar
        // una fracción mínima de ese tiempo.
        XCTAssertLessThan(elapsed, 1.0, "Sintetizar 4 s de audio tardó \(elapsed) s")
    }

    // MARK: - Utilidades

    private func node(_ type: SoundNodeType, pitch: Float = 0) -> SoundNode {
        SoundNode(name: "\(type)", type: type, pitch: pitch, positionX: 0, positionY: 1.25, positionZ: 0)
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        zip(samples, samples.dropFirst()).count { ($0 < 0) != ($1 < 0) }
    }
}

/// Ejecuta el callback de audio real, igual que lo haría RealityKit.
enum AudioProbe {
    static let frameCount: AUAudioFrameCount = 512

    static func renderer(
        node: SoundNode,
        heldSeconds: TimeInterval = 1,
        attacks: [UInt64]? = nil
    ) -> SpatialVoiceRenderer {
        SpatialVoiceRenderer(
            node: node,
            sustainSeconds: heldSeconds,
            attackHostTimes: attacks ?? [mach_absolute_time()]
        )
    }

    static func render(node: SoundNode, heldSeconds: TimeInterval = 1, blocks: Int) -> [Float] {
        drain(renderer(node: node, heldSeconds: heldSeconds), blocks: blocks)
    }

    /// Bloques consecutivos con el reloj interno del renderizador, que avanza
    /// exactamente un bloque cada vez: da una línea de tiempo determinista.
    static func drain(_ renderer: SpatialVoiceRenderer, blocks: Int) -> [Float] {
        var output: [Float] = []
        output.reserveCapacity(blocks * Int(frameCount))
        for _ in 0..<blocks {
            output.append(contentsOf: renderOneBlock(renderer))
        }
        return output
    }

    private static func renderOneBlock(_ renderer: SpatialVoiceRenderer) -> [Float] {
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

        // Sin host time válido: el renderizador usa su contador interno, que
        // avanza un bloque por llamada.
        var stamp = AudioTimeStamp()
        var isSilence = ObjCBool(true)
        _ = withUnsafePointer(to: &stamp) { stampPointer in
            renderer.render(&isSilence, stampPointer, frameCount, bufferList.unsafeMutablePointer)
        }
        return Array(UnsafeBufferPointer(start: samples, count: count))
    }
}
