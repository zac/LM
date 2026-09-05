#include <metal_stdlib>
using namespace metal;

struct LunarMorphVertex {
    packed_float3 position;
    packed_float3 normal;
    packed_float3 tangent;
    packed_float3 bitangent;
    float2 uv;
};

kernel void lunarMorphVertices(device const float4 *a [[buffer(0)]],
                               device const float4 *b [[buffer(1)]],
                               device LunarMorphVertex *out [[buffer(2)]],
                               constant float &weight [[buffer(3)]],
                               constant uint &count [[buffer(4)]],
                               device const LunarMorphVertex *existing [[buffer(5)]],
                               uint i [[thread_position_in_grid]]) {
    if (i >= count) return;
    LunarMorphVertex v = existing[i];
    v.position.y = weight <= 0 ? a[i].w : (weight >= 1 ? b[i].w : fma(weight, b[i].w - a[i].w, a[i].w));
    v.normal = weight <= 0 ? a[i].xyz : (weight >= 1 ? b[i].xyz : a[i].xyz + (b[i].xyz - a[i].xyz) * weight);
    float3 n = normalize(float3(v.normal)), east = float3(0, 0, -1);
    v.tangent = normalize(east - n * dot(n, east));
    v.bitangent = cross(n, float3(v.tangent));
    out[i] = v;
}

// Affine maps take common tile UVs to each endpoint's existing texture UVs.
// Color sources are sRGB textures, so interpolation occurs in linear light.
kernel void lunarMorphAppearance(texture2d<float> aColor [[texture(0)]],
                                 texture2d<float> bColor [[texture(1)]],
                                 texture2d<float> aNormal [[texture(2)]],
                                 texture2d<float> bNormal [[texture(3)]],
                                 texture2d<float, access::write> color [[texture(4)]],
                                 texture2d<float, access::write> normal [[texture(5)]],
                                 constant float4 &aMap [[buffer(0)]],
                                 constant float4 &bMap [[buffer(1)]],
                                 constant float &weight [[buffer(2)]],
                                 uint2 p [[thread_position_in_grid]]) {
    if (p.x >= color.get_width() || p.y >= color.get_height()) return;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(p) + 0.5f) / float2(color.get_width(), color.get_height());
    float2 auv = uv * aMap.xy + aMap.zw, buv = uv * bMap.xy + bMap.zw;
    float4 ca = aColor.sample(s, auv, level(0)), cb = bColor.sample(s, buv, level(0));
    float3 na = aNormal.sample(s, auv, level(0)).xyz;
    float3 nb = bNormal.sample(s, buv, level(0)).xyz;
    // Preserve endpoint encoding exactly; normalizing at the endpoints would
    // alter the existing 8-bit normal-map quantization.
    float3 n = weight <= 0 ? na : (weight >= 1 ? nb :
        normalize(mix(na * 2 - 1, nb * 2 - 1, weight)) * 0.5f + 0.5f);
    // TextureResource.copy preserves the endpoint row order. RealityKit
    // applies the same mesh-UV convention to both texture resource kinds.
    uint2 destination = p;
    color.write(weight <= 0 ? ca : (weight >= 1 ? cb : mix(ca, cb, weight)), destination);
    normal.write(float4(n, 1), destination);
}
