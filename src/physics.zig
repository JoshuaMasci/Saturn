const std = @import("std");
const za = @import("zalgebra");
const jolt = @import("zjolt");

const UnscaledTransform = @import("unscaled_transform.zig");
const ObjectPool = @import("object_pool.zig").ObjectPool;

pub fn init(allocator: std.mem.Allocator) !void {
    return jolt.init(allocator, .{});
}

pub fn deinit() void {
    jolt.deinit();
}

pub fn create_sphere(radius: f32) !Shape {
    var settings = try jolt.SphereShapeSettings.create(radius);
    defer settings.release();
    return try settings.createShape();
}

pub fn create_box(half_extent: za.Vec3) !Shape {
    var settings = try jolt.BoxShapeSettings.create(half_extent.toArray());
    defer settings.release();
    return try settings.createShape();
}

pub fn create_cylinder(
    half_height: f32,
    radius: f32,
) !Shape {
    var settings = try jolt.CylinderShapeSettings.create(half_height, radius);
    defer settings.release();
    return try settings.createShape();
}

pub fn create_capsule(
    half_height: f32,
    radius: f32,
) !Shape {
    var settings = try jolt.CapsuleShapeSettings.create(half_height, radius);
    defer settings.release();
    return try settings.createShape();
}

pub const BodyHandle = jolt.BodyId;
pub const Shape = *jolt.Shape;

pub const BodyMotionType = jolt.MotionType;
pub const BodySettings = struct {
    motion_type: BodyMotionType = .dynamic,
};

pub const Character = struct {
    gravity_vector: [3]f32 = .{ 0.0, 0.0, 0.0 },
    character: *jolt.CharacterVirtual,
    //TODO: Add rigidbody for ability to push objects

    pub fn deinit(self: *@This()) void {
        self.character.destroy();
    }
};
const CharacterPool = ObjectPool(u8, Character);
pub const CharacterHandle = CharacterPool.Handle;

