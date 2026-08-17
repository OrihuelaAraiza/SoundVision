import RealityKit
import XCTest
@testable import SoundVision

/// La onda tiene que *propagarse*: crecer y desvanecerse. Una esfera que
/// aparece y desaparece de golpe se lee como un parpadeo, no como sonido
/// emitido, que era el problema de la versión anterior.
@MainActor
final class VisualFeedbackTests: XCTestCase {
    private let style = NodeVisualStyle.style(for: .pad)

    func testWaveGrowsAndFadesOverItsLife() throws {
        let root = makeRootWithWaves()
        let birth = SIMD4<Double>(0, -.infinity, -.infinity, -.infinity)

        WaveformVisualizer.update(in: root, style: style, birthTimes: birth, time: 0.05)
        let early = try firstWave(in: root)
        let earlyScale = early.scale.x
        let earlyOpacity = try XCTUnwrap(early.components[OpacityComponent.self]?.opacity)
        XCTAssertTrue(early.isEnabled)

        WaveformVisualizer.update(in: root, style: style, birthTimes: birth, time: 0.5)
        let late = try firstWave(in: root)
        let lateScale = late.scale.x
        let lateOpacity = try XCTUnwrap(late.components[OpacityComponent.self]?.opacity)

        XCTAssertGreaterThan(lateScale, earlyScale, "La onda debe expandirse")
        XCTAssertLessThan(lateOpacity, earlyOpacity, "La onda debe desvanecerse")
    }

    func testWaveDisappearsAfterItsLifetime() throws {
        let root = makeRootWithWaves()
        let birth = SIMD4<Double>(0, -.infinity, -.infinity, -.infinity)

        WaveformVisualizer.update(in: root, style: style, birthTimes: birth, time: 0.3)
        XCTAssertTrue(try firstWave(in: root).isEnabled)

        WaveformVisualizer.update(
            in: root,
            style: style,
            birthTimes: birth,
            time: WaveformVisualizer.lifetime + 0.1
        )
        XCTAssertFalse(try firstWave(in: root).isEnabled, "La onda debe apagarse al agotarse")
    }

    /// Un pasaje rápido lanza varias ondas: deben poder convivir.
    func testSeveralWavesCanBeAliveAtOnce() throws {
        let root = makeRootWithWaves()
        let now: Double = 1.0
        let birth = SIMD4<Double>(now, now - 0.1, now - 0.2, -.infinity)

        WaveformVisualizer.update(in: root, style: style, birthTimes: birth, time: now)

        let enabled = (0..<WaveformVisualizer.concurrentWaves).filter {
            root.findEntity(named: WaveformVisualizer.name(at: $0))?.isEnabled == true
        }
        XCTAssertEqual(enabled.count, 3)
    }

    func testUnbornWavesStayHidden() throws {
        let root = makeRootWithWaves()
        WaveformVisualizer.update(
            in: root,
            style: style,
            birthTimes: SIMD4<Double>(repeating: -.infinity),
            time: 5
        )
        for index in 0..<WaveformVisualizer.concurrentWaves {
            XCTAssertFalse(root.findEntity(named: WaveformVisualizer.name(at: index))?.isEnabled ?? true)
        }
    }

    /// Ocho etiquetas visibles a la vez llenaban el espacio de texto que nadie
    /// leía: solo el organismo seleccionado enseña la suya.
    func testReadoutStartsHidden() throws {
        let node = SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0)
        let entity = NodeEntityFactory.makeNode(node)

        let readouts = entity.children.filter { $0.name.hasPrefix("node-readout-") }
        XCTAssertFalse(readouts.isEmpty, "El organismo debe traer su etiqueta")
        XCTAssertTrue(readouts.allSatisfy { !$0.isEnabled })
    }

    // MARK: - Utilidades

    private func makeRootWithWaves() -> Entity {
        let root = Entity()
        WaveformVisualizer.makeWaves(for: .pad).forEach { root.addChild($0) }
        return root
    }

    private func firstWave(in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: WaveformVisualizer.name(at: 0)))
    }
}
