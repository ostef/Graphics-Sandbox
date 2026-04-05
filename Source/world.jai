#import "Paged_Array";
#import "Random";

GUID :: #type,distinct Basic.U128;

Null_GUID :: GUID.{0,0};

g_guid_random_state_low : Random_State;
g_guid_random_state_high : Random_State;

GenerateGUID :: () -> GUID {
    if g_guid_random_state_low.low == 0 && g_guid_random_state_low.high == 0 {
        seed := Basic.current_time_monotonic();
        random_seed(*g_guid_random_state_low, Random_State.{xx seed.low, xx seed.high});
        random_seed(*g_guid_random_state_high, Random_State.{xx seed.high, xx seed.low});
    }

    return .{
        random_get(*g_guid_random_state_low),
        random_get(*g_guid_random_state_high),
    };
}

CompareGUIDs :: inline (a : GUID, b : GUID) -> bool {
    return a.low == b.low && a.high == b.high;
}

operator == :: inline (a : GUID, b : GUID) -> bool {
    return CompareGUIDs(a, b);
}

HashGUID :: inline (guid : GUID) -> u64 {
    #import "Hash";

    h := fnv1a_hash(guid.low);
    h = fnv1a_hash(guid.high, h);

    return h;
}

World :: struct {
    filename : string;

    entities_by_guid : HashMap(
        GUID, *Entity,
        hash_func = HashGUID,
        comp_func = (a, b) => a == b
    );
    entities_by_name : HashMap(string, *Entity);

    Empty_entities : PagedArray(EmptyEntity, 100);
    Mesh_entities : PagedArray(MeshEntity, 100);
}

Entity :: struct {
    Kind :: enum {
        Empty;
        Mesh;
    }

    kind : Entity.Kind;
    slot_info : PagedArraySlotInfo;
    name : string;
    guid : GUID;

    local_position : Vec3f;
    local_rotation : Quatf;
    local_scale : Vec3f;
    world_transform : Mat4f;
    inv_world_transform : Mat4f;

    parent : GUID;
    children : [..]GUID;
}

EmptyEntity :: struct {
    #as using base : Entity;
    kind = .Empty;
}

MeshEntity :: struct {
    #as using base : Entity;
    kind = .Mesh;

    mesh : *StaticMesh;
}

GetEntity :: (world : *World, guid : GUID) -> *Entity {
    return HashMapGet(*world.entities_by_guid, guid);
}

CreateEntity :: (world : *World, $T : Type, name := "") -> *T {
    K :: #run T.{}.kind;

    storage := #insert #run TPrint("*world.%_entities;", K);
    ptr, slot := PagedArrayFindSlot(storage);
    ptr.slot_info = slot;
    ptr.guid = GenerateGUID();
    ptr.name = StringClone(name);

    HashMapInsert(*world.entities_by_guid, ptr.guid, ptr);
    if name {
        HashMapInsert(*world.entities_by_name, ptr.name, ptr);
    }

    return ptr;
}

DestroyEntity :: (world : *World, entity : *Entity) {
    if !entity {
        return;
    }

    DetachEntity(world, entity);

    if entity.name {
        HashMapRemove(*world.entities_by_name, entity.name);
    }
    HashMapRemove(*world.entities_by_guid, entity.guid);

    #insert -> string {
        builder : StringBuilder;

        Appendln(*builder, "if entity.kind == {");
        for kind : type_info(Entity.Kind).names {
            Appendln(*builder, "case .%1; PagedArrayFreeSlot(*world.%1_entities, entity.slot_info);", kind);
        }
        Appendln(*builder, "}");

        return StringBuilderBuild(*builder);
    }
}

UpdateWorldTransform :: (world : *World, entity : *Entity, update_children := true) {
    parent := ifx entity.parent != Null_GUID then GetEntity(world, entity.parent);

    local_transform := Mat4fTransformSRT(entity.local_position, entity.local_rotation, entity.local_scale);

    if parent {
        entity.world_transform = parent.world_transform * local_transform;

        // Remove skewing from world transform
        Q, S := PolarDecompose(entity.world_transform);
        S2 := Mat4f.{r0c0=S.r0c0, r1c1=S.r1c1, r2c2=S.r2c2, r3c3=1};

        T := Mat4fTranslate(TranslationVector(entity.world_transform));

        entity.world_transform = T * ToMat4f(Q) * S2;
    } else {
        entity.world_transform = local_transform;
    }

    entity.inv_world_transform = Inverse(entity.world_transform);

    if update_children {
        for entity.children {
            child := GetEntity(world, it);
            Assert(child != null);

            UpdateWorldTransform(world, child);
        }
    }
}

