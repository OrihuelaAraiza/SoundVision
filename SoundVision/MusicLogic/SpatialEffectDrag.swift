import Foundation

extension SoundParameter {
    var title: String {
        switch self {
        case .volume: "Volumen"
        case .reverb: "Reverb"
        case .delay: "Delay"
        case .distortion: "Distorsión"
        }
    }

    func value(in node: SoundNode) -> Float {
        switch self {
        case .volume: node.volume
        case .reverb: node.reverb
        case .delay: node.delay
        case .distortion: node.distortion
        }
    }
}

/// Un dial relativo: agarrarlo conserva el valor actual. El desplazamiento
/// vertical se mide en puntos del gesto, sin depender del giro o escala del
/// organismo, ni de la orientación de un BillboardComponent.
struct SpatialEffectDrag {
    static let pointsForFullRange: Double = 240
    private var previousTranslation: Double
    private(set) var value: Float

    init(value: Float, translationY: Double) {
        self.value = value.isFinite ? max(0, min(value, 1)) : 0
        previousTranslation = translationY.isFinite ? translationY : 0
    }

    @discardableResult
    mutating func update(translationY: Double) -> Float? {
        guard translationY.isFinite else { return nil }
        let delta = (previousTranslation - translationY) / Self.pointsForFullRange
        previousTranslation = translationY
        let next = Float(max(0, min(Double(value) + delta, 1)))
        guard next != value else { return nil }
        value = next
        return next
    }
}

/// Una edición espacial equivale a un solo movimiento de slider. Mantiene el
/// feedback local a cada frame y publica al modelo como máximo a 20 Hz.
@MainActor
final class SpatialEffectEditingSession {
    let nodeID: UUID
    let parameter: SoundParameter
    private var drag: SpatialEffectDrag
    private var recordedUndo = false
    private var lastCommitTime: TimeInterval = -.infinity
    var value: Float { drag.value }

    init(node: SoundNode, parameter: SoundParameter, translationY: Double) {
        nodeID = node.id
        self.parameter = parameter
        drag = SpatialEffectDrag(value: parameter.value(in: node), translationY: translationY)
    }

    func update(translationY: Double, at time: TimeInterval, state: CompositionState, finish: Bool = false) {
        guard state.selectedNodeID == nodeID, let node = state.node(id: nodeID) else { return }
        defer { if finish && recordedUndo { state.endParameterEdit() } }
        drag.update(translationY: translationY)
        guard finish || time - lastCommitTime >= 0.05 else { return }
        guard parameter.value(in: node) != drag.value else { return }
        if !recordedUndo {
            state.beginParameterEdit("Ajustar \(parameter.title)")
            recordedUndo = true
        }
        lastCommitTime = time
        state.setSoundParameter(id: nodeID, parameter: parameter, value: drag.value)
    }
}
