#import "Vulkan";

#load "initialization.jai";
#load "buffer.jai";
#load "texture.jai";
#load "render_pass.jai";
#load "compute_pass.jai";
#load "copy_pass.jai";
#load "pipelines.jai";
#load "binding_set.jai";
#load "barriers.jai";
#load "profiler.jai";
#load "shader.jai";

Log_Vulkan :: Log_Section.{name="Graphics/Vulkan"};

Vulkan_Break_On_Error :: true;

Frame_Max_Wait :: Second_To_Nano * 4;

Gfx_Viewport_Origin_Bottom_Left :: false;

GfxContext :: struct {
    window : *SDL_Window;
    instance : VkInstance;
    debug_messenger : VkDebugUtilsMessengerEXT;
    surface : VkSurfaceKHR;
    physical_device : VkPhysicalDevice;
    device : VkDevice;
    general_purpose_queue_index : u32;
    present_queue_index : u32;
    general_purpose_queue : VkQueue;
    present_queue : VkQueue;
    swapchain : VkSwapchainKHR;
    swapchain_format : GfxPixelFormat;
    swapchain_extent : VkExtent2D;
    swapchain_textures : []GfxTexture;
    frame_command_pools : []GfxCommandPool;
    swapchain_image_acquired_semaphores : []VkSemaphore;
    swapchain_image_ready_for_present_semaphores : []VkSemaphore;
    frame_in_flight_fences : []VkFence;
    frame_in_flight : int;
    frame_index : int;
    frame_swapchain_image_index : u32;
    allocator : VmaAllocator;
    limits : GfxLimits;
    last_frame_statistics : GfxFrameStatistics;
    frame_statistics : GfxFrameStatistics;

    texture_view_collectors : [Gfx_Num_Frames_In_Flight]GfxGarbageCollector(GfxTexture);
    texture_collectors : [Gfx_Num_Frames_In_Flight]GfxGarbageCollector(GfxTexture);
    sampler_collectors : [Gfx_Num_Frames_In_Flight]GfxGarbageCollector(GfxSampler);
    buffer_collectors : [Gfx_Num_Frames_In_Flight]GfxGarbageCollector(GfxBuffer);

    command_buffers_to_submit : [..]VkCommandBuffer;

    vkSetDebugUtilsObjectNameEXT : PFN_vkSetDebugUtilsObjectNameEXT;
    vkCmdBeginDebugUtilsLabelEXT : PFN_vkCmdBeginDebugUtilsLabelEXT;
    vkCmdEndDebugUtilsLabelEXT : PFN_vkCmdEndDebugUtilsLabelEXT;
    vkQueueBeginDebugUtilsLabelEXT : PFN_vkQueueBeginDebugUtilsLabelEXT;
    vkQueueEndDebugUtilsLabelEXT : PFN_vkQueueEndDebugUtilsLabelEXT;
}

g_vk_alloc_callbacks : *VkAllocationCallbacks;

GetFrameInFlight :: inline () -> int {
    return g_gfx_context.frame_in_flight;
} @NoProfile

GetGfxLimits :: inline () -> GfxLimits {
    return g_gfx_context.limits;
} @NoProfile

GetGfxFrameStatistics :: () -> GfxFrameStatistics {
    return g_gfx_context.last_frame_statistics;
} @NoProfile

MakeGfxLimits :: inline (limits : VkPhysicalDeviceLimits) -> GfxLimits {
    result : GfxLimits;
    result.max_texture_1d_dimension = limits.maxImageDimension1D;
    result.max_texture_2d_dimension = limits.maxImageDimension2D;
    result.max_texture_3d_dimension = limits.maxImageDimension3D;
    result.max_texture_cube_dimension = limits.maxImageDimensionCube;
    result.max_texture_array_layers = limits.maxImageArrayLayers;
    result.max_memory_allocation_count = limits.maxMemoryAllocationCount;
    result.max_sampler_allocation_count = limits.maxSamplerAllocationCount;
    result.max_uniform_buffer_size = limits.maxUniformBufferRange;
    result.max_storage_buffer_size = limits.maxStorageBufferRange;
    result.uniform_buffer_offset_alignment = xx limits.minUniformBufferOffsetAlignment;
    result.storage_buffer_offset_alignment = xx limits.minStorageBufferOffsetAlignment;
    result.timestamp_tick_period = xx limits.timestampPeriod;

    return result;
} @NoProfile