pub const GravityVolume = struct {
    body_id: jolt.BodyId,
    bodies_in_volume: std.AutoHashMap(jolt.BodyId, f32),
    point_gravity_strength: f32,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        const radius = 50.0;
        const gravity_at_surface = 9.8;
        const force = gravity_at_surface * (radius * radius);

        return .{
            .body_id = 0,
            .bodies_in_volume = std.AutoHashMap(jolt.BodyId, f32).init(allocator),
            .point_gravity_strength = force,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.bodies_in_volume.deinit();
    }
};
pub const GravityVolumeMap = std.AutoHashMap(jolt.BodyId, *GravityVolume);

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    broad_phase_layer_interface: *BroadPhaseLayerInterface,
    object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
    object_layer_pair_filter: *ObjectLayerPairFilter,
    contact_listener: *ContactListener,
    physics_system: *jolt.PhysicsSystem,

    characters: CharacterPool,

    gravity_volumes: *GravityVolumeMap,
    gravity_step_listener: *GravityStepListener,

    pub fn init(allocator: std.mem.Allocator, args: struct {
        max_bodies: u32 = 1024,
        num_body_mutexes: u32 = 0,
        max_body_pairs: u32 = 1024,
        max_contact_constraints: u32 = 1024,
    }) !Self {
        const broad_phase_layer_interface = try allocator.create(BroadPhaseLayerInterface);
        broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();

        const object_vs_broad_phase_layer_filter = try allocator.create(ObjectVsBroadPhaseLayerFilter);
        object_vs_broad_phase_layer_filter.* = .{};

        const object_layer_pair_filter = try allocator.create(ObjectLayerPairFilter);
        object_layer_pair_filter.* = .{};

        const gravity_volumes = try allocator.create(GravityVolumeMap);
        gravity_volumes.* = GravityVolumeMap.init(allocator);

        const contact_listener = try allocator.create(ContactListener);
        contact_listener.* = .{ .gravity_volumes = gravity_volumes };

        var physics_system = try jolt.PhysicsSystem.create(
            @as(*const jolt.BroadPhaseLayerInterface, @ptrCast(broad_phase_layer_interface)),
            @as(*const jolt.ObjectVsBroadPhaseLayerFilter, @ptrCast(object_vs_broad_phase_layer_filter)),
            @as(*const jolt.ObjectLayerPairFilter, @ptrCast(object_layer_pair_filter)),
            .{
                .max_bodies = args.max_bodies,
                .num_body_mutexes = args.num_body_mutexes,
                .max_body_pairs = args.max_body_pairs,
                .max_contact_constraints = args.max_contact_constraints,
            },
        );
        physics_system.setContactListener(contact_listener);

        physics_system.setGravity(.{ 0.0, 0.0, 0.0 });

        const gravity_step_listener = try allocator.create(GravityStepListener);
        gravity_step_listener.* = .{ .gravity_volumes = gravity_volumes };
        physics_system.addStepListener(gravity_step_listener);

        {
            var body_interface = physics_system.getBodyInterfaceMut();
            var shape = try create_sphere(150.0);
            defer shape.release();
            const body_id = try body_interface.createAndAddBody(.{
                .position = .{ 0.0, 100.0, 0.0, 0.0 },
                .rotation = .{ 1.0, 0.0, 0.0, 0.0 },
                .shape = shape,
                .motion_type = .static,
                .object_layer = object_layers.non_moving,
                .mass_properties_override = .{},
                .is_sensor = true,
            }, .activate);
            const gravity_volume = try allocator.create(GravityVolume);
            gravity_volume.* = try GravityVolume.init(allocator);
            gravity_volume.body_id = body_id;
            try gravity_volumes.put(body_id, gravity_volume);
        }

        return .{
            .allocator = allocator,
            .broad_phase_layer_interface = broad_phase_layer_interface,
            .object_vs_broad_phase_layer_filter = object_vs_broad_phase_layer_filter,
            .object_layer_pair_filter = object_layer_pair_filter,
            .contact_listener = contact_listener,
            .physics_system = physics_system,
            .characters = CharacterPool.init(allocator),
            .gravity_volumes = gravity_volumes,
            .gravity_step_listener = gravity_step_listener,
        };
    }

    pub fn deinit(self: *Self) void {
        var volume_iterator = self.gravity_volumes.iterator();
        while (volume_iterator.next()) |volume_entry| {
            volume_entry.value_ptr.*.deinit();
            self.allocator.destroy(volume_entry.value_ptr.*);
        }
        self.gravity_volumes.deinit();
        self.allocator.destroy(self.gravity_volumes);
        self.allocator.destroy(self.gravity_step_listener);

        self.characters.deinit_with_entries();
        self.physics_system.destroy();
        self.contact_listener.deinit();
        self.allocator.destroy(self.contact_listener);
        self.allocator.destroy(self.object_vs_broad_phase_layer_filter);
        self.allocator.destroy(self.object_layer_pair_filter);
        self.allocator.destroy(self.broad_phase_layer_interface);
    }

    //TODO: temp math to be removed later
    pub fn try_orbit(self: *Self, body_handle: BodyHandle) void {
        var iterator = self.gravity_volumes.iterator();
        if (iterator.next()) |volume_entry| {
            const center_of_gravity = self.get_body(volume_entry.value_ptr.*.body_id).get_position();

            var body_interface = self.get_body(body_handle);
            const body_position = body_interface.get_position();
            const distance = center_of_gravity.sub(body_position).length();
            const orbital_velocity = @sqrt(volume_entry.value_ptr.*.point_gravity_strength / distance);
            body_interface.set_linear_velocity(za.Vec3.NEG_Z.scale(orbital_velocity));

            const orbital_period = 2.0 * std.math.pi * @sqrt(std.math.pow(f32, distance, 3.0) / volume_entry.value_ptr.*.point_gravity_strength);

            std.log.info("orbital_velocity: {d:.3}", .{orbital_velocity});
            std.log.info("orbital_period: {d:.3}s", .{orbital_period});
        }
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        {
            var character_iter = self.characters.iterator();
            while (character_iter.next()) |entry| {
                //TODO: add wrapper for extented_update for stick_to_floor and walk_stair
                entry.value_ptr.character.update(delta_time, entry.value_ptr.gravity_vector, .{});
            }
        }

        try self.physics_system.update(delta_time, .{});
    }

    pub fn create_body(
        self: *Self,
        tranform: UnscaledTransform,
        shape: *jolt.Shape,
        settings: BodySettings,
    ) !BodyHandle {
        const body_interface = self.physics_system.getBodyInterfaceMut();

        const object_layer = switch (settings.motion_type) {
            .static => object_layers.non_moving,
            else => object_layers.moving,
        };

        return try body_interface.createAndAddBody(.{
            .position = tranform.position.toVec4(0.0).toArray(),
            .rotation = tranform.rotation.toArray(),
            .shape = shape,
            .motion_type = settings.motion_type,
            .object_layer = object_layer,
            .linear_damping = 0.0,
            .angular_damping = 0.0,
        }, .activate);
    }

    pub fn destory_body(self: *Self, handle: BodyHandle) void {
        const body_interface = self.physics_system.getBodyInterfaceMut();
        body_interface.removeAndDestroyBody(handle);
    }

    pub fn get_body(self: *Self, handle: BodyHandle) BodyInterface {
        return .{
            .id = handle,
            .interface = self.physics_system.getBodyInterfaceMut(),
        };
    }

    pub fn create_character(
        self: *Self,
        transform: UnscaledTransform,
        shape: *jolt.Shape,
    ) !CharacterHandle {
        var character_settings = try jolt.CharacterVirtualSettings.create();
        defer character_settings.release();

        const up = transform.get_up();

        character_settings.base.up = up.toVec4(0.0).toArray();
        character_settings.base.max_slope_angle = 45.0;
        character_settings.base.shape = shape;

        const character = try jolt.CharacterVirtual.create(
            character_settings,
            transform.position.toArray(),
            .{ transform.rotation.w, transform.rotation.x, transform.rotation.y, transform.rotation.z },
            self.physics_system,
        );

        return self.characters.insert(.{
            .character = character,
        });
    }

    pub fn destroy_character(self: *Self, handle: CharacterHandle) !void {
        if (try self.characters.remove(handle)) |character| {
            character.deinit();
        }
    }

    pub fn get_character(self: *Self, handle: CharacterHandle) ?CharacterInterface {
        if (self.characters.getPtr(handle)) |ptr| {
            return .{ .ptr = ptr };
        } else {
            return null;
        }
    }
};

