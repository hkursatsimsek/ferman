#include <metal_stdlib>
using namespace metal;

// Single overhead lamp: light falls off from the lit center toward the sand
// edge (design brief §3.1 — "ışık tek yönlü ve yukarıdan").
[[ stitchable ]]
half4 sandTableLight(float2 position, half4 color, float2 size, half4 litColor, half4 shadowColor) {
    float2 center = float2(size.x * 0.5, size.y * 0.34);
    float2 radius = float2(max(size.x * 0.7, 1.0), max(size.y * 0.5, 1.0));
    float2 delta = (position - center) / radius;
    float t = clamp(length(delta), 0.0, 1.0);
    return mix(litColor, shadowColor, half(t));
}
