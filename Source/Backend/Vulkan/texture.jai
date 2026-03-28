GfxTexture :: struct {
    image : VkImage;
    image_view : VkImageView; // Default view for this texture
    allocation : VmaAllocation;
    name : string;
    desc : GfxTextureAndViewDesc;
}

IsNull :: inline (texture : *GfxTexture) -> bool {
    return texture == null || texture.image == VK_NULL_HANDLE;
} @NoProfile

CreateGfxTexture :: (name : string, desc : GfxTextureDesc, panic_on_failure := true) -> GfxTexture {
    LogSectionScope(*Log_Vulkan);

    image_info : VkImageCreateInfo;
    if #complete desc.type == {
    case .Invalid; Panic("Invalid image type");
    case .Texture1D;        image_info.imageType = ._1D;
    case .Texture2D;        image_info.imageType = ._2D;
    case .Texture2DMS;      image_info.imageType = ._2D;
    case .Texture3D;        image_info.imageType = ._3D;
    case .TextureCube;      image_info.imageType = ._2D;
    case .Texture1DArray;   image_info.imageType = ._1D;
    case .Texture2DArray;   image_info.imageType = ._2D;
    case .Texture2DMSArray; image_info.imageType = ._2D;
    case .TextureCubeArray; image_info.imageType = ._2D;
    }

    if desc.num_samples == {
    case 1;  image_info.samples = ._1_BIT;
    case 2;  image_info.samples = ._2_BIT;
    case 4;  image_info.samples = ._4_BIT;
    case 8;  image_info.samples = ._8_BIT;
    case 16; image_info.samples = ._16_BIT;
    case 32; image_info.samples = ._32_BIT;
    case 64; image_info.samples = ._64_BIT;
    case;
        Panic("Invalid sample count % for texture (expected 1, 2, 4, 8, 16, 32 or 64)", desc.num_samples);
    }

    image_info.format = MakeVkFormat(desc.pixel_format);
    image_info.tiling = .OPTIMAL;

    image_info.arrayLayers = desc.num_array_layers;
    image_info.mipLevels = desc.num_mipmap_levels;
    image_info.extent = .{desc.width, desc.height, desc.depth};

    if desc.type == .TextureCube || desc.type == .TextureCubeArray {
        image_info.flags |= .CUBE_COMPATIBLE_BIT;
        image_info.arrayLayers *= 6;
    }

    if desc.usage & .TransferSrc {
        image_info.usage |= .TRANSFER_SRC_BIT;
    }
    if desc.usage & .TransferDst {
        image_info.usage |= .TRANSFER_DST_BIT;
    }
    if desc.usage & .Sampled {
        image_info.usage |= .SAMPLED_BIT;
    }
    if desc.usage & .Storage {
        image_info.usage |= .STORAGE_BIT;
    }
    if desc.usage & .ColorAttachment {
        image_info.usage |= .COLOR_ATTACHMENT_BIT;
    }
    if desc.usage & .DepthStencilAttachment {
        image_info.usage |= .DEPTH_STENCIL_ATTACHMENT_BIT;
    }

    image_info.sharingMode = .EXCLUSIVE;
    image_info.queueFamilyIndexCount = 1;
    image_info.pQueueFamilyIndices = *g_gfx_context.general_purpose_queue_index;

    alloc_info : VmaAllocationCreateInfo;
    alloc_info.usage = .AUTO;
    alloc_info.flags = .DEDICATED_MEMORY_BIT;
    alloc_info.priority = 1;

    image : VkImage;
    allocation : VmaAllocation;
    if vmaCreateImage(g_gfx_context.allocator, *image_info, *alloc_info, *image, *allocation, null) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create texture '%' with desc %", name, desc);
        }

        return .{};
    }

    view_info : VkImageViewCreateInfo;
    view_info.image = image;
    view_info.format = image_info.format;

    if #complete desc.type == {
    case .Invalid;
    case .Texture1D;        view_info.viewType = ._1D;
    case .Texture2D;        view_info.viewType = ._2D;
    case .Texture2DMS;      view_info.viewType = ._2D;
    case .Texture3D;        view_info.viewType = ._3D;
    case .TextureCube;      view_info.viewType = .CUBE;
    case .Texture1DArray;   view_info.viewType = ._1D_ARRAY;
    case .Texture2DArray;   view_info.viewType = ._2D_ARRAY;
    case .Texture2DMSArray; view_info.viewType = ._2D_ARRAY;
    case .TextureCubeArray; view_info.viewType = .CUBE_ARRAY;
    }

    if desc.pixel_format == {
    case .Depth32FloatStencil8;
        view_info.subresourceRange.aspectMask = .DEPTH_BIT | .STENCIL_BIT;
    case .Depth32Float;
        view_info.subresourceRange.aspectMask = .DEPTH_BIT;
    case .Stencil8;
        view_info.subresourceRange.aspectMask = .STENCIL_BIT;
    case;
        view_info.subresourceRange.aspectMask = .COLOR_BIT;
    }

    view_info.subresourceRange.baseMipLevel = 0;
    view_info.subresourceRange.levelCount = image_info.mipLevels;
    view_info.subresourceRange.baseArrayLayer = 0;
    view_info.subresourceRange.layerCount = image_info.arrayLayers;

    image_view : VkImageView;
    if vkCreateImageView(g_gfx_context.device, *view_info, g_vk_alloc_callbacks, *image_view) != .SUCCESS {
        vmaDestroyImage(g_gfx_context.allocator, image, allocation);

        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create texture '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(image, TPrint("Image '%'", name));
    SetDebugName(image_view, TPrint("Image View '%'", name));

    return .{image=image, image_view=image_view, allocation=allocation, name=StringClone(name), desc=MakeGfxTextureAndViewDesc(desc)};
} @NoProfile

