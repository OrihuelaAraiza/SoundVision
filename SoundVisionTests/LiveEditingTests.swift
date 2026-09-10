import Combine
import XCTest
@testable import SoundVision

@MainActor
final class LiveEditingTests: XCTestCase {
    func testMovingRotatingAndMixingKeepTheSamePlaybackSession() throws {
        let state = CompositionState()
        let a = state.createNode(of: .electricPiano, at: [0, 1.25, 0])
        let b = state.createNode(of: .flute, at: [0.5, 1.25, 0])
        state.connect(sourceID: a, destinationID: b)
        state.togglePlayback()
        let session = try XCTUnwrap(state.spatialAudioSession)
        state.moveNode(id: a, to: [-0.6, 1.8, 0.5])
        state.rotateNode(id: a, addingTo: .zero, delta: [.pi / 3, .pi / 2, .pi / 4])
        state.setPitch(id: a, semitones: 7)
        state.beginParameterEdit()
        state.setSoundParameter(id: a, parameter: .volume, value: 0.4)
        state.setSoundParameter(id: a, parameter: .reverb, value: 0.8)
        state.setSoundParameter(id: a, parameter: .delay, value: 0.3)
        state.setSoundParameter(id: a, parameter: .distortion, value: 0.2)
        let node = try XCTUnwrap(state.node(id: a))
        XCTAssertEqual(node.pitch, 7)
        XCTAssertEqual(node.volume, 0.4)
        XCTAssertEqual(node.reverb, 0.8)
        XCTAssertEqual(node.delay, 0.3)
        XCTAssertEqual(node.distortion, 0.2)
        XCTAssertFalse(node.isSoundLocked, "Afinar no debe bloquear los gestos por sorpresa")
        XCTAssertTrue(state.graphTransport.isPlaying)
        XCTAssertEqual(state.spatialAudioSession?.id, session.id)
        XCTAssertEqual(state.spatialAudioSession?.events, session.events, "El pulso en curso no debe saltar")
        XCTAssertTrue(state.hasPendingTimingChanges)
        state.undo()
        XCTAssertTrue(state.graphTransport.isPlaying, "Deshacer un ajuste sonoro tampoco corta Play")
        state.createNode(of: .strings)
        XCTAssertTrue(state.graphTransport.isPlaying, "Añadir un nodo libre no debe cortar la pista")
        XCTAssertEqual(state.spatialAudioSession?.id, session.id)
        state.stopPlayback()
        XCTAssertFalse(state.hasPendingTimingChanges)
        state.togglePlayback()
        XCTAssertNotEqual(state.spatialAudioSession?.events, session.events, "El siguiente Play incorpora los tiempos nuevos")
        state.stopPlayback()
    }

    func testMoveAndRotatePublishCoherentNodes() {
        let state = CompositionState()
        let id = state.createNode(of: .strings)
        var snapshots: [[SoundNode]] = []
        let observation = state.$nodes.dropFirst().sink { snapshots.append($0) }
        state.rotateNode(id: id, addingTo: .zero, delta: [.pi / 2, .pi / 2, .pi / 2])
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.first?.reverb, 0.5)
        XCTAssertEqual(snapshots.first?.first?.delay, 0.5)
        XCTAssertEqual(snapshots.first?.first?.distortion, 0.5)
        withExtendedLifetime(observation) {}
    }

    func testLockOnlyPreventsSpatialRemapping() throws {
        let state = CompositionState()
        let id = state.createNode(of: .brass)
        state.toggleSoundLock(id: id)
        state.togglePlayback()
        let pitch = try XCTUnwrap(state.node(id: id)).pitch
        state.moveNode(id: id, to: [1, 2, 1])
        XCTAssertEqual(state.node(id: id)?.pitch, pitch)
        state.setPitch(id: id, semitones: 12)
        state.setSoundParameter(id: id, parameter: .delay, value: 0.7)
        XCTAssertEqual(state.node(id: id)?.pitch, 12)
        XCTAssertEqual(state.node(id: id)?.delay, 0.7)
        XCTAssertTrue(state.graphTransport.isPlaying)
        state.stopPlayback()
    }
}
