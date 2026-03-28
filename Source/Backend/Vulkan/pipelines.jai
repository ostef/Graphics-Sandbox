// I don't like having this concept in the abstraction layer as I don't find this very useful.
// Currently it is needed so we can bind the global frame binding set at the beginning of the
// frame outside of any render passes (and without needing a full pipeline).
GfxPipelineLayout :: struct {
    layout : VkPipelineLayout;
    name : string;
}

IsNull :: inline (layout : *GfxPipelineLayout) -> bool {
    return layout == null || layout.layout == VK_NULL_HANDLE;
} @NoProfile

CreateGfxPipelineLayout :: (name : string, desc : GfxPipelineLayoutDesc, panic_on_failure := true) -> GfxPipelineLayout {
    LogSectionScope(*Log_Vulkan);

    layout_info : VkPipelineLayoutCreateInfo;
    layout_info.setLayoutCount = xx desc.binding_sets.count;
    layout_info.pSetLayouts = Alloc(VkDescriptorSetLayout, desc.binding_sets.count, initialize=true ,, Temp);
    for desc.binding_sets {
        layout_info.pSetLayouts[it_index] = it.layout;
    }

    layout : VkPipelineLayout;
    if vkCreatePipelineLayout(g_gfx_context.device, *layout_info, g_vk_alloc_callbacks, *layout) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create pipeline layout '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(layout, TPrint("Pipeline Layout '%'", name));

    return .{layout=layout, name=StringClone(name)};
}

DestroyGfxPipelineLayout :: (layout : *GfxPipelineLayout) {
    Free(layout.name.data);
    vkDestroyPipelineLayout(g_gfx_context.device, layout.layout, g_vk_alloc_callbacks);
    layout.* = .{};
}

GfxGraphicsPipeline :: struct {
    layout : GfxPipelineLayout;
    pipeline : VkPipeline;
    name : string;
    desc : GfxGraphicsPipelineDesc;
}

IsNull :: inline (pipeline : *GfxGraphicsPipeline) -> bool {
    return pipeline == null || pipeline.pipeline == VK_NULL_HANDLE || IsNull(*pipeline.layout);
} @NoProfile

