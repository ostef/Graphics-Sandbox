ForwardPassBindingSet :: struct {
    viewpoint : GfxBindingUniformBuffer; @Binding(0) @VertexStage @FragmentStage
} @BindingSet

MeshBindingSet :: struct {
    mesh_instances : GfxBindingStorageBuffer; @Binding(0) @VertexStage @FragmentStage
} @BindingSet

FrameInfo :: struct {
    time : float;
    frame_index : u32;
} @ShaderType

Viewpoint :: struct {
    position : Vec3f;
    direction : Vec3f;
    right : Vec3f;
    up : Vec3f;
    transform : Mat4f;
    view : Mat4f;
    projection : Mat4f;
    inv_projection : Mat4f;
    view_projection : Mat4f;
    inv_view_projection : Mat4f;
    viewport_size : Vec2f;
    fov : float;
    z_near : float;
    z_far : float;
} @ShaderType

MakeViewpoint :: (camera : *Camera) -> Viewpoint {
    view_projection := camera.projection * camera.view;
    w, h := GetWindowPixelSize(g_window);

    viewpoint : Viewpoint;
    viewpoint.position = TranslationVector(camera.transform);
    viewpoint.direction = ForwardVector(camera.transform);
    viewpoint.right = RightVector(camera.transform);
    viewpoint.up = UpVector(camera.transform);
    viewpoint.transform = camera.transform;
    viewpoint.view = camera.view;
    viewpoint.projection = camera.projection;
    viewpoint.inv_projection = camera.inv_projection;
    viewpoint.view_projection = view_projection;
    viewpoint.inv_view_projection = Inverse(view_projection);
    viewpoint.fov = ToRads(camera.fov_in_degrees);
    viewpoint.z_near = camera.z_near;
    viewpoint.z_far = camera.z_far;
    viewpoint.viewport_size = .{xx w, xx h};

    return viewpoint;
}

MeshInstance :: struct {
    transform : Mat4f;
    normal_transform : Mat3f;
} @ShaderType

g_forward_pass_pipeline : GfxGraphicsPipeline;

InitForwardPassPipeline :: () {
    desc : GfxGraphicsPipelineDesc;
    desc.vertex_shader = GetVertexShader("mesh_geometry");
    desc.fragment_shader = GetFragmentShader("opaque_shading");

    desc.vertex_input = MakeVertexInputDesc(StaticVertex, 0);
    desc.layout.binding_sets = .[
        g_binding_set_layouts.FrameBindingSet,
        g_binding_set_layouts.ForwardPassBindingSet,
        g_binding_set_layouts.MeshBindingSet,
    ];

    desc.depth_state = .{test_enabled=true, write_enabled=true, compare_op=Depth_Compare_Op};

    desc.num_color_attachments = 1;
    desc.color_formats[0] = .RGBA8UNorm;
    desc.depth_format = .Depth32Float;
    CreateGfxGraphicsPipeline(*g_forward_pass_pipeline, "Forward Pass", desc);
}

ForwardPass :: (cmd_buffer : *GfxCommandBuffer, world : *World, camera : *Camera) {
    if IsNull(*g_forward_pass_pipeline) {
        InitForwardPassPipeline();
    }

    viewpoint := MakeViewpoint(camera);
    viewpoint_offset, viewpoint_size := AllocAndPackUniformFrameData(viewpoint);

    pass_bindings := ForwardPassBindingSet.{
        viewpoint=.{buffer=FrameDataBuffer(), offset=xx viewpoint_offset, size=xx viewpoint_size},
    };
    pass_binding_set := CreateGfxBindingSet(GlobalBindingSetAllocator(), pass_bindings);

    num_meshes : u64 = xx world.Mesh_entities.count;
    meshes_size := GLSLStd430Size(MeshInstance) * num_meshes;
    meshes_offset, meshes_ptr := AllocFrameData(meshes_size);
    for world.Mesh_entities {
        instance : MeshInstance = ---;
        instance.transform = it.world_transform;
        instance.normal_transform = ToMat3f(Transposed(Inverse(it.world_transform)));

        PackToGLSLStd(instance, meshes_ptr, .Std430);
        meshes_ptr += GLSLStd430Size(MeshInstance);
    }

    meshes_bindings := MeshBindingSet.{
        mesh_instances=.{buffer=FrameDataBuffer(), offset=xx meshes_offset, size=xx meshes_size},
    };
    meshes_binding_set := CreateGfxBindingSet(GlobalBindingSetAllocator(), meshes_bindings);

    w, h := viewpoint.viewport_size.x, viewpoint.viewport_size.y;

    pass_desc : GfxRenderPassDesc;
    AddColorAttachment(*pass_desc, *g_final_texture);
    AddDepthAttachment(*pass_desc, *g_depth_texture);
    ClearColor(*pass_desc, 0, Vec4f.{0,0,0,1});
    ClearDepth(*pass_desc, Depth_Clear);

    pass := BeginGfxRenderPass(cmd_buffer, "Forward Pass", pass_desc);
    {
        SetViewport(*pass, .{width=xx w, height=xx h});
        SetScissor(*pass, .{w=xx w, h=xx h});

        BindGraphicsPipeline(*pass, *g_forward_pass_pipeline);
        BindGraphicsBindingSet(*pass, 1, *pass_binding_set);
        BindGraphicsBindingSet(*pass, 2, *meshes_binding_set);

        base_instance : u32 = 0;
        for world.Mesh_entities {
            defer base_instance += 1;

            if !it.mesh {
                continue;
            }

            if IsNull(*it.mesh.vertex_buffer) {
                continue;
            }

            BindVertexBuffer(*pass, 0, *it.mesh.vertex_buffer);

            if !IsNull(*it.mesh.index_buffer) {
                BindIndexBuffer(*pass, .UInt32, *it.mesh.index_buffer);
                DrawIndexed(*pass, it.mesh.index_count, 1, base_instance=base_instance);
            } else {
                Draw(*pass, it.mesh.vertex_count, 1, base_instance=base_instance);
            }
        }
    }
    EndGfxRenderPass(*pass);
}
