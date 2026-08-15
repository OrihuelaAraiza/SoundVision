#include <metal_stdlib>
using namespace metal;

struct EnergyRibbonParameters {
    float time;
    float intensity;
    uint segmentCount;
    uint ribbonCount;
};

struct EnergyRibbonVertex {
    float4 position;
    float4 normal;
};

kernel void updateEnergyRibbons(
    constant EnergyRibbonParameters &parameters [[buffer(0)]],
    device EnergyRibbonVertex *vertices [[buffer(1)]],
    uint vertexID [[thread_position_in_grid]]
) {
    const uint vertexCount = parameters.segmentCount * parameters.ribbonCount * 2;
    if (vertexID >= vertexCount) return;

    const uint ribbon = vertexID / (parameters.segmentCount * 2);
    const uint localVertex = vertexID % (parameters.segmentCount * 2);
    const uint segment = localVertex / 2;
    const uint side = localVertex % 2;

    const float tau = 6.28318530718;
    const float angle = (float(segment) / float(parameters.segmentCount)) * tau;
    const float ribbonPhase = float(ribbon) * 3.14159265359;
    const float phase = parameters.time * (0.42 + float(ribbon) * 0.07) + ribbonPhase;
    const float pulse = sin(angle * (3.0 + float(ribbon)) + phase) * (0.012 + parameters.intensity * 0.022);
    const float radius = 0.29 + float(ribbon) * 0.047 + pulse;
    const float wave = sin(angle * 2.0 - phase * 1.25) * (0.024 + parameters.intensity * 0.032);
    const float width = 0.006 + parameters.intensity * 0.009;
    const float sideOffset = side == 0 ? -width : width;

    const float3 position = float3(
        cos(angle) * radius,
        wave + (float(ribbon) - 0.5) * 0.025 + sideOffset,
        sin(angle) * radius
    );
    const float3 normal = normalize(float3(cos(angle), 0.28, sin(angle)));
    vertices[vertexID].position = float4(position, 1.0);
    vertices[vertexID].normal = float4(normal, 0.0);
}