BeginGfxFrame :: () {
    ctx := *g_gfx_context;

    ctx.last_frame_statistics = ctx.frame_statistics;
    ctx.frame_statistics = .{};

    ctx.frame_in_flight += 1;
    ctx.frame_in_flight %= Gfx_Num_Frames_In_Flight;
    ctx.frame_index += 1;

    {
        // ProfileBlock(*g_cpu_profiler, "WaitForFrameFence");

        wait_result := vkWaitForFences(ctx.device, 1, *ctx.frame_in_flight_fences[ctx.frame_in_flight], VK_TRUE, Frame_Max_Wait);
        Assert(wait_result == .SUCCESS, "vkWaitForFences failed: %", wait_result);
    }

    {
        // ProfileBlock(*g_cpu_profiler, "AcquireNextImage");

        while true {
            acquire_result := vkAcquireNextImageKHR(ctx.device, ctx.swapchain, Frame_Max_Wait, ctx.swapchain_image_acquired_semaphores[ctx.frame_in_flight], null, *ctx.frame_swapchain_image_index);

            // If we get SUBOPTIMAL_KHR then semaphore has been signaled so we cannot
            // ask again with the same semaphore.
            // Continue rendering as normal, we'll recreate the swapchain later
            if acquire_result == .SUBOPTIMAL_KHR || acquire_result == .SUCCESS {
                break;
            } else if acquire_result == .ERROR_OUT_OF_DATE_KHR {
                RecreateSwapchain();
            } else {
                Panic("vkAcquireNextImageKHR failed: %", acquire_result);
                break;
            }
        }
    }

    vkResetFences(ctx.device, 1, *ctx.frame_in_flight_fences[ctx.frame_in_flight]);

    cmd_pool := *ctx.frame_command_pools[ctx.frame_in_flight];
    ResetGfxCommandPool(cmd_pool);

    BeginGfxDebugMarker(TPrint("Frame %", ctx.frame_index));

    CollectGarbage(*ctx.texture_view_collectors[ctx.frame_in_flight]);
    CollectGarbage(*ctx.texture_collectors[ctx.frame_in_flight]);
    CollectGarbage(*ctx.sampler_collectors[ctx.frame_in_flight]);
    CollectGarbage(*ctx.buffer_collectors[ctx.frame_in_flight]);
}

SubmitGfxFrame :: () {
    ctx := *g_gfx_context;

    EndGfxDebugMarker();

    submit_stage_mask := VkPipelineStageFlags.COLOR_ATTACHMENT_OUTPUT_BIT;
    submit_info : VkSubmitInfo;
    submit_info.waitSemaphoreCount = 1;
    submit_info.pWaitSemaphores = *ctx.swapchain_image_acquired_semaphores[ctx.frame_in_flight];
    submit_info.pWaitDstStageMask = *submit_stage_mask;
    submit_info.signalSemaphoreCount = 1;
    submit_info.pSignalSemaphores = *ctx.swapchain_image_ready_for_present_semaphores[ctx.frame_swapchain_image_index];
    submit_info.commandBufferCount = xx ctx.command_buffers_to_submit.count;
    submit_info.pCommandBuffers = ctx.command_buffers_to_submit.data;
    vkQueueSubmit(ctx.general_purpose_queue, 1, *submit_info, ctx.frame_in_flight_fences[ctx.frame_in_flight]);

    ArrayClear(*ctx.command_buffers_to_submit);

    present_info : VkPresentInfoKHR;
    present_info.swapchainCount = 1;
    present_info.pSwapchains = *ctx.swapchain;
    present_info.waitSemaphoreCount = 1;
    present_info.pWaitSemaphores = *ctx.swapchain_image_ready_for_present_semaphores[ctx.frame_swapchain_image_index];
    present_info.pImageIndices = *ctx.frame_swapchain_image_index;
    present_result := vkQueuePresentKHR(ctx.present_queue, *present_info);
    if present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR {
        RecreateSwapchain();
    } else {
        Assert(present_result == .SUCCESS, "Failed to present swapchain image");
    }
}

WaitForGPUIdle :: () {
    vkDeviceWaitIdle(g_gfx_context.device);
} @Profile

GfxCommandPool :: struct {
    pool : VkCommandPool;
    free_cmd_buffers : [..]GfxCommandBuffer;
    used_cmd_buffers : [..]GfxCommandBuffer;
    name : string;
}

IsNull :: inline (pool : *GfxCommandPool) -> bool {
    return pool == null || pool.pool == VK_NULL_HANDLE;
} @NoProfile

CreateGfxCommandPool :: (name : string, panic_on_failure := true) -> GfxCommandPool {
    ctx := *g_gfx_context;

    pool_info : VkCommandPoolCreateInfo;
    pool_info.queueFamilyIndex = ctx.general_purpose_queue_index;

    pool : VkCommandPool;
    if vkCreateCommandPool(ctx.device, *pool_info, g_vk_alloc_callbacks, *pool) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create command pool '%'", name);
        }

        return .{};
    }

    SetDebugName(pool, TPrint("Command Pool '%'", name));

    return .{pool=pool, name=StringClone(name)};
}

