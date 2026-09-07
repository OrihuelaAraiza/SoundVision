import Foundation

/// Ejercicios pequeños y reproducibles. Se comprueba la música resultante,
/// no una lista de botones pulsados.
enum MusicLesson: String, CaseIterable, Identifiable {
    case pulse, melody, harmony, branches
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pulse: "Pulso y ritmo"
        case .melody: "Una melodía que sube"
        case .harmony: "Notas que suenan juntas"
        case .branches: "Rutas que se encuentran"
        }
    }
    var icon: String {
        switch self {
        case .pulse: "metronome"
        case .melody: "music.note"
        case .harmony: "pianokeys"
        case .branches: "arrow.triangle.branch"
        }
    }
    var explanation: String {
        switch self {
        case .pulse:
            "El pulso es la referencia regular de la música. El tempo indica cuántos pulsos caben en un minuto: a 120 BPM, un pulso dura medio segundo. En SoundVision, el tiempo de cada conexión se mide en pulsos (beats)."
        case .melody:
            "Una melodía ordena notas en el tiempo. Un semitono es un paso de afinación; doce forman una octava. Aquí usamos La–Do–Mi: tres notas de La menor. El mismo timbre permite escuchar claramente el cambio de altura."
        case .harmony:
            "Un acorde combina varias notas a la vez. La, Do y Mi forman un acorde de La menor. Desde un nodo, tres salidas con el mismo tiempo disparan las tres notas juntas. El tiempo se cuenta desde el origen de cada conexión."
        case .branches:
            "Cada salida sigue su propia ruta. Dos caminos que llegan a un mismo nodo en el mismo instante producen un solo ataque. Si llegan en instantes distintos, ese nodo vuelve a sonar. Así puedes crear respuestas y ritmos entrelazados."
        }
    }
    var challenge: String {
        switch self {
        case .pulse: "Selecciona «Pulso 1» y fija su salida a 1 beat. Repite con «Pulso 2» y «Pulso 3». Debes oír cuatro golpes igualmente espaciados."
        case .melody: "En «Nodo → Afinación», deja «La» en 0 st, sube «Do» a +3 st y «Mi» a +7 st. Escucha la melodía completa."
        case .harmony: "Selecciona «Entrada» y fija sus tres salidas a 1 beat. Las notas La, Do y Mi deben empezar juntas después del primer golpe."
        case .branches: "Las dos ramas llegan juntas a «Campana». Selecciona «Rama B» y cambia su salida a 2 beats. Ahora la campana debe sonar en los beats 2 y 3."
        }
    }
    var success: String {
        switch self {
        case .pulse: "Los ataques están separados por un pulso: construiste un ritmo regular. Prueba ahora otro tempo."
        case .melody: "La–Do–Mi: escuchaste una tercera menor y una quinta justa respecto a La."
        case .harmony: "Las tres notas llegan juntas y forman La menor. La simultaneidad la deciden los tiempos de las conexiones."
        case .branches: "La campana tiene dos entradas y dos ataques distintos. Cada llegada conserva su tiempo."
        }
    }

    func composition() -> Composition {
        func node(_ name: String, _ type: SoundNodeType, _ index: Int, pitch: Float = 0) -> SoundNode {
            SoundNode(name: name, type: type, volume: 0.65, pitch: pitch,
                      positionX: Float(index % 3 - 1) * 0.65,
                      positionY: 1.1 + Float(index / 3) * 0.5, positionZ: -0.4,
                      isSoundLocked: true)
        }
        let nodes: [SoundNode]
        let edges: [(Int, Int, Double)]
        switch self {
        case .pulse:
            nodes = (0..<4).map { node("Pulso \($0 + 1)", $0 == 2 ? .snare : .tom, $0) }
            edges = [(0, 1, 0.5), (1, 2, 1.5), (2, 3, 0.5)]
        case .melody:
            nodes = [node("La", .marimba, 0), node("Do", .marimba, 1), node("Mi", .marimba, 2)]
            edges = [(0, 1, 1), (1, 2, 1)]
        case .harmony:
            nodes = [node("Entrada", .kick, 0), node("La", .organ, 1),
                     node("Do", .organ, 2, pitch: 3), node("Mi", .organ, 3, pitch: 7)]
            edges = [(0, 1, 0.5), (0, 2, 1), (0, 3, 1.5)]
        case .branches:
            nodes = [node("Entrada", .kick, 0), node("Rama A", .shaker, 1),
                     node("Rama B", .tom, 2), node("Campana", .bell, 3)]
            edges = [(0, 1, 1), (0, 2, 1), (1, 3, 1), (2, 3, 1)]
        }
        return Composition(title: title, bpm: 100, steps: 16, nodes: nodes,
            connections: [SoundConnection(sourceNodeID: nil, destinationNodeID: nodes[0].id)] + edges.map {
                SoundConnection(sourceNodeID: nodes[$0.0].id, destinationNodeID: nodes[$0.1].id,
                                durationBeats: $0.2, usesSpatialTiming: false)
            }, loopPasses: 1)
    }

    func isComplete(_ composition: Composition) -> Bool {
        let plan = GraphSchedule.makePlan(nodes: composition.nodes, connections: composition.connections,
                                         loopPasses: composition.loopPasses)
        guard !plan.isTruncated else { return false }
        func attacks(_ name: String) -> [Double] {
            guard let node = composition.nodes.first(where: { $0.name == name && $0.isActive }) else { return [] }
            return plan.events.filter { $0.nodeID == node.id }.map(\.beat)
        }
        func matches(_ actual: [Double], _ expected: [Double]) -> Bool {
            actual.count == expected.count && zip(actual, expected).allSatisfy { abs($0 - $1) < 0.001 }
        }
        func pitched(_ name: String, _ pitch: Float, _ type: SoundNodeType) -> Bool {
            composition.nodes.contains { $0.name == name && $0.type == type && abs($0.pitch - pitch) < 0.01 && $0.isActive }
        }
        switch self {
        case .pulse:
            return (0..<4).allSatisfy { matches(attacks("Pulso \($0 + 1)"), [Double($0)]) }
        case .melody:
            return pitched("La", 0, .marimba) && pitched("Do", 3, .marimba) && pitched("Mi", 7, .marimba)
                && matches(attacks("La"), [0]) && matches(attacks("Do"), [1]) && matches(attacks("Mi"), [2])
        case .harmony:
            return pitched("La", 0, .organ) && pitched("Do", 3, .organ) && pitched("Mi", 7, .organ)
                && ["La", "Do", "Mi"].allSatisfy { matches(attacks($0), [1]) }
        case .branches:
            guard let bell = composition.nodes.first(where: { $0.name == "Campana" }) else { return false }
            return composition.connections.filter { $0.destinationNodeID == bell.id && $0.sourceNodeID != nil }.count == 2
                && matches(attacks("Campana"), [2, 3])
        }
    }
}
