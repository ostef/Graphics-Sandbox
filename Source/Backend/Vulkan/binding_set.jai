GfxBindingSetLayout :: struct {
    layout : VkDescriptorSetLayout;
    name : string;
    desc : GfxBindingSetLayoutDesc;
}

IsNull :: inline (layout : *GfxBindingSetLayout) -> bool {
    return layout == null || layout.layout == VK_NULL_HANDLE;
} @NoProfile

CreateGfxBindingSetLayout :: (name : string, desc : GfxBindingSetLayoutDesc, panic_on_failure := true) -> GfxBindingSetLayout {
    LogSectionScope(*Log_Vulkan);

    create_info : VkDescriptorSetLayoutCreateInfo;
    create_info.bindingCount = xx desc.bindings.count;
    create_info.pBindings = Alloc(VkDescriptorSetLayoutBinding, desc.bindings.count, initialize=true ,, Temp);

    binding_flags : VkDescriptorSetLayoutBindingFlagsCreateInfo;
    binding_flags.bindingCount = xx desc.bindings.count;
    binding_flags.pBindingFlags = Alloc(VkDescriptorBindingFlags, desc.bindings.count, initialize=true ,, Temp);

    create_info.pNext = *binding_flags;

    for desc.bindings {
        binding := *create_info.pBindings[it_index];
        binding.binding = it.binding;
        binding.descriptorType = MakeVkDescriptorType(it.type);
        binding.descriptorCount = it.num_array_layers;
        binding.stageFlags = MakeVkShaderStageFlags(it.stage_flags);

        binding_flags.pBindingFlags[it_index] = MakeVkDescriptorBindingFlags(it.flags);
    }

    layout : VkDescriptorSetLayout;
    if vkCreateDescriptorSetLayout(g_gfx_context.device, *create_info, g_vk_alloc_callbacks, *layout) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create binding set layout '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(layout, TPrint("Descriptor Set Layout '%'", name));

    copied_desc := desc;
    copied_desc.bindings = ArrayClone(desc.bindings);

    return .{layout=layout, name=StringClone(name), desc=copied_desc};
}

DestroyGfxBindingSetLayout :: (layout : *GfxBindingSetLayout) {
    LogSectionScope(*Log_Vulkan);

    Free(layout.name.data);
    Free(layout.desc.bindings.data);
    vkDestroyDescriptorSetLayout(g_gfx_context.device, layout.layout, g_vk_alloc_callbacks);
    layout.* = .{};
}

GfxBindingPool :: struct {
    pool : VkDescriptorPool;
}

IsNull :: inline (pool : *GfxBindingPool) -> bool {
    return pool == null || pool.pool == VK_NULL_HANDLE;
} @NoProfile

CreateGfxBindingPool :: (name : string, desc : GfxBindingPoolDesc, panic_on_failure := true) -> GfxBindingPool {
    pool_sizes : [..]VkDescriptorPoolSize;
    pool_sizes.allocator = Temp;

    if desc.max_uniform_buffers > 0 {
        ArrayPush(*pool_sizes, .{type=.UNIFORM_BUFFER, descriptorCount=desc.max_uniform_buffers});
    }
    if desc.max_storage_buffers > 0 {
        ArrayPush(*pool_sizes, .{type=.STORAGE_BUFFER, descriptorCount=desc.max_storage_buffers});
    }
    if desc.max_textures > 0 {
        ArrayPush(*pool_sizes, .{type=.SAMPLED_IMAGE, descriptorCount=desc.max_textures});
    }
    if desc.max_samplers > 0 {
        ArrayPush(*pool_sizes, .{type=.SAMPLER, descriptorCount=desc.max_samplers});
    }
    if desc.max_combined_texture_samplers > 0 {
        ArrayPush(*pool_sizes, .{type=.COMBINED_IMAGE_SAMPLER, descriptorCount=desc.max_combined_texture_samplers});
    }
    if desc.max_storage_images > 0 {
        ArrayPush(*pool_sizes, .{type=.STORAGE_IMAGE, descriptorCount=desc.max_storage_images});
    }

    info : VkDescriptorPoolCreateInfo;
    info.maxSets = desc.max_binding_sets;
    info.poolSizeCount = xx pool_sizes.count;
    info.pPoolSizes = pool_sizes.data;

    pool : VkDescriptorPool;
    if vkCreateDescriptorPool(g_gfx_context.device, *info, g_vk_alloc_callbacks, *pool) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create binding set layout '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(pool, TPrint("Descriptor Pool '%'", name));

    return .{pool=pool};
}

DestroyGfxBindingPool :: (pool : *GfxBindingPool) {
    vkDestroyDescriptorPool(g_gfx_context.device, pool.pool, g_vk_alloc_callbacks);
    pool.* = .{};
}

ResetGfxBindingPool :: (pool : *GfxBindingPool) {
    vkResetDescriptorPool(g_gfx_context.device, pool.pool, 0);
}