DestroyGfxCommandPool :: (pool : *GfxCommandPool) {
    ArrayFree(*pool.free_cmd_buffers);
    ArrayFree(*pool.used_cmd_buffers);

    Free(pool.name.data);
    vkDestroyCommandPool(g_gfx_context.device, pool.pool, g_vk_alloc_callbacks);
    pool.* = .{};
}

ResetGfxCommandPool :: (pool : *GfxCommandPool) {
    for pool.used_cmd_buffers {
        ArrayPush(*pool.free_cmd_buffers, it);
    }

    ArrayClear(*pool.used_cmd_buffers);

    vkResetCommandPool(g_gfx_context.device, pool.pool, 0);
}

GfxCommandBuffer :: struct {
    cmd_buffer : VkCommandBuffer;
}

IsNull :: inline (cmd_buffer : *GfxCommandBuffer) -> bool {
    return cmd_buffer == null || cmd_buffer.cmd_buffer == VK_NULL_HANDLE;
} @NoProfile

CreateGfxCommandBuffer :: (name : string, panic_on_failure := true) -> GfxCommandBuffer {
    ctx := *g_gfx_context;
    pool := *ctx.frame_command_pools[ctx.frame_in_flight];

    if pool.free_cmd_buffers.count > 0 {
        cmd_buffer := pool.free_cmd_buffers[pool.free_cmd_buffers.count - 1];
        ArrayPop(*pool.free_cmd_buffers);
        ArrayPush(*pool.used_cmd_buffers, cmd_buffer);

        begin_info : VkCommandBufferBeginInfo;
        begin_info.flags = .ONE_TIME_SUBMIT_BIT;
        vkBeginCommandBuffer(cmd_buffer.cmd_buffer, *begin_info);

        SetDebugName(cmd_buffer.cmd_buffer, TPrint("Command Buffer '%'", name));

        return cmd_buffer;
    }

    create_info : VkCommandBufferAllocateInfo;
    create_info.commandPool = pool.pool;
    create_info.level = .PRIMARY;
    create_info.commandBufferCount = 1;

    cmd_buffer : VkCommandBuffer;
    if vkAllocateCommandBuffers(ctx.device, *create_info, *cmd_buffer) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create command buffer '%'", name);
        }

        return .{};
    }

    begin_info : VkCommandBufferBeginInfo;
    begin_info.flags = .ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd_buffer, *begin_info);

    SetDebugName(cmd_buffer, TPrint("Command Buffer '%'", name));

    result := GfxCommandBuffer.{cmd_buffer=cmd_buffer};

    ArrayPush(*pool.used_cmd_buffers, result);

    return result;
}

SubmitGfxCommandBuffer :: (cmd_buffer : *GfxCommandBuffer) {
    ctx := *g_gfx_context;

    vkEndCommandBuffer(cmd_buffer.cmd_buffer);
    ArrayPush(*ctx.command_buffers_to_submit, cmd_buffer.cmd_buffer);
}

BeginGfxDebugMarker :: (cmd_buffer : *GfxCommandBuffer, name : string) {
    LogSectionScope(*Log_Vulkan);

    if !g_gfx_context.vkCmdBeginDebugUtilsLabelEXT || !g_gfx_context.vkCmdEndDebugUtilsLabelEXT {
        return;
    }

    label : VkDebugUtilsLabelEXT;
    label.pLabelName = CStringClone(name ,, Temp);
    g_gfx_context.vkCmdBeginDebugUtilsLabelEXT(cmd_buffer.cmd_buffer, *label);
} @NoProfile

EndGfxDebugMarker :: (cmd_buffer : *GfxCommandBuffer) {
    LogSectionScope(*Log_Vulkan);

    if !g_gfx_context.vkCmdBeginDebugUtilsLabelEXT || !g_gfx_context.vkCmdEndDebugUtilsLabelEXT {
        return;
    }

    g_gfx_context.vkCmdEndDebugUtilsLabelEXT(cmd_buffer.cmd_buffer);
} @NoProfile

BeginGfxDebugMarker :: (name : string) {
    LogSectionScope(*Log_Vulkan);

    if !g_gfx_context.vkQueueBeginDebugUtilsLabelEXT || !g_gfx_context.vkQueueEndDebugUtilsLabelEXT {
        return;
    }

    label : VkDebugUtilsLabelEXT;
    label.pLabelName = CStringClone(name ,, Temp);
    g_gfx_context.vkQueueBeginDebugUtilsLabelEXT(g_gfx_context.general_purpose_queue, *label);
} @NoProfile

EndGfxDebugMarker :: () {
    LogSectionScope(*Log_Vulkan);

    if !g_gfx_context.vkQueueBeginDebugUtilsLabelEXT || !g_gfx_context.vkQueueEndDebugUtilsLabelEXT {
        return;
    }

    g_gfx_context.vkQueueEndDebugUtilsLabelEXT(g_gfx_context.general_purpose_queue);
} @NoProfile

