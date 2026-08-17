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
    var isActive: Bool
    var isSelected: Bool
    var isTriggered: Bool
    var isConnectionSource: Bool
    var isSoundLocked: Bool

    init(node: SoundNode, isSelected: Bool, isTriggered: Bool, isConnectionSource: Bool = false) {
        type = node.type
        position = [node.positionX, node.positionY, node.positionZ]
        rotation = [node.rotationX, node.rotationY, node.rotationZ]
        isActive = node.isActive
        self.isSelected = isSelected
        self.isTriggered = isTriggered
        self.isConnectionSource = isConnectionSource
        isSoundLocked = node.isSoundLocked
    }
}

/// Estado del núcleo de transporte, con la misma disciplina que los nodos.
struct TransportVisualComponent: Component, Equatable {
    var isPlaying: Bool
    var activeCount: Int
    var triggeredCount: Int
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

/// Referencias a las piezas del organismo, resueltas una sola vez al crearlo.
/// Buscarlas por nombre costaba siete recorridos recursivos del subárbol por
/// nodo y por frame, y eso se notaba como tirones con varios organismos.
struct NodePartsComponent: Component {
    var waves: [Entity] = []
    var halo: Entity?
    var connector: Entity?
    var soundLockPlinth: Entity?
}

/// Ondas vivas de un organismo. `-infinity` marca una ranura libre.
private struct TriggerWaveComponent: Component {
    var birthTimes = SIMD4<Double>(repeating: -.infinity)
    var nextSlot = 0
    var wasTriggered = false
}

/// Anima los organismos sonoros a frame rate. Antes esta lógica colgaba de un
/// `TimelineView` a 12–20 Hz, lo que se percibía como tartamudeo constante en
/// Vision Pro; un `System` de RealityKit corre al ritmo del compositor.
struct NodeAnimationSystem: System {
    private static let query = EntityQuery(where: .has(SoundNodeVisualComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let time = CACurrentMediaTime()
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let node = entity.components[SoundNodeVisualComponent.self] else { continue }
            animate(entity, node: node, time: time)
        }
    }

    private func animate(_ entity: Entity, node: SoundNodeVisualComponent, time: TimeInterval) {
        let style = NodeVisualStyle.style(for: node.type)
        let typePhase = Double(SoundNodeType.allCases.firstIndex(of: node.type) ?? 0) * 0.73
        let idle = node.isActive
            ? sin(time * Double(style.idleSpeed) + typePhase) * Double(style.idleAmplitude)
            : 0

        entity.position = [
            node.position.x,
            node.position.y + style.verticalOffset + Float(idle),
            node.position.z
        ]
        let scale = node.isTriggered
            ? style.triggerScale
            : (node.isActive ? style.baseScale : style.baseScale * 0.78)
        entity.scale = SIMD3(repeating: scale)

        let renderedState = NodeRenderedStateComponent(isActive: node.isActive, isTriggered: node.isTriggered)
        if entity.components[NodeRenderedStateComponent.self] != renderedState {
            updateMaterials(in: entity, node: node)
            entity.components.set(renderedState)
        }
        let parts = entity.components[NodePartsComponent.self] ?? NodePartsComponent()
        updateWaves(in: entity, parts: parts, node: node, style: style, time: time)
        updatePersonality(in: entity, node: node, time: time)
        ParticleEffectSystem.updateNode(
            in: entity,
            isSelected: node.isSelected,
            isTriggered: node.isTriggered,
            isActive: node.isActive
        )

        if let halo = parts.halo {
            halo.isEnabled = node.isSelected
            halo.scale = SIMD3(repeating: node.isSelected ? 1.08 + Float(sin(time * 2.4)) * 0.05 : 1)
        }

        // El conector late siempre un poco para invitar a tirar de él, y se
        // agranda mientras el hilo está en el aire.
        if let connector = parts.connector {
            let pulse = 1 + Float(sin(time * 1.9)) * 0.09
            // Crece al seleccionar el organismo: una vez que ya lo elegiste,
            // tirar del hilo es lo siguiente que vas a querer hacer.
            let emphasis: Float = node.isConnectionSource ? 1.55 : (node.isSelected ? 1.3 : pulse)
            connector.scale = SIMD3(repeating: emphasis)
        }

        parts.soundLockPlinth?.isEnabled = node.isSoundLocked
    }