pub const BodyInterface = struct {
    const Self = @This();

    id: jolt.BodyId,
    interface: *jolt.BodyInterface,

    pub fn setActive(self: Self, active: bool) void {
        if (active) {
            self.interface.activate(self.id);
        } else {
            self.interface.deactivate(self.id);
        }
    }

    pub fn isActive(self: Self) bool {
        return self.interface.isActive(self.id);
    }

    pub fn set_linear_velocity(self: Self, velocity: za.Vec3) void {
        self.interface.setLinearVelocity(self.id, velocity.toArray());
    }
    pub fn get_linear_velocity(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getLinearVelocity(self.id));
    }
    pub fn add_linear_velocity(self: Self, velocity: za.Vec3) void {
        self.interface.addLinearVelocity(self.id, velocity.toArray());
    }

    pub fn set_angular_velocity(self: Self, velocity: za.Vec3) void {
        self.interface.setAngularVelocity(self.id, velocity.toArray());
    }
    pub fn get_angular_velocity(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getAngularVelocity(self.id));
    }

    pub fn get_point_velocity(self: Self, point: za.Vec3) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getPointVelocity(self.id, point));
    }

    pub fn set_position(self: Self, position: za.Vec3) void {
        self.interface.setPosition(self.id, position.toArray(), .dont_activate);
    }
    pub fn get_position(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getPosition(self.id));
    }
    pub fn get_center_if_mass_position(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getCenterOfMassPosition(self.id));
    }

    pub fn set_rotation(self: Self, rotation: za.Quat) void {
        self.interface.setRotation(self.id, rotation.toArray(), .dont_activate);
    }
    pub fn get_rotation(self: Self) za.Quat {
        return za.Quat.fromArray(self.interface.getRotation(self.id));
    }

    pub fn set_transform(self: Self, transform: UnscaledTransform) void {
        self.set_position(transform.position);
        self.set_rotation(transform.rotation);
    }
    pub fn get_transform(self: Self) UnscaledTransform {
        return .{
            .position = self.get_position(),
            .rotation = self.get_rotation(),
        };
    }
    pub fn set_transform_if_changed(self: Self, transform: UnscaledTransform) void {
        const current_transform = self.get_transform();
        if (!current_transform.eql(transform)) {
            self.set_transform(transform);
        }
    }

    pub fn add_force(self: Self, force: za.Vec3) void {
        self.interface.addForce(self.id, force.toArray());
    }
    pub fn add_force_at_position(self: Self, force: za.Vec3, position: za.Vec3) void {
        self.interface.addForceAtPosition(self.id, force.toArray(), position.toArray());
    }
    pub fn add_torque(self: Self, torque: za.Vec3) void {
        self.interface.addTorque(self.id, torque.toArray());
    }

    pub fn add_tmpulse(self: Self, impulse: za.Vec3) void {
        self.interface.addImpulse(self.id, impulse.toArray());
    }
    pub fn add_impulse_at_position(self: Self, impulse: za.Vec3, position: za.Vec3) void {
        self.interface.addImpulseAtPosition(self.id, impulse.toArray(), position.toArray());
    }
    pub fn add_angular_impulse(self: Self, impulse: za.Vec3) void {
        self.interface.addAngularImpulse(self.id, impulse.toArray());
    }
};

