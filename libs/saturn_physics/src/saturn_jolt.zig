const std = @import("std");

const c = @cImport({
    @cInclude("saturn_jolt.h");
});

// TODO LIST:
//  1. Shape Functions
//  2. Volume
//  3. VirtualCharacter
//  4. Multi Shape functions

pub fn init(allocator: std.mem.Allocator) void {
    std.debug.assert(mem_allocator == null and mem_allocations == null);

    mem_allocator = allocator;
    mem_allocations = std.AutoHashMap(usize, SizeAndAlignment).init(allocator);
    mem_allocations.?.ensureTotalCapacity(32) catch unreachable;

    c.init(&c.AllocationFunctions{
        .alloc = zjoltAlloc,
        .free = zjoltFree,
        .aligned_alloc = zjoltAlignedAlloc,
        .aligned_free = zjoltFree,
        .realloc = zjoltReallocate,
    });
}
pub fn deinit() void {
    c.deinit();

    mem_allocations.?.deinit();
    mem_allocations = null;
    mem_allocator = null;
}

// Shapes
pub const Shape = struct {
    const Self = @This();

    handle: c.ShapeHandle,

    pub fn init_sphere(radius: f32, density: f32) Self {
        return .{
            .handle = c.create_sphere_shape(radius, density),
        };
    }

    pub fn init_box(half_extent: [3]f32, density: f32) Self {
        return .{
            .handle = c.create_box_shape(&half_extent, density),
        };
    }

    pub fn init_cylinder(half_height: f32, radius: f32, density: f32) Self {
        return .{
            .handle = c.create_cylinder_shape(half_height, radius, density),
        };
    }

    pub fn init_capsule(half_height: f32, radius: f32, density: f32) Self {
        return .{
            .handle = c.create_capsule_shape(half_height, radius, density),
        };
    }

    pub fn init_convex_hull(positions: [][3]f32, density: f32) Self {
        return .{
            .handle = c.create_convex_hull_shape(@alignCast(@ptrCast(positions.ptr)), positions.len, density),
        };
    }

    pub fn init_mesh(positions: [][3]f32, indices: []u32) Self {
        return .{
            .handle = c.create_mesh_shape(@alignCast(@ptrCast(positions.ptr)), positions.len, @alignCast(@ptrCast(indices.ptr)), indices.len),
        };
    }

    pub fn init_compound_shape() Self {
        return .{
            .handle = c.create_mut_compound_shape(),
        };
    }

    pub fn deinit(self: Self) void {
        c.destroy_shape(self.handle);
    }

    // Will crash if not given compound shape handle
    //TODO: move compound shape functions elsewhere?
    pub fn add_child_shape(self: Self, transform: *const Transform, child_shape: Shape, user_data: u32) ChildHandle {
        return c.add_child_shape(self.handle, transform, child_shape.handle, user_data);
    }
    pub fn remove_child_shape(self: Self, child_handle: ChildHandle) void {
        return c.remove_child_shape(self.handle, child_handle);
    }
    pub fn modify_child_shape(self: Self, child_handle: ChildHandle, transform: *const Transform) ChildHandle {
        return c.remove_child_shape(self.handle, child_handle, transform);
    }
    pub fn recalculate_center_of_mass(self: Self) void {
        c.recalculate_center_of_mass(self.handle);
    }
};

pub const Transform = c.Transform;
pub const ObjectLayer = c.ObjectLayer;
pub const BodyHandle = c.BodyHandle;
pub const MotionType = enum(u32) {
    static = 0,
    kinematic = 1,
    dynamic = 2,
};
pub const ChildHandle = c.ChildShapeHandle;

pub const BodySettings = struct {
    shape: Shape,
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    linear_velocity: [3]f32 = .{ 0.0, 0.0, 0.0 },
    angular_velocity: [3]f32 = .{ 0.0, 0.0, 0.0 },
    user_data: u64 = 0,
    object_layer: ObjectLayer = 0,
    motion_type: MotionType,
    is_sensor: bool = false,
    allow_sleep: bool = true,
    friction: f32 = 0.2,
    linear_damping: f32 = 0.05,
    angular_damping: f32 = 0.05,
    gravity_factor: f32 = 1.0,
};

