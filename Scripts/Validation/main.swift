import AVFAudio
import Foundation
import RealityKit

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

// Usa el callback real de producción, sin abrir el motor de RealityKit.
func render(_ voice: SpatialVoiceRenderer, at seconds: Double) -> [Float] {
    let count = 512
    let samples = UnsafeMutablePointer<Float>.allocate(capacity: count)
    samples.initialize(repeating: 0, count: count)
    defer { samples.deallocate() }
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1,
        mDataByteSize: UInt32(count * MemoryLayout<Float>.size), mData: samples))
    var timestamp = AudioTimeStamp()
    timestamp.mHostTime = AVAudioTime.hostTime(forSeconds: seconds)
    timestamp.mFlags = .hostTimeValid
    var silent: ObjCBool = false
    _ = withUnsafeMutablePointer(to: &list) { buffers in
        withUnsafePointer(to: &timestamp) { time in
            voice.render(&silent, time, AUAudioFrameCount(count), buffers)
        }
    }
    return Array(UnsafeBufferPointer(start: samples, count: count))
}

for type in SoundNodeType.allCases {
    let node = SoundNode(name: type.rawValue, type: type, positionX: 0, positionY: 1.25, positionZ: 0)
    let voice = SpatialVoiceRenderer(node: node, sustainSeconds: 0.3)
    let start = AVAudioTime.seconds(forHostTime: mach_absolute_time())
    voice.schedule.publish([start], loopStart: start, repeatingEvery: 1)
    var firstPeak: Float = 0
    var secondPeak: Float = 0
    for block in 0..<110 {
        let time = start + Double(block * 512) / 48_000
        let output = render(voice, at: time)
        check(output.allSatisfy(\.isFinite), "Non-finite output: \(type)")
        let peak = output.map(abs).max() ?? 0
        check(peak <= 1, "Unbounded output: \(type)")
        if block < 30 { firstPeak = max(firstPeak, peak) }
        if block >= 94 { secondPeak = max(secondPeak, peak) }
    }
    check(firstPeak > 0.0001 && secondPeak > 0.0001, "Missing initial/repeated attack: \(type)")
    let stop = start + Double(110 * 512) / 48_000
    voice.schedule.stop(at: stop)
    _ = render(voice, at: stop)
    let tail = render(voice, at: stop + 0.1)
    check(tail.allSatisfy { abs($0) < 0.0001 }, "Stop left audio: \(type)")
    print("PASS renderer \(type.rawValue): first pass, repeated pass, finite samples, Stop")
}

for lesson in MusicLesson.allCases {
    var composition = lesson.composition()
    check(!lesson.isComplete(composition), "Lesson starts completed")
    switch lesson {
    case .pulse, .harmony:
        for index in composition.connections.indices where composition.connections[index].sourceNodeID != nil {
            composition.connections[index].durationBeats = 1
        }
    case .melody:
        composition.nodes[1].pitch = 3
        composition.nodes[2].pitch = 7
    case .branches:
        let initial = GraphSchedule.makePlan(nodes: composition.nodes, connections: composition.connections, loopPasses: 1)
        check(initial.events.filter { $0.nodeID == composition.nodes[3].id }.map(\.beat) == [2], "Convergence doubled")
        composition.connections[4].durationBeats = 2
    }
    check(lesson.isComplete(composition), "Correct exercise rejected: \(lesson)")
    let restored = try JSONDecoder().decode(Composition.self, from: JSONEncoder().encode(composition))
    check(restored == composition, "Persistence changed composition")
    composition.nodes[composition.nodes.count - 1].isActive = false
    check(!lesson.isComplete(composition), "Muted exercise accepted")
    print("PASS lesson \(lesson.rawValue): challenge, solution, muted result, persistence")
}