CreateGfxGraphicsPipeline :: (name : string, desc : GfxGraphicsPipelineDesc, panic_on_failure := true) -> GfxGraphicsPipeline {
    LogSectionScope(*Log_Vulkan);

    layout := CreateGfxPipelineLayout(name, desc.layout, panic_on_failure);
    if IsNull(*layout) {
        return .{};
    }

    vertex_stage : VkPipelineShaderStageCreateInfo;
    vertex_stage.stage = .VERTEX_BIT;
    vertex_stage.pName = "main";
    vertex_stage.module = desc.vertex_shader.module;

    fragment_stage : VkPipelineShaderStageCreateInfo;
    if !IsNull(desc.fragment_shader) {
        fragment_stage.stage = .FRAGMENT_BIT;
        fragment_stage.pName = "main";
        fragment_stage.module = desc.fragment_shader.module;
    }

    shader_stages := VkPipelineShaderStageCreateInfo.[vertex_stage, fragment_stage];

    vertex_input_state : VkPipelineVertexInputStateCreateInfo;
    vertex_input_state.vertexBindingDescriptionCount = xx desc.vertex_input.buffer_bindings.count;
    vertex_input_state.pVertexBindingDescriptions = Alloc(VkVertexInputBindingDescription, desc.vertex_input.buffer_bindings.count, initialize=true ,, Temp);
    for desc.vertex_input.buffer_bindings {
        vertex_input_state.pVertexBindingDescriptions[it_index].binding = it.binding;
        vertex_input_state.pVertexBindingDescriptions[it_index].stride = it.stride;
        vertex_input_state.pVertexBindingDescriptions[it_index].inputRate = .VERTEX;
    }

    vertex_input_state.vertexAttributeDescriptionCount = xx desc.vertex_input.attributes.count;
    vertex_input_state.pVertexAttributeDescriptions = Alloc(VkVertexInputAttributeDescription, desc.vertex_input.attributes.count, initialize=true ,, Temp);
    for desc.vertex_input.attributes {
        vertex_input_state.pVertexAttributeDescriptions[it_index].location = it.location;
        vertex_input_state.pVertexAttributeDescriptions[it_index].binding = it.binding;
        vertex_input_state.pVertexAttributeDescriptions[it_index].format = MakeVkFormat(it.format, it.normalized);
        vertex_input_state.pVertexAttributeDescriptions[it_index].offset = it.offset;
    }

    input_assembly_state : VkPipelineInputAssemblyStateCreateInfo;
    if #complete desc.primitive_topology == {
    case .PointList;    input_assembly_state.topology = .POINT_LIST;
    case .LineList;     input_assembly_state.topology = .LINE_LIST;
    case .TriangleList; input_assembly_state.topology = .TRIANGLE_LIST;
    }

    dynamic_states := VkDynamicState.[.VIEWPORT, .SCISSOR, .BLEND_CONSTANTS, .STENCIL_REFERENCE];
    dynamic_state : VkPipelineDynamicStateCreateInfo;
    dynamic_state.dynamicStateCount = dynamic_states.count;
    dynamic_state.pDynamicStates = dynamic_states.data;

    viewport_state : VkPipelineViewportStateCreateInfo;
    viewport_state.viewportCount = 1;
    viewport_state.scissorCount = 1;

    rasterizer_state : VkPipelineRasterizationStateCreateInfo;
    if #complete desc.rasterizer_state.fill_mode == {
    case .Fill;  rasterizer_state.polygonMode = .FILL;
    case .Lines; rasterizer_state.polygonMode = .LINE;
    }

    rasterizer_state.lineWidth = 1;
    if #complete desc.rasterizer_state.cull_face == {
    case .None;  rasterizer_state.cullMode = 0;
    case .Front; rasterizer_state.cullMode = .FRONT_BIT;
    case .Back;  rasterizer_state.cullMode = .BACK_BIT;
    }

    if #complete desc.rasterizer_state.winding_order == {
    case .Clockwise;        rasterizer_state.frontFace = .CLOCKWISE;
    case .CounterClockwise; rasterizer_state.frontFace = .COUNTER_CLOCKWISE;
    }

    multisample_state : VkPipelineMultisampleStateCreateInfo;
    multisample_state.sampleShadingEnable = VK_FALSE;

    if desc.rasterizer_state.num_samples == {
    case 1;  multisample_state.rasterizationSamples = ._1_BIT;
    case 2;  multisample_state.rasterizationSamples = ._2_BIT;
    case 4;  multisample_state.rasterizationSamples = ._4_BIT;
    case 8;  multisample_state.rasterizationSamples = ._8_BIT;
    case 16; multisample_state.rasterizationSamples = ._16_BIT;
    case 32; multisample_state.rasterizationSamples = ._32_BIT;
    case 64; multisample_state.rasterizationSamples = ._64_BIT;
    case; Panic("Invalid sample count % for texture (expected 1, 2, 4, 8, 16, 32 or 64)", desc.rasterizer_state.num_samples);
    }

    blend_states : [Gfx_Max_Color_Attachments]VkPipelineColorBlendAttachmentState;
    for desc.blend_states {
        blend_states[it_index].colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT;
        blend_states[it_index].blendEnable = cast(VkBool32, it.enabled);
        blend_states[it_index].srcColorBlendFactor = MakeVkBlendFactor(it.src_color_factor);
        blend_states[it_index].dstColorBlendFactor = MakeVkBlendFactor(it.dst_color_factor);
        blend_states[it_index].srcAlphaBlendFactor = MakeVkBlendFactor(it.src_alpha_factor);
        blend_states[it_index].dstAlphaBlendFactor = MakeVkBlendFactor(it.dst_alpha_factor);
        blend_states[it_index].colorBlendOp = MakeVkBlendOp(it.color_op);
        blend_states[it_index].alphaBlendOp = MakeVkBlendOp(it.alpha_op);
    }

    blend_state : VkPipelineColorBlendStateCreateInfo;
    blend_state.attachmentCount = desc.num_color_attachments;
    blend_state.pAttachments = blend_states.data;

    depth_stencil_state : VkPipelineDepthStencilStateCreateInfo;
    depth_stencil_state.depthTestEnable = cast(VkBool32, desc.depth_state.test_enabled);
    depth_stencil_state.depthWriteEnable = cast(VkBool32, desc.depth_state.write_enabled);
    depth_stencil_state.depthCompareOp = MakeVkCompareOp(desc.depth_state.compare_op);
    depth_stencil_state.stencilTestEnable = cast(VkBool32, desc.stencil_state.test_enabled);

    for i : 0..1 {
        result := ifx i == 0 then *depth_stencil_state.front else *depth_stencil_state.back;
        stencil := ifx i == 0 then *desc.stencil_state.front_face else *desc.stencil_state.back_face;

        result.failOp = MakeVkStencilOp(stencil.failed_op);
        result.passOp = MakeVkStencilOp(stencil.passed_op);
        result.depthFailOp = MakeVkStencilOp(stencil.depth_failed_op);
        result.compareOp = MakeVkCompareOp(stencil.compare_op);
        result.writeMask = stencil.write_mask;
        result.compareMask = stencil.read_mask;
    }

    color_attachments : [Gfx_Max_Color_Attachments]VkFormat;
    for desc.color_formats {
        color_attachments[it_index] = MakeVkFormat(it);
    }

    rendering_info : VkPipelineRenderingCreateInfo;
    rendering_info.colorAttachmentCount = desc.num_color_attachments;
    rendering_info.pColorAttachmentFormats = color_attachments.data;
    rendering_info.depthAttachmentFormat = MakeVkFormat(desc.depth_format);
    rendering_info.stencilAttachmentFormat = MakeVkFormat(desc.stencil_format);

    pipeline_info : VkGraphicsPipelineCreateInfo;
    pipeline_info.pNext = *rendering_info;
    pipeline_info.stageCount = xx ifx IsNull(desc.fragment_shader) then 1 else 2;
    pipeline_info.pStages = shader_stages.data;
    pipeline_info.pVertexInputState = *vertex_input_state;
    pipeline_info.pInputAssemblyState = *input_assembly_state;
    pipeline_info.pViewportState = *viewport_state;
    pipeline_info.pRasterizationState = *rasterizer_state;
    pipeline_info.pMultisampleState = *multisample_state;
    pipeline_info.pDepthStencilState = *depth_stencil_state;
    pipeline_info.pColorBlendState = *blend_state;
    pipeline_info.pDynamicState = *dynamic_state;
    pipeline_info.layout = layout.layout;

    pipeline : VkPipeline;
    if vkCreateGraphicsPipelines(g_gfx_context.device, VK_NULL_HANDLE, 1, *pipeline_info, g_vk_alloc_callbacks, *pipeline) != .SUCCESS {
        DestroyGfxPipelineLayout(*layout);

        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create graphics pipeline '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(pipeline, TPrint("Graphics Pipeline '%'", name));

    copied_desc := desc;
    copied_desc.vertex_input.attributes = ArrayClone(desc.vertex_input.attributes);
    copied_desc.vertex_input.buffer_bindings = ArrayClone(desc.vertex_input.buffer_bindings);

    return .{layout=layout, pipeline=pipeline, name=StringClone(name), desc=copied_desc};
}

