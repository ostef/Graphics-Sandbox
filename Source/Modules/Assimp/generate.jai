// Assimp 6.0.4
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
    "-DBUILD_SHARED_LIBS=ON",
    "-DASSIMP_BUILD_SAMPLES=OFF",
    "-DASSIMP_BUILD_TESTS=OFF",
    "-DASSIMP_BUILD_ASSIMP_VIEW=OFF",
    "-DASSIMP_INSTALL=OFF",
    "-DASSIMP_IGNORE_GIT_HASH=ON",
];

#run {
    #import "Compiler";

    set_build_options_dc(.{do_output = false});

    compile_source := false;

    args := get_build_options().compile_time_command_line;
    for args {
        if it == {
        case "build";
            compile_source = true;
        }
    }

    if compile_source {
        if !BuildAssimp() {
            compiler_set_workspace_status(.FAILED);
            return;
        }
    }

    if !GenerateBindings() {
        compiler_set_workspace_status(.FAILED);
        return;
    }
}

BuildAssimp :: () -> bool {
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

        if run_command(..cmd).exit_code != 0 {
            return false;
        }

        if run_command("cmake", "--build", ".build").exit_code != 0 {
            return false;
        }
    }

    ok := true;

    delete_directory("Headers");
    ok &= make_directory_if_it_does_not_exist("Headers/assimp", recursive=true);
    ok &= make_directory_if_it_does_not_exist("Headers/assimp/Compiler", recursive=true);

    ok &= copy_file("Source/include/assimp/types.h", "Headers/assimp/types.h");
    ok &= copy_file("Source/include/assimp/quaternion.h", "Headers/assimp/quaternion.h");
    ok &= copy_file("Source/include/assimp/quaternion.inl", "Headers/assimp/quaternion.inl");
    ok &= copy_file("Source/include/assimp/vector2.h", "Headers/assimp/vector2.h");
    ok &= copy_file("Source/include/assimp/vector2.inl", "Headers/assimp/vector2.inl");
    ok &= copy_file("Source/include/assimp/vector3.h", "Headers/assimp/vector3.h");
    ok &= copy_file("Source/include/assimp/vector3.inl", "Headers/assimp/vector3.inl");
    ok &= copy_file("Source/include/assimp/matrix3x3.h", "Headers/assimp/matrix3x3.h");
    ok &= copy_file("Source/include/assimp/matrix3x3.inl", "Headers/assimp/matrix3x3.inl");
    ok &= copy_file("Source/include/assimp/matrix4x4.h", "Headers/assimp/matrix4x4.h");
    ok &= copy_file("Source/include/assimp/matrix4x4.inl", "Headers/assimp/matrix4x4.inl");
    ok &= copy_file("Source/include/assimp/color4.h", "Headers/assimp/color4.h");
    ok &= copy_file("Source/include/assimp/color4.inl", "Headers/assimp/color4.inl");
    ok &= copy_file("Source/include/assimp/aabb.h", "Headers/assimp/aabb.h");
    ok &= copy_file("Source/include/assimp/defs.h", "Headers/assimp/defs.h");
    ok &= copy_file("Source/include/assimp/metadata.h", "Headers/assimp/metadata.h");
    ok &= copy_file("Source/include/assimp/light.h", "Headers/assimp/light.h");
    ok &= copy_file("Source/include/assimp/material.h", "Headers/assimp/material.h");
    ok &= copy_file("Source/include/assimp/texture.h", "Headers/assimp/texture.h");
    ok &= copy_file("Source/include/assimp/mesh.h", "Headers/assimp/mesh.h");
    ok &= copy_file("Source/include/assimp/anim.h", "Headers/assimp/anim.h");
    ok &= copy_file("Source/include/assimp/camera.h", "Headers/assimp/camera.h");
    ok &= copy_file("Source/include/assimp/scene.h", "Headers/assimp/scene.h");
    ok &= copy_file("Source/include/assimp/importerdesc.h", "Headers/assimp/importerdesc.h");
    ok &= copy_file("Source/include/assimp/postprocess.h", "Headers/assimp/postprocess.h");
    ok &= copy_file("Source/include/assimp/version.h", "Headers/assimp/version.h");
    ok &= copy_file("Source/include/assimp/cfileio.h", "Headers/assimp/cfileio.h");
    ok &= copy_file("Source/include/assimp/cexport.h", "Headers/assimp/cexport.h");
    ok &= copy_file("Source/include/assimp/cimport.h", "Headers/assimp/cimport.h");
    ok &= copy_file("Source/include/assimp/cimport.h", "Headers/assimp/cimport.h");
    ok &= copy_file("Source/include/assimp/Compiler/pushpack1.h", "Headers/assimp/Compiler/pushpack1.h");
    ok &= copy_file("Source/include/assimp/Compiler/poppack1.h", "Headers/assimp/Compiler/poppack1.h");
    ok &= copy_file("Source/include/assimp/Compiler/pstdint.h", "Headers/assimp/Compiler/pstdint.h");
    ok &= copy_file("Source/.build/include/assimp/config.h", "Headers/assimp/config.h");
    ok &= copy_file("Source/.build/include/assimp/revision.h", "Headers/assimp/revision.h");

    #if OS == .WINDOWS {
        delete_directory("Libs/Windows");
        ok &= make_directory_if_it_does_not_exist("Libs/Windows", recursive=true);

        ok &= copy_file("Source/.build/bin/Debug/assimp-vc143-mtd.pdb", "Libs/Windows/assimp-vc143-mtd.pdb");
        ok &= copy_file("Source/.build/bin/Debug/assimp-vc143-mtd.dll", "Libs/Windows/assimp-vc143-mtd.dll");
        ok &= copy_file("Source/.build/lib/Debug/assimp-vc143-mtd.lib", "Libs/Windows/assimp-vc143-mtd.lib");
    } else #if OS == .LINUX {
        make_directory_if_it_does_not_exist("Lib/Linux", recursive=true);

        #assert false "@Todo";
    } else {
        #assert false "@Todo";
    }

    return ok;
}