AllocGfxBindingSet :: (pool : *GfxBindingPool, layout : *GfxBindingSetLayout) -> GfxBindingSet, GfxBindingPoolAllocResult {
    info : VkDescriptorSetAllocateInfo;
    info.descriptorPool = pool.pool;
    info.descriptorSetCount = 1;
    info.pSetLayouts = *layout.layout;

    set : VkDescriptorSet;
    result := vkAllocateDescriptorSets(g_gfx_context.device, *info, *set);
    if result != .SUCCESS {
        return .{}, MakeGfxBindingPoolAllocResult(result);
    }

    return .{set=set}, .Success;
} @NoProfile

GfxBindingSet :: struct {
    set : VkDescriptorSet;
}

IsNull :: inline (set : *GfxBindingSet) -> bool {
    return set == null || set.set == VK_NULL_HANDLE;
} @NoProfile

// Generates VkDescriptorBufferInfo, VkDescriptorImageInfo and VkWriteDescriptorSet then calls vkUpdateDescriptorSets automatically
// @AllowNull bindings are handled using the partially bound feature, so it is expected that when the binding is null it
// is not accessed in the shader. It is not the same thing as the null descriptor feature and failure to comply to this
// will result in crashes!
UpdateGfxBindingSet :: (set : *GfxBindingSet, value : $T) {
    #insert -> string {
        AppendBufferInfo :: (builder : *StringBuilder, name : string) {
            Appendln(builder, "    .{buffer=ifx value.%1.buffer then value.%1.buffer.buffer, offset=value.%1.offset, range=value.%1.size},", name);
        }

        AppendImageInfo :: (builder : *StringBuilder, name : string) {
            Appendln(builder, "    .{imageView=ifx value.%1.texture then value.%1.texture.image_view else VK_NULL_HANDLE, imageLayout=.READ_ONLY_OPTIMAL},", name);
        }

        AppendSamplerInfo :: (builder : *StringBuilder, name : string) {
            Appendln(builder, "    .{sampler=ifx value.%1.sampler then value.%1.sampler.sampler else VK_NULL_HANDLE},", name);
        }

        AppendCombinedImageSamplerInfo :: (builder : *StringBuilder, name : string) {
            Appendln(builder, "    .{sampler=ifx value.%1.sampler then value.%1.sampler.sampler else VK_NULL_HANDLE, imageView=ifx value.%1.texture then value.%1.texture.image_view else VK_NULL_HANDLE, imageLayout=.READ_ONLY_OPTIMAL},", name);
        }

        AppendStorageImageInfo :: (builder : *StringBuilder, name : string) {
            Appendln(builder, "    .{imageView=ifx value.%1.texture then value.%1.texture.image_view else VK_NULL_HANDLE, imageLayout=.GENERAL},", name);
        }

        builder : StringBuilder;
        info := type_info(T);

        Appendln(*builder, "// UpdateGfxBindingSet(%)", T);
        Appendln(*builder, "buffer_infos := VkDescriptorBufferInfo.[");

        max_possible_writes := 0;

        for info.members {
            if it.type.type == .ARRAY {
                continue;
            }

            type := GetGfxBindingType(it.type);
            if type == {
            case .UniformBuffer; #through;
            case .StorageBuffer;
                AppendBufferInfo(*builder, it.name);
                max_possible_writes += 1;
            }
        }

        Appendln(*builder, "];");

        Appendln(*builder, "image_infos := VkDescriptorImageInfo.[");

        for info.members {
            if it.type.type == .ARRAY {
                count := cast(*Type_Info_Array, it.type).array_count;
                type := GetGfxBindingType(cast(*Type_Info_Array, it.type).element_type);
                for i : 0..count - 1 {
                    if type == {
                    case .Texture;
                        AppendImageInfo(*builder, TPrint("%[%]", it.name, i));
                    case .Sampler;
                        AppendSamplerInfo(*builder, TPrint("%[%]", it.name, i));
                    case .CombinedTextureSampler;
                        AppendCombinedImageSamplerInfo(*builder, TPrint("%[%]", it.name, i));
                    case .StorageImage;
                        AppendStorageImageInfo(*builder, TPrint("%[%]", it.name, i));
                    }
                }

                max_possible_writes += count;
            } else {
                type := GetGfxBindingType(it.type);
                if type == {
                case .Texture;
                    AppendImageInfo(*builder, it.name);
                case .Sampler;
                    AppendSamplerInfo(*builder, it.name);
                case .CombinedTextureSampler;
                    AppendCombinedImageSamplerInfo(*builder, it.name);
                case .StorageImage;
                    AppendStorageImageInfo(*builder, it.name);
                }

                max_possible_writes += 1;
            }
        }

        Appendln(*builder, "];");

        AppendWrite :: (builder : *StringBuilder, allow_null : bool, binding : int, type : GfxBindingType, name : string, array_index : int, buffer_info_index : *int, image_info_index : *int) {
            if allow_null {
                if type == {
                case .UniformBuffer; #through;
                case .StorageBuffer;
                    Appendln(builder, "if !IsNull(value.%1.buffer) && value.%1.size > 0 {", name);

                case .Texture; #through;
                case .StorageImage;
                    Appendln(builder, "if !IsNull(value.%1) {", name);

                case .Sampler;
                    Appendln(builder, "if !IsNull(value.%1) {", name);

                case .CombinedTextureSampler;
                    Appendln(builder, "if !IsNull(value.%1.texture) {", name);
                }
            }

            if allow_null {
                Append(builder, "    ");
            }

            Appendln(builder, "write = ArrayPush(*writes);");

            if allow_null {
                Append(builder, "    ");
            }

            Append(builder,   "write.* = .{dstSet=set.set, dstBinding=%, descriptorType=.%, descriptorCount=1, dstArrayElement=%, ", binding, MakeVkDescriptorType(type), array_index);

            if type == {
            case .UniformBuffer; #through;
            case .StorageBuffer;
                Append(builder, "pBufferInfo=*buffer_infos[%]", buffer_info_index.*);
                buffer_info_index.* += 1;

            case .StorageImage; #through;
            case .Texture; #through;
            case .Sampler; #through;
            case .CombinedTextureSampler;
                Append(builder, "pImageInfo=*image_infos[%]", image_info_index.*);
                image_info_index.* += 1;
            }

            Appendln(builder, "};");

            if allow_null {
                Appendln(builder, "}");
            }
        }

        buffer_info_index := 0;
        image_info_index := 0;

        Appendln(*builder, "writes_stack_data : [%]VkWriteDescriptorSet = ---;", max_possible_writes);
        Appendln(*builder, "writes : [..]VkWriteDescriptorSet;");
        Appendln(*builder, "writes.allocator = Trap;");
        Appendln(*builder, "writes.data = writes_stack_data.data;");
        Appendln(*builder, "writes.allocated = writes_stack_data.count;");
        Appendln(*builder, "write : *VkWriteDescriptorSet;");

        for info.members {
            has_binding_note, binding := GetNote(it.notes, "Binding", int);
            allow_null := GetNote(it.notes, "AllowNull");

            if it.type.type == .ARRAY {
                elem_type := cast(*Type_Info_Array, it.type).element_type;
                elem_count := cast(*Type_Info_Array, it.type).array_count;
                type := GetGfxBindingType(elem_type);
                for i : 0..elem_count - 1 {
                    AppendWrite(*builder, allow_null, binding, type, TPrint("%[%]", it.name, i), i, *buffer_info_index, *image_info_index);
                }
            } else {
                type := GetGfxBindingType(it.type);
                AppendWrite(*builder, allow_null, binding, type, it.name, 0, *buffer_info_index, *image_info_index);
            }
        }

        return StringBuilderBuild(*builder);
    }

    vkUpdateDescriptorSets(g_gfx_context.device, xx writes.count, writes.data, 0, null);
} @NoProfile

