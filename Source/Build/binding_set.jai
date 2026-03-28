#scope_file

g_shader_binding_set_types : [..]*Type_Info_Struct;
g_generated_binding_set_code : bool;

#scope_export

AddBindingSetType :: (workspace : Workspace, decl : *Code_Declaration) {
    location := make_location(decl);

    struct_type : *Type_Info_Struct;
    if decl.expression && decl.expression.kind == .STRUCT {
        struct_type = cast(*Code_Struct, decl.expression).defined_type;
    }

    if struct_type {
        ArrayPushUnique(*g_shader_binding_set_types, struct_type);
    } else {
        compiler_report(
            "Adding binding set type but declaration is not a struct.",
            location
        );
    }
}

GenerateBindingSetCode :: (workspace : Workspace) {
    if g_generated_binding_set_code {
        return;
    }

    defer g_generated_binding_set_code = true;

    builder : StringBuilder;

    Appendln(*builder, "Shader_Binding_Set_Types :: Type.[");
    for g_shader_binding_set_types {
        Appendln(*builder, "    %,", it.name);
    }
    Appendln(*builder, "];");

    add_build_string(StringBuilderBuild(*builder), workspace);

    LogMessage("Generated binding set code");
}