pub const CharacterHandle = u32; // TODO: this

pub const GroundState = enum(u32) {
    OnGround = 0,
    OnSteepGround = 1,
    InAir = 2,
    NotSupported = 3,
};

pub const RayCastHit = c.RayCastHit;
pub const ShapeCastHit = c.ShapeCastHit;
pub const ShapeCastCallback = *const fn (?*anyopaque, ShapeCastHit) callconv(.C) void;

// World
pub const World = struct {
    const Self = @This();

    pub const Settings = struct {
        max_bodies: u32 = 1024,
        num_body_mutexes: u32 = 0,
        max_body_pairs: u32 = 1024,
        max_contact_constraints: u32 = 1024,
        temp_allocation_size: u32 = 1024 * 1024 * 10,
    };

    ptr: ?*c.PhysicsWorld,

    pub fn init(settings: Settings) Self {
        return .{
            .ptr = c.create_physics_world(&.{
                .max_bodies = settings.max_bodies,
                .num_body_mutexes = settings.num_body_mutexes,
                .max_body_pairs = settings.max_body_pairs,
                .max_contact_constraints = settings.max_contact_constraints,
                .temp_allocation_size = settings.temp_allocation_size,
            }),
        };
    }
    pub fn deinit(self: *Self) void {
        c.destroy_physics_world(self.ptr);
    }

    pub fn update(self: *Self, delta_time: f32, collisions_steps: i32) void {
        c.update_physics_world(self.ptr, delta_time, collisions_steps);
    }

    pub fn add_body(self: *Self, body_settings: *const BodySettings) BodyHandle {
        const c_body_settings: c.BodySettings = .{
            .shape = body_settings.shape.handle,
            .position = body_settings.position,
            .rotation = body_settings.rotation,
            .linear_velocity = body_settings.linear_velocity,
            .angular_velocity = body_settings.angular_velocity,
            .user_data = body_settings.user_data,
            .object_layer = body_settings.object_layer,
            .motion_type = @intFromEnum(body_settings.motion_type),
            .is_sensor = body_settings.is_sensor,
            .allow_sleep = body_settings.allow_sleep,
            .friction = body_settings.friction,
            .linear_damping = body_settings.linear_damping,
            .angular_damping = body_settings.angular_damping,
            .gravity_factor = body_settings.gravity_factor,
        };
        const handle = c.create_body(self.ptr, &c_body_settings);

        return handle;
    }

    pub fn remove_body(self: *Self, handle: BodyHandle) void {
        c.destroy_body(self.ptr, handle);
    }

    pub fn get_body_transform(self: *Self, handle: BodyHandle) Transform {
        return c.get_body_transform(self.ptr, handle);
    }
    pub fn set_body_transform(self: *Self, handle: BodyHandle, transform: *const Transform) void {
        return c.set_body_transform(self.ptr, handle, transform);
    }

    pub fn get_body_linear_velocity(self: *Self, handle: BodyHandle) [3]f32 {
        var velocity: [3]f32 = .{ 0.0, 0.0, 0.0 };
        c.get_body_linear_velocity(self.ptr, handle, @ptrCast(&velocity[0]));
        return velocity;
    }
    pub fn set_body_linear_velocity(self: *Self, handle: BodyHandle, velocity: [3]f32) void {
        const c_velocity: [*c]const f32 = @ptrCast(&velocity);
        c.set_body_linear_velocity(self.ptr, handle, c_velocity);
    }

    pub fn get_body_angular_velocity(self: *Self, handle: BodyHandle) [3]f32 {
        var velocity: [3]f32 = .{ 0.0, 0.0, 0.0 };
        c.get_body_angular_velocity(self.ptr, handle, @ptrCast(&velocity[0]));
        return velocity;
    }
    pub fn set_body_angular_velocity(self: *Self, handle: BodyHandle, velocity: [3]f32) void {
        const c_velocity: [*c]const f32 = @ptrCast(&velocity);
        c.set_body_angular_velocity(self.ptr, handle, c_velocity);
    }

    pub fn get_body_contact_list(self: *Self, handle: BodyHandle) ?[]BodyHandle {
        const result = c.get_body_contact_list(self.ptr, handle);
        if (result.ptr == null or result.count == 0) {
            return null;
        } else {
            return result.ptr[0..result.count];
        }
    }

    pub fn set_body_gravity_mode_radial(self: *Self, handle: BodyHandle, gravity_strength: f32) void {
        c.set_body_gravity_mode_radial(self.ptr, handle, gravity_strength);
    }

    pub fn set_body_gravity_mode_vector(self: *Self, handle: BodyHandle, gravity: [3]f32) void {
        const c_gravity: [*c]const f32 = @ptrCast(&gravity);
        c.set_body_gravity_mode_vector(self.ptr, handle, c_gravity);
    }

    pub fn add_character(self: *Self, shape: Shape, transform: *const Transform, user_data: u64, inner_body_opt: ?struct { shape: Shape, object_layer: ObjectLayer }) CharacterHandle {
        var inner_body_shape = c.INVALID_SHAPE_HANDLE;
        var inner_body_layer: u16 = 0;
        if (inner_body_opt) |inner_body| {
            inner_body_shape = inner_body.shape.handle;
            inner_body_layer = inner_body.object_layer;
        }

        return c.add_character(self.ptr, &.{
            .shape = shape.handle,
            .position = transform.position,
            .rotation = transform.rotation,
            .user_data = user_data,
            .inner_body_shape = inner_body_shape,
            .inner_body_layer = inner_body_layer,
        });
    }

    pub fn remove_character(self: *Self, handle: CharacterHandle) void {
        c.destroy_character(self.ptr, handle);
    }

    pub fn set_character_position(self: *Self, handle: CharacterHandle, position: [3]f32) void {
        const c_position: [*c]const f32 = @ptrCast(&position);
        c.set_character_position(self.ptr, handle, c_position);
    }

    pub fn set_character_rotation(self: *Self, handle: CharacterHandle, rotation: [4]f32) void {
        const c_rotation: [*c]const f32 = @ptrCast(&rotation);
        c.set_character_rotation(self.ptr, handle, c_rotation);
    }

    pub fn get_character_transform(self: *Self, handle: CharacterHandle) Transform {
        return c.get_character_transform(self.ptr, handle);
    }

    pub fn get_character_linear_velocity(self: *Self, handle: CharacterHandle) [3]f32 {
        var velocity: [3]f32 = .{ 0.0, 0.0, 0.0 };
        c.get_character_linear_velocity(self.ptr, handle, @ptrCast(&velocity[0]));
        return velocity;
    }

    pub fn set_character_linear_velocity(self: *Self, handle: CharacterHandle, velocity: [3]f32) void {
        const c_velocity: [*c]const f32 = @ptrCast(&velocity);
        c.set_character_linear_velocity(self.ptr, handle, c_velocity);
    }

    pub fn get_character_ground_velocity(self: *Self, handle: CharacterHandle) [3]f32 {
        var velocity: [3]f32 = .{ 0.0, 0.0, 0.0 };
        c.get_character_ground_velocity(self.ptr, handle, @ptrCast(&velocity[0]));
        return velocity;
    }

    pub fn get_character_ground_state(self: *Self, handle: CharacterHandle) GroundState {
        return @enumFromInt(c.get_character_ground_state(self.ptr, handle));
    }

    pub fn ray_cast_closest(self: Self, object_layer_pattern: ObjectLayer, origin: [3]f32, direction: [3]f32) ?RayCastHit {
        var raycast_hit: c.RayCastHit = .{};
        const has_hit = c.ray_cast_closest(self.ptr, object_layer_pattern, @ptrCast(&origin[0]), @ptrCast(&direction[0]), &raycast_hit);
        return if (has_hit) raycast_hit else null;
    }

    pub fn ray_cast_closest_ignore(self: Self, object_layer_pattern: ObjectLayer, ignore_body: BodyHandle, origin: [3]f32, direction: [3]f32) ?RayCastHit {
        var raycast_hit: c.RayCastHit = .{};
        const has_hit = c.ray_cast_closest_ignore(self.ptr, object_layer_pattern, ignore_body, @ptrCast(&origin[0]), @ptrCast(&direction[0]), &raycast_hit);
        return if (has_hit) raycast_hit else null;
    }

    pub fn ray_cast_closest_ignore_character(self: Self, object_layer_pattern: ObjectLayer, ignore_character: CharacterHandle, origin: [3]f32, direction: [3]f32) ?RayCastHit {
        var raycast_hit: c.RayCastHit = .{};
        const has_hit = c.ray_cast_closest_ignore_character(self.ptr, object_layer_pattern, ignore_character, @ptrCast(&origin[0]), @ptrCast(&direction[0]), &raycast_hit);
        return if (has_hit) raycast_hit else null;
    }

    pub fn shape_cast(
        self: Self,
        object_layer_pattern: ObjectLayer,
        shape: Shape,
        transform: *const Transform,
        callback: ShapeCastCallback,
        callback_data: ?*anyopaque,
    ) void {
        var zig_callback_info = .{ .callback = callback, .callback_data = callback_data };
        c.shape_cast(self.ptr, object_layer_pattern, shape.handle, transform, &shape_cast_callback, @ptrCast(&zig_callback_info));
    }
};

