GfxShader :: struct {
    module : VkShaderModule;
}

IsNull :: inline (shader : *GfxShader) -> bool {
    return shader == null || shader.module == VK_NULL_HANDLE;
} @NoProfile

// @Todo: integrate libshaderc instead of launching a child process
LoadGfxShader :: (name : string, extra_compiler_args : []string = .[], dependencies : *[..]string = null) -> GfxShader {
    #import "Process";

    stage := ifx StringEndsWith(name, ".vert")
        then "vert"
        else ifx StringEndsWith(name, ".frag")
        then "frag"
        else ifx StringEndsWith(name, ".comp")
        then "comp";

    if !stage {
        LogError("Could not detect shader stage for shader '%'", name);
        return .{};
    }

    stage_define := ifx stage == "vert"
        then "SHADER_STAGE_VERTEX"
        else ifx stage == "frag"
        then "SHADER_STAGE_FRAGMENT"
        else ifx stage == "comp"
        then "SHADER_STAGE_COMPUTE";

    filename := TPrint("Shaders/%.glsl", name);
    output_filename := TPrint("Shaders/%.spv", name);

    args : [..]string;
    args.allocator = Temp;
    ArrayPush(*args, "glslc");
    ArrayPush(*args, "-g");
    ArrayPush(*args, "-std=460");
    ArrayPush(*args, "--target-env=vulkan1.3");
    ArrayPush(*args, TPrint("-fshader-stage=%", stage));
    ArrayPush(*args, TPrint("-D%", stage_define));
    ArrayPushMultiple(*args, extra_compiler_args);
    ArrayPush(*args, filename);

    ArrayPush(*args, TPrint("-o%", output_filename));

    result, stdout, stderr := run_command(..args, capture_and_return_output=true);

    defer {
        Free(stdout.data);
        Free(stderr.data);
    }

    if result.exit_code != 0 {
        LogError("Could not compile shader '%':\n%", filename, stderr);
        return .{};
    }

    if dependencies {
        ArrayPop(*args);
        ArrayPush(*args, "-M");

        _, stdout, stderr := run_command(..args, capture_and_return_output=true);
        defer Free(stdout.data);
        defer Free(stderr.data);

        dependencies_str := stdout;
        colon_index := find_index_from_left(dependencies_str, ":");
        if colon_index >= 0 {
            dependencies_str = StringAdvance(dependencies_str, colon_index + 1);
        }

        splits := split(dependencies_str, " " ,, Temp);
        for splits {
            if it.count <= 0 {
                continue;
            }

            dep := trim(it);
            dep = get_absolute_path(dep ,, Temp);
            path_overwrite_separators(dep, #char "/");

            ArrayPush(dependencies, StringClone(dep));
        }
    }

    code, ok := read_entire_file(output_filename);
    if !ok {
        LogError("Could not read file '%'", output_filename);
        return .{};
    }

    defer Free(code.data);

    create_info : VkShaderModuleCreateInfo;
    create_info.sType = .SHADER_MODULE_CREATE_INFO;
    create_info.codeSize = xx code.count;
    create_info.pCode = cast(*u32, code.data);

    module : VkShaderModule;
    if vkCreateShaderModule(g_gfx_context.device, *create_info, g_vk_alloc_callbacks, *module) != .SUCCESS {
        LogError("Could not create shader module");
        return .{};
    }

    SetDebugName(module, TPrint("Shader '%'", name));

    return .{module=module};
}

DestroyGfxShader :: (shader : *GfxShader) {
    vkDestroyShaderModule(g_gfx_context.device, shader.module, g_vk_alloc_callbacks);
    shader.* = .{};
}
