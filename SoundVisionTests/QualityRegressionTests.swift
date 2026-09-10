import RealityKit
import XCTest
@testable import SoundVision

@MainActor
final class QualityRegressionTests: XCTestCase {
    func testOneGestureHasOneUndoAndRedoPreservesNodeIdentity() {
        let state = CompositionState()
        let id = state.createNode(of: .pad)
        let original = state.snapshot
        state.beginParameterEdit("Mover sonido")
        state.moveNode(id: id, to: [0.2, 1.6, 0.1])
        state.moveNode(id: id, to: [0.4, 1.8, 0.2])
        state.endParameterEdit()
        let edited = state.snapshot
        state.undo()
        XCTAssertEqual(state.snapshot, original)
        state.redo()
        XCTAssertEqual(state.snapshot, edited)
        state.beginParameterEdit()
        state.endParameterEdit()
        state.undo()
        XCTAssertEqual(state.snapshot, original, "Touching without editing must not consume history")
    }

    func testReturningToTheOriginalValueDoesNotConsumeUndoOrRedo() {
        let state = CompositionState()
        let id = state.createNode(of: .pad)
        state.setPitch(id: id, semitones: 7)
        state.undo()
        let before = state.node(id: id)!.volume
        state.beginParameterEdit()
        state.setSoundParameter(id: id, parameter: .volume, value: 0.2)
        state.setSoundParameter(id: id, parameter: .volume, value: before)
        state.endParameterEdit()
        XCTAssertTrue(state.canRedo)
        state.redo()
        XCTAssertEqual(state.node(id: id)?.pitch, 7)
    }

    func testDistinctAttacksCreateDistinctWaveSlotsWhileStillHighlighted() throws {
        let entity = Entity()
        VisualAttackFeedback.emit(on: entity, at: 1)
        VisualAttackFeedback.emit(on: entity, at: 1.08)
        let attacks = try XCTUnwrap(entity.components[VisualAttackComponent.self])
        XCTAssertEqual(attacks.sequence, 2)
        XCTAssertEqual(attacks.birthTimes[0], 1)
        XCTAssertEqual(attacks.birthTimes[1], 1.08)
    }

    func testMutedGraphKeepsConnectionDirectionAndContextualTiming() throws {
        let root = Entity()
        root.addChild(ConnectionLineSystem.makeContainer())
        let a = SoundNode(name: "A", type: .kick, positionX: -1, positionY: 1.25, positionZ: 0)
        let b = SoundNode(name: "B", type: .pad, isActive: false, positionX: 1, positionY: 1.25, positionZ: 0)
        let edge = SoundConnection(sourceNodeID: a.id, destinationNodeID: b.id, durationBeats: 2, usesSpatialTiming: false)
        ConnectionLineSystem.synchronize(in: root, nodes: [a, b], connections: [edge], triggeredIDs: [], selectedNodeID: a.id)
        let line = try XCTUnwrap(root.findEntity(named: ConnectionLineSystem.prefix + edge.id.uuidString))
        XCTAssertTrue(line.isEnabled)
        XCTAssertTrue(try XCTUnwrap(line.components[ConnectionLineComponent.self]).isMuted)
        let marker = try XCTUnwrap(root.findEntity(named: "marker-" + edge.id.uuidString))
        XCTAssertNotNil(marker.findEntity(named: "direction"))
        XCTAssertTrue(try XCTUnwrap(marker.findEntity(named: "timing")).isEnabled)
        ConnectionLineSystem.synchronize(in: root, nodes: [a, b], connections: [edge], triggeredIDs: [], selectedNodeID: b.id)
        XCTAssertFalse(try XCTUnwrap(marker.findEntity(named: "timing")).isEnabled)
        XCTAssertTrue(line.isEnabled)
    }

