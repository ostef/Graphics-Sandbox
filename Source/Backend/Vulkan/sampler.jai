GfxSampler :: struct {
    sampler : VkSampler;
    name : string;
    desc : GfxSamplerDesc;
}

IsNull :: inline (sampler : *GfxSampler) -> bool {
    return sampler == null || sampler.sampler == VK_NULL_HANDLE;
} @NoProfile

CreateGfxSampler :: (desc : GfxSamplerDesc, panic_on_failure := true) -> GfxSampler {
    LogSectionScope(*Log_Vulkan);

    existing := HashMapGetPtr(*g_gfx_context.sampler_cache, desc);
    if existing {
        existing.ref_count += 1;
        return existing.sampler;
    }

    create_info : VkSamplerCreateInfo;
    create_info.minFilter = MakeVkFilter(desc.min_filter);
    create_info.magFilter = MakeVkFilter(desc.mag_filter);
    create_info.mipmapMode = MakeVkSamplerMipmapMode(desc.mipmap_filter);
    create_info.mipLodBias = desc.mip_lod_bias;
    create_info.minLod = desc.min_lod;
    create_info.maxLod = desc.max_lod;
    create_info.addressModeU = MakeVkSamplerAddressMode(desc.u_address_mode);
    create_info.addressModeV = MakeVkSamplerAddressMode(desc.v_address_mode);
    create_info.addressModeW = MakeVkSamplerAddressMode(desc.w_address_mode);
    if desc.compare_op != .None {
        create_info.compareEnable = VK_TRUE;
        create_info.compareOp = MakeVkCompareOp(desc.compare_op);
    }
    create_info.anisotropyEnable = xx desc.anisotropy_enabled;
    create_info.maxAnisotropy = desc.max_anisotropy;
    create_info.borderColor = MakeVkBorderColor(desc.border_color);

    name_builder : StringBuilder;
    if desc.min_filter == desc.mag_filter && desc.min_filter == desc.mipmap_filter {
        Append(*name_builder, "%, ", desc.min_filter);
    } else if desc.min_filter == desc.mag_filter {
        Append(*name_builder, "%, Mip %, ", desc.min_filter, desc.mipmap_filter);
    } else {
        Append(*name_builder, "Min %, Mag %, Mip %, ", desc.min_filter, desc.mag_filter, desc.mipmap_filter);
    }

    if desc.u_address_mode == desc.v_address_mode && desc.u_address_mode == desc.w_address_mode {
        Append(*name_builder, "%", desc.u_address_mode);
    } else if desc.u_address_mode == desc.v_address_mode {
        Append(*name_builder, "UV %, W %", desc.u_address_mode, desc.w_address_mode);
    } else {
        Append(*name_builder, "U %, V %, W %", desc.u_address_mode, desc.v_address_mode, desc.w_address_mode);
    }

    if desc.border_color != .Transparent {
        Append(*name_builder, ", Border %", desc.border_color);
    }

    if desc.compare_op != .None {
        Append(*name_builder, ", Compare %", desc.compare_op);
    }

    if desc.mip_lod_bias != 0 || desc.min_lod != 0 || desc.max_lod != F32_Inf {
        Append(*name_builder, ", LOD %/%/%", desc.min_lod, desc.max_lod, desc.mip_lod_bias);
    }

    name := StringBuilderBuild(*name_builder);

    sampler : VkSampler;
    if vkCreateSampler(g_gfx_context.device, *create_info, g_vk_alloc_callbacks, *sampler) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create sampler '%' with desc %", name, desc);
        }

        Free(name.data);

        return .{};
    }

    s := GfxSampler.{sampler=sampler, name=name, desc=desc};
    SetDebugName(sampler, TPrint("Sampler '%'", name));

    HashMapInsert(*g_gfx_context.sampler_cache, desc, .{ref_count=1, sampler=s});

    return s;
} @NoProfile

DestroyGfxSampler :: (sampler : *GfxSampler) {
    LogSectionScope(*Log_Vulkan);

    cached := HashMapGetPtr(*g_gfx_context.sampler_cache, sampler.desc);
    if cached {
        if sampler != *cached.sampler {
            sampler.* = .{};
        }

        cached.ref_count -= 1;
        if cached.ref_count > 0 {
            return;
        }

        sampler = *cached.sampler;
    }

    Free(sampler.name.data);
    vkDestroySampler(g_gfx_context.device, sampler.sampler, g_vk_alloc_callbacks);
    sampler.* = .{};

    HashMapRemove(*g_gfx_context.sampler_cache, sampler.desc);
} @NoProfile

QueueDestroyGfxSampler :: (sampler : *GfxSampler) {
    collector := *g_gfx_context.sampler_collectors[g_gfx_context.frame_in_flight];
    AddGarbage(collector, sampler);
    sampler.* = .{};
} @NoProfile

MakeVkFilter :: inline (filter : GfxSamplerFilter) -> VkFilter {
    if #complete filter == {
    case .Nearest; return .NEAREST;
    case .Linear; return .LINEAR;
    }
} @NoProfile

MakeVkSamplerMipmapMode :: inline (filter : GfxSamplerFilter) -> VkSamplerMipmapMode {
    if #complete filter == {
    case .Nearest; return .NEAREST;
    case .Linear; return .LINEAR;
    }
} @NoProfile

MakeVkSamplerAddressMode :: (mode : GfxSamplerAddressMode) -> VkSamplerAddressMode {
    if #complete mode == {
    case .Repeat;            return .REPEAT;
    case .ClampToEdge;       return .CLAMP_TO_EDGE;
    case .ClampToBorder;     return .CLAMP_TO_BORDER;
    case .MirrorRepeat;      return .MIRRORED_REPEAT;
    case .MirrorClampToEdge; return .MIRROR_CLAMP_TO_EDGE;
    }
} @NoProfile

MakeVkBorderColor :: (color : GfxSamplerBorderColor) -> VkBorderColor {
    if #complete color == {
    case .Transparent; return .FLOAT_TRANSPARENT_BLACK;
    case .OpaqueBlack; return .FLOAT_OPAQUE_BLACK;
    case .OpaqueWhite; return .FLOAT_OPAQUE_WHITE;
    }
} @NoProfile