let first = SoundNode(name: "Root", type: .tom, positionX: 0, positionY: 1.25, positionZ: 0)
var nodes = [first]
var edges = [SoundConnection(sourceNodeID: nil, destinationNodeID: first.id)]
var last = first
for level in 0..<9 {
    let group = (0..<3).map { SoundNode(name: "\(level)-\($0)", type: .bell, positionX: 0, positionY: 1.25, positionZ: 0) }
    nodes += group
    edges += [(last, group[0]), (last, group[1]), (group[0], group[2]), (group[1], group[2])].map {
        SoundConnection(sourceNodeID: $0.0.id, destinationNodeID: $0.1.id)
    }
    last = group[2]
}
let before = Date()
let plan = GraphSchedule.makePlan(nodes: nodes, connections: edges, loopPasses: 1, maximumEvents: nodes.count)
check(!plan.isTruncated && plan.events.count == nodes.count, "Convergences consumed unique event budget")
check(plan.events.last?.nodeID == last.id && plan.events.last?.beat == 18, "Lost final branch")
let reversed = GraphSchedule.makePlan(nodes: nodes, connections: edges.reversed(), loopPasses: 1)
check(reversed.events == plan.events, "Unstable ordering")
let truncated = GraphSchedule.makePlan(nodes: nodes, connections: edges, loopPasses: 1, maximumEvents: 2)
check(truncated.isTruncated && truncated.events.count == 2, "Overflow was hidden")
print("PASS dense graph: \(nodes.count) unique attacks, deterministic order, overflow reported (\(Date().timeIntervalSince(before)) s)")

let cycle = [SoundConnection(sourceNodeID: nil, destinationNodeID: nodes[0].id),
             SoundConnection(sourceNodeID: nodes[0].id, destinationNodeID: nodes[1].id),
             SoundConnection(sourceNodeID: nodes[1].id, destinationNodeID: nodes[0].id)]
check(GraphSchedule.makePlan(nodes: nodes, connections: cycle, loopPasses: 2).events.map(\.beat) == [0, 1, 2, 3, 4], "Cycle regression")
print("PASS bounded cycles")

MainActor.assumeIsolated {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    let state = CompositionState(storage: CompositionStorage(customURL: url))
    let source = state.createNode(of: .pluck)
    let destination = state.createNode(of: .bell)
    check(state.connect(sourceID: source, destinationID: destination), "Connection rejected")
    let edge = state.connections.last!
    state.setConnectionBeats(id: edge.id, beats: 0.5)
    state.moveNode(id: destination, to: [2, 2, -1])
    check(state.connections.last?.durationBeats == 0.5, "Moving changed fixed timing")
    state.sequencer.bpm = 135
    state.graphTransport.loopPasses = 5
    state.save()
    state.load()
    check(state.connections.last?.durationBeats == 0.5 && state.connections.last?.usesSpatialTiming == false, "Loading changed timing")
    check(state.graphTransport.loopPasses == 5, "Lost cycle count")
    state.focusNode(id: destination)
    let original = state.snapshot
    let undoLabel = state.undoLabel
    state.beginLesson(.melody)
    state.beginLesson(.harmony)
    state.finishLesson()
    check(state.snapshot == original && state.selectedNodeID == destination, "Practice lost composition")
    check(state.undoLabel == undoLabel, "Practice lost undo history")
    state.setConnectionBeats(id: edge.id, beats: 2)
    state.undo()
    check(state.connections.last?.durationBeats == 0.5, "Undo lost fixed time")
    state.togglePlayback()
    check(state.graphTransport.isPlaying, "Play did not start")
    state.setConnectionBeats(id: edge.id, beats: 1)
    check(state.graphTransport.isPlaying && state.spatialAudioSession != nil && state.hasPendingTimingChanges, "Timing edit interrupted playback")
    state.startNewComposition()
    for _ in 0..<35 { state.createNode(of: .tom) }
    check(state.nodes.count == 32, "Voice limit not enforced")
    print("PASS state: fixed timing, save/load, lesson restoration, undo, playback edits, 32-voice limit")
}

let lowBass = SoundNode(name: "Low", type: .bass, pitch: -24, positionX: 0, positionY: 1.25, positionZ: 0)
check(SpatialParameterMapper.noteName(for: lowBass) == "La-1", "Incorrect bass register")
print("PASS note register at lowest supported pitch")

