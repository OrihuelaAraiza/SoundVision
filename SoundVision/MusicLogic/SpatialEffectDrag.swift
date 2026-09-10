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
///
/// La ganancia no es fija. Con una sola constante había que elegir entre
/// recorrer el rango con un gesto cómodo o poder afinar un 1 %, y con la mano
/// en el aire —que tiembla— ganaba siempre lo primero: el valor saltaba de
/// tres en tres por ciento. Aquí el mismo gesto hace las dos cosas, como la
/// aceleración de un puntero: lo que se mueve despacio avanza fino, y un
/// barrido rápido sigue cruzando de 0 a 100 % de una pasada.
struct SpatialEffectDrag {
    /// Puntos que barren todo el rango en un gesto amplio.
    static let pointsForFullRange: Double = 240
    /// Ganancia de un movimiento lento y deliberado: a este ritmo hacen falta
    /// unos 750 puntos para el rango entero, o sea ~0.13 % por punto.
    static let fineGain: Double = 0.32
    /// Desplazamiento por evento (a ~90 Hz) a partir del cual el gesto se lee
    /// como barrido y recupera la ganancia completa.
    static let sweepPointsPerUpdate: Double = 9
    /// El valor publicado avanza en pasos de 1 %, que es la resolución que
    /// enseñan el gizmo y la consola. Soltar cae siempre sobre un número
    /// alcanzable a propósito, no sobre un 0.6374 invisible.
    static let step: Double = 0.01
    private var previousTranslation: Double
    /// Continuo y sin cuantizar: si el acumulador se redondeara, un
    /// movimiento lento perdería su avance en cada evento y no llegaría nunca.
    private var rawValue: Double
    private(set) var value: Float

    init(value: Float, translationY: Double) {
        let start = value.isFinite ? Double(max(0, min(value, 1))) : 0
        rawValue = start
        // Sin cuantizar al agarrar: el valor exacto del nodo se conserva hasta
        // que la mano se mueve de verdad.
        self.value = Float(start)
        previousTranslation = translationY.isFinite ? translationY : 0
    }

    @discardableResult
    mutating func update(translationY: Double) -> Float? {
        guard translationY.isFinite else { return nil }
        let travel = previousTranslation - translationY
        previousTranslation = translationY
        // El recorte va sobre el acumulador, no solo sobre lo que se publica:
        // así volver desde un extremo responde al primer punto en vez de
        // gastar antes todo el margen que se pasó de largo.
        rawValue = max(0, min(rawValue + travel * Self.gain(forTravel: travel) / Self.pointsForFullRange, 1))
        let next = Float((rawValue / Self.step).rounded() * Self.step)
        guard next != value else { return nil }
        value = next
        return next
    }

    /// Curva de aceleración, del ajuste fino al barrido completo.
    static func gain(forTravel travel: Double) -> Double {
        guard travel.isFinite else { return fineGain }
        let speed = min(abs(travel) / sweepPointsPerUpdate, 1)
        return fineGain + (1 - fineGain) * speed
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