pub const CharacterInterface = struct {
    const Self = @This();

    ptr: *Character,

    pub fn set_linear_velocity(self: Self, velocity: za.Vec3) void {
        self.ptr.character.setLinearVelocity(velocity.toArray());
    }
    pub fn get_linear_velocity(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.ptr.character.getLinearVelocity());
    }
    pub fn add_linear_velocity(self: Self, velocity: za.Vec3) void {
        self.set_linear_velocity(self.get_linear_velocity().add(velocity));
    }

    pub fn set_position(self: Self, position: za.Vec3) void {
        self.ptr.character.setPosition(position.toArray());
    }
    pub fn get_position(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.ptr.character.getPosition());
    }

    pub fn set_rotation(self: Self, rotation: za.Quat) void {
        self.ptr.character.setUp(rotation.rotateVec(za.Vec3.Y).toArray()); //TODO: seperate rotation up from character up?
        self.ptr.character.setRotation(rotation.toArray());
    }
    pub fn get_rotation(self: Self) za.Quat {
        return za.Quat.fromArray(self.ptr.character.getRotation());
    }

    pub fn set_transform(self: Self, transform: UnscaledTransform) void {
        self.set_position(transform.position);
        self.set_rotation(transform.rotation);
    }
    pub fn get_transform(self: Self) UnscaledTransform {
        return .{
            .position = self.get_position(),
            .rotation = self.get_rotation(),
        };
    }

    pub fn get_ground_state(self: Self) jolt.CharacterGroundState {
        return self.ptr.character.getGroundState();
    }

    /// Sets gravity, only used for collision, doesn't change velocity
    pub fn set_gravity(self: Self, gravity: za.Vec3) void {
        self.ptr.gravity_vector = gravity.toArray();
    }
};

