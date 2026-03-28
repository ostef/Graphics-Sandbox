#load "shader.jai";
#load "binding_set.jai";
#load "allocator.jai";
#load "glsl_packing.jai";
#load "imgui.jai";

Reverse_Depth_Range :: true;

#if Reverse_Depth_Range {
    Depth_Compare_Op :: GfxCompareOp.GreaterEqual;
    Depth_Clear :: 0.0;
} else {
    Depth_Compare_Op :: GfxCompareOp.LessEqual;
    Depth_Clear :: 1.0;
}

g_final_texture : GfxTexture;

g_linear_clamp_sampler : GfxSampler;
g_nearest_clamp_sampler : GfxSampler;

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
}

ShutdownRenderer :: () {
    WaitForGPUIdle();

    DestroyGfxSampler(*g_linear_clamp_sampler);
    DestroyGfxSampler(*g_nearest_clamp_sampler);

    DestroyImGuiRenderer();

    for g_graphics_pipelines {
        DestroyGfxGraphicsPipeline(it);
    }
    ArrayFree(*g_graphics_pipelines);

    for g_compute_pipelines {
        DestroyGfxComputePipeline(it);
    }
    ArrayFree(*g_compute_pipelines);

    DestroyRenderTargets();

    DestroyAllShaders();
}

DestroyRenderTargets :: () {
    DestroyGfxTexture(*g_final_texture);
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
}

RenderFrame :: () {
    BeginGfxFrame();

    ProfilerBeginFrame(*g_gpu_frame_profiler);

    ResetFrameDataAllocator();
    ResetBindingSetAllocators();

    cmd_buffer := CreateGfxCommandBuffer("Main");

    AddTextureBarrier(*cmd_buffer, .Undefined, .ColorAttachment, *g_final_texture);

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