DestroyGfxGraphicsPipeline :: (pipeline : *GfxGraphicsPipeline) {
    LogSectionScope(*Log_Vulkan);

    Free(pipeline.name.data);
    Free(pipeline.desc.vertex_input.attributes.data);
    Free(pipeline.desc.vertex_input.buffer_bindings.data);

    DestroyGfxPipelineLayout(*pipeline.layout);
    vkDestroyPipeline(g_gfx_context.device, pipeline.pipeline, g_vk_alloc_callbacks);
    pipeline.* = .{};
}

GfxComputePipeline :: struct {
    layout : GfxPipelineLayout;
    pipeline : VkPipeline;
    name : string;
    desc : GfxComputePipelineDesc;
}

IsNull :: inline (pipeline : *GfxComputePipeline) -> bool {
    return pipeline == null || pipeline.pipeline == VK_NULL_HANDLE || IsNull(*pipeline.layout);
} @NoProfile

CreateGfxComputePipeline :: (name : string, desc : GfxComputePipelineDesc, panic_on_failure := true) -> GfxComputePipeline {
    LogSectionScope(*Log_Vulkan);

    layout := CreateGfxPipelineLayout(name, desc.layout, panic_on_failure);
    if IsNull(*layout) {
        return .{};
    }

    create_info : VkComputePipelineCreateInfo;
    create_info.stage.stage = .COMPUTE_BIT;
    create_info.stage.pName = "main";
    create_info.stage.module = desc.shader.module;
    create_info.layout = layout.layout;

    pipeline : VkPipeline;
    if vkCreateComputePipelines(g_gfx_context.device, VK_NULL_HANDLE, 1, *create_info, g_vk_alloc_callbacks, *pipeline) != .SUCCESS {
        DestroyGfxPipelineLayout(*layout);

        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create compute pipeline '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(pipeline, TPrint("Compute Pipeline '%'", name));

    return .{layout=layout, pipeline=pipeline, name=StringClone(name), desc=desc};
}

DestroyGfxComputePipeline :: (pipeline : *GfxComputePipeline) {
    LogSectionScope(*Log_Vulkan);

    Free(pipeline.name.data);
    DestroyGfxPipelineLayout(*pipeline.layout);
    vkDestroyPipeline(g_gfx_context.device, pipeline.pipeline, g_vk_alloc_callbacks);
    pipeline.* = .{};
}

MakeVkCompareOp :: inline (compare_op : GfxCompareOp) -> VkCompareOp {
    if #complete compare_op == {
    case; #through;
    case .None; Panic("Invalid value for compare_op");
    case .Never;        return .NEVER;
    case .Always;       return .ALWAYS;
    case .Less;         return .LESS;
    case .LessEqual;    return .LESS_OR_EQUAL;
    case .Greater;      return .GREATER;
    case .GreaterEqual; return .GREATER_OR_EQUAL;
    case .Equal;        return .EQUAL;
    case .NotEqual;     return .NOT_EQUAL;
    }
    return .MAX_ENUM;
} @NoProfile