    /// Cada ataque lanza una onda nueva en la siguiente ranura libre. Lo que
    /// dispara es el **flanco**, no el estado: mientras el nodo sigue sonando no
    /// deben brotar ondas sin parar.
    private func updateWaves(
        in entity: Entity,
        parts: NodePartsComponent,
        node: SoundNodeVisualComponent,
        style: NodeVisualStyle,
        time: TimeInterval
    ) {
        var waves = entity.components[TriggerWaveComponent.self] ?? TriggerWaveComponent()

        if node.isTriggered && !waves.wasTriggered {
            waves.birthTimes[waves.nextSlot] = time
            waves.nextSlot = (waves.nextSlot + 1) % WaveformVisualizer.concurrentWaves
        }
        waves.wasTriggered = node.isTriggered
        entity.components.set(waves)

        WaveformVisualizer.update(
            waves: parts.waves,
            style: style,
            birthTimes: waves.birthTimes,
            time: time
        )
    }

    private func updateMaterials(in root: Entity, node: SoundNodeVisualComponent) {
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

    private func updatePersonality(in root: Entity, node: SoundNodeVisualComponent, time: TimeInterval) {
        let userRotation = simd_quatf(angle: node.rotation.y, axis: [0, 1, 0])
            * simd_quatf(angle: node.rotation.x, axis: [1, 0, 0])
            * simd_quatf(angle: node.rotation.z, axis: [0, 0, 1])
        let idleAngle: Float = switch node.type {
        case .pad: Float(sin(time * 0.22)) * 0.06
        case .lead: Float(sin(time * 0.65)) * 0.045
        case .fx: Float(time * (node.isTriggered ? 0.7 : 0.12)).truncatingRemainder(dividingBy: .pi * 2)
        case .kick, .bass: Float(sin(time * 0.7)) * 0.014
        case .snare, .hiHat, .clap: 0
        }
        root.orientation = userRotation * simd_quatf(angle: idleAngle, axis: [0.25, 1, 0.15])

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
        case .pad, .lead, .fx, .kick, .bass:
            break
        }
    }
}

/// Anima el núcleo Play y su campo Metal, también a frame rate.
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
                triggeredCount: state.triggeredCount
            )
            MetalEnergyFieldSystem.update(
                in: transport,
                time: time,
                isPlaying: state.isPlaying,
                triggeredCount: state.triggeredCount
            )
            transport.scale = SIMD3(repeating: state.isPlaying ? 1.12 : 1)
        }
    }

    private func animateCore(_ core: Entity, state: TransportVisualComponent, time: TimeInterval) {
        let activity = Float(state.activeCount) / 8
        let breathing = Float(sin(time * 1.35)) * 0.035
        core.findEntity(named: "core-outer")?.scale = SIMD3(repeating: 1 + activity * 0.28 + breathing)
        core.findEntity(named: "core-heart")?.scale = SIMD3(
            repeating: 0.9 + activity * 0.42 + Float(state.triggeredCount) * 0.16
        )

        guard let shell = core.findEntity(named: "core-shell") as? ModelEntity else { return }
        shell.scale = SIMD3(repeating: 1 + activity * 0.12 + (state.triggeredCount > 0 ? 0.16 : 0))
        let materialBand = min(4, state.activeCount / 2) + (state.triggeredCount > 0 ? 10 : 0)
        if core.components[CoreRenderedStateComponent.self]?.materialBand != materialBand {
            shell.model?.materials = [SoundVisionMaterials.core(intensity: 0.5 + activity * 0.5)]
            core.components.set(CoreRenderedStateComponent(materialBand: materialBand))
        }
        shell.orientation = simd_quatf(angle: Float(time * 0.16), axis: [0.3, 1, 0.2])
    }
}
