// meshoptimizer 1.1
// To compile do `jai generate.jai - build` or do it manually:
// > cd Source
// > cmake -B .build [options..]
// > cmake --build .build

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Process";
#import "Bindings_Generator";

#if OS != .WINDOWS && OS != .LINUX && OS != .MACOS {
    #assert false "Only Windows, Linux and MacOS are supported for now.";
}

CMake_Options :: string.[
];

#run {
    #import "Compiler";

    set_build_options_dc(.{do_output = false});

    compile_source := false;

    build_config := "RelWithDebInfo";
    args := get_build_options().compile_time_command_line;
    index := 0;
    while index < args.count {
        defer index += 1;

        if args[index] == {
        case "build";
            compile_source = true;

        case "config";
            index += 1;

            if index == args.count {
                log_error("Missing parameter for 'config'");
                compiler_set_workspace_status(.FAILED);
                return;
            }

            build_config = args[index];
        }
    }

    if compile_source {
        if !BuildMeshoptimizer(build_config) {
            compiler_set_workspace_status(.FAILED);
            return;
        }
    }

    if !GenerateBindings(build_config) {
        compiler_set_workspace_status(.FAILED);
        return;
    }
}

BuildMeshoptimizer :: (config : string) -> bool {
    if config == {
    case "Debug";
    case "Release";
    case "MinSizeRel";
    case "RelWithDebInfo";
    case;
        log_error("Invalid config '%'", config);
        return false;
    }

    release := config != "Debug";

    {
        working_dir := get_working_directory();
        defer set_working_directory(working_dir);

        if !set_working_directory(tprint("%/Source", working_dir)) {
            return false;
        }

        if run_command("rm", "-rf", ".build").exit_code != 0 {
            return false;
        }

        cmd : [..]string;
        array_add(*cmd, "cmake");
        array_add(*cmd, "-B");
        array_add(*cmd, ".build");
        for CMake_Options {
            array_add(*cmd, it);
        }

        array_add(*cmd, tprint("-DCMAKE_BUILD_TYPE=%", config));

        if run_command(..cmd).exit_code != 0 {
            return false;
        }

        if run_command("cmake", "--build", ".build", "--config", config).exit_code != 0 {
            return false;
        }
    }

    ok := true;

    #if OS == .WINDOWS {
        delete_directory("Libs/Windows");
        ok &= make_directory_if_it_does_not_exist("Libs/Windows", recursive=true);

        ok &= copy_file(tprint("Source/.build/%/meshoptimizer.lib", config), "Libs/Windows/meshoptimizer.lib");
    } else #if OS == .LINUX {
        delete_directory("Libs/Linux");
        make_directory_if_it_does_not_exist("Lib/Linux", recursive=true);

        #assert false "@Todo";
    } else {
        #assert false "@Todo";
    }

    return ok;
}

GenerateBindings :: (config : string) -> bool {
    if config == {
    case "Debug";
    case "Release";
    case "MinSizeRel";
    case "RelWithDebInfo";
    case;
        log_error("Invalid config '%'", config);
        return false;
    }

    #if OS == .WINDOWS {
        output_filename := "meshoptimizer_windows.jai";
    } else #if OS == .LINUX {
        output_filename := "meshoptimizer_linux.jai";
    } else #if OS == .MACOS {
        output_filename := "meshoptimizer_macos.jai";
    }

    opts : Generate_Bindings_Options;
    // opts.generate_library_declarations = false;

    #if OS == .WINDOWS {
        array_add(*opts.library_search_paths, "Libs/Windows");
    } else #if OS == .LINUX {
        array_add(*opts.library_search_paths, "Libs/Linux");
    } else #if OS == .MACOS {
        array_add(*opts.library_search_paths, "Libs/MacOS");
    }

    array_add(*opts.libraries, Library.{filename="meshoptimizer", identifier="meshoptimizer"});
    array_add(*opts.include_paths, "Source/src");

    array_add(*opts.source_files, "Source/src/meshoptimizer.h");

    array_add(*opts.strip_prefixes, "meshopt");

    opts.generate_compile_time_struct_checks = false;
    // opts.strip_flags |= .INLINED_FUNCTIONS;

    return generate_bindings(opts, output_filename);
}
