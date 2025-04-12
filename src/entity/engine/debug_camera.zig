const std = @import("std");
const zm = @import("zmath");

const input = @import("../../input.zig");

const Entity = @import("../entity.zig");
const World = @import("../world.zig");
const physics = @import("physics.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;

pub const DebugCameraEntitySystem = struct {
    const Self = @This();

    linear_speed: zm.Vec = zm.splat(zm.Vec, 5.0),
    angular_speed: zm.Vec = zm.splat(zm.Vec, std.math.pi),

    linear_input: zm.Vec = zm.splat(zm.Vec, 0.0),
    angular_input: zm.Vec = zm.splat(zm.Vec, 0.0),

    cast_ray: bool = false,

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn updateParallel(self: *Self, stage: UpdateStage, entity: *Entity, delta_time: f32) void {
        if (stage != .pre_physics)
            return;

        const linear_speed = zm.rotate(entity.transform.rotation, self.linear_input * self.linear_speed);
        if (entity.systems.get(physics.PhysicsEntitySystem)) |entity_physics| {
            entity_physics.linear_velocity = linear_speed;
            entity_physics.angular_velocity = zm.splat(zm.Vec, 0.0);
        } else {
            entity.transform.position += linear_speed * zm.f32x4s(delta_time);
        }

        const angular_rotation = self.angular_input * self.angular_speed * zm.f32x4s(delta_time);

        const forward = entity.transform.getForward();
        const x = forward[0];
        const y = forward[1];
        const z = forward[2];
        const xz = zm.loadArr2(.{ x, z });

        const pitch = -std.math.atan2(y, zm.length2(xz)[0]);
        const yaw = std.math.atan2(x, z);
        var pitch_yaw = zm.loadArr2(.{ pitch, yaw }) + angular_rotation;

        // Clamp pitch and keep roation between 0->360 degrees
        const pi_2 = std.math.pi * 2.0;
        const max_angle: f32 = std.math.degreesToRadians(89.9);
        pitch_yaw = zm.loadArr2(.{ std.math.clamp(pitch_yaw[0], -max_angle, max_angle), @mod(pitch_yaw[1], pi_2) });

        const pitch_quat = zm.quatFromAxisAngle(zm.f32x4(1, 0, 0, 0), pitch_yaw[0]);
        const yaw_quat = zm.quatFromAxisAngle(zm.f32x4(0, 1, 0, 0), pitch_yaw[1]);
        entity.transform.rotation = zm.normalize4(zm.qmul(pitch_quat, yaw_quat));

        // Axis events should fire each frame they are active, so the input is reset each update
        self.angular_input = zm.splat(zm.Vec, 0.0);
    }

    pub fn updateExclusive(self: *Self, stage: UpdateStage, entity: *Entity, delta_time: f32) void {
        _ = delta_time; // autofix

        if (stage == .post_physics) {
            if (self.cast_ray) {
                if (entity.world.?.systems.get(physics.PhysicsWorldSystem)) |physics_world| {
                    const entity_transform = entity.getWorldTransform();

                    if (physics_world.castRayIgnoreEntity(
                        1,
                        entity,
                        entity_transform.position,
                        entity_transform.getForward() * zm.splat(zm.Vec, 10.0),
                    )) |hit| {
                        const hit_entity = entity.world.?.entities.get(hit.entity_handle).?;
                        if (hit_entity.systems.get(@import("../../game/button.zig").ButtonComponent)) |button| {
                            button.pressButton(hit_entity.universe);
                        }
                    }
                }
                self.cast_ray = false;
            }
        }
    }

    pub fn onInput(self: *Self, input_context: *const @import("../../input_bindings.zig").DebugCameraInputContext) void {
        if (input_context.getButtonPressed(.interact)) {
            self.cast_ray = true;
        }

        self.linear_input[0] = input_context.getAxisValue(.move_left_right, true);
        self.linear_input[1] = input_context.getAxisValue(.move_up_down, true);
        self.linear_input[2] = input_context.getAxisValue(.move_forward_backward, true);

        self.angular_input[0] = input_context.getAxisValue(.rotate_pitch, true);
        self.angular_input[1] = input_context.getAxisValue(.rotate_yaw, true);
    }
};
