#include "common.glsl"

DECLARE_STATIC_VERTEX_ATTRIBUTES();

DECLARE_PER_FRAME_PARAMS();
DECLARE_FORWARD_PASS_PARAMS();
DECLARE_PER_DRAW_CALL_MESH_PARAMS();

layout(location=0) out float3 out_viewpoint_position;
layout(location=1) out float3 out_position;
layout(location=2) out float3 out_normal;
layout(location=3) out float3 out_tangent;
layout(location=4) out float3 out_bitangent;
layout(location=5) out float2 out_tex_coords;
layout(location=6) out float4 out_color;

void main() {
    MeshInstance mesh = u_mesh_instances[gl_InstanceIndex];

    float3 model_space_position = in_position;
    float3 model_space_normal   = in_normal;
    float3 model_space_tangent  = in_tangent.xyz;

    float3 world_space_position = (mesh.transform * float4(model_space_position, 1)).xyz;
    float3 world_space_normal = normalize(mesh.normal_transform * model_space_normal);
    float3 world_space_tangent = normalize(mesh.normal_transform * model_space_tangent);
    world_space_tangent = normalize(world_space_tangent - dot(world_space_tangent, world_space_normal) * world_space_normal);

    out_viewpoint_position = u_viewpoint.position;
    out_position = world_space_position;
    out_normal = world_space_normal;
    out_tangent = world_space_tangent;
    out_bitangent = -in_tangent.w * cross(out_normal, out_tangent);
    out_tex_coords = in_tex_coords;
    out_tex_coords.y = 1 - out_tex_coords.y;
    out_color = in_color;

    gl_Position = u_viewpoint.projection * u_viewpoint.view * float4(world_space_position, 1);
    gl_Position.y = -gl_Position.y;
}