GenerateBindings :: () -> bool {
    #if OS == .WINDOWS {
        output_filename := "assimp_windows.jai";
    } else #if OS == .LINUX {
        output_filename := "assimp_linux.jai";
    } else #if OS == .MACOS {
        output_filename := "assimp_macos.jai";
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

    array_add(*opts.libraries, Library.{filename="assimp-vc143-mtd", identifier="Assimp"});
    array_add(*opts.include_paths, "Headers");

    array_add(*opts.source_files, "Headers/assimp/types.h");
    array_add(*opts.source_files, "Headers/assimp/quaternion.h");
    array_add(*opts.source_files, "Headers/assimp/vector2.h");
    array_add(*opts.source_files, "Headers/assimp/vector3.h");
    array_add(*opts.source_files, "Headers/assimp/matrix3x3.h");
    array_add(*opts.source_files, "Headers/assimp/matrix4x4.h");
    array_add(*opts.source_files, "Headers/assimp/aabb.h");
    array_add(*opts.source_files, "Headers/assimp/color4.h");
    array_add(*opts.source_files, "Headers/assimp/defs.h");
    array_add(*opts.source_files, "Headers/assimp/metadata.h");
    array_add(*opts.source_files, "Headers/assimp/light.h");
    array_add(*opts.source_files, "Headers/assimp/material.h");
    array_add(*opts.source_files, "Headers/assimp/texture.h");
    array_add(*opts.source_files, "Headers/assimp/mesh.h");
    array_add(*opts.source_files, "Headers/assimp/anim.h");
    array_add(*opts.source_files, "Headers/assimp/camera.h");
    array_add(*opts.source_files, "Headers/assimp/scene.h");
    array_add(*opts.source_files, "Headers/assimp/postprocess.h");
    array_add(*opts.source_files, "Headers/assimp/version.h");
    array_add(*opts.source_files, "Headers/assimp/cfileio.h");
    array_add(*opts.source_files, "Headers/assimp/cexport.h");
    array_add(*opts.source_files, "Headers/assimp/cimport.h");
    array_add(*opts.source_files, "Headers/assimp/config.h");
    array_add(*opts.source_files, "Headers/assimp/revision.h");

    opts.generate_compile_time_struct_checks = false;
    // opts.strip_flags |= .INLINED_FUNCTIONS;

    return generate_bindings(opts, output_filename);
}