MakeVkStencilOp :: inline (stencil_op : GfxStencilOp) -> VkStencilOp {
    if #complete stencil_op == {
    case; Panic("Invalid value for stencil_op");
    case .Keep;           return .KEEP;
    case .Zero;           return .ZERO;
    case .Replace;        return .REPLACE;
    case .IncrementClamp; return .INCREMENT_AND_CLAMP;
    case .IncrementWrap;  return .INCREMENT_AND_WRAP;
    case .DecrementClamp; return .DECREMENT_AND_CLAMP;
    case .DecrementWrap;  return .DECREMENT_AND_WRAP;
    case .Invert;         return .INVERT;
    }
    return .MAX_ENUM;
} @NoProfile

MakeVkBlendFactor :: inline (blend_factor : GfxBlendFactor) -> VkBlendFactor {
    if #complete blend_factor == {
    case; Panic("Invalid value for blend_factor");
    case .Zero;                  return .ZERO;
    case .One;                   return .ONE;
    case .SrcColor;              return .SRC_COLOR;
    case .OneMinusSrcColor;      return .ONE_MINUS_SRC_COLOR;
    case .DstColor;              return .DST_COLOR;
    case .OneMinusDstColor;      return .ONE_MINUS_DST_COLOR;
    case .SrcAlpha;              return .SRC_ALPHA;
    case .OneMinusSrcAlpha;      return .ONE_MINUS_SRC_ALPHA;
    case .DstAlpha;              return .DST_ALPHA;
    case .OneMinusDstAlpha;      return .ONE_MINUS_DST_ALPHA;
    case .ConstantColor;         return .CONSTANT_COLOR;
    case .OneMinusConstantColor; return .ONE_MINUS_CONSTANT_COLOR;
    case .ConstantAlpha;         return .CONSTANT_ALPHA;
    case .OneMinusConstantAlpha; return .ONE_MINUS_CONSTANT_ALPHA;
    case .SrcAlphaSaturate;      return .SRC_ALPHA_SATURATE;
    case .Src1Color;             return .SRC1_COLOR;
    case .OneMinusSrc1Color;     return .ONE_MINUS_SRC1_COLOR;
    case .Src1Alpha;             return .SRC1_ALPHA;
    case .OneMinusSrc1Alpha;     return .ONE_MINUS_SRC1_ALPHA;
    }
    return .MAX_ENUM;
} @NoProfile

