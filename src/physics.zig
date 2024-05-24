const std = @import("std");
const zm = @import("zmath");
const jolt = @import("zjolt");

pub fn init(allocator: std.mem.Allocator) !void {
    return jolt.init(allocator, .{});
}

pub fn deinit() void {
    jolt.deinit();
}

pub fn create_box(half_extent: zm.Vec) !*jolt.BoxShapeSettings {
    return jolt.BoxShapeSettings.create(zm.vecToArr3(half_extent));
}

pub const BodyHandle = jolt.BodyId;

pub const Transform = struct {
    position: zm.Vec = zm.splat(zm.Vec, 0.0),
    rotation: zm.Quat = zm.qidentity(),
};

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    broad_phase_layer_interface: *BroadPhaseLayerInterface,
    object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
    object_layer_pair_filter: *ObjectLayerPairFilter,
    contact_listener: *ContactListener,
    physics_system: *jolt.PhysicsSystem,

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

        const physics_system = try jolt.PhysicsSystem.create(
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

        return .{
            .allocator = allocator,
            .broad_phase_layer_interface = broad_phase_layer_interface,
            .object_vs_broad_phase_layer_filter = object_vs_broad_phase_layer_filter,
            .object_layer_pair_filter = object_layer_pair_filter,
            .contact_listener = contact_listener,
            .physics_system = physics_system,
        };
    }

    pub fn deinit(self: *Self) void {
        self.physics_system.destroy();
        self.allocator.destroy(self.contact_listener);
        self.allocator.destroy(self.object_vs_broad_phase_layer_filter);
        self.allocator.destroy(self.object_layer_pair_filter);
        self.allocator.destroy(self.broad_phase_layer_interface);
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        try self.physics_system.update(delta_time, .{});
    }

    pub fn create_body(
        self: *Self,
        tranform: Transform,
        shape: ?*jolt.Shape,
        motion_type: jolt.MotionType,
    ) !BodyHandle {
        const body_interface = self.physics_system.getBodyInterfaceMut();

        const object_layer = switch (motion_type) {
            .static => object_layers.non_moving,
            else => object_layers.moving,
        };

        return try body_interface.createAndAddBody(.{
            .position = zm.vecToArr4(tranform.position),
            .rotation = tranform.rotation,
            .shape = shape,
            .motion_type = motion_type,
            .object_layer = object_layer,
        }, .activate);
    }

    pub fn destory_body(self: *Self, handle: BodyHandle) void {
        const body_interface = self.physics_system.getBodyInterfaceMut();
        body_interface.removeAndDestroyBody(handle);
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
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }
};
