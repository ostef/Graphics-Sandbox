#load "shader.jai";
#load "binding_set.jai";
#load "allocator.jai";
#load "glsl_packing.jai";
#load "imgui.jai";
#load "forward_pass.jai";

Reverse_Depth_Range :: true;

#if Reverse_Depth_Range {
    Depth_Compare_Op :: GfxCompareOp.GreaterEqual;
    Depth_Clear :: 0.0;
} else {
    Depth_Compare_Op :: GfxCompareOp.LessEqual;
    Depth_Clear :: 1.0;
}

g_dummy_frame_pipeline_layout : GfxPipelineLayout; // Used to bind the per frame binding set outside of a pass

g_final_texture : GfxTexture;
g_hdr_color_texture : GfxTexture;
g_depth_texture : GfxTexture;

g_linear_clamp_sampler : GfxSampler;
g_nearest_clamp_sampler : GfxSampler;

FrameBindingSet :: struct {
    frame_info : GfxBindingUniformBuffer; @Binding(0) @VertexStage @FragmentStage
} @BindingSet

InitRenderer :: () {
    if !LoadAllShaders() {
        Basic.exit(1);
    }

    RecreateRenderTargets();

    InitFrameDataAllocators();

    InitBindingSetAllocators();

    CreateAllBindingSetLayouts();

    InitImGuiRenderer();

    sampler_desc : GfxSamplerDesc;
    sampler_desc.min_filter = .Linear;
    sampler_desc.mag_filter = .Linear;
    g_linear_clamp_sampler = CreateGfxSampler("Linear Clamp", sampler_desc);

    sampler_desc = .{};
    sampler_desc.min_filter = .Nearest;
    sampler_desc.mag_filter = .Nearest;
    g_nearest_clamp_sampler = CreateGfxSampler("Nearest Clamp", sampler_desc);

    frame_layout_desc : GfxPipelineLayoutDesc;
    frame_layout_desc.binding_sets = .[
        g_binding_set_layouts.FrameBindingSet,
    ];
    g_dummy_frame_pipeline_layout = CreateGfxPipelineLayout("Dummy Frame", frame_layout_desc);
}

ShutdownRenderer :: () {
    WaitForGPUIdle();

    DestroyGfxPipelineLayout(*g_dummy_frame_pipeline_layout);

    DestroyGfxSampler(*g_linear_clamp_sampler);
    DestroyGfxSampler(*g_nearest_clamp_sampler);

    DestroyImGuiRenderer();

    DestroyFrameDataAllocators();

    for g_graphics_pipelines {
        DestroyGfxGraphicsPipeline(it);
    }
    ArrayFree(*g_graphics_pipelines);

    for g_compute_pipelines {
        DestroyGfxComputePipeline(it);
    }
    ArrayFree(*g_compute_pipelines);

    DestroyRenderTargets();

    DestroyBindingSetAllocators();

    DestroyAllBindingSetLayouts();

    DestroyAllShaders();
}

DestroyRenderTargets :: () {
    DestroyGfxTexture(*g_final_texture);
    DestroyGfxTexture(*g_hdr_color_texture);
    DestroyGfxTexture(*g_depth_texture);
}

RecreateRenderTargets :: () {
    WaitForGPUIdle();

    DestroyRenderTargets();

    w, h := GetWindowPixelSize(g_window);

    desc : GfxTextureDesc;
    desc.type = .Texture2D;
    desc.width = xx w;
    desc.height = xx h;

    desc.pixel_format = .RGBA8UNorm;
    desc.usage = .ColorAttachment | .TransferSrc;
    g_final_texture = CreateGfxTexture("Final", desc);

    desc.pixel_format = .RGBA16Float;
    desc.usage = .ColorAttachment | .Sampled;
    g_hdr_color_texture = CreateGfxTexture("HDR Color", desc);

    desc.pixel_format = .Depth32Float;
    desc.usage = .DepthStencilAttachment;
    g_depth_texture = CreateGfxTexture("Depth", desc);
}

RenderFrame :: (world : *World, camera : *Camera) {
    BeginGfxFrame();

    ProfilerBeginFrame(*g_gpu_frame_profiler);

    ResetFrameDataAllocator();
    ResetBindingSetAllocators();

    cmd_buffer := CreateGfxCommandBuffer("Main");

    upload_pass := BeginGfxCopyPass(*cmd_buffer, "Upload");
        PerformPendingBufferUploads(*upload_pass);
    EndGfxCopyPass(*upload_pass);

    AddTextureBarriers(*cmd_buffer, .Undefined, .ColorAttachment, .[*g_final_texture, *g_hdr_color_texture]);

    frame_info := FrameInfo.{
        time=xx Basic.to_float64_seconds(Basic.current_time_monotonic()),
        frame_index=xx,no_check GetFrameIndex(),
    };
    frame_info_offset, frame_info_size := AllocAndPackUniformFrameData(frame_info);

    frame_bindings := FrameBindingSet.{
        frame_info=.{buffer=FrameDataBuffer(), offset=xx frame_info_offset, size=xx frame_info_size},
    };
    frame_binding_set := CreateGfxBindingSet(GlobalBindingSetAllocator(), frame_bindings);

    BindGraphicsBindingSet(*cmd_buffer, *g_dummy_frame_pipeline_layout, 0, *frame_binding_set);

    ForwardPass(*cmd_buffer, world, camera);
    ImGuiPass(*cmd_buffer, ImGui.GetDrawData());

    AddTextureBarrier(*cmd_buffer, .ColorAttachment, .TransferSrc, *g_final_texture);

    swapchain_texture := *g_gfx_context.swapchain_textures[g_gfx_context.frame_swapchain_image_index];
    AddTextureBarrier(*cmd_buffer, 0, 0, .AllGraphics, .AllWrites | .AllReads, .Undefined, .TransferDst, swapchain_texture);

    region : VkImageBlit;
    region.srcSubresource = MakeVkImageSubresourceLayers(g_final_texture.desc, 0);
    region.srcOffsets[1].x = xx g_final_texture.desc.width;
    region.srcOffsets[1].y = xx g_final_texture.desc.height;
    region.srcOffsets[1].z = 1;

    region.dstSubresource = MakeVkImageSubresourceLayers(swapchain_texture.desc, 0);
    region.dstOffsets[1].x = xx swapchain_texture.desc.width;
    region.dstOffsets[1].y = xx swapchain_texture.desc.height;
    region.dstOffsets[1].z = 1;

    vkCmdBlitImage(cmd_buffer.cmd_buffer, g_final_texture.image, .TRANSFER_SRC_OPTIMAL, swapchain_texture.image, .TRANSFER_DST_OPTIMAL, 1, *region, .LINEAR);

    AddTextureBarrier(*cmd_buffer, .AllGraphics, .AllWrites, 0, 0, .TransferDst, .PresentSrc, swapchain_texture);

    SubmitGfxCommandBuffer(*cmd_buffer);

    SubmitGfxFrame();
}