const ShapeCastCallbackData = struct {
    callback: ShapeCastCallback,
    callback_data: ?*anyopaque,
};

fn shape_cast_callback(ptr_opt: ?*anyopaque, hit: ShapeCastHit) callconv(.C) void {
    const zig_callback_info: *ShapeCastCallbackData = @alignCast(@ptrCast(ptr_opt.?));
    zig_callback_info.callback(zig_callback_info.callback_data, hit);
}

// Memory Allocation
const SizeAndAlignment = packed struct(u64) {
    size: u48,
    alignment: u16,
};
var mem_allocator: ?std.mem.Allocator = null;
var mem_allocations: ?std.AutoHashMap(usize, SizeAndAlignment) = null;
var mem_mutex: std.Thread.Mutex = .{};
const default_mem_alignment = 16;

fn zjoltAlloc(size: usize) callconv(.C) ?*anyopaque {
    return zjoltAlignedAlloc(size, default_mem_alignment);
}

fn zjoltAlignedAlloc(size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    std.debug.assert(alignment == 64 or alignment == 16);

    mem_mutex.lock();
    defer mem_mutex.unlock();

    const ptr = mem_allocator.?.rawAlloc(
        size,
        std.math.log2_int(u29, @as(u29, @intCast(alignment))),
        @returnAddress(),
    );
    if (ptr == null)
        @panic("saturn_jolt: out of memory");

    mem_allocations.?.put(
        @intFromPtr(ptr),
        .{ .size = @as(u32, @intCast(size)), .alignment = @as(u16, @intCast(alignment)) },
    ) catch @panic("saturn_jolt: out of memory");

    return ptr;
}