const object_layers = struct {
    const non_moving: jolt.ObjectLayer = 0;
    const moving: jolt.ObjectLayer = 1;
    const len: u32 = 2;
};

const broad_phase_layers = struct {
    const non_moving: jolt.BroadPhaseLayer = 0;
    const moving: jolt.BroadPhaseLayer = 1;
    const len: u32 = 2;
};

pub const AreaIdPair = struct {
    area: struct {
        body_id: jolt.BodyId,
        sub_shape_id: jolt.SubShapeId,
    },
    body: struct {
        body_id: jolt.BodyId,
        sub_shape_id: jolt.SubShapeId,
    },
};

const ContactListener = struct {
    usingnamespace jolt.ContactListener.Methods(@This());
    __v: *const jolt.ContactListener.VTable = &vtable,

    gravity_volumes: *GravityVolumeMap,

    const vtable = jolt.ContactListener.VTable{
        .onContactAdded = _onContactAdded,
        .onContactRemoved = _onContactRemoved,
    };

    pub fn deinit(self: *@This()) void {
        _ = self; // autofix
    }

    pub fn _onContactAdded(
        cl: *jolt.ContactListener,
        body1: *const jolt.Body,
        body2: *const jolt.Body,
        manifold: *const jolt.ContactManifold,
        settings: *jolt.ContactSettings,
    ) callconv(.C) void {
        _ = manifold; // autofix
        _ = settings; // autofix

        const self = @as(*ContactListener, @ptrCast(cl));

        if (self.gravity_volumes.get(body1.id)) |gravity_volume| {
            //std.log.info("Adding Body2: {}:{}", .{ body2.id, manifold.shape2_sub_shape_id });
            gravity_volume.bodies_in_volume.put(body2.id, body2.motion_properties.?.gravity_factor) catch |err| std.debug.panic("Failed to append set: {}", .{err});
        }

        if (self.gravity_volumes.get(body2.id)) |gravity_volume| {
            //std.log.info("Adding Body1: {}:{}", .{ body1.id, manifold.shape1_sub_shape_id });
            gravity_volume.bodies_in_volume.put(body1.id, body1.motion_properties.?.gravity_factor) catch |err| std.debug.panic("Failed to append set: {}", .{err});
        }
    }

    pub fn _onContactRemoved(
        cl: *jolt.ContactListener,
        sub_shape_pair: *const jolt.SubShapeIdPair,
    ) callconv(.C) void {
        const self = @as(*ContactListener, @ptrCast(cl));

        if (self.gravity_volumes.get(sub_shape_pair.first.body_id)) |gravity_volume| {
            //std.log.info("Adding Body2: {}:{}", .{ body2.id, manifold.shape2_sub_shape_id });
            _ = gravity_volume.bodies_in_volume.remove(sub_shape_pair.second.body_id);
        }

        if (self.gravity_volumes.get(sub_shape_pair.second.body_id)) |gravity_volume| {
            //std.log.info("Adding Body1: {}:{}", .{ body1.id, manifold.shape1_sub_shape_id });
            _ = gravity_volume.bodies_in_volume.remove(sub_shape_pair.first.body_id);
        }
    }
};

const GravityAffectedBody = struct {
    id: jolt.BodyId,
    gravity_factor: f32,
};