DestroyGfxTexture :: (texture : *GfxTexture) {
    LogSectionScope(*Log_Vulkan);

    Free(texture.name.data);
    vkDestroyImageView(g_gfx_context.device, texture.image_view, g_vk_alloc_callbacks);
    vmaDestroyImage(g_gfx_context.allocator, texture.image, texture.allocation);
    texture.* = .{};
} @NoProfile

QueueDestroyGfxTexture :: (texture : *GfxTexture) {
    collector := *g_gfx_context.texture_collectors[g_gfx_context.frame_in_flight];
    AddGarbage(collector, texture);
    texture.* = .{};
} @NoProfile

CreateGfxTextureView :: (name : string, desc : GfxTextureViewDesc, texture : *GfxTexture) -> GfxTexture {
    if IsNull(texture) {
        return .{};
    }

    view_info : VkImageViewCreateInfo;
    view_info.image = texture.image;
    view_info.format = MakeVkFormat(desc.pixel_format);

    if #complete desc.type == {
    case .Invalid;
    case .Texture1D;        view_info.viewType = ._1D;
    case .Texture2D;        view_info.viewType = ._2D;
    case .Texture2DMS;      view_info.viewType = ._2D;
    case .Texture3D;        view_info.viewType = ._3D;
    case .TextureCube;      view_info.viewType = .CUBE;
    case .Texture1DArray;   view_info.viewType = ._1D_ARRAY;
    case .Texture2DArray;   view_info.viewType = ._2D_ARRAY;
    case .Texture2DMSArray; view_info.viewType = ._2D_ARRAY;
    case .TextureCubeArray; view_info.viewType = .CUBE_ARRAY;
    }

    if desc.pixel_format == {
    case .Depth32FloatStencil8;
        view_info.subresourceRange.aspectMask = .DEPTH_BIT | .STENCIL_BIT;
    case .Depth32Float;
        view_info.subresourceRange.aspectMask = .DEPTH_BIT;
    case .Stencil8;
        view_info.subresourceRange.aspectMask = .STENCIL_BIT;
    case;
        view_info.subresourceRange.aspectMask = .COLOR_BIT;
    }

    view_info.subresourceRange.baseMipLevel = desc.first_mipmap_level;
    view_info.subresourceRange.levelCount = desc.num_mipmap_levels;
    view_info.subresourceRange.baseArrayLayer = desc.first_array_layer;
    view_info.subresourceRange.layerCount = desc.num_array_layers;

    image_view : VkImageView;
    if vkCreateImageView(g_gfx_context.device, *view_info, g_vk_alloc_callbacks, *image_view) != .SUCCESS {
        return .{};
    }

    SetDebugName(image_view, TPrint("Image View '%'", name));

    return .{image=texture.image, image_view=image_view, allocation=texture.allocation, name=StringClone(name), desc=MakeGfxTextureAndViewDesc(texture.desc, desc)};
} @NoProfile

DestroyGfxTextureView :: (texture : *GfxTexture) {
    LogSectionScope(*Log_Vulkan);

    Free(texture.name.data);
    vkDestroyImageView(g_gfx_context.device, texture.image_view, g_vk_alloc_callbacks);
    texture.* = .{};
} @NoProfile

