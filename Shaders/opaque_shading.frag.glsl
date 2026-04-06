#include "common.glsl"

DECLARE_PER_FRAME_PARAMS();
DECLARE_FORWARD_PASS_PARAMS();
DECLARE_PER_DRAW_CALL_MESH_PARAMS();

layout(location=0) in float3 in_viewpoint_position;
layout(location=1) in float3 in_position;
layout(location=2) in float3 in_normal;
layout(location=3) in float3 in_tangent;
layout(location=4) in float3 in_bitangent;
layout(location=5) in float2 in_tex_coords;
layout(location=6) in float4 in_color;

layout(location=0) out float4 out_color;

void main() {
    out_color = float4(in_position,1);
}
