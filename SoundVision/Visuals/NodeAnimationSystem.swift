import Foundation
import QuartzCore
import RealityKit

/// Estado musical que la animación necesita en cada frame. La vista solo
/// escribe este componente cuando algo cambia de verdad; el movimiento continuo
/// lo produce `NodeAnimationSystem` a la tasa de refresco de RealityKit.
struct SoundNodeVisualComponent: Component, Equatable {
    var type: SoundNodeType
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>
    /// Reverb, delay y distorsión. Viajan en el componente para que las barras
    /// del cuerpo se actualicen cuando el valor cambia de verdad, y no porque
    /// alguien recorra la escena buscando qué ha cambiado.
    var effects: SIMD3<Float>
    var isActive: Bool
    var isSelected: Bool
    var isTriggered: Bool
    var isConnectionSource: Bool
    var isSoundLocked: Bool
    var reduceMotion: Bool

    init(node: SoundNode, isSelected: Bool, isTriggered: Bool, isConnectionSource: Bool = false, reduceMotion: Bool = false) {
        type = node.type
        position = [node.positionX, node.positionY, node.positionZ]
        rotation = [node.rotationX, node.rotationY, node.rotationZ]
        effects = [node.reverb, node.delay, node.distortion]
        isActive = node.isActive
        self.isSelected = isSelected
        self.isTriggered = isTriggered
        self.isConnectionSource = isConnectionSource
        isSoundLocked = node.isSoundLocked
        self.reduceMotion = reduceMotion
    }
}

/// Estado del núcleo de transporte, con la misma disciplina que los nodos.
struct TransportVisualComponent: Component, Equatable {
    var isPlaying: Bool
    var activeCount: Int
    var triggeredCount: Int
    var reduceMotion: Bool = false
}

/// Marca lo último que se envió a las mallas para no reconstruir materiales en
/// cada frame; solo el estado discreto (activo/disparado) justifica ese costo.
private struct NodeRenderedStateComponent: Component, Equatable {
    var isActive: Bool
    var isTriggered: Bool
}

private struct CoreRenderedStateComponent: Component, Equatable {
    var materialBand: Int
}

/// Último nivel dibujado en las barras de efecto, en porcentaje entero: por
/// debajo de eso el indicador no cambiaría de aspecto y no vale la pena tocarlo.
private struct NodeEffectRenderedComponent: Component, Equatable {
    var levels: SIMD3<Int32>
}

/// Referencias a las piezas del organismo, resueltas una sola vez al crearlo.
/// Buscarlas por nombre costaba siete recorridos recursivos del subárbol por
/// nodo y por frame, y eso se notaba como tirones con varios organismos.
struct NodePartsComponent: Component {
    var waves: [Entity] = []
    var halo: Entity?
    var connector: Entity?
    var soundLockPlinth: Entity?
    var effectMeter: Entity?
    var effectBars: [NodeEffectMeter.Bar] = []
}

/// Ondas vivas de un organismo. `-infinity` marca una ranura libre.
struct VisualAttackComponent: Component {
    var birthTimes = SIMD4<Double>(repeating: -.infinity)
    var nextSlot = 0
    var sequence: UInt64 = 0
}

@MainActor
enum VisualAttackFeedback {
    static func emit(on entity: Entity, at time: TimeInterval) {
        var attacks = entity.components[VisualAttackComponent.self] ?? VisualAttackComponent()
        attacks.birthTimes[attacks.nextSlot] = time
        attacks.nextSlot = (attacks.nextSlot + 1) % 4
        attacks.sequence &+= 1
        entity.components.set(attacks)
    }
}

/// Anima los organismos sonoros a frame rate. Antes esta lógica colgaba de un
/// `TimelineView` a 12–20 Hz, lo que se percibía como tartamudeo constante en
/// Vision Pro; un `System` de RealityKit corre al ritmo del compositor.
@MainActor
struct NodeAnimationSystem: System {
    private static let query = EntityQuery(where: .has(SoundNodeVisualComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let time = CACurrentMediaTime()
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let node = entity.components[SoundNodeVisualComponent.self] else { continue }
            Self.apply(to: entity, node: node, time: time)
        }
    }