QueueDestroyGfxTextureView :: (texture : *GfxTexture) {
    collector := *g_gfx_context.texture_view_collectors[g_gfx_context.frame_in_flight];
    AddGarbage(collector, texture);
    texture.* = .{};
} @NoProfile

MakeVkFormat :: inline (pixel_format : GfxPixelFormat) -> VkFormat {
    if #complete pixel_format == {
    case .Invalid; return .UNDEFINED;
    case .R8UNorm; return .R8_UNORM;
    case .R8SNorm; return .R8_SNORM;
    case .R8UInt; return .R8_UINT;
    case .R8SInt; return .R8_SINT;
    case .RGBA8SRGB; return .R8G8B8A8_SRGB;
    case .RGBA8UNorm; return .R8G8B8A8_UNORM;
    case .RGBA8SNorm; return .R8G8B8A8_SNORM;
    case .RGBA8UInt; return .R8G8B8A8_UINT;
    case .RGBA8SInt; return .R8G8B8A8_SINT;
    case .BGRA8UNorm; return .B8G8R8A8_UNORM;
    case .BGRA8SRGB; return .B8G8R8A8_SRGB;
    case .R32UInt; return .R32_UINT;
    case .R32SInt; return .R32_SINT;
    case .RGBA16Float; return .R16G16B16A16_SFLOAT;
    case .RGBA32UInt; return .R32G32B32A32_UINT;
    case .RGBA32SInt; return .R32G32B32A32_SINT;
    case .RGBA32Float; return .R32G32B32A32_SFLOAT;
    case .Depth32FloatStencil8; return .D32_SFLOAT_S8_UINT;
    case .Depth32Float; return .D32_SFLOAT;
    case .Stencil8; return .S8_UINT;
    }
    return .UNDEFINED;
} @NoProfile

MakeGfxPixelFormat :: inline (format : VkFormat) -> GfxPixelFormat {
    if format == {
    case .UNDEFINED; return .Invalid;
    case .R8_UNORM; return .R8UNorm;
    case .R8_SNORM; return .R8SNorm;
    case .R8_UINT; return .R8UInt;
    case .R8_SINT; return .R8SInt;
    case .R8G8B8A8_SRGB; return .RGBA8SRGB;
    case .R8G8B8A8_UNORM; return .RGBA8UNorm;
    case .R8G8B8A8_SNORM; return .RGBA8SNorm;
    case .R8G8B8A8_UINT; return .RGBA8UInt;
    case .R8G8B8A8_SINT; return .RGBA8SInt;
    case .B8G8R8A8_UNORM; return .BGRA8UNorm;
    case .B8G8R8A8_SRGB; return .BGRA8SRGB;
    case .R32_UINT; return .R32UInt;
    case .R32_SINT; return .R32SInt;
    case .R16G16B16A16_SFLOAT; return .RGBA16Float;
    case .R32G32B32A32_UINT; return .RGBA32UInt;
    case .R32G32B32A32_SINT; return .RGBA32SInt;
    case .R32G32B32A32_SFLOAT; return .RGBA32Float;
    case .D32_SFLOAT_S8_UINT; return .Depth32FloatStencil8;
    case .D32_SFLOAT; return .Depth32Float;
    case .S8_UINT; return .Stencil8;
    }
    return .Invalid;
} @NoProfile

GfxSampler :: struct {
    sampler : VkSampler;
    name : string;
    desc : GfxSamplerDesc;
}

IsNull :: inline (sampler : *GfxSampler) -> bool {
    return sampler == null || sampler.sampler == VK_NULL_HANDLE;
} @NoProfile

CreateGfxSampler :: (name : string, desc : GfxSamplerDesc, panic_on_failure := true) -> GfxSampler {
    LogSectionScope(*Log_Vulkan);

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

    sampler : VkSampler;
    if vkCreateSampler(g_gfx_context.device, *create_info, g_vk_alloc_callbacks, *sampler) != .SUCCESS {
        if panic_on_failure {
            ScopeLongFormStructFormat();
            Panic("Could not create sampler '%' with desc %", name, desc);
        }

        return .{};
    }

    SetDebugName(sampler, TPrint("Sampler '%'", name));

    return .{sampler=sampler, name=StringClone(name), desc=desc};
} @NoProfile

DestroyGfxSampler :: (sampler : *GfxSampler) {
    LogSectionScope(*Log_Vulkan);

    Free(sampler.name.data);
    vkDestroySampler(g_gfx_context.device, sampler.sampler, g_vk_alloc_callbacks);
    sampler.* = .{};
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