EntityIsInHierarchy :: (world : *World, entity : *Entity, of : *Entity) -> bool {
    if !entity {
        return false;
    }

    if entity == of {
        return true;
    }

    if of.children.count == 0 {
        return false;
    }

    for of.children {
        child := GetEntity(world, it);
        if entity == child {
            return true;
        }
    }

    for of.children {
        child := GetEntity(world, it);

        if EntityIsInHierarchy(world, entity, child) {
            return true;
        }
    }

    return false;
}

AttachEntity :: (using world : *World, entity : *Entity, to : *Entity) {
    Assert(entity != null);
    Assert(to != null);

    if entity == to {
        LogError("Trying to attach entity to itself");
        return;
    }

    // Detect entity attaching itself to one of its descendants
    if EntityIsInHierarchy(world, to, entity) {
        LogError("Trying to recursively attach entity to one of its descendants");
        return;
    }

    if entity.parent != Null_GUID {
        DetachEntity(world, entity);
    }

    ArrayPush(*to.children, entity.guid);

    entity.parent = to.guid;

    UpdateWorldTransform(world, entity);
}

DetachEntity :: (using world : *World, entity : *Entity) {
    if entity.parent == Null_GUID {
        return;
    }

    parent := GetEntity(world, entity.parent);
    Assert(parent != null);

    child_index := ArrayFindFirst(parent.children, entity.guid, CompareGUIDs);
    Assert(child_index != -1);

    ArrayRemove(*parent.children, child_index);

    entity.parent = Null_GUID;

    UpdateWorldTransform(world, entity);
}

LoadWorld :: (world : *World, filename : string) -> bool {
    LogSectionScope(*Log_Assets);

    world.filename = StringClone(filename);

    cfilename := CStringClone(filename ,, Temp);
    LogMessage("Loading world '%'", filename);
    ai_scene := Assimp.aiImportFileEx(cfilename, xx (Assimp.aiPostProcessSteps.Triangulate | .CalcTangentSpace), null);
    if !ai_scene {
        return false;
    }

    LogMessage("Imported Assimp scene '%'", filename);

    defer Assimp.aiReleaseImport(ai_scene);

    loaded_meshes : [..]*StaticMesh;
    loaded_meshes.allocator = Temp;

    for i : 0..cast(int, ai_scene.mNumMeshes) - 1 {
        ai_mesh := ai_scene.mMeshes[i];
        mesh := CreateStaticMesh();

        if LoadStaticMeshFromAssimpMesh(mesh, ai_mesh) {
            ArrayPush(*loaded_meshes, mesh);
        } else {
            DestroyStaticMesh(mesh);
            ArrayPush(*loaded_meshes, null);
        }
    }

    CreateEntityHierarchy :: (world : *World, parent : *Entity, ai_node : *Assimp.aiNode, loaded_meshes : []*StaticMesh) {
        name := string.{count=ai_node.mName.length, data=ai_node.mName.data.data};
        entity : *Entity;

        position : Vec3f;
        scale : Vec3f;
        ai_rotation : Assimp.aiQuaternion;
        Assimp.aiDecomposeMatrix(*ai_node.mTransformation, xx *scale, *ai_rotation, xx *position);

        rotation := Quatf.{ai_rotation.x, ai_rotation.y, ai_rotation.z, ai_rotation.w};

        if ai_node.mNumMeshes == 0 {
            entity = CreateEntity(world, EmptyEntity);
            entity.local_position = position;
            entity.local_rotation = rotation;
            entity.local_scale = scale;
            if parent {
                AttachEntity(world, entity, parent);
            }
        } else {
            entity : *Entity;
            if ai_node.mNumMeshes > 1 {
                entity = CreateEntity(world, EmptyEntity);
                entity.local_position = position;
                entity.local_rotation = rotation;
                entity.local_scale = scale;
                if parent {
                    AttachEntity(world, entity, parent);
                }
            }

            for i : 0..ai_node.mNumMeshes - 1 {
                mesh_index := ai_node.mMeshes[i];

                mesh_entity := CreateEntity(world, MeshEntity);
                mesh_entity.local_position = position;
                mesh_entity.local_rotation = rotation;
                mesh_entity.local_scale = scale;
                mesh_entity.mesh = loaded_meshes[mesh_index];
                if parent {
                    AttachEntity(world, mesh_entity, parent);
                }

                if !entity {
                    entity = mesh_entity;
                }
            }
        }

        for i : 0..cast(int, ai_node.mNumChildren) - 1 {
            child := ai_node.mChildren[i];
            CreateEntityHierarchy(world, entity, child, loaded_meshes);
        }
    }

    CreateEntityHierarchy(world, null, ai_scene.mRootNode, loaded_meshes);

    LogMessage("Loaded world '%'", filename);

    return true;
}
