import Foundation

enum SoundNodeType: String, Codable, CaseIterable, Sendable {
    case kick, snare, hiHat, clap, bass, pad, lead, fx

    static func displayName(for type: SoundNodeType) -> String {
        switch type {
        case .kick: "Kick"
        case .snare: "Snare"
        case .hiHat: "Hi-hat"
        case .clap: "Clap"
        case .bass: "Bass"
        case .pad: "Pad"
        case .lead: "Lead"
        case .fx: "FX"
        }
    }

    static func icon(for type: SoundNodeType) -> String {
        switch type {
        case .kick: "circle.fill"
        case .snare: "square.fill"
        case .hiHat: "triangle.fill"
        case .clap: "hands.clap.fill"
        case .bass: "waveform.path"
        case .pad: "cloud.fill"
        case .lead: "bolt.fill"
        case .fx: "sparkles"
        }
    }
}

struct SoundNode: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var type: SoundNodeType
    var isActive: Bool
    var volume: Float
    /// Semitonos relativos al pitch original.
    var pitch: Float
    var stepIndex: Int
    var positionX: Float
    var positionY: Float
    var positionZ: Float
    var rotationX: Float
    var rotationY: Float
    var rotationZ: Float
    var durationBeats: Double
    var reverb: Float
    var delay: Float
    var distortion: Float

    init(
        id: UUID = UUID(),
        name: String,
        type: SoundNodeType,
        isActive: Bool = true,
        volume: Float = 0.78,
        pitch: Float = 0,
        stepIndex: Int = 0,
        positionX: Float,
        positionY: Float,
        positionZ: Float,
        rotationX: Float = 0,
        rotationY: Float = 0,
        rotationZ: Float = 0,
        durationBeats: Double = 1,
        reverb: Float = 0,
        delay: Float = 0,
        distortion: Float = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isActive = isActive
        self.volume = volume
        self.pitch = pitch
        self.stepIndex = stepIndex
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.durationBeats = durationBeats
        self.reverb = reverb
        self.delay = delay
        self.distortion = distortion
    }

    static func starterPattern(radius: Float = 1.15) -> [SoundNode] {
        let definitions: [(String, SoundNodeType, Int, Bool)] = [
            ("Kick", .kick, 0, true), ("Snare", .snare, 2, true),
            ("Hi-hat", .hiHat, 4, true), ("Clap", .clap, 6, false),
            ("Bass", .bass, 8, true), ("Pad", .pad, 10, true),
            ("Lead", .lead, 12, false), ("FX", .fx, 14, true)
        ]

        return definitions.enumerated().map { index, definition in
            let angle = Float(index) / Float(definitions.count) * 2 * .pi
            return SoundNode(
                name: definition.0,
                type: definition.1,
                isActive: definition.3,
                stepIndex: definition.2,
                positionX: cos(angle) * radius,
                positionY: 1.25 + sin(Float(index) * 1.7) * 0.12,
                positionZ: sin(angle) * radius
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, isActive, volume, pitch, stepIndex
        case positionX, positionY, positionZ
        case rotationX, rotationY, rotationZ, durationBeats
        case reverb, delay, distortion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(SoundNodeType.self, forKey: .type)
        isActive = try values.decode(Bool.self, forKey: .isActive)
        volume = try values.decode(Float.self, forKey: .volume)
        pitch = try values.decode(Float.self, forKey: .pitch)
        stepIndex = try values.decodeIfPresent(Int.self, forKey: .stepIndex) ?? 0
        positionX = try values.decode(Float.self, forKey: .positionX)
        positionY = try values.decode(Float.self, forKey: .positionY)
        positionZ = try values.decode(Float.self, forKey: .positionZ)
        rotationX = try values.decodeIfPresent(Float.self, forKey: .rotationX) ?? 0
        rotationY = try values.decodeIfPresent(Float.self, forKey: .rotationY) ?? 0
        rotationZ = try values.decodeIfPresent(Float.self, forKey: .rotationZ) ?? 0
        durationBeats = try values.decodeIfPresent(Double.self, forKey: .durationBeats) ?? 1
        reverb = try values.decodeIfPresent(Float.self, forKey: .reverb) ?? 0
        delay = try values.decodeIfPresent(Float.self, forKey: .delay) ?? 0
        distortion = try values.decodeIfPresent(Float.self, forKey: .distortion) ?? 0
    }
}

struct SoundConnection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// `nil` representa el nodo raíz Play.
    var sourceNodeID: UUID?
    var destinationNodeID: UUID
    var durationBeats: Double

    init(id: UUID = UUID(), sourceNodeID: UUID?, destinationNodeID: UUID, durationBeats: Double = 1) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
        self.durationBeats = durationBeats
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceNodeID, destinationNodeID, durationBeats
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceNodeID = try values.decodeIfPresent(UUID.self, forKey: .sourceNodeID)
        destinationNodeID = try values.decode(UUID.self, forKey: .destinationNodeID)
        durationBeats = try values.decodeIfPresent(Double.self, forKey: .durationBeats) ?? 1
    }
}

struct Composition: Codable, Equatable, Sendable {
    var title: String
    var bpm: Double
    var steps: Int
    var nodes: [SoundNode]
    var connections: [SoundConnection]

    init(title: String, bpm: Double, steps: Int, nodes: [SoundNode], connections: [SoundConnection] = []) {
        self.title = title
        self.bpm = bpm
        self.steps = steps
        self.nodes = nodes
        self.connections = connections
    }

    private enum CodingKeys: String, CodingKey {
        case title, bpm, steps, nodes, connections
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        bpm = try values.decode(Double.self, forKey: .bpm)
        steps = try values.decodeIfPresent(Int.self, forKey: .steps) ?? 16
        nodes = try values.decode([SoundNode].self, forKey: .nodes)
        connections = try values.decodeIfPresent([SoundConnection].self, forKey: .connections) ?? []
    }
}