const GravityStepListener = extern struct {
    usingnamespace jolt.PhysicsStepListener.Methods(@This());
    __v: *const jolt.PhysicsStepListener.VTable = &vtable,

    gravity_volumes: *GravityVolumeMap,

    const vtable = jolt.PhysicsStepListener.VTable{ .onStep = _onStep };

    fn _onStep(psl: *jolt.PhysicsStepListener, delta_time: f32, physics_system: *jolt.PhysicsSystem) callconv(.C) void {
        const self = @as(*GravityStepListener, @ptrCast(psl));
        const body_interface = physics_system.getBodyInterfaceMutNoLock();

        var volume_iterator = self.gravity_volumes.iterator();
        while (volume_iterator.next()) |volume_entry| {
            const gravity_strength = volume_entry.value_ptr.*.point_gravity_strength;
            const center_of_gravity = za.Vec3.fromArray(body_interface.getPosition(volume_entry.key_ptr.*));

            var iterator = volume_entry.value_ptr.*.bodies_in_volume.iterator();
            while (iterator.next()) |affected_body| {
                const body_id = affected_body.key_ptr.*;
                const gravity_factor = affected_body.value_ptr.*;

                if (body_interface.isActive(body_id)) {
                    const body_position = za.Vec3.fromArray(body_interface.getPosition(body_id));
                    const distance2 = std.math.pow(f32, center_of_gravity.sub(body_position).length(), 2);
                    const gravity_scale = gravity_strength / (distance2);
                    const gravity_vector = center_of_gravity.sub(body_position).norm().scale(gravity_scale * gravity_factor * delta_time);
                    const velocity = za.Vec3.fromArray(body_interface.getLinearVelocity(body_id));
                    body_interface.setLinearVelocity(body_id, velocity.add(gravity_vector).toArray());
                }
            }
        }
    }
};

const BroadPhaseLayerInterface = extern struct {
    usingnamespace jolt.BroadPhaseLayerInterface.Methods(@This());
    __v: *const jolt.BroadPhaseLayerInterface.VTable = &vtable,

    object_to_broad_phase: [object_layers.len]jolt.BroadPhaseLayer = undefined,

    const vtable = jolt.BroadPhaseLayerInterface.VTable{
        .getNumBroadPhaseLayers = _getNumBroadPhaseLayers,
        .getBroadPhaseLayer = _getBroadPhaseLayer,
    };

    fn init() BroadPhaseLayerInterface {
        var layer_interface: BroadPhaseLayerInterface = .{};
        layer_interface.object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        layer_interface.object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return layer_interface;
    }

    fn _getNumBroadPhaseLayers(_: *const jolt.BroadPhaseLayerInterface) callconv(.C) u32 {
        return broad_phase_layers.len;
    }

    fn _getBroadPhaseLayer(
        iself: *const jolt.BroadPhaseLayerInterface,
        layer: jolt.ObjectLayer,
    ) callconv(.C) jolt.BroadPhaseLayer {
        const self = @as(*const BroadPhaseLayerInterface, @ptrCast(iself));
        return self.object_to_broad_phase[layer];
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    usingnamespace jolt.ObjectVsBroadPhaseLayerFilter.Methods(@This());
    __v: *const jolt.ObjectVsBroadPhaseLayerFilter.VTable = &vtable,
    const vtable = jolt.ObjectVsBroadPhaseLayerFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const jolt.ObjectVsBroadPhaseLayerFilter,
        layer1: jolt.ObjectLayer,
        layer2: jolt.BroadPhaseLayer,
    ) callconv(.C) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    usingnamespace jolt.ObjectLayerPairFilter.Methods(@This());
    __v: *const jolt.ObjectLayerPairFilter.VTable = &vtable,
    const vtable = jolt.ObjectLayerPairFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const jolt.ObjectLayerPairFilter,
        object1: jolt.ObjectLayer,
        object2: jolt.ObjectLayer,
    ) callconv(.C) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const BroadPhaseLayerFilter = extern struct {
    usingnamespace jolt.BroadPhaseLayerFilter.Methods(@This());
    __v: *const jolt.BroadPhaseLayerFilter.VTable = &vtable,
    const vtable = jolt.BroadPhaseLayerFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const jolt.BroadPhaseLayerFilter,
        layer: jolt.BroadPhaseLayer,
    ) callconv(.C) bool {
        _ = layer; // autofix
        return true;
    }
};
