StaticVertex :: struct {
    position : Vec3f;
    normal : Vec3f;
    tangent : Vec4f;
    tex_coords : Vec2f;
    color : Vec4f;
}

StaticMesh :: struct {
    name : string;
    slot_index : PagedArraySlotInfo;
    vertex_buffer : GfxBuffer;
    index_buffer : GfxBuffer;
    vertex_count : int;
    index_count : int;
}

g_static_meshes : PagedArray(StaticMesh, 100);

CreateStaticMesh :: () -> *StaticMesh {
    ptr, slot_index := PagedArrayFindSlot(*g_static_meshes);
    ptr.slot_index = slot_index;

    return ptr;
}

DestroyStaticMesh :: (mesh : *StaticMesh) {
    Free(mesh.name.data);

    if !IsNull(*mesh.index_buffer) {
        QueueDestroyGfxBuffer(*mesh.index_buffer);
    }
    if !IsNull(*mesh.vertex_buffer) {
        QueueDestroyGfxBuffer(*mesh.vertex_buffer);
    }

    slot_index := mesh.slot_index;
    mesh.* = .{};

    PagedArrayFreeSlot(*g_static_meshes, slot_index);
}

LoadStaticMeshFromAssimpMesh :: (mesh : *StaticMesh, ai_mesh : *Assimp.aiMesh) -> bool {
    LogSectionScope(*Log_Assets);

    if ai_mesh.mPrimitiveTypes & ~cast(u32, Assimp.aiPrimitiveType.TRIANGLE | Assimp.aiPrimitiveType.NGONEncodingFlag) {
        LogError("Only triangle meshes are handled (got %)", cast(Assimp.aiPrimitiveType, ai_mesh.mPrimitiveTypes));
        return false;
    }

    name := string.{count=ai_mesh.mName.length, data=ai_mesh.mName.data.data};

    vertices : [..]StaticVertex;
    defer ArrayFree(*vertices);

    indices : [..]u32;
    defer ArrayFree(*indices);

    colors := ai_mesh.mColors[0];
    tex_coords : *Assimp.aiVector3D;
    for ai_mesh.mNumUVComponents {
        if it == 2 {
            tex_coords = ai_mesh.mTextureCoords[it_index];
            break;
        }
    }

    for i : 0..cast(int, ai_mesh.mNumVertices) - 1 {
        vertex := ArrayPush(*vertices);
        vertex.position = xx,force ai_mesh.mVertices[i];

        if ai_mesh.mNormals {
            vertex.normal = xx,force ai_mesh.mNormals[i];

            if ai_mesh.mTangents && ai_mesh.mBitangents {
                t := cast,force(Vec3f, ai_mesh.mTangents[i]);
                b := cast,force(Vec3f, ai_mesh.mBitangents[i]);
                n := vertex.normal;

                vertex.tangent.xyz = Normalized(Reject(t, n));
                vertex.tangent.w = ifx Dot(Cross(t, b), n) > 0 then 1.0 else -1.0;
            }
        }

        if colors {
            vertex.color = xx,force colors[i];
        }

        if tex_coords {
            vertex.tex_coords = .{tex_coords[i].x, tex_coords[i].y};
        }
    }

    for i : 0..cast(int, ai_mesh.mNumFaces) - 1 {
        face := ai_mesh.mFaces[i];
        if face.mNumIndices != 3 {
            return false;
        }

        for ii : 0..2 {
            ArrayPush(*indices, face.mIndices[ii]);
        }
    }

    index_buffer_desc : GfxBufferDesc;
    index_buffer_desc.size = xx (indices.count * size_of(u32));
    index_buffer_desc.usage = .TransferDst | .IndexBuffer;
    index_buffer_desc.memory_usage = .GPUOnly;
    mesh.index_buffer = CreateGfxBuffer(TPrint("'%' indices", name), index_buffer_desc);
    mesh.index_count = indices.count;
    QueueBufferUpload(*mesh.index_buffer, indices.data, xx index_buffer_desc.size);

    vertex_buffer_desc : GfxBufferDesc;
    vertex_buffer_desc.size = xx (vertices.count * size_of(StaticVertex));
    vertex_buffer_desc.usage = .TransferDst | .VertexBuffer;
    vertex_buffer_desc.memory_usage = .GPUOnly;
    mesh.vertex_buffer = CreateGfxBuffer(TPrint("'%' vertices", name), vertex_buffer_desc);
    mesh.vertex_count = vertices.count;
    QueueBufferUpload(*mesh.vertex_buffer, vertices.data, xx vertex_buffer_desc.size);

    mesh.name = StringClone(name);

    LogMessage("Loaded mesh '%'", mesh.name);

    return true;
}
