#import "Common";
#import "String";
#import "File";
#import "File_Utilities";
#import "Compiler";
#import "Metaprogram_Plugins";
Basic :: #import "Basic";
using,only(.["+","-","*","/","<",">","=="]) Basic;

#load "Source/Build/binding_set.jai";
#load "Source/Build/shader_codegen.jai";

Bindings_To_Generate :: string.[
    "Source/Modules/ImGui",
    "Source/Modules/Vulkan",
    "Source/Modules/Assimp",
    "Source/Modules/meshoptimizer",
];

Default_Plugins :: string.[
];

HandleDeclaration :: (workspace : Workspace, decl : *Code_Declaration) {
    for note : decl.notes {
        if note.text == "BindingSet" {
            AddBindingSetType(workspace, decl);
        }
        if note.text == "ShaderType" {
            AddShaderType(decl);
        }
    }
}

HandleCompilerMessage :: (msg : *Message) {
    if msg.kind == {
    case .TYPECHECKED;
        typechecked := cast(*Message_Typechecked, msg);
        for typechecked.declarations {
            HandleDeclaration(msg.workspace, it.expression);
        }

    case .PHASE;
        phase := cast(*Message_Phase, msg);
        if phase.phase == .TYPECHECKED_ALL_WE_CAN {
            GenerateBindingSetCode(msg.workspace);
        }

    case .COMPLETE;
        // GenerateShaderCode();
    }
}

GenerateBindings :: (module_name : string, build : bool) {
    ws := compiler_create_workspace(module_name);

    options := get_build_options(ws);
    if build {
        options.compile_time_command_line = .["build"];
    }
    set_build_options(options, ws);

    compiler_begin_intercept(ws);

    add_build_file(SPrint("%/generate.jai", module_name), ws);

    working_dir := Basic.get_working_directory();
    defer Basic.set_working_directory(working_dir);

    Basic.set_working_directory(SPrint("%/%", working_dir, module_name));

    while true {
        msg := compiler_wait_for_message();
        if msg.workspace == ws && msg.kind == .COMPLETE {
            if cast(*Message_Complete, msg).error_code != .NONE {
                LogError("Could not generate bindings for %", module_name);
            } else {
                LogMessage("Generated bindings for %", module_name);
            }

            break;
        }
    }

    compiler_end_intercept(ws);
}

PrintUsage :: () {
    Println("Usage: % [default metaprogram option(s)] [- option(s)]", ifx OS == .WINDOWS then "Build" else "./Build.sh");
    Println("Valid options:");
    Println("  generate_bindings: (re)generate all bindings");
    Println("  build_bindings:    (re)generate all bindings after building their source code (simply passes build to the bindings' generate.jai)");
}

Build :: () {
    Log_Build :: Log_Section.{name="Build"};
    LogSectionScope(*Log_Build);

    console_logger : ConsoleLogger;
    InitConsoleLogger(*console_logger);
    SetContextLogger(*console_logger, ConsoleLoggerProc);

    generate_bindings : bool;
    build_bindings : bool;

    start_time := Basic.current_time_monotonic();
    defer {
        end_time := Basic.current_time_monotonic();
        total_time := end_time - start_time;
        Println("  Total time: % seconds", Basic.to_float64_seconds(total_time));
    }

    set_build_options_dc(.{do_output=false, write_added_strings=false});

    args := get_build_options().compile_time_command_line;

    success:, plugins_to_create:, args = parse_plugin_arguments(args);
    if !success {
        Basic.exit(1);
    }

    arg_index := 0;
    while arg_index < args.count {
        defer arg_index += 1;

        if args[arg_index] == {
        case "generate_bindings";
            generate_bindings = true;
        case "build_bindings";
            generate_bindings = true;
            build_bindings = true;
        case;
            LogError("Unknown argument '%'", args[arg_index]);
            PrintUsage();
            Basic.exit(1);
        }
    }

    if generate_bindings {
        for Bindings_To_Generate {
            GenerateBindings(it, build=build_bindings);
        }
    }

    compilation_failed := false;

    defer if compilation_failed {
        LogError("Compilation failed");
        Basic.exit(1);
    }

    ws := compiler_create_workspace("Graphics Sandbox");

    for Default_Plugins {
        ArrayPush(*plugins_to_create, .{name=it});
    }

    plugins : [..]*Metaprogram_Plugin;
    if !init_plugins(plugins_to_create, *plugins, ws) {
        LogError("A plugin failed to initialize");
        Basic.exit(1);
    }

    options := get_build_options(ws);
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "graphics";
    options.interactive_bytecode_debugger = get_build_options().interactive_bytecode_debugger;
    options.import_path = get_build_options().import_path;
    options.Commonly_Propagated = get_build_options().Commonly_Propagated;
    options.write_added_strings = true;
    options.stack_trace = true;
    options.text_output_flags = .OUTPUT_LINK_LINE;

    #if OS == .LINUX {
        #import "POSIX";

        options.additional_linker_arguments = .[
            TPrint("-L%/lib", MakeString(getenv("VULKAN_SDK"))),
        ];
    }

    set_build_options(options, ws);

    intercept_flags : Intercept_Flags;
    for plugins {
        if it.before_intercept {
            it.before_intercept(it, *intercept_flags);
        }
    }

    compiler_begin_intercept(ws, intercept_flags);

    add_build_file("Source/main.jai", ws);

    for plugins {
        if it.add_source {
            it.add_source(it);
        }
    }

    while true {
        msg := compiler_wait_for_message();

        for plugins {
            if it.message {
                it.message(it, msg);
            }
        }

        HandleCompilerMessage(msg);

        if msg.workspace == ws {
            if msg.kind == .COMPLETE {
                complete := cast(*Message_Complete, msg);
                if complete.error_code != .NONE {
                    compilation_failed = true;
                }

                break;
            }
        }
    }

    compiler_end_intercept(ws);

    for plugins {
        if it.finish {
            it.finish(it);
        }
    }

    for plugins {
        if it.shutdown {
            it.shutdown(it);
        }
    }

    if !compilation_failed {
        GenerateGLSLShaderCode();
    }

    #if OS == .WINDOWS {
        if !file_exists("ImGui.dll") {
            copy_file("Source/Modules/ImGui/Libs/Windows/ImGui.dll", "ImGui.dll");
        }

        if !file_exists("SDL2.dll") {
            copy_file("Source/Modules/SDL/Libs/Windows/SDL2.dll", "SDL2.dll");
        }

        if !file_exists("assimp-vc143-mt.dll") {
            copy_file("Source/Modules/Assimp/Libs/Windows/assimp-vc143-mt.dll", "assimp-vc143-mt.dll");
        }
    }
}

#run,stallable Build();