    static func apply(to entity: Entity, node: SoundNodeVisualComponent, time: TimeInterval) {
        let style = NodeVisualStyle.style(for: node.type)
        let typePhase = Double(SoundNodeType.allCases.firstIndex(of: node.type) ?? 0) * 0.73
        let idle = node.isActive && !node.reduceMotion
            ? sin(time * Double(style.idleSpeed) + typePhase) * Double(style.idleAmplitude)
            : 0

        entity.position = [
            node.position.x,
            node.position.y + style.verticalOffset + Float(idle),
            node.position.z
        ]
        let scale = node.isTriggered && !node.reduceMotion
            ? style.triggerScale
            : (node.isActive ? style.baseScale : style.baseScale * 0.78)
        entity.scale = SIMD3(repeating: scale)

        var materialNode = node
        if node.reduceMotion {
            let births = entity.components[VisualAttackComponent.self]?.birthTimes ?? SIMD4(repeating: -.infinity)
            materialNode.isTriggered = (0..<4).contains { time >= births[$0] && time - births[$0] < 0.06 }
        }
        let renderedState = NodeRenderedStateComponent(isActive: node.isActive, isTriggered: materialNode.isTriggered)
        if entity.components[NodeRenderedStateComponent.self] != renderedState {
            updateMaterials(in: entity, node: materialNode)
            entity.components.set(renderedState)
        }
        let parts = entity.components[NodePartsComponent.self] ?? NodePartsComponent()
        updateWaves(in: entity, parts: parts, node: node, style: style, time: time)
        updatePersonality(in: entity, node: node, time: time)
        updateEffectMeter(in: entity, parts: parts, node: node, scale: scale)
        ParticleEffectSystem.updateNode(
            in: entity,
            isSelected: node.isSelected,
            isTriggered: node.isTriggered,
            isActive: node.isActive,
            reduceMotion: node.reduceMotion
        )

        if let halo = parts.halo {
            halo.isEnabled = node.isSelected
            halo.scale = SIMD3(repeating: node.isSelected ? 1.08 + (node.reduceMotion ? 0 : Float(sin(time * 2.4)) * 0.05) : 1)
        }

        // El conector late siempre un poco para invitar a tirar de él, y se
        // agranda mientras el hilo está en el aire.
        if let connector = parts.connector {
            let pulse: Float = node.reduceMotion ? 1 : 1 + Float(sin(time * 1.9)) * 0.09
            // Crece al seleccionar el organismo: una vez que ya lo elegiste,
            // tirar del hilo es lo siguiente que vas a querer hacer.
            let emphasis: Float = node.isConnectionSource ? 1.55 : (node.isSelected ? 1.3 : pulse)
            connector.scale = SIMD3(repeating: emphasis)
        }

        parts.soundLockPlinth?.isEnabled = node.isSoundLocked
    }

    /// Las barras de efecto no heredan ni el giro ni el pulso del cuerpo: se
    /// contrarresta la transformada del organismo para que se queden quietas y
    /// de frente. Colgando del cuerpo sin más, orientar un Pad se llevaba las
    /// barras a su espalda y un ataque las hacía saltar justo cuando había
    /// algo que leer.
    private static func updateEffectMeter(
        in entity: Entity,
        parts: NodePartsComponent,
        node: SoundNodeVisualComponent,
        scale: Float
    ) {
        guard let meter = parts.effectMeter else { return }
        let safeScale = scale.isFinite && scale > 0.0001 ? scale : 1
        let inverse = entity.orientation.inverse
        meter.position = inverse.act(SIMD3<Float>(0, NodeEffectMeter.elevation, 0) / safeScale)
        meter.scale = SIMD3(repeating: 1 / safeScale)

        let levels = NodeEffectMeter.levels(
            reverb: node.effects.x,
            delay: node.effects.y,
            distortion: node.effects.z
        )
        guard entity.components[NodeEffectRenderedComponent.self]?.levels != levels else { return }
        NodeEffectMeter.update(bars: parts.effectBars, levels: levels)
        entity.components.set(NodeEffectRenderedComponent(levels: levels))
    }

    /// La agenda entrega cada ataque por separado. Las ondas leen sus fechas,
    /// sin depender de que el estado de iluminación se apague entre dos notas.
    private static func updateWaves(
        in entity: Entity,
        parts: NodePartsComponent,
        node: SoundNodeVisualComponent,
        style: NodeVisualStyle,
        time: TimeInterval
    ) {
        let attacks = entity.components[VisualAttackComponent.self] ?? VisualAttackComponent()
        if node.reduceMotion {
            // Static bodies and selection remain legible; the material still marks attacks.
            parts.waves.forEach { $0.isEnabled = false }
        } else {
            WaveformVisualizer.update(waves: parts.waves, style: style,
                birthTimes: attacks.birthTimes, time: time)
        }
    }

    private static func updateMaterials(in root: Entity, node: SoundNodeVisualComponent) {
        for child in root.children.compactMap({ $0 as? ModelEntity }) {
            if child.name.hasPrefix("node-core") {
                child.model?.materials = [SoundVisionMaterials.nodeSurface(
                    for: node.type,
                    isActive: node.isActive,
                    isTriggered: node.isTriggered
                )]
            } else if child.name == "accent" || child.name.hasPrefix("fragment-") {
                child.model?.materials = [node.isActive
                    ? SoundVisionMaterials.accentGlow(for: node.type, alpha: node.isTriggered ? 0.95 : 0.52)
                    : SoundVisionMaterials.translucentAccent(for: node.type, alpha: 0.05)]
            }
        }
    }