    func testReduceMotionKeepsSelectedBodyStillAndHidesDecorativeMotion() throws {
        let node = SoundNode(name: "Pad", type: .pad, positionX: 0, positionY: 1.25, positionZ: 0)
        let body = NodeEntityFactory.makeNode(node)
        VisualAttackFeedback.emit(on: body, at: 1)
        let reduced = SoundNodeVisualComponent(node: node, isSelected: true, isTriggered: true, reduceMotion: true)
        NodeAnimationSystem.apply(to: body, node: reduced, time: 1.05)
        let transform = body.transform
        NodeAnimationSystem.apply(to: body, node: reduced, time: 1.4)
        XCTAssertEqual(body.transform, transform)
        let parts = try XCTUnwrap(body.components[NodePartsComponent.self])
        XCTAssertTrue(try XCTUnwrap(parts.halo).isEnabled)
        XCTAssertTrue(parts.waves.allSatisfy { !$0.isEnabled })
        XCTAssertFalse(try XCTUnwrap(body.findEntity(named: ParticleEffectSystem.nodeEmitterName)).isEnabled)
        var normal = reduced
        normal.reduceMotion = false
        NodeAnimationSystem.apply(to: body, node: normal, time: 1.45)
        XCTAssertTrue(try XCTUnwrap(body.findEntity(named: ParticleEffectSystem.nodeEmitterName)).isEnabled)
    }

    func testPlacementBoundsContainEveryAnimatedBody() {
        for type in SoundNodeType.allCases {
            let node = SoundNode(name: "Test", type: type, positionX: 0, positionY: 0, positionZ: 0)
            let body = NodeEntityFactory.makeNode(node)
            let style = NodeVisualStyle.style(for: type)
            for child in body.children where child.components[InputTargetComponent.self] != nil
                && child.name != NodeEntityFactory.connectorName {
                let bounds = child.visualBounds(relativeTo: body)
                // Corners bound every possible user rotation; decoration waves are excluded.
                for x in [bounds.min.x, bounds.max.x] {
                    for y in [bounds.min.y, bounds.max.y] {
                        for z in [bounds.min.z, bounds.max.z] {
                            let localReach: Float
                            if type == .pad || type == .strings || (type == .kick && child.name == "node-core") {
                                localReach = simd_length(bounds.center) + bounds.extents.x / 2
                            } else if type == .kick && child.name == "accent" {
                                localReach = sqrt(pow(bounds.extents.x / 2, 2) + pow(max(abs(bounds.min.y), abs(bounds.max.y)), 2))
                            } else { localReach = simd_length(SIMD3(x, y, z)) }
                            let reach = localReach * max(style.baseScale, style.triggerScale)
                                + abs(style.verticalOffset) + style.idleAmplitude
                            XCTAssertLessThanOrEqual(reach, SpatialNodePlacement.radius(for: type), "\(type): \(child.name)")
                        }
                    }
                }
            }
        }
    }

    func testRecoveryRestoresLessonAndOriginalWithoutChangingManualSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = CompositionStorage(customURL: folder.appendingPathComponent("composition.json"))
        let state = CompositionState(storage: storage, enableRecovery: true)
        state.createNode(of: .bass)
        state.save()
        let original = state.snapshot
        state.beginLesson(.harmony)
        let recovered = CompositionState(storage: storage, enableRecovery: true)
        XCTAssertTrue(recovered.recoveryAvailable)
        recovered.restoreRecoveredSession()
        XCTAssertEqual(recovered.activeLesson, .harmony)
        recovered.finishLesson()
        XCTAssertEqual(recovered.snapshot, original)
        XCTAssertEqual(try storage.load(), original)
    }

    func testLessonExplainsWhichPitchNeedsChanging() {
        let scene = MusicLesson.melody.composition()
        let result = MusicLesson.melody.feedback(for: scene)
        XCTAssertTrue(result.contains { $0.nodeID == scene.nodes[1].id && $0.message.contains("3 semitonos") })
        XCTAssertTrue(result.contains { $0.nodeID == scene.nodes[2].id && $0.message.contains("7 semitonos") })
    }
}
