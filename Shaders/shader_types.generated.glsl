// This file was auto generated

#ifndef SHADER_TYPES_GENERATED_GLSL
#define SHADER_TYPES_GENERATED_GLSL

struct FrameInfo {
    float time;
    uint frame_index;
};

struct Viewpoint {
    float3 position;
    float3 direction;
    float3 right;
    float3 up;
    float4x4 transform;
    float4x4 view;
    float4x4 projection;
    float4x4 inv_projection;
    float4x4 view_projection;
    float4x4 inv_view_projection;
    float2 viewport_size;
    float fov;
    float z_near;
    float z_far;
};

struct MeshInstance {
    float4x4 transform;
    float3x3 normal_transform;
};

#endif
