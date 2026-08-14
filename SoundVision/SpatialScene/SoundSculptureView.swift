import RealityKit
import SwiftUI

struct SoundSculptureView: View {
    @EnvironmentObject private var state: CompositionState
    private let ringConfig = SequencerRingConfig.soundVision

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            RealityView { content in
                content.add(makeSculpture())
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == "sound-sculpture" }) else { return }
                updateScene(root, at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .gesture(
                TapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        if let id = NodeEntityFactory.id(from: value.entity) {
                            state.toggleNode(id: id)
                        }
                    }
            )
            .overlay(alignment: .bottom) {
                controlPanel.padding(.bottom, 34)
            }
        }
    }

    private var controlPanel: some View {
        HStack(spacing: 16) {
            Button { state.sequencer.togglePlayback() } label: {
                Image(systemName: state.sequencer.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.sequencer.isPlaying ? .pink : .cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("PASO \(displayedStep)/16")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.cyan)
                if let selected = state.nodes.first(where: { $0.id == state.selectedNodeID }) {
                    Text("\(selected.name) · \(selected.isActive ? "Activo" : "Inactivo")")
                        .font(.footnote.weight(.medium))
                } else {
                    Text("Toca un organismo sonoro")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 145, alignment: .leading)

            Slider(
                value: Binding(get: { state.sequencer.bpm }, set: { state.sequencer.bpm = $0 }),
                in: 70...160,
                step: 1
            )
            .frame(width: 125)

            Text("\(Int(state.sequencer.bpm))")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)

            Button { state.save() } label: { Image(systemName: "square.and.arrow.down") }
            Button { state.reset() } label: { Image(systemName: "arrow.counterclockwise") }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .glassBackgroundEffect(in: .rect(cornerRadius: 22))
    }

    private var displayedStep: Int {
        state.sequencer.currentStep + 1
    }

    private func makeSculpture() -> Entity {
        let root = Entity()
        root.name = "sound-sculpture"
        root.position = [0, -1.15, -1.8]

        root.addChild(SequencerRing.make(config: ringConfig))
        root.addChild(ConnectionLineSystem.makeConnections(for: state.nodes, corePosition: [0, ringConfig.height, 0]))
        root.addChild(CentralCoreSystem.make())
        root.addChild(PulseIndicator.make())
        state.nodes.forEach { root.addChild(NodeEntityFactory.makeNode($0)) }
        return root
    }

    private func updateScene(_ root: Entity, at time: TimeInterval) {
        updatePulse(in: root, at: time)
        updateStepMarkers(in: root)
        ConnectionLineSystem.update(in: root, nodes: state.nodes, triggeredIDs: state.lastTriggeredNodeIDs)

        if let core = root.findEntity(named: "mix-core") {
            CentralCoreSystem.update(
                core,
                activeCount: state.nodes.filter(\.isActive).count,
                triggeredCount: state.lastTriggeredNodeIDs.count,
                time: time
            )
        }

        for node in state.nodes {
            guard let entity = root.findEntity(named: NodeEntityFactory.nodePrefix + node.id.uuidString) else { continue }
            NodeAnimationSystem.update(
                entity,
                node: node,
                isSelected: state.selectedNodeID == node.id,
                isTriggered: state.lastTriggeredNodeIDs.contains(node.id),
                time: time
            )
        }
    }

    private func updatePulse(in root: Entity, at time: TimeInterval) {
        guard let pulse = root.findEntity(named: "pulse-indicator") else { return }
        let elapsed = max(0, time - state.sequencer.lastTickTime)
        let progress = state.sequencer.isPlaying
            ? Float(min(elapsed / state.sequencer.secondsPerStep, 1))
            : 0
        let activeSteps = Set(state.nodes.filter(\.isActive).map(\.stepIndex))
        PulseIndicator.update(
            pulse,
            currentStep: state.sequencer.currentStep,
            progress: progress,
            radius: ringConfig.radius,
            height: ringConfig.height,
            activeSteps: activeSteps
        )
    }

    private func updateStepMarkers(in root: Entity) {
        let soundingStep = state.sequencer.currentStep
        for step in 0..<Sequencer.totalSteps {
            guard let marker = root.findEntity(named: "step-marker-\(step)") as? ModelEntity else { continue }
            if step == soundingStep {
                marker.model?.materials = [SoundVisionMaterials.pulse(isOnActiveStep: state.nodes.contains { $0.isActive && $0.stepIndex == step })]
                marker.scale = SIMD3(repeating: 1.18)
            } else {
                marker.model?.materials = [SoundVisionMaterials.ring(isMajor: step.isMultiple(of: 4))]
                marker.scale = .one
            }
        }
    }
}