SetDebugName :: (obj : $T, name : string) {
    ctx := *g_gfx_context;
    if !ctx.vkSetDebugUtilsObjectNameEXT {
        return;
    }

    Object_Types :: (struct{type : Type; vk_type : VkObjectType;}).[
        .{VkPhysicalDevice, .PHYSICAL_DEVICE},
        .{VkDevice, .DEVICE},
        .{VkQueue, .QUEUE},
        .{VkSemaphore, .SEMAPHORE},
        .{VkFence, .FENCE},
        .{VkBuffer, .BUFFER},
        .{VkBufferView, .BUFFER_VIEW},
        .{VkImage, .IMAGE},
        .{VkImageView, .IMAGE_VIEW},
        .{VkShaderModule, .SHADER_MODULE},
        .{VkPipelineCache, .PIPELINE_CACHE},
        .{VkPipelineLayout, .PIPELINE_LAYOUT},
        .{VkRenderPass, .RENDER_PASS},
        .{VkPipeline, .PIPELINE},
        .{VkDescriptorSetLayout, .DESCRIPTOR_SET_LAYOUT},
        .{VkSampler, .SAMPLER},
        .{VkDescriptorPool, .DESCRIPTOR_POOL},
        .{VkDescriptorSet, .DESCRIPTOR_SET},
        .{VkFramebuffer, .FRAMEBUFFER},
        .{VkCommandPool, .COMMAND_POOL},
        .{VkCommandBuffer, .COMMAND_BUFFER},
        .{VkSurfaceKHR, .SURFACE_KHR},
        .{VkSwapchainKHR, .SWAPCHAIN_KHR},
        .{VkDebugReportCallbackEXT, .DEBUG_REPORT_CALLBACK_EXT},
        .{VkDisplayKHR, .DISPLAY_KHR},
        .{VkDisplayModeKHR, .DISPLAY_MODE_KHR},
        .{VkValidationCacheEXT, .VALIDATION_CACHE_EXT},
    ];

    name_info : VkDebugUtilsObjectNameInfoEXT;
    name_info.objectType = #run -> VkObjectType {
        for Object_Types {
            if it.type == T {
                return it.vk_type;
            }
        }

        Panic("Unhandled object type %", T);
        return .UNKNOWN;
    }

    name_info.objectHandle = xx obj;
    name_info.pObjectName = CStringClone(name ,, Temp);
    ctx.vkSetDebugUtilsObjectNameEXT(ctx.device, *name_info);
} @NoProfile

VulkanDebugCallback :: (
    severity : VkDebugUtilsMessageSeverityFlagBitsEXT,
    type : VkDebugUtilsMessageTypeFlagsEXT,
    callback_data : *VkDebugUtilsMessengerCallbackDataEXT,
    user_data : *void
) -> VkBool32 #c_call {
    if callback_data.messageIdNumber == {
    case 0xc81ad50e; // WARNING-Shader-OutputNotConsumed
        return VK_FALSE;
    }

    ctx := cast(*#Context, user_data).*;
    push_context,defer_pop ctx;

    LogSectionScope(*Log_Vulkan);

    msg := MakeString(callback_data.pMessage);
    msg=, spec, verbose := MakeVulkanDebugMessageLessVerbose(msg);

    if verbose {
        LogMessage("messageId=0x%, %", FormatIntHex(callback_data.messageIdNumber), verbose, flags=.VERBOSE_ONLY);
    } else if callback_data.messageIdNumber != 0 {
        LogMessage("messageId=0x%", FormatIntHex(callback_data.messageIdNumber), flags=.VERBOSE_ONLY);
    }

    if severity & .ERROR_BIT_EXT {
        LogError("%\n%", msg, spec);
        #if Vulkan_Break_On_Error {
            Panic("Vulkan error");
        }
    } else if severity & .WARNING_BIT_EXT {
        LogWarning("%\n%", msg, spec);
    } else {
        LogMessage("%\n%", msg, spec);
    }

    return VK_FALSE;
}

MakeVulkanDebugMessageLessVerbose :: (msg : string) -> msg : string, spec : string, verbose : string {
    i := find_index_from_left(msg, "MessageID = 0x");
    if i < 0 {
        return msg, "", "";
    }

    result := StringAdvance(msg, i + "MessageID = 0x".count);
    _, _, result = Basic.string_to_int(result, base=16);
    result = StringAdvance(result, " | ".count);

    spec : string;

    i2 := find_index_from_left(result, "The Vulkan spec states: ");
    if i2 >= 0 {
        spec = StringAdvance(result, i2 + "The Vulkan spec states: ".count);
        result.count = i2;
    }

    verbose := msg;
    verbose.count = i;

    return result, spec, verbose;
}