MainActor.assumeIsolated {
    let state = CompositionState()
    let a = state.createNode(of: .electricPiano, at: [0, 1.25, 0])
    let b = state.createNode(of: .flute, at: [0.5, 1.25, 0])
    state.connect(sourceID: a, destinationID: b)
    state.togglePlayback()
    let session = state.spatialAudioSession!
    state.moveNode(id: a, to: [-0.6, 1.8, 0.5])
    state.rotateNode(id: a, addingTo: .zero, delta: [.pi / 2, .pi / 3, .pi / 4])
    state.setPitch(id: a, semitones: 7)
    state.beginParameterEdit()
    state.setSoundParameter(id: a, parameter: .volume, value: 0.4)
    state.setSoundParameter(id: a, parameter: .delay, value: 0.7)
    check(state.node(id: a)?.pitch == 7 && state.node(id: a)?.volume == 0.4 && state.node(id: a)?.delay == 0.7, "Live parameter lost")
    check(state.node(id: a)?.isSoundLocked == false, "Pitch unexpectedly locked movement")
    check(state.graphTransport.isPlaying && state.spatialAudioSession?.id == session.id, "Live editing stopped or restarted audio")
    check(state.spatialAudioSession?.events == session.events && state.hasPendingTimingChanges, "Live gesture changed pulse")
    state.undo()
    check(state.graphTransport.isPlaying, "Undo stopped live editing")
    state.createNode(of: .strings)
    check(state.graphTransport.isPlaying && state.spatialAudioSession?.id == session.id, "Adding a free node interrupted audio")
    state.stopPlayback()
    state.togglePlayback()
    check(state.spatialAudioSession?.events != session.events, "Next Play lost timing edits")
    state.stopPlayback()
    print("PASS live gestures and mixer: unchanged session, continuous transport, next-Play timing, undo")
}

// Desmutear un nodo inicialmente silencioso debe recuperar su misma agenda.
var mutedNode = SoundNode(name: "Muted", type: .organ, isActive: false, positionX: 0, positionY: 1.25, positionZ: 0)
let mutedVoice = SpatialVoiceRenderer(node: mutedNode, sustainSeconds: 1)
let mutedStart = AVAudioTime.seconds(forHostTime: mach_absolute_time())
mutedVoice.schedule.publish([mutedStart], loopStart: mutedStart, repeatingEvery: 1)
let originalGeneration = mutedVoice.schedule.snapshot().generation
check(render(mutedVoice, at: mutedStart).allSatisfy { $0 == 0 }, "Muted startup leaked audio")
mutedNode.isActive = true
mutedVoice.parameters.update(from: mutedNode, heldSeconds: 1)
var resumedPeak: Float = 0
for block in 1..<40 {
    resumedPeak = max(resumedPeak, render(mutedVoice, at: mutedStart + Double(block * 512) / 48_000).map(abs).max() ?? 0)
}
check(resumedPeak > 0.01 && mutedVoice.schedule.snapshot().generation == originalGeneration, "Unmute lost the original schedule")
mutedNode.pitch = 12
mutedNode.distortion = 0.5
mutedNode.delay = 0.4
mutedVoice.parameters.update(from: mutedNode, heldSeconds: 1)
check(mutedVoice.parameters.snapshot().frequency == 440, "Pitch did not reach live audio")
let changed = render(mutedVoice, at: mutedStart + Double(40 * 512) / 48_000)
check(changed.allSatisfy(\.isFinite) && changed.contains { abs($0) > 0.001 }, "Live effects lost audio")
mutedNode.isActive = false
mutedVoice.parameters.update(from: mutedNode, heldSeconds: 1)
var lastMuted: [Float] = []
for block in 41..<65 { lastMuted = render(mutedVoice, at: mutedStart + Double(block * 512) / 48_000) }
check(lastMuted.allSatisfy { abs($0) < 0.0001 }, "Mute did not fade to silence")
print("PASS live renderer: initially muted, unmute, pitch/effects, mute fade without schedule replacement")
