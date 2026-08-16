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

    func testBakedDurationIsCappedForVeryDistantNodes() {
        let duration = VoiceSynthesis.duration(for: .pad, sustainSeconds: 60)
        XCTAssertLessThanOrEqual(duration, VoiceSynthesis.maximumDuration)
    }

    // MARK: - Síntesis

    func testEveryInstrumentProducesSound() {
        for type in SoundNodeType.allCases {
            let node = SoundNode(name: "x", type: type, positionX: 0, positionY: 1.25, positionZ: 0)
            let samples = VoiceSynthesis.bake(node: node, sustainSeconds: 1, sampleRate: 48_000)
            XCTAssertFalse(samples.isEmpty, "\(type) no produjo muestras")
            XCTAssertTrue(samples.contains { $0 != 0 }, "\(type) salió en silencio")
            XCTAssertTrue(
                samples.allSatisfy { $0.isFinite && abs($0) <= 1.05 },
                "\(type) produjo muestras fuera de rango o no finitas"
            )
        }
    }

    /// Ninguna nota debe cortarse de golpe, o se oye un clic al final. El
    /// arranque es otra historia: un percusivo *tiene* que entrar de golpe, y
    /// solo los tonales suben por su envolvente de ataque.
    func testNotesEndSilentlyAndTonalOnesFadeIn() {
        for type in SoundNodeType.allCases {
            let node = SoundNode(name: "x", type: type, positionX: 0, positionY: 1.25, positionZ: 0)
            let samples = VoiceSynthesis.bake(node: node, sustainSeconds: 0.8, sampleRate: 48_000)

            XCTAssertLessThan(abs(samples[samples.count - 1]), 0.05, "\(type) corta de golpe")
            if !VoiceSynthesis.isPercussive(type) {
                XCTAssertLessThan(abs(samples[0]), 0.05, "\(type) arranca con un salto")
            }
        }
    }

    func testHigherPitchProducesFasterOscillation() {
        let low = SoundNode(name: "low", type: .lead, pitch: -12, positionX: 0, positionY: 1.25, positionZ: 0)
        let high = SoundNode(name: "high", type: .lead, pitch: 12, positionX: 0, positionY: 1.25, positionZ: 0)

        XCTAssertGreaterThan(
            zeroCrossings(VoiceSynthesis.bake(node: high, sustainSeconds: 0.5, sampleRate: 48_000)),
            zeroCrossings(VoiceSynthesis.bake(node: low, sustainSeconds: 0.5, sampleRate: 48_000))
        )
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        zip(samples, samples.dropFirst()).count { ($0 < 0) != ($1 < 0) }
    }
}
