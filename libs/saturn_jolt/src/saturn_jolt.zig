const std = @import("std");

const options = @import("options");

const c = @cImport({
    if (options.use_double_precision) {
        @cDefine("JPH_DOUBLE_PRECISION", 1);
    }

    @cInclude("saturn_jolt.h");
});

pub fn init(allocator: std.mem.Allocator) void {
    std.debug.assert(mem_allocator == null);

    mem_allocator = allocator;
    c.init(&c.AllocationFunctions{
        .alloc = alloc,
        .free = free,
        .aligned_alloc = alignedAlloc,
        .aligned_free = free,
        .realloc = reallocate,
    });
}
pub fn deinit() void {
    c.deinit();
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
pub const SubShapeIndex = c.SubShapeIndex;
pub const MassProperties = c.MassProperties;

pub const RayCastHit = c.RayCastHit;
pub const ShapeCastHit = c.ShapeCastHit;
pub const ShapeCastCallback = c.ShapeCastCallback;

pub const SubShapeSettings = struct {
    shape: Shape,
    position: Vec3,
    rotation: Quat,
};

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

    pub fn initMeshStatic(positions: [][3]f32, indices: []u32, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateMesh(@alignCast(@ptrCast(positions.ptr)), positions.len, @alignCast(@ptrCast(indices.ptr)), indices.len, null, user_data),
        };
    }

    pub fn initMeshWithMass(positions: [][3]f32, indices: []u32, mass_properites: MassProperties, user_data: UserData) Self {
        return .{
            .handle = c.shapeCreateMesh(@alignCast(@ptrCast(positions.ptr)), positions.len, @alignCast(@ptrCast(indices.ptr)), indices.len, &mass_properites, user_data),
        };
    }

    pub fn initCompound(sub_shapes: []const SubShapeSettings, user_data: UserData) Self {
        //TODO: since Shape is currently a wrapper type, we can cast it to a c.SubShapeSettings without issue, may become a problem on diffrent platforms
        comptime std.debug.assert(@sizeOf(SubShapeSettings) == @sizeOf(c.SubShapeSettings));
        return .{
            .handle = c.shapeCreateCompound(@alignCast(@ptrCast(sub_shapes.ptr)), sub_shapes.len, user_data),
        };
    }

    pub fn deinit(self: *Self) void {
        c.shapeDestroy(self.handle);
    }

    pub fn getMassProperties(self: Self) MassProperties {
        return c.shapeGetMassProperties(self.handle);
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
        threads: u16 = 4,
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
                .threads = settings.threads,
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

    pub fn castRayClosest(self: Self, object_layer_pattern: ObjectLayer, origin: RVec3, direction: Vec3) ?RayCastHit {
        var hit: c.RayCastHit = .{};
        return if (c.worldCastRayAll(self.ptr, object_layer_pattern, @ptrCast(&origin[0]), @ptrCast(&direction[0]), &hit))
            hit
        else
            null;
    }

    pub fn castRayClosestIgnoreBody(self: Self, object_layer_pattern: ObjectLayer, ignore_body: Body, origin: RVec3, direction: Vec3) ?c.RayCastHit {
        var hit: c.RayCastHit = .{};
        return if (c.worldCastRayClosetIgnoreBody(self.ptr, object_layer_pattern, ignore_body.ptr, @ptrCast(&origin[0]), @ptrCast(&direction[0]), &hit))
            hit
        else
            null;
    }

    pub fn castShape(self: Self, object_layer_pattern: ObjectLayer, shape: Shape, transform: *const Transform, callback: ShapeCastCallback, callback_data: *anyopaque) void {
        c.worldCastShape(self.ptr, object_layer_pattern, shape.handle, transform, callback, callback_data);
    }
};