fn zjoltReallocate(maybe_ptr: ?*anyopaque, reported_old_size: usize, new_size: usize) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const old_size = if (maybe_ptr != null) reported_old_size else 0;

    const old_mem = if (old_size > 0)
        @as([*]align(default_mem_alignment) u8, @ptrCast(@alignCast(maybe_ptr)))[0..old_size]
    else
        @as([*]align(default_mem_alignment) u8, undefined)[0..0];

    const mem = mem_allocator.?.realloc(old_mem, new_size) catch @panic("saturn_jolt: out of memory");

    if (maybe_ptr != null) {
        const removed = mem_allocations.?.remove(@intFromPtr(maybe_ptr.?));
        std.debug.assert(removed);
    }

    mem_allocations.?.put(
        @intFromPtr(mem.ptr),
        .{ .size = @as(u48, @intCast(new_size)), .alignment = default_mem_alignment },
    ) catch @panic("saturn_jolt: out of memory");

    return mem.ptr;
}

fn zjoltFree(maybe_ptr: ?*anyopaque) callconv(.C) void {
    if (maybe_ptr) |ptr| {
        mem_mutex.lock();
        defer mem_mutex.unlock();

        const info = mem_allocations.?.fetchRemove(@intFromPtr(ptr)).?.value;

        const mem = @as([*]u8, @ptrCast(ptr))[0..info.size];

        mem_allocator.?.rawFree(
            mem,
            std.math.log2_int(u29, @as(u29, @intCast(info.alignment))),
            @returnAddress(),
        );
    }
}
