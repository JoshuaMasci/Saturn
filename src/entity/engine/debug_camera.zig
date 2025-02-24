const std = @import("std");
const za = @import("zalgebra");

const input = @import("../../input.zig");

const Entity = @import("../entity.zig");
const World = @import("../world.zig");
const physics = @import("physics.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;

const StringHash = @import("../../string_hash.zig");
const DebugCameraInputContext = StringHash.new("DebugCamera");
const DebugCameraForwardBackwardAxis = StringHash.new("DebugCameraForwardBackward");
const DebugCamearInteract = StringHash.new("DebugCameraInteract");

pub const DebugCameraEntitySystem = struct {
    const Self = @This();

    linear_speed: za.Vec3 = za.Vec3.set(5.0),
    angular_speed: za.Vec3 = za.Vec3.set(std.math.pi),

    linear_input: za.Vec3 = za.Vec3.ZERO,
    angular_input: za.Vec3 = za.Vec3.ZERO,

    cast_ray: bool = false,

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn updateParallel(self: *Self, stage: UpdateStage, entity: *Entity, delta_time: f32) void {
        if (stage != .pre_physics)
            return;

        if (@import("../../global.zig").input.getContext(DebugCameraInputContext)) |input_context| {
            self.linear_input.zMut().* = input_context.getAxisValue(DebugCameraForwardBackwardAxis, true);

            if (input_context.isButtonPressed(DebugCamearInteract)) {
                self.cast_ray = true;
            }
        }

        const linear_speed = entity.transform.rotation.rotateVec(self.linear_input.mul(
            self.linear_speed,
        ));
        if (entity.systems.get(physics.PhysicsEntitySystem)) |entity_physics| {
            entity_physics.linear_velocity = linear_speed;
            entity_physics.angular_velocity = za.Vec3.ZERO;
        } else {
            entity.transform.position = entity.transform.position.add(linear_speed.scale(delta_time));
        }

        const angular_rotation = self.angular_input.mul(self.angular_speed).scale(delta_time);

        const foward = entity.transform.getForward();
        const y = foward.y();
        const xz = foward.swizzle2(.x, .z);

        const pitch = -std.math.atan2(y, xz.length());
        const yaw = std.math.atan2(xz.x(), xz.y());
        var pitch_yaw = za.Vec2.new(pitch, yaw).add(angular_rotation.toVec2());

        // Clamp pitch and keep roation between 0->360 degrees
        const pi_2 = std.math.pi * 2.0;
        const max_angle: f32 = std.math.degreesToRadians(89.9);
        pitch_yaw = za.Vec2.new(std.math.clamp(pitch_yaw.x(), -max_angle, max_angle), @mod(pitch_yaw.y(), pi_2));

        const pitch_quat = za.Quat.fromAxis(pitch_yaw.x(), za.Vec3.X);
        const yaw_quat = za.Quat.fromAxis(pitch_yaw.y(), za.Vec3.Y);
        entity.transform.rotation = yaw_quat.mul(pitch_quat).norm();

        // Axis events should fire each frame they are active, so the input is reset each update
        self.angular_input = za.Vec3.set(0.0);
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
                        entity_transform.getForward().scale(10.0),
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

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        if (event.button == .player_interact and event.state == .pressed) {
            self.cast_ray = true;
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        switch (event.axis) {
            .player_move_left_right => self.linear_input.data[0] = event.get_value(true),
            .player_move_up_down => self.linear_input.data[1] = event.get_value(true),
            .player_move_forward_backward => self.linear_input.data[2] = event.get_value(true),

            .player_rotate_pitch => self.angular_input.data[0] = event.get_value(false),
            .player_rotate_yaw => self.angular_input.data[1] = event.get_value(false),

            //else => {},
        }
    }
};
