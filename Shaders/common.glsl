#ifndef COMMON_GLSL
#define COMMON_GLSL

#extension GL_EXT_shader_image_load_formatted : enable // Because GLSL sucks...
// We cannot pass image2D to functions unless this extension is enabled, because
// the GLSL spec does not handle it.

#define float2 vec2
#define float3 vec3
#define float4 vec4
#define float3x3 mat3
#define float4x4 mat4
#define double2 dvec2
#define double3 dvec3
#define double4 dvec4
#define double3x3 dmat3
#define double4x4 dmat4
#define int2 ivec2
#define int3 ivec3
#define int4 ivec4
#define uint2 uvec2
#define uint3 uvec3
#define uint4 uvec4

#include "shader_types.generated.glsl"

#define DECLARE_STATIC_VERTEX_ATTRIBUTES() \
    layout(location=0) in float3 in_position; \
    layout(location=1) in float3 in_normal; \
    layout(location=2) in float4 in_tangent; \
    layout(location=3) in float2 in_tex_coords; \
    layout(location=4) in float4 in_color

#define DECLARE_PER_FRAME_PARAMS() \
    layout(set=0, binding=0, std140) uniform FrameData { \
        FrameInfo u_frame_info; \
    }

#define DECLARE_FORWARD_PASS_PARAMS() \
    layout(set=1, binding=0) uniform ViewpointData { \
        Viewpoint u_viewpoint; \
    }

#define DECLARE_PER_DRAW_CALL_MESH_PARAMS() \
    layout(set=2, binding=0, std430) readonly buffer MeshData { \
        MeshInstance u_mesh_instances[]; \
    }

#define Pi 3.14159265359
#define Tau (Pi * 2)
#define To_Rads (Pi / 180.0)
#define To_Degs (180.0 / Pi)

#define lerp mix

float Acos(float x) {
    return acos(clamp(x, -1.0, 1.0));
}

float Asin(float x) {
    return asin(clamp(x, -1.0, 1.0));
}

#endif // COMMON_GLSL
