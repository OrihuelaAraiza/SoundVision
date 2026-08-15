import Metal
import RealityKit
import UIKit

/// Campo dinámico alrededor del transporte. RealityKit conserva render,
/// profundidad y composición espacial; Metal únicamente actualiza los vértices
/// del LowLevelMesh para mantener el trabajo geométrico en GPU.
enum MetalEnergyFieldSystem {
    static let entityName = "metal-energy-field"

    private static let segmentCount = 64
    private static let ribbonCount = 2
    private static let verticesPerSegment = 2
    @MainActor private static var lastGPUUpdateTime: TimeInterval = -.infinity

    private struct Parameters {
        var time: Float
        var intensity: Float
        var segmentCount: UInt32
        var ribbonCount: UInt32
    }

    @MainActor
    private final class Runtime {
        let commandQueue: MTLCommandQueue?
        let pipeline: MTLComputePipelineState?

        init() {
            guard let device = MTLCreateSystemDefaultDevice() else {
                commandQueue = nil
                pipeline = nil
                return
            }
            commandQueue = device.makeCommandQueue()
            guard let function = device.makeDefaultLibrary()?.makeFunction(name: "updateEnergyRibbons") else {
                pipeline = nil
                return
            }
            pipeline = try? device.makeComputePipelineState(function: function)
        }
    }

    @MainActor private static let runtime = Runtime()

    @MainActor
    static func make() -> ModelEntity {
        do {
            let lowLevelMesh = try makeLowLevelMesh()
            let mesh = try MeshResource(from: lowLevelMesh)
            let entity = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: UIColor(red: 0.2, green: 0.88, blue: 1, alpha: 0.46))]
            )
            entity.name = entityName
            return entity
        } catch {
            let fallback = ModelEntity(
                mesh: .generateCylinder(height: 0.006, radius: 0.34),
                materials: [UnlitMaterial(color: UIColor.systemCyan.withAlphaComponent(0.18))]
            )
            fallback.name = entityName
            return fallback
        }
    }

    @MainActor
    static func update(in transport: Entity, time: TimeInterval, isPlaying: Bool, triggeredCount: Int) {
        guard let entity = transport.findEntity(named: entityName) as? ModelEntity else { return }
        entity.orientation = simd_quatf(angle: Float(time * (isPlaying ? 0.16 : 0.045)), axis: [0.15, 1, 0.1])

        let minimumInterval = isPlaying ? 1.0 / 20.0 : 1.0 / 3.0
        guard time < lastGPUUpdateTime || time - lastGPUUpdateTime >= minimumInterval else { return }
        lastGPUUpdateTime = time

        guard let lowLevelMesh = entity.model?.mesh.lowLevelMesh,
              let queue = runtime.commandQueue,
              let pipeline = runtime.pipeline,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        var parameters = Parameters(
            time: Float(time.truncatingRemainder(dividingBy: 10_000)),
            intensity: isPlaying ? min(1, 0.38 + Float(triggeredCount) * 0.2) : 0.12,
            segmentCount: UInt32(segmentCount),
            ribbonCount: UInt32(ribbonCount)
        )
        let vertexBuffer = lowLevelMesh.replace(bufferIndex: 0, using: commandBuffer)
        encoder.label = "SoundVision Energy Ribbons"
        encoder.setComputePipelineState(pipeline)
        encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 1)

        let vertexCount = segmentCount * ribbonCount * verticesPerSegment
        let width = min(pipeline.threadExecutionWidth, vertexCount)
        encoder.dispatchThreads(
            MTLSize(width: vertexCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
    }

    @MainActor
    private static func makeLowLevelMesh() throws -> LowLevelMesh {
        let vertexCount = segmentCount * ribbonCount * verticesPerSegment
        let indexCount = segmentCount * ribbonCount * 6
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: vertexCount,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, offset: 0),
                .init(semantic: .normal, format: .float3, offset: 16)
            ],
            vertexLayouts: [.init(bufferIndex: 0, bufferStride: 32)],
            indexCapacity: indexCount,
            indexType: .uint32
        )
        let mesh = try LowLevelMesh(descriptor: descriptor)

        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
        }
        mesh.replaceUnsafeMutableIndices { rawBuffer in
            let indices = rawBuffer.bindMemory(to: UInt32.self)
            var cursor = 0
            for ribbon in 0..<ribbonCount {
                let ribbonBase = ribbon * segmentCount * verticesPerSegment
                for segment in 0..<segmentCount {
                    let next = (segment + 1) % segmentCount
                    let lower = UInt32(ribbonBase + segment * 2)
                    let upper = lower + 1
                    let nextLower = UInt32(ribbonBase + next * 2)
                    let nextUpper = nextLower + 1
                    indices[cursor + 0] = lower
                    indices[cursor + 1] = nextLower
                    indices[cursor + 2] = upper
                    indices[cursor + 3] = upper
                    indices[cursor + 4] = nextLower
                    indices[cursor + 5] = nextUpper
                    cursor += 6
                }
            }
        }
        mesh.parts.replaceAll([
            .init(
                indexCount: indexCount,
                topology: .triangle,
                bounds: BoundingBox(min: [-0.52, -0.18, -0.52], max: [0.52, 0.18, 0.52])
            )
        ])
        return mesh
    }
}
