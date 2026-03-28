// @Todo: make sure the device supports timestamp queries
// @Todo: make this thread safe
// https://docs.vulkan.org/samples/latest/samples/api/timestamp_queries/README.html

GPUFrameProfiler :: struct {
    query_pools : [Gfx_Num_Frames_In_Flight]VkQueryPool;
    query_results : []u64;
    query_pool_capacity : u32;
    events_for_frame : [Gfx_Num_Frames_In_Flight][]GPUProfilingEvent;
    num_events_for_frame : [Gfx_Num_Frames_In_Flight]int;
    latest_frame : []GPUProfilingEvent;
    frame_index : int;

    current_event : *GPUProfilingEvent;
}

InitGPUFrameProfiler :: (profiler : *GPUFrameProfiler, max_events : int) {
    profiler.* = .{};

    pool_create_info : VkQueryPoolCreateInfo;
    pool_create_info.queryType = .TIMESTAMP;
    pool_create_info.queryCount = xx (max_events * 2);
    for * profiler.query_pools {
        result := vkCreateQueryPool(g_gfx_context.device, *pool_create_info, g_vk_alloc_callbacks, it);
        Assert(result == .SUCCESS, "Could not create query pool for GPU frame profiler");
    }

    profiler.query_results = AllocArray(u64, max_events * 2);

    profiler.query_pool_capacity = xx (max_events * 2);

    for * profiler.events_for_frame {
        it.* = AllocArray(GPUProfilingEvent, max_events);
    }

    profiler.latest_frame = AllocArray(GPUProfilingEvent, max_events);
    profiler.latest_frame.count = 0;
}

DestroyGPUFrameProfiler :: (profiler : *GPUFrameProfiler) {
    Free(profiler.latest_frame.data);

    for profiler.events_for_frame {
        Free(it.data);
    }

    Free(profiler.query_results.data);

    for profiler.query_pools {
        vkDestroyQueryPool(g_gfx_context.device, it, g_vk_alloc_callbacks);
    }

    profiler.* = .{};
}

ClearGPUFrameProfiler :: (profiler : *GPUFrameProfiler) {
    Assert(profiler.current_event == null, "Cannot clear GPU frame profiler while profiling is active");

    for * profiler.num_events_for_frame {
        it.* = 0;
    }

    profiler.latest_frame.count = 0;
}

ProfilerBeginFrame :: (profiler : *GPUFrameProfiler) {
    profiler.frame_index += 1;

    // Only query results starting at the third frame, because frames prior don't have anything
    if profiler.frame_index >= 3 {
        vkGetQueryPoolResults(g_gfx_context.device, profiler.query_pools[GetFrameInFlight()], 0, profiler.query_pool_capacity, profiler.query_pool_capacity * size_of(u64), profiler.query_results.data, size_of(u64), ._64_BIT);

        for * profiler.latest_frame {
            Free(it.name.data);
        }

        profiler.latest_frame.count = profiler.num_events_for_frame[GetFrameInFlight()];
        for * profiler.latest_frame {
            event := profiler.events_for_frame[GetFrameInFlight()][it_index];
            it.* = event;
            it.start_gpu_tick = profiler.query_results[it_index * 2 + 0];
            it.end_gpu_tick   = profiler.query_results[it_index * 2 + 1];
            it.elapsed_time_ms = (it.end_gpu_tick - it.start_gpu_tick) * GetGfxLimits().timestamp_tick_period / 1000000.0;
            if event.parent {
                it.parent = *profiler.latest_frame[event.parent.index];

                if !it.parent.first_child {
                    it.parent.first_child = it;
                }

                if it.parent.last_child {
                    it.parent.last_child.next_sibling = it;
                }

                it.parent.last_child = it;
            } else {
                it.parent = null;
                it.first_child = null;
                it.last_child = null;
                it.next_sibling = null;
            }
        }
    }

    vkResetQueryPool(g_gfx_context.device, profiler.query_pools[GetFrameInFlight()], 0, profiler.query_pool_capacity);

    profiler.num_events_for_frame[GetFrameInFlight()] = 0;
    profiler.current_event = null;
} @NoProfile

ProfilerBeginEvent :: (cmd_buffer : *GfxCommandBuffer, profiler : *GPUFrameProfiler, name : string, location := #caller_location) -> *GPUProfilingEvent {
    if profiler.num_events_for_frame[GetFrameInFlight()] >= profiler.events_for_frame[GetFrameInFlight()].count {
        return null;
    }

    event := *profiler.events_for_frame[GetFrameInFlight()][profiler.num_events_for_frame[GetFrameInFlight()]];
    event.* = .{};
    event.name = StringClone(name);
    event.index = profiler.num_events_for_frame[GetFrameInFlight()];
    event.parent = profiler.current_event;
    event.location = location;
    profiler.current_event = event;

    vkCmdWriteTimestamp(cmd_buffer.cmd_buffer, .TOP_OF_PIPE_BIT, profiler.query_pools[GetFrameInFlight()], xx (event.index * 2));
    profiler.num_events_for_frame[GetFrameInFlight()] += 1;

    return event;
} @NoProfile

ProfilerEndEvent :: (cmd_buffer : *GfxCommandBuffer, profiler : *GPUFrameProfiler, event : *GPUProfilingEvent) {
    if !event {
        return;
    }

    vkCmdWriteTimestamp(cmd_buffer.cmd_buffer, .BOTTOM_OF_PIPE_BIT, profiler.query_pools[GetFrameInFlight()], xx (event.index * 2 + 1));
    profiler.current_event = event.parent;
} @NoProfile
