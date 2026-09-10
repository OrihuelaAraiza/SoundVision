import AVFAudio
import Foundation
import simd

@MainActor
func runQualityChecks() async throws {
    let state = CompositionState()
    let id = state.createNode(of: .pad)
    let original = state.snapshot
    state.beginParameterEdit("Mover sonido")
    state.moveNode(id: id, to: [0.3, 1.5, 0.1])
    state.moveNode(id: id, to: [0.6, 1.8, 0.2])
    state.endParameterEdit()
    let moved = state.snapshot
    state.undo()
    check(state.snapshot == original, "Move undo destroyed the node or lost spatial timing")
    state.redo()
    check(state.snapshot == moved, "Redo did not restore the entire gesture")
    let lastLabel = state.undoLabel
    state.beginParameterEdit()
    state.endParameterEdit()
    check(state.undoLabel == lastLabel, "An untouched control consumed history")
    state.undo()
    state.toggleNode(id: id)
    check(!state.canRedo, "A new edit retained stale redo")
    state.undo()
    check(state.node(id: id)?.isActive == true, "Mute is not undoable")
    state.toggleSoundLock(id: id)
    state.undo()
    check(state.node(id: id)?.isSoundLocked == false, "Sound lock is not undoable")
    state.setTempo(144)
    state.undo()
    check(state.sequencer.bpm == original.bpm, "Tempo undo failed")
    state.setLoopPasses(6)
    state.undo()
    check(state.graphTransport.loopPasses == original.loopPasses, "Cycle undo failed")
    state.togglePlayback()
    let sessionID = state.spatialAudioSession?.id
    state.beginParameterEdit("Girar sonido")
    state.rotateNode(id: id, addingTo: .zero, delta: [0.2, 0.4, 0.6])
    state.rotateNode(id: id, addingTo: .zero, delta: [0.4, 0.6, 0.8])
    state.endParameterEdit()
    state.undo()
    state.redo()
    check(state.graphTransport.isPlaying && state.spatialAudioSession?.id == sessionID, "History restarted live sound")
    state.setTempo(155)
    check(state.sequencer.bpm == original.bpm, "Tempo changed while playing")
    state.stopPlayback()
    print("PASS quality history: grouped move/rotation, no-op, redo invalidation, mute, lock, tempo, cycles, live session")

    for type in [SoundNodeType.pad, .kick, .fx] {
        let crowded = CompositionState()
        for _ in 0..<32 { crowded.createNode(of: type) }
        for (index, node) in crowded.nodes.enumerated() {
            for other in crowded.nodes.dropFirst(index + 1) {
                let gap = simd_distance(SIMD3(node.positionX, node.positionY, node.positionZ),
                    SIMD3(other.positionX, other.positionY, other.positionZ))
                    - SpatialNodePlacement.radius(for: node.type) - SpatialNodePlacement.radius(for: other.type)
                check(gap >= 0.079, "Overlapping automatic placement: \(type), gap \(gap)")
            }
        }
        crowded.focusNode(id: crowded.nodes[8].id)
        crowded.deleteSelectedNode()
        crowded.createNode(of: .organ)
        let newNode = crowded.nodes.last!
        check(crowded.nodes.dropLast().allSatisfy {
            simd_distance(SIMD3($0.positionX, $0.positionY, $0.positionZ), SIMD3(newNode.positionX, newNode.positionY, newNode.positionZ))
                >= SpatialNodePlacement.radius(for: $0.type) + SpatialNodePlacement.radius(for: newNode.type) + 0.079
        }, "Replacement node overlaps a survivor")
    }
    print("PASS quality placement: 32 large bodies, deletion, refill, bounded coordinates")

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("soundvision-quality-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = CompositionStorage(customURL: folder.appendingPathComponent("composition.json"))
    let recoveryStore = try storage.recoveryStorage()
    let persistent = CompositionState(storage: storage, enableRecovery: true)
    let ownID = persistent.createNode(of: .bass)
    persistent.save()
    let manual = try storage.load()
    persistent.setSoundParameter(id: ownID, parameter: .delay, value: 0.7)
    let ownComposition = persistent.snapshot
    persistent.beginLesson(.melody)
    let practiceID = persistent.nodes[1].id
    persistent.setPitch(id: practiceID, semitones: 3)
    persistent.flushRecovery()
    let restored = CompositionState(storage: storage, enableRecovery: true)
    check(restored.recoveryAvailable && restored.nodes.isEmpty, "Recovery must be offered, not silently applied")
    restored.restoreRecoveredSession()
    check(restored.activeLesson == .melody && restored.node(id: practiceID)?.pitch == 3, "Practice recovery lost edits")
    restored.finishLesson()
    check(restored.snapshot == ownComposition, "Practice recovery lost original composition")
    let afterPracticeManual = try storage.load()
    check(afterPracticeManual == manual, "Automatic recovery overwrote manual save")
    restored.undo()
    check(restored.node(id: ownID)?.delay == manual.nodes[0].delay, "Recovered original history failed")

    restored.beginParameterEdit("Mover sonido")
    let beforeInterruptedDrag = restored.snapshot
    restored.moveNode(id: ownID, to: [1, 1.8, -0.7])
    restored.flushRecovery() // Simulate process termination before gesture-end.
    let interrupted = CompositionState(storage: storage, enableRecovery: true)
    interrupted.restoreRecoveredSession()
    interrupted.undo()
    check(interrupted.snapshot == beforeInterruptedDrag, "Recovered gesture was not sealed into one undo")
    interrupted.removeConnection(id: interrupted.connections[0].id)
    interrupted.flushRecovery()
    let rootless = CompositionState(storage: storage, enableRecovery: true)
    rootless.restoreRecoveredSession()
    check(rootless.playEntryNodeID == nil, "Recovery invented a Play entry")
    let previous = recoveryStore.load()!
    rootless.setTempo(150)
    rootless.flushRecovery()
    try Data("{incomplete".utf8).write(to: recoveryStore.url)
    check(recoveryStore.load()?.current == previous.current, "Corrupt current file did not fall back to known-good backup")
    try Data("invalid".utf8).write(to: recoveryStore.backupURL)
    check(recoveryStore.load() == nil, "Two corrupt files were accepted")
    let afterCorruptionManual = try storage.load()
    check(afterCorruptionManual == manual, "Corruption touched manual save")

    let debouncedStorage = CompositionStorage(customURL: folder.appendingPathComponent("debounced.json"))
    let debounced = CompositionState(storage: debouncedStorage, enableRecovery: true)
    debounced.createNode(of: .tom)
    try await Task.sleep(for: .milliseconds(1200))
    let autoSaved = try debouncedStorage.recoveryStorage().load()
    check(autoSaved?.current.nodes.count == 1, "One-second autosave did not run")
    check(debounced.recoveryProblem == nil, "Autosave reported an error")
    print("PASS quality recovery: debounce, lesson and original history, interrupted gesture, rootless graph, corrupt-file fallback, manual-save isolation")

    var silentNode = SoundNode(name: "Zero", type: .organ, volume: 0, positionX: 0, positionY: 1.25, positionZ: 0)
    let renderer = SpatialVoiceRenderer(node: silentNode, sustainSeconds: 0.5)
    let start = PlaybackClock.now
    renderer.schedule.publish([start], loopStart: start, repeatingEvery: 0.6)
    let generation = renderer.schedule.snapshot().generation
    var audibleAfterRaise: Float = 0
    for block in 0..<280 {
        if block == 60 { silentNode.volume = 0.8; renderer.parameters.update(from: silentNode, heldSeconds: 0.5) }
        if block == 140 { silentNode.volume = 0; renderer.parameters.update(from: silentNode, heldSeconds: 0.5) }
        if block == 210 { silentNode.volume = 0.8; silentNode.isActive = false; renderer.parameters.update(from: silentNode, heldSeconds: 0.5) }
        let output = render(renderer, at: start + Double(block * 512) / 48_000)
        check(output.allSatisfy(\.isFinite), "Volume ramp generated invalid samples")
        let peak = output.map(abs).max() ?? 0
        if block < 60 || (block > 150 && block < 210) { check(peak == 0, "Volume zero left a nonzero signal") }
        if block >= 65 && block < 140 { audibleAfterRaise = max(audibleAfterRaise, peak) }
        if block > 225 { check(peak < 0.00001, "Mute was coupled to volume") }
    }
    check(audibleAfterRaise > 0.001, "Raising zero volume did not recover sound")
    check(renderer.schedule.snapshot().generation == generation, "Volume editing replaced the audio schedule")
    let idleNode = SoundNode(name: "Idle", type: .organ, volume: 0.8, positionX: 0, positionY: 1.25, positionZ: 0)
    let idleVoice = SpatialVoiceRenderer(node: idleNode)
    var zeroBeforePlay = idleNode
    zeroBeforePlay.volume = 0
    idleVoice.parameters.update(from: zeroBeforePlay, heldSeconds: 0.5)
    _ = render(idleVoice, at: start)
    idleVoice.schedule.publish([start + 0.1])
    check(render(idleVoice, at: start + 0.15).allSatisfy { $0 == 0 }, "Setting zero before Play left an attack transient")
    print("PASS quality volume: exact zero, smooth restoration over repeated loops, independent mute, unchanged schedule")

    let attacks = CompositionState()
    let a = attacks.createNode(of: .tom)
    let b = attacks.createNode(of: .bell)
    attacks.connect(sourceID: a, destinationID: b)
    attacks.connect(sourceID: b, destinationID: a)
    for edge in attacks.connections where edge.sourceNodeID != nil { attacks.setConnectionBeats(id: edge.id, beats: 0.25) }
    attacks.setTempo(180)
    attacks.setLoopPasses(1)
    var emitted: [UUID] = []
    attacks.onVisualAttack = { emitted.append($0) }
    var effective: TimeInterval = 0
    attacks.scheduleAudio = { session in
        effective = PlaybackClock.effectiveStart(requested: PlaybackClock.now - 1, now: PlaybackClock.now + 0.1)
        return effective
    }
    attacks.togglePlayback()
    check(attacks.graphTransport.effectiveStartSeconds == effective, "Visual transport ignored the engine's effective start")
    try await Task.sleep(for: .milliseconds(400))
    attacks.stopPlayback()
    check(Array(emitted.prefix(3)) == [a, b, a], "Fast repeated attacks collapsed or changed order")
    print("PASS quality timing: shared delayed start, two distinct visual attacks below 280 ms")

    let routes = CompositionState()
    let entry = routes.createNode(of: .kick)
    let free = routes.createNode(of: .pad)
    let proposal = routes.connectionProposal(from: .node(free), to: .node(entry))
    check(proposal.sourceID == entry && proposal.destinationID == free && proposal.isValid, "Preview direction differs from gesture")
    routes.connectByDragging(from: .node(free), to: .node(entry))
    check(!routes.connectionProposal(from: .node(entry), to: .node(free)).isValid, "Duplicate preview accepted")
    check(!routes.connectionProposal(from: .node(free), to: .play).isValid, "Occupied Play preview accepted")
    check(routes.onboardingProgress == 2, "Guide did not observe actual connection")
    routes.togglePlayback()
    check(routes.onboardingProgress == 3, "Guide did not observe playback")
    routes.stopPlayback()
    let melody = MusicLesson.melody.composition()
    let issues = MusicLesson.melody.feedback(for: melody)
    check(issues.contains { $0.nodeID == melody.nodes[1].id && $0.message.contains("3 semitonos") }, "Lesson feedback did not locate wrong pitch")
    print("PASS quality guidance: effective connection direction, rejected endpoints, action-based onboarding, specific lesson feedback")
}