MakeVkBlendOp :: inline (blend_op : GfxBlendOp) -> VkBlendOp {
    if #complete blend_op == {
    case .Add;             return .ADD;
    case .Subtract;        return .SUBTRACT;
    case .ReverseSubtract; return .REVERSE_SUBTRACT;
    case .Min;             return .MIN;
    case .Max;             return .MAX;
    }
    return .MAX_ENUM;
} @NoProfile

MakeVkFormat :: (format : GfxVertexFormat, normalized : bool) -> VkFormat {
    if #complete format == {
    case .Invalid; return .UNDEFINED;
    case .Float; return .R32_SFLOAT;
    case .Float2; return .R32G32_SFLOAT;
    case .Float3; return .R32G32B32_SFLOAT;
    case .Float4; return .R32G32B32A32_SFLOAT;
    case .Char2; return ifx normalized then .R8G8_SNORM else .R8G8_SINT;
    case .Char3; return ifx normalized then .R8G8B8_SNORM else .R8G8B8_SINT;
    case .Char4; return ifx normalized then .R8G8B8A8_SNORM else .R8G8B8A8_SINT;
    case .UChar2; return ifx normalized then .R8G8_UNORM else .R8G8_UINT;
    case .UChar3; return ifx normalized then .R8G8B8_UNORM else .R8G8B8_UINT;
    case .UChar4; return ifx normalized then .R8G8B8A8_UNORM else .R8G8B8A8_UINT;
    case .Short2; return ifx normalized then .R16G16_SNORM else .R16G16_SINT;
    case .Short3; return ifx normalized then .R16G16B16_SNORM else .R16G16B16_SINT;
    case .Short4; return ifx normalized then .R16G16B16A16_SNORM else .R16G16B16A16_SINT;
    case .UShort2; return ifx normalized then .R16G16_UNORM else .R16G16_UINT;
    case .UShort3; return ifx normalized then .R16G16B16_UNORM else .R16G16B16_UINT;
    case .UShort4; return ifx normalized then .R16G16B16A16_UNORM else .R16G16B16A16_UINT;
    // No normalized 32-bit integer formats?
    case .Int; return .R32_SINT;
    case .Int2; return .R32G32_SINT;
    case .Int3; return .R32G32B32_SINT;
    case .Int4; return .R32G32B32A32_SINT;
    case .UInt; return .R32G32_UINT;
    case .UInt2; return .R32G32_UINT;
    case .UInt3; return .R32G32B32_UINT;
    case .UInt4; return .R32G32B32A32_UINT;
    }
} @NoProfile
