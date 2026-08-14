import Combine
import Foundation

@MainActor
final class CompositionState: ObservableObject {
    @Published var nodes: [SoundNode]
    @Published var isImmersiveSpaceOpen = false
    @Published var lastTriggeredNodeIDs: Set<UUID> = []
    @Published var selectedNodeID: UUID?
    @Published var statusMessage: String?

    let sequencer = Sequencer()
    private let audio = AudioEngineManager()
    private let storage: CompositionStorage
    private var pulseClearTask: Task<Void, Never>?
    private var sequencerObservation: AnyCancellable?

    init(storage: CompositionStorage = CompositionStorage()) {
        self.storage = storage
        nodes = SoundNode.starterPattern()
        sequencer.onStep = { [weak self] step in
            self?.triggerNodes(at: step)
        }
        sequencerObservation = sequencer.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func toggleNode(id: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        selectedNodeID = id
        nodes[index].isActive.toggle()
    }

    func save() {
        do {
            try storage.save(snapshot)
            statusMessage = "Composición guardada localmente."
        } catch {
            statusMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    func load() {
        do {
            let composition = try storage.load()
            sequencer.stop()
            sequencer.bpm = composition.bpm
            nodes = composition.nodes
            selectedNodeID = nil
            statusMessage = "Composición cargada."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reset() {
        sequencer.reset()
        audio.stopAll()
        nodes = SoundNode.starterPattern()
        lastTriggeredNodeIDs = []
        selectedNodeID = nil
        statusMessage = "Patrón inicial restaurado."
    }

    var snapshot: Composition {
        Composition(title: "Anatomía del Sonido", bpm: sequencer.bpm, steps: Sequencer.totalSteps, nodes: nodes)
    }

    private func triggerNodes(at step: Int) {
        let triggered = nodes.filter { $0.isActive && $0.stepIndex == step }
        lastTriggeredNodeIDs = Set(triggered.map(\.id))
        triggered.forEach(audio.play)

        pulseClearTask?.cancel()
        pulseClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.lastTriggeredNodeIDs = []
        }
    }
}
