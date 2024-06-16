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
    is_sensor: bool = false,
};

pub const Character = struct {
    gravity_vector: [3]f32 = .{ 0.0, 0.0, 0.0 },
    character: *jolt.CharacterVirtual,

    pub fn deinit(self: *@This()) void {
        self.character.destroy();
    }
};
const CharacterPool = ObjectPool(u8, Character);
pub const CharacterHandle = CharacterPool.Handle;

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    broad_phase_layer_interface: *BroadPhaseLayerInterface,
    object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
    object_layer_pair_filter: *ObjectLayerPairFilter,
    contact_listener: *ContactListener,
    physics_system: *jolt.PhysicsSystem,

    characters: CharacterPool,

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

        const contact_listener = try allocator.create(ContactListener);
        contact_listener.* = .{};

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

        return .{
            .allocator = allocator,
            .broad_phase_layer_interface = broad_phase_layer_interface,
            .object_vs_broad_phase_layer_filter = object_vs_broad_phase_layer_filter,
            .object_layer_pair_filter = object_layer_pair_filter,
            .contact_listener = contact_listener,
            .physics_system = physics_system,
            .characters = CharacterPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.characters.deinit_with_entries();
        self.physics_system.destroy();
        self.allocator.destroy(self.contact_listener);
        self.allocator.destroy(self.object_vs_broad_phase_layer_filter);
        self.allocator.destroy(self.object_layer_pair_filter);
        self.allocator.destroy(self.broad_phase_layer_interface);
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
            .mass_properties_override = .{},
            .is_sensor = settings.is_sensor,
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
        character_settings.base.shape = shape;

        const character = try jolt.CharacterVirtual.create(character_settings, transform.position.toArray(), .{ transform.rotation.w, transform.rotation.x, transform.rotation.y, transform.rotation.z }, self.physics_system);

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
        self.interface.setPosition(self.id, position.toArray(), .activate);
    }
    pub fn get_position(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getPosition(self.id));
    }
    pub fn get_center_if_mass_position(self: Self) za.Vec3 {
        return za.Vec3.fromArray(self.interface.getCenterOfMassPosition(self.id));
    }

    pub fn set_rotation(self: Self, rotation: za.Quat) void {
        self.interface.setRotation(self.id, rotation.toArray(), .activate);
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

const ContactListener = extern struct {
    usingnamespace jolt.ContactListener.Methods(@This());
    __v: *const jolt.ContactListener.VTable = &vtable,
    const vtable = jolt.ContactListener.VTable{ .onContactValidate = _onContactValidate };

    fn _onContactValidate(
        self: *jolt.ContactListener,
        body1: *const jolt.Body,
        body2: *const jolt.Body,
        base_offset: *const [3]jolt.Real,
        collision_result: *const jolt.CollideShapeResult,
    ) callconv(.C) jolt.ValidateResult {
        _ = self;
        _ = base_offset;
        _ = collision_result;

        if (body1.isSensor() or body2.isSensor()) {
            std.log.info("Contact Body1: {} Body2: {}", .{ body1.id, body2.id });
        }

        return .accept_all_contacts;
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
