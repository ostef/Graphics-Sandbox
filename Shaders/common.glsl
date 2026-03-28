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

#endif // COMMON_GLSL