MakeGfxBindingPoolAllocResult :: inline (result : VkResult) -> GfxBindingPoolAllocResult {
    if result == {
    case .SUCCESS; return .Success;
    case .ERROR_OUT_OF_POOL_MEMORY; return .OutOfPoolMemory;
    case .ERROR_OUT_OF_DEVICE_MEMORY; return .OutOfDeviceMemory;
    case .ERROR_OUT_OF_HOST_MEMORY; return .OutOfHostMemory;
    case .ERROR_FRAGMENTED_POOL; return .FragmentedPool;
    case; return .UnknownError;
    }
} @NoProfile

MakeVkShaderStageFlags :: inline (stages : GfxShaderStageFlags) -> VkShaderStageFlags {
    result : VkShaderStageFlags;
    if stages & .Vertex {
        result |= .VERTEX_BIT;
    }
    if stages & .Fragment {
        result |= .FRAGMENT_BIT;
    }
    if stages & .Compute {
        result |= .COMPUTE_BIT;
    }

    return result;
} @NoProfile

MakeVkDescriptorType :: inline (type : GfxBindingType) -> VkDescriptorType {
    if #complete type == {
    case .UniformBuffer;          return .UNIFORM_BUFFER;
    case .StorageBuffer;          return .STORAGE_BUFFER;
    case .Texture;                return .SAMPLED_IMAGE;
    case .Sampler;                return .SAMPLER;
    case .CombinedTextureSampler; return .COMBINED_IMAGE_SAMPLER;
    case .StorageImage;           return .STORAGE_IMAGE;
    }
} @NoProfile

MakeVkDescriptorBindingFlags :: inline (flags : GfxBindingFlags) -> VkDescriptorBindingFlags {
    result : VkDescriptorBindingFlags;
    if flags & .AllowNull {
        result |= .PARTIALLY_BOUND_BIT;
    }

    return result;
} @NoProfile
