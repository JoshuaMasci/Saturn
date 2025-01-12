const std = @import("std");

const options = @import("options");

const c = @cImport({
    if (options.use_double_precision) {
        @cDefine("JPH_DOUBLE_PRECISION", 1);
    }

    @cInclude("saturn_jolt.h");
});

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

// Types
pub const RVec3 = c.RVec3;
pub const Vec3 = c.Vec3;
pub const Quat = c.Quat;

pub const Transform = c.Transform;
pub const Velocity = c.Velocity;

pub const UserData = c.UserData;
pub const ObjectLayer = c.ObjectLayer;

pub const Shape = struct {
    const Self = @This();

    handle: c.Shape,

    pub fn initSphere(radius: f32, density: f32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateSphere(radius, density, user_data),
        };
    }

    pub fn initBox(half_extent: [3]f32, density: f32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateBox(&half_extent, density, user_data),
        };
    }

    pub fn initCylinder(half_height: f32, radius: f32, density: f32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateCylinder(half_height, radius, density, user_data),
        };
    }

    pub fn initCapsule(half_height: f32, radius: f32, density: f32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateCapsule(half_height, radius, density, user_data),
        };
    }

    pub fn initConvexHull(positions: [][3]f32, density: f32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateConvexHull(@alignCast(@ptrCast(positions.ptr)), positions.len, density, user_data),
        };
    }

    pub fn initMesh(positions: [][3]f32, indices: []u32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateMesh(@alignCast(@ptrCast(positions.ptr)), positions.len, @alignCast(@ptrCast(indices.ptr)), indices.len, user_data),
        };
    }

    pub fn deinit(self: *Self) void {
        c.shapeDestroy(self.handle);
    }
};

pub const MotionType = enum(u32) {
    static = 0,
    kinematic = 1,
    dynamic = 2,
};

pub const World = struct {
    const Self = @This();

    pub const Settings = struct {
        max_bodies: u32 = 1024,
        num_body_mutexes: u32 = 0,
        max_body_pairs: u32 = 1024,
        max_contact_constraints: u32 = 1024,
        temp_allocation_size: u32 = 1024 * 1024 * 10,
    };

    ptr: ?*c.World,

    pub fn init(settings: Settings) Self {
        return .{
            .ptr = c.worldCreate(&.{
                .max_bodies = settings.max_bodies,
                .num_body_mutexes = settings.num_body_mutexes,
                .max_body_pairs = settings.max_body_pairs,
                .max_contact_constraints = settings.max_contact_constraints,
                .temp_allocation_size = settings.temp_allocation_size,
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        c.worldDestroy(self.ptr);
    }

    pub fn addBody(self: *Self, body: Body) void {
        c.worldAddBody(self.ptr, body.ptr);
    }

    pub fn removeBody(self: *Self, body: Body) void {
        c.worldRemoveBody(self.ptr, body.ptr);
    }

    pub fn update(self: *Self, delta_time: f32, collisions_steps: i32) void {
        c.worldUpdate(self.ptr, delta_time, collisions_steps);
    }
};

pub const Body = struct {
    const Self = @This();

    pub const Settings = struct {
        position: RVec3 = .{ 0.0, 0.0, 0.0 },
        rotation: Quat = .{ 0.0, 0.0, 0.0, 1.0 },
        linear_velocity: Vec3 = .{ 0.0, 0.0, 0.0 },
        angular_velocity: Vec3 = .{ 0.0, 0.0, 0.0 },
        user_data: UserData = 0,
        object_layer: ObjectLayer,
        motion_type: MotionType,
        allow_sleep: bool = true,
        friction: f32 = 0.0,
        linear_damping: f32 = 0.0,
        angular_damping: f32 = 0.0,
        gravity_factor: f32 = 1.0,
    };

    ptr: ?*c.Body,

    pub fn init(settings: Settings) Self {
        return .{
            .ptr = c.bodyCreate(&.{
                .position = settings.position,
                .rotation = settings.rotation,
                .linear_velocity = settings.linear_velocity,
                .angular_velocity = settings.angular_velocity,
                .user_data = settings.user_data,
                .object_layer = settings.object_layer,
                .motion_type = @intFromEnum(settings.motion_type),
                .allow_sleep = settings.allow_sleep,
                .friction = settings.friction,
                .linear_damping = settings.angular_damping,
                .gravity_factor = settings.gravity_factor,
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        c.bodyDestroy(self.ptr);
    }

    pub fn getWorld(self: *Self) ?World {
        if (c.bodyGetWorld(self.ptr)) |world_ptr| {
            return .{ .ptr = world_ptr };
        }
        return null;
    }

    pub fn getTransform(self: *Self) Transform {
        return c.bodyGetTransform(self.ptr);
    }

    pub fn setTransform(self: *Self, transform: *const Transform) void {
        c.bodySetTransform(self.ptr, transform);
    }

    pub fn getVelocity(self: *Self) Velocity {
        return c.bodyGetVelocity(self.ptr);
    }

    pub fn setVelocity(self: *Self, velocity: *const Velocity) void {
        c.bodySetVelocity(self.ptr, velocity);
    }
};

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
