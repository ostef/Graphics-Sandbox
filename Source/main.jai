#import "Common";
#import "Linalg";
#import "Hash_Map";
#import "Type_Utils";

#import "SDL";
ImGui :: #import "ImGui";
ImGui_SDL :: #import "ImGui/Impl/SDL";

Basic :: #import "Basic";
using,only(.["+","-","*","/","<",">","=="]) Basic;
Math :: #import "Math";

#import "Compiler";
#import "String";
#import "File";
#import "File_Utilities";

#load "utils.jai";
#load "input.jai";
#load "abstraction_layer.jai";
#load "Renderer/renderer.jai";

g_console_logger : ConsoleLogger;

g_window : *SDL_Window;
g_quit := false;

g_gfx_context : GfxContext;

g_last_frame_start_time : Basic.Apollo_Time;
g_frame_times : [120]float;
g_frame_time_index : int;

g_avg_frame_time : float = 1 / 60.0;
g_min_frame_time : float = 1 / 60.0;
g_max_frame_time : float = 1 / 60.0;
g_last_frame_time : float = 1 / 60.0;

UpdateFrameTimes :: () {
    if g_last_frame_start_time != .{} {
        frame_end := Basic.current_time_monotonic();
        frame_time := Basic.to_float64_seconds(frame_end - g_last_frame_start_time);

        g_last_frame_time = xx frame_time;

        g_frame_times[g_frame_time_index] = xx frame_time;

        if g_frame_time_index == g_frame_times.count - 1 {
            g_frame_time_index = 0;

            min := F32_Inf;
            max := -F32_Inf;
            avg : float;
            for g_frame_times {
                min = Min(min, it);
                max = Max(max, it);
                avg += it;
            }

            avg /= g_frame_times.count;

            g_min_frame_time = min;
            g_max_frame_time = max;
            g_avg_frame_time = avg;
        } else {
            g_frame_time_index += 1;
        }
    };

    g_last_frame_start_time = Basic.current_time_monotonic();
}

main :: () {
    InitConsoleLogger(*g_console_logger);
    SetContextLogger(*g_console_logger, ConsoleLoggerProc);
    g_console_logger.print_stack_trace = false;

    window_flags := SDL_WINDOW_RESIZABLE;
    #if Gfx_Backend == .Vulkan {
        window_flags |= SDL_WINDOW_VULKAN;
    }

    g_window = SDL_CreateWindow("Graphics Sandbox", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1600, 900, window_flags);
    defer SDL_DestroyWindow(g_window);

    InitGfxContext(g_window);
    defer DestroyGfxContext();

    InitGPUFrameProfiler(*g_gpu_frame_profiler, 1000);
    defer DestroyGPUFrameProfiler(*g_gpu_frame_profiler);

    ImGui.CreateContext();
    defer ImGui.DestroyContext();

    ImGui_SDL.Init(g_window);
    defer ImGui_SDL.Terminate();

    InitRenderer();
    defer ShutdownRenderer();

    while !g_quit {
        UpdateFrameTimes();

        ResetTemporaryStorage();

        UpdateInputState();

        should_recreate_swapchain := false;
        event : SDL_Event;
        while SDL_PollEvent(*event) {
            if event.type == SDL_WINDOWEVENT {
                if event.window.event == SDL_WINDOWEVENT_RESIZED
                || event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED
                || event.window.event == SDL_WINDOWEVENT_MINIMIZED {
                    should_recreate_swapchain = true;
                }
            }

            if event.type == SDL_QUIT {
                g_quit = true;
            }

            HandleInputEvent(event);
            ImGui_SDL.HandleWindowEvent(event);
        }

        w, h := GetWindowPixelSize(g_window);

        if should_recreate_swapchain && w > 0 && h > 0 {
            RecreateSwapchain();
            RecreateRenderTargets();
        }

        ProcessShaderDirectoryChanges();

        ImGui_SDL.NewFrame();
        ImGui.NewFrame();
        ImGui.ShowDemoWindow();

        ImGui.Render();

        RenderFrame();

        if !(SDL_GetWindowFlags(g_window) & SDL_WINDOW_INPUT_FOCUS) {
            elapsed := g_last_frame_time;
            sleep_time := cast(s32, 1000 * (1 / 10.0 - elapsed));
            if sleep_time > 1 {
                Basic.sleep_milliseconds(sleep_time);
            }
        }
    }
}