    private static func updatePersonality(in root: Entity, node: SoundNodeVisualComponent, time: TimeInterval) {
        let userRotation = simd_quatf(angle: node.rotation.y, axis: [0, 1, 0])
            * simd_quatf(angle: node.rotation.x, axis: [1, 0, 0])
            * simd_quatf(angle: node.rotation.z, axis: [0, 0, 1])
        let idleAngle: Float = switch node.type {
        case .pad, .organ, .strings, .brass: Float(sin(time * 0.22)) * 0.06
        case .lead, .bell, .pluck, .flute, .electricPiano: Float(sin(time * 0.65)) * 0.045
        case .fx: Float(time * (node.isTriggered ? 0.7 : 0.12)).truncatingRemainder(dividingBy: .pi * 2)
        case .kick, .bass, .tom, .subBass, .conga: Float(sin(time * 0.7)) * 0.014
        case .snare, .hiHat, .clap, .shaker, .marimba, .rimshot, .woodblock, .cowbell, .openHat: 0
        }
        root.orientation = userRotation * simd_quatf(angle: node.reduceMotion ? 0 : idleAngle, axis: [0.25, 1, 0.15])

        guard !node.reduceMotion else { return }
        switch node.type {
        case .clap:
            let gap: Float = node.isTriggered ? 0.035 : 0.072
            root.findEntity(named: "node-core")?.position.x = -gap
            root.findEntity(named: "node-core-secondary")?.position.x = gap
        case .snare:
            let offset: Float = node.isTriggered ? 0.175 : 0.145
            let accents = root.children.filter { $0.name == "accent" }
            if accents.count == 2 {
                accents[0].position.x = -offset
                accents[1].position.x = offset
            }
        case .hiHat:
            root.findEntity(named: "accent")?.position.y = node.isTriggered ? 0.012 : 0.035
        case .pad, .lead, .fx, .kick, .bass, .tom, .shaker, .bell, .marimba, .pluck, .organ, .rimshot, .cowbell, .conga, .woodblock, .openHat, .electricPiano, .flute, .strings, .brass, .subBass:
            break
        }
    }
}

/// Anima el núcleo Play y su campo Metal, también a frame rate.
@MainActor
struct TransportAnimationSystem: System {
    private static let query = EntityQuery(where: .has(TransportVisualComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let time = CACurrentMediaTime()
        for transport in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let state = transport.components[TransportVisualComponent.self],
                  let core = transport.findEntity(named: "mix-core")
            else { continue }

            animateCore(core, state: state, time: time)
            ParticleEffectSystem.updateCore(
                in: core,
                isPlaying: state.isPlaying,
                triggeredCount: state.triggeredCount,
                reduceMotion: state.reduceMotion
            )
            MetalEnergyFieldSystem.update(
                in: transport,
                time: time,
                isPlaying: state.isPlaying,
                triggeredCount: state.triggeredCount,
                reduceMotion: state.reduceMotion
            )
            transport.scale = SIMD3(repeating: state.isPlaying && !state.reduceMotion ? 1.12 : 1)
        }
    }

    private func animateCore(_ core: Entity, state: TransportVisualComponent, time: TimeInterval) {
        let activity = Float(state.activeCount) / 8
        let breathing: Float = state.reduceMotion ? 0 : Float(sin(time * 1.35)) * 0.035
        core.findEntity(named: "core-outer")?.scale = SIMD3(repeating: 1 + activity * 0.28 + breathing)
        core.findEntity(named: "core-heart")?.scale = SIMD3(
            repeating: 0.9 + activity * 0.42 + (state.reduceMotion ? 0 : Float(state.triggeredCount) * 0.16)
        )

        guard let shell = core.findEntity(named: "core-shell") as? ModelEntity else { return }
        shell.scale = SIMD3(repeating: 1 + activity * 0.12 + (state.triggeredCount > 0 && !state.reduceMotion ? 0.16 : 0))
        let materialBand = min(4, state.activeCount / 2) + (state.triggeredCount > 0 ? 10 : 0)
        if core.components[CoreRenderedStateComponent.self]?.materialBand != materialBand {
            shell.model?.materials = [SoundVisionMaterials.core(intensity: 0.5 + activity * 0.5)]
            core.components.set(CoreRenderedStateComponent(materialBand: materialBand))
        }
        shell.orientation = simd_quatf(angle: state.reduceMotion ? 0 : Float(time * 0.16), axis: [0.3, 1, 0.2])
    }
}
