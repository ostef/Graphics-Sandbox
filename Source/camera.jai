Camera :: struct {
    position := #run Normalized(Vec3f.{-1,1,-1}) * 10;
    rotation : Quatf;

    target_yaw := #run ToRads(30.0);
    target_pitch := #run ToRads(30.0);

    yaw := #run ToRads(30.0);
    pitch := #run ToRads(30.0);

    rotation_speed := 0.2;
    rotation_smoothing := 0.3;

    fov_in_degrees := 80.0;
    z_near := 0.1;
    z_far := 1000.0;

    transform : Mat4f;
    view : Mat4f;
    projection : Mat4f;
    inv_projection : Mat4f;
    ortho_projection : Mat4f;
    inv_ortho_projection : Mat4f;

    is_moving : bool;
    speed_mult := 1.0;
    base_speed := 0.1;
    fast_speed := 1.0;
}

CalculateCameraTransforms :: (camera : *Camera, size : Vec2f) {
    camera.yaw = Lerp(camera.yaw, camera.target_yaw, camera.rotation_smoothing);
    camera.pitch = Lerp(camera.pitch, camera.target_pitch, camera.rotation_smoothing);

    camera.rotation = QuatfFromEulerAnglesYXZ(.{x=camera.pitch,y=camera.yaw});

    camera.transform = Mat4fTranslate(camera.position) * Mat4fFromQuat(camera.rotation);
    camera.view = Inverse(camera.transform);

    if Reverse_Depth_Range {
        camera.projection = Mat4fPerspectiveProjection(camera.fov_in_degrees, size.x / size.y, camera.z_far, camera.z_near);
    } else {
        camera.projection = Mat4fPerspectiveProjection(camera.fov_in_degrees, size.x / size.y, camera.z_near, camera.z_far);
    }

    camera.inv_projection = Inverse(camera.projection);

    camera.ortho_projection = Mat4fOrthographicProjection(0, size.x, size.y, 0, -1, 1);
    camera.inv_ortho_projection = Inverse(camera.ortho_projection);
}

UpdateCamera :: (world : *World, camera : *Camera) {
    defer {
        width, height := GetWindowPixelSize(g_window);
        CalculateCameraTransforms(camera, .{xx width, xx height});
    }

    was_moving_camera := camera.is_moving;
    camera.is_moving = IsMouseButtonDown(.Right);

    if !camera.is_moving && was_moving_camera {
        SDL_SetRelativeMouseMode(SDL_FALSE);
    }

    if camera.is_moving {
        SDL_SetRelativeMouseMode(SDL_TRUE);

        mouse_wheel := GetMouseWheel();

        if mouse_wheel.y < 0 {
            camera.speed_mult -= 0.2;
        } else if mouse_wheel.y > 0 {
            camera.speed_mult += 0.2;
        }
        camera.speed_mult = Clamp(camera.speed_mult, 0.2, 100);

        rotation_delta := GetRawMouseDelta() * camera.rotation_speed;

        camera.target_yaw += ToRads(rotation_delta.x);
        camera.target_pitch += ToRads(rotation_delta.y);
        camera.target_pitch = Clamp(camera.target_pitch, ToRads(-90), ToRads(90));

        if !IsKeyDown(.Ctrl) {
            movement_input : Vec3f;
            movement_input.x = GetKeyAxisValue(.A, .D);
            movement_input.y = GetKeyAxisValue(.Q, .E);
            movement_input.z = GetKeyAxisValue(.S, .W);
            movement_input = Normalized(movement_input);

            speed := ifx IsKeyDown(.Shift)
                then camera.fast_speed
                else camera.base_speed;

            speed *= camera.speed_mult;

            // @Todo: delta timing
            camera.position += speed * (
                RightVector(camera.rotation) * movement_input.x +
                UpVector(camera.rotation) * movement_input.y +
                ForwardVector (camera.rotation) * movement_input.z
            );
        }
    }
}