pub const Body = struct {
    const Self = @This();

    pub const Settings = struct {
        transform: Transform = .{
            .position = .{ 0.0, 0.0, 0.0 },
            .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
        },
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
                .position = settings.transform.position,
                .rotation = settings.transform.rotation,
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

    pub fn addForce(self: *Self, force: Vec3, activate: bool) void {
        c.bodyAddForce(self.ptr, @ptrCast(&force[0]), activate);
    }

    pub fn addShape(self: *Self, shape: Shape, position: Vec3, rotation: Quat, user_data: UserData) SubShapeIndex {
        return c.bodyAddShape(self.ptr, shape.handle, @ptrCast(&position[0]), @ptrCast(&rotation[0]), user_data);
    }

    pub fn removeShape(self: *Self, index: SubShapeIndex) void {
        return c.bodyRemoveShape(self.ptr, index);
    }

    pub fn updateShapeTransform(self: *Self, index: SubShapeIndex, position: Vec3, rotation: Quat) void {
        return c.bodyUpdateShapeTransform(self.ptr, index, @ptrCast(&position[0]), @ptrCast(&rotation[0]));
    }

    pub fn removeAllShapes(self: *Self) void {
        return c.bodyRemoveAllShapes(self.ptr);
    }

    pub fn commitShapeChanges(self: *Self) void {
        return c.bodyCommitShapeChanges(self.ptr);
    }
};

pub const MeshPrimitive = c.MeshPrimitive;
pub const Vertex = c.Vertex;
pub const Triangle = c.Triangle;
pub const DebugRendererCallbacks = c.DebugRendererCallbacks;
pub const DrawLineData = c.DrawLineData;
pub const DrawTriangleData = c.DrawTriangleData;
pub const DrawTextData = c.DrawTextData;
pub const DrawGeometryData = c.DrawGeometryData;

pub const CullMode = enum(c.CullMode) {
    back_face = c.CULL_MODE_BACK,
    front_face = c.CULL_MODE_FRONT,
    off = c.CULL_MODE_OFF,
};

pub const DrawMode = enum(c.DrawMode) {
    solid = c.DRAW_MODE_SOLID,
    wireframe = c.DRAW_MODE_WIREFRAME,
};

pub fn initDebugRenderer(debug_renderer: c.DebugRendererCallbacks) void {
    c.debugRendererCreate(debug_renderer);
}

pub fn deinitDebugRenderer() void {
    c.debugRendererDestroy();
}

pub fn debugRendererBuildFrame(world: *World, transform: Transform, ignore_bodies: []const Body) void {
    c.debugRendererBuildFrame(world.ptr, transform, @ptrCast(ignore_bodies.ptr), @intCast(ignore_bodies.len));
}

// Memory Allocation
var mem_allocator: ?std.mem.Allocator = null;
const Metadata = struct {
    size: usize,
    alignment: usize,
};

fn alloc(size: usize) callconv(.C) ?*anyopaque {
    return alignedAlloc(size, 16);
}

fn alignedAlloc(size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    if (mem_allocator) |allocator| {
        const allocation_size = size + alignment;

        const allocation: []u8 = switch (alignment) {
            16 => allocator.alignedAlloc(u8, 16, allocation_size),
            32 => allocator.alignedAlloc(u8, 32, allocation_size),
            64 => allocator.alignedAlloc(u8, 64, allocation_size),
            else => |x| std.debug.panic("Unsupported memory aligment: {}", .{x}),
        } catch return null;

        const data_ptr_int: usize = @as(usize, @intFromPtr(allocation.ptr)) + alignment;
        const data_ptr: *u8 = @ptrFromInt(data_ptr_int);
        const metadata_ptr: *Metadata = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
        metadata_ptr.size = size;
        metadata_ptr.alignment = alignment;

        return data_ptr;
    }
    return null;
}

fn reallocate(maybe_ptr: ?*anyopaque, old_size: usize, new_size: usize) callconv(.C) ?*anyopaque {
    if (maybe_ptr) |data_ptr| {
        if (mem_allocator) |allocator| {
            const data_ptr_int: usize = @intFromPtr(data_ptr);
            const metadata_ptr: *Metadata = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
            const allocation_ptr: [*]u8 = @ptrFromInt(data_ptr_int - metadata_ptr.alignment);
            const allocation_size: usize = metadata_ptr.size + metadata_ptr.alignment;

            if (old_size != metadata_ptr.size) {
                std.log.warn("Jolt expected memory size({}) doesn't match memory's metadata({}), there may be a bug in the allocator", .{ old_size, metadata_ptr.size });
            }

            const new_allocation_size = new_size + metadata_ptr.alignment;

            // Try to resize current buffer
            const resized: bool = switch (metadata_ptr.alignment) {
                16 => allocator.resize(@as([*]align(16) u8, @alignCast(allocation_ptr))[0..allocation_size], new_allocation_size),
                32 => allocator.resize(@as([*]align(32) u8, @alignCast(allocation_ptr))[0..allocation_size], new_allocation_size),
                64 => allocator.resize(@as([*]align(64) u8, @alignCast(allocation_ptr))[0..allocation_size], new_allocation_size),
                else => |x| std.debug.panic("Unsupported memory aligment: {}", .{x}),
            };
            if (resized) {
                metadata_ptr.size = new_size;
                return data_ptr;
            }

            // If resize fails, try allocate and memcopy new buffer
            if (alignedAlloc(new_size, metadata_ptr.alignment)) |new_ptr| {
                defer free(maybe_ptr);

                if (new_size != 0) {
                    var old_data_ptr_bytes: [*]u8 = @ptrCast(data_ptr);
                    var new_data_ptr_bytes: [*]u8 = @ptrCast(new_ptr);
                    const copy_size = @min(metadata_ptr.size, new_size);
                    @memcpy(new_data_ptr_bytes[0..copy_size], old_data_ptr_bytes[0..copy_size]);
                    return new_ptr;
                } else {
                    return null;
                }
            }
        }
    }
    return alloc(new_size);
}

fn free(maybe_ptr: ?*anyopaque) callconv(.C) void {
    if (maybe_ptr) |data_ptr| {
        if (mem_allocator) |allocator| {
            const data_ptr_int: usize = @intFromPtr(data_ptr);
            const metadata_ptr: *Metadata = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
            const allocation_ptr: [*]u8 = @ptrFromInt(data_ptr_int - metadata_ptr.alignment);
            const allocation_size: usize = metadata_ptr.size + metadata_ptr.alignment;

            switch (metadata_ptr.alignment) {
                16 => allocator.free(@as([*]align(16) u8, @alignCast(allocation_ptr))[0..allocation_size]),
                32 => allocator.free(@as([*]align(32) u8, @alignCast(allocation_ptr))[0..allocation_size]),
                64 => allocator.free(@as([*]align(64) u8, @alignCast(allocation_ptr))[0..allocation_size]),
                else => |x| std.debug.panic("Unsupported memory aligment: {}", .{x}),
            }
        }
    }
}
