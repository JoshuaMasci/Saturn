const std = @import("std");

const c = @cImport({
    @cInclude("saturn_jolt.h");
});

//TODO LIST:
// 1. Shape Functions
// 2. Volume
// 3. VirtualCharacter
// 4. Multi Shape functions

pub fn init(allocator: std.mem.Allocator) void {
    std.debug.assert(mem_allocator == null and mem_allocations == null);

    mem_allocator = allocator;
    mem_allocations = std.AutoHashMap(usize, SizeAndAlignment).init(allocator);
    mem_allocations.?.ensureTotalCapacity(32) catch unreachable;

    c.SPH_Init(&c.SPH_AllocationFunctions{
        .alloc = zjoltAlloc,
        .free = zjoltFree,
        .aligned_alloc = zjoltAlignedAlloc,
        .aligned_free = zjoltFree,
    });
}
pub fn deinit() void {
    c.SPH_Deinit();

    mem_allocations.?.deinit();
    mem_allocations = null;
    mem_allocator = null;
}

// Shapes
pub const Shape = struct {
    const Self = @This();

    handle: c.SPH_ShapeHandle,

    pub fn init_sphere(radius: f32, density: f32) Self {
        return .{
            .handle = c.SPH_Shape_Sphere(radius, density),
        };
    }

    pub fn init_box(half_extent: [3]f32, density: f32) Self {
        return .{
            .handle = c.SPH_Shape_Box(&half_extent, density),
        };
    }

    pub fn init_cylinder(half_height: f32, radius: f32, density: f32) Self {
        return .{
            .handle = c.SPH_Shape_Cylinder(half_height, radius, density),
        };
    }

    pub fn init_capsule(half_height: f32, radius: f32, density: f32) Self {
        return .{
            .handle = c.SPH_Shape_Capsule(half_height, radius, density),
        };
    }

    pub fn deinit(self: Self) void {
        c.SPH_Shape_Destroy(self.handle);
    }
};

pub const Transform = c.SPH_Transform;

pub const BodyHandle = c.SPH_BodyHandle;
pub const MotionType = enum(u32) {
    Static = 0,
    Kinematic = 1,
    Dynamic = 2,
};

pub const BodySettings = struct {
    shape: Shape,
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    linear_velocity: [3]f32 = .{ 0.0, 0.0, 0.0 },
    angular_velocity: [3]f32 = .{ 0.0, 0.0, 0.0 },
    user_data: u64 = 0,
    motion_type: MotionType,
    is_sensor: bool = false,
    allow_sleep: bool = true,
    friction: f32 = 0.2,
    linear_damping: f32 = 0.05,
    angular_damping: f32 = 0.05,
    gravity_factor: f32 = 1.0,
};

pub const CharacterHandle = u32; //TODO: this

pub const GroundState = enum(u32) {
    OnGround = 0,
    OnSteepGround = 1,
    InAir = 2,
    NotSupported = 3,
};

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

    ptr: ?*c.SPH_PhysicsWorld,

    pub fn init(settings: Settings) Self {
        return .{
            .ptr = c.SPH_PhysicsWorld_Create(&.{
                .max_bodies = settings.max_bodies,
                .num_body_mutexes = settings.num_body_mutexes,
                .max_body_pairs = settings.max_body_pairs,
                .max_contact_constraints = settings.max_contact_constraints,
                .temp_allocation_size = settings.temp_allocation_size,
            }),
        };
    }
    pub fn deinit(self: *Self) void {
        c.SPH_PhysicsWorld_Destroy(self.ptr);
    }

    pub fn update(self: *Self, delta_time: f32, collisions_steps: i32) void {
        c.SPH_PhysicsWorld_Update(self.ptr, delta_time, collisions_steps);
    }

    pub fn add_body(self: *Self, body_settings: *const BodySettings) BodyHandle {
        const c_body_settings: c.SPH_BodySettings = .{
            .shape = body_settings.shape.handle,
            .position = body_settings.position,
            .rotation = body_settings.rotation,
            .linear_velocity = body_settings.linear_velocity,
            .angular_velocity = body_settings.angular_velocity,
            .user_data = body_settings.user_data,
            .motion_type = @intFromEnum(body_settings.motion_type),
            .is_sensor = body_settings.is_sensor,
            .allow_sleep = body_settings.allow_sleep,
            .friction = body_settings.friction,
            .linear_damping = body_settings.linear_damping,
            .angular_damping = body_settings.angular_damping,
            .gravity_factor = body_settings.gravity_factor,
        };
        const handle = c.SPH_PhysicsWorld_Body_Create(self.ptr, &c_body_settings);

        return handle;
    }

    pub fn remove_body(self: *Self, handle: BodyHandle) void {
        c.SPH_PhysicsWorld_Body_Destroy(self.ptr, handle);
    }

    pub fn get_body_transform(self: *Self, handle: BodyHandle) Transform {
        return c.SPH_PhysicsWorld_Body_GetTransform(self.ptr, handle);
    }

    pub fn set_body_linear_velocity(self: *Self, handle: BodyHandle, velocity: [3]f32) void {
        const c_velocity: [*c]const f32 = @ptrCast(&velocity);
        c.SPH_PhysicsWorld_Body_SetLinearVelocity(self.ptr, handle, c_velocity);
    }

    pub fn get_body_contact_list(self: *Self, handle: BodyHandle) ?[]BodyHandle {
        const result = c.SPH_PhysicsWorld_Body_GetContactList(self.ptr, handle);
        if (result.ptr == null or result.count == 0) {
            return null;
        } else {
            return result.ptr[0..result.count];
        }
    }

    pub fn set_body_volume_gravity_strength(self: *Self, handle: BodyHandle, gravity_strength: f32) void {
        c.SPH_PhysicsWorld_Body_AddRadialGravity(self.ptr, handle, gravity_strength);
    }

    pub fn add_character(self: *Self, shape: Shape, transform: *const Transform) CharacterHandle {
        return c.SPH_PhysicsWorld_Character_Add(self.ptr, shape.handle, transform);
    }

    pub fn remove_character(self: *Self, handle: CharacterHandle) void {
        c.SPH_PhysicsWorld_Character_Remove(self.ptr, handle);
    }

    pub fn get_character_transform(self: *Self, handle: CharacterHandle) Transform {
        return c.SPH_PhysicsWorld_Character_GetTransform(self.ptr, handle);
    }

    pub fn get_character_ground_state(self: *Self, handle: CharacterHandle) GroundState {
        return @enumFromInt(c.SPH_PhysicsWorld_Character_GetGroundState(self.ptr, handle));
    }
};

pub const BodyInterface = struct {
    const Self = @This();

    // Create/Destroy
    pub fn create_body(self: *Self) void {
        _ = self; // autofix
    }

    pub fn create_body_with_id(self: *Self) void {
        _ = self; // autofix
    }

    pub fn destroy_body(self: *Self) void {
        _ = self; // autofix
    }

    pub fn add_body(self: *Self) void {
        _ = self; // autofix
    }

    pub fn remove_body(self: *Self) void {
        _ = self; // autofix
    }

    pub fn create_and_add_body(self: *Self) void {
        _ = self; // autofix
    }

    pub fn remove_and_destroy_body(self: *Self) void {
        _ = self; // autofix
    }

    pub fn is_added(self: *Self) void {
        _ = self; // autofix
    }

    // Activate/Deactivate
    pub fn activate(self: *Self) void {
        _ = self; // autofix
    }

    pub fn deactivate(self: *Self) void {
        _ = self; // autofix
    }

    pub fn is_active(self: *Self) void {
        _ = self; // autofix
    }

    // Transform
    pub fn set_position_and_rotation(self: *Self) void {
        _ = self; // autofix
    }
    pub fn set_position_and_rotation_when_changed(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_position_and_rotation(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_position(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_position(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_center_of_mass_position(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_rotation(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_rotation(self: *Self) void {
        _ = self; // autofix
    }

    // Velocity
    pub fn set_linear_velocity(self: *Self) void {
        _ = self; // autofix
    }

    pub fn get_linear_velocity(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_angular_velocity(self: *Self) void {
        _ = self; // autofix
    }

    pub fn get_angular_velocity(self: *Self) void {
        _ = self; // autofix
    }

    pub fn get_point_velocity(self: *Self) void {
        _ = self; // autofix
    }

    // Force
    pub fn add_force(self: *Self) void {
        _ = self; // autofix
    }
    pub fn add_force_at_position(self: *Self) void {
        _ = self; // autofix
    }
    pub fn add_torque(self: *Self) void {
        _ = self; // autofix
    }
    // Impulse
    pub fn add_tmpulse(self: *Self) void {
        _ = self; // autofix
    }
    pub fn add_impulse_at_position(self: *Self) void {
        _ = self; // autofix
    }
    pub fn add_angular_impulse(self: *Self) void {
        _ = self; // autofix
    }

    // Body Settings
    pub fn get_body_type(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_motion_type(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_motion_type(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_restitution(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_restitution(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_friction(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_friction(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_gravity_factor(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_gravity_factor(self: *Self) void {
        _ = self; // autofix
    }

    // UserData
    pub fn set_user_data(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_user_data(self: *Self) void {
        _ = self; // autofix
    }

    // Volume Functions
    pub fn get_bodies_in_volume(self: *Self) void {
        _ = self; // autofix
    }

    pub fn set_gravity_mode(self: *Self) void {
        _ = self; // autofix
    }
    pub fn get_gravity_mode(self: *Self) void {
        _ = self; // autofix
    }
};

//Memory Allocation
const SizeAndAlignment = packed struct(u64) {
    size: u48,
    alignment: u16,
};
var mem_allocator: ?std.mem.Allocator = null;
var mem_allocations: ?std.AutoHashMap(usize, SizeAndAlignment) = null;
var mem_mutex: std.Thread.Mutex = .{};
const mem_alignment = 16;

fn zjoltAlloc(size: usize) callconv(.C) ?*anyopaque {
    return zjoltAlignedAlloc(size, mem_alignment);
}

fn zjoltAlignedAlloc(size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const ptr = mem_allocator.?.rawAlloc(
        size,
        std.math.log2_int(u29, @as(u29, @intCast(alignment))),
        @returnAddress(),
    );
    if (ptr == null) @panic("zjolt: out of memory");

    mem_allocations.?.put(
        @intFromPtr(ptr),
        .{ .size = @as(u32, @intCast(size)), .alignment = @as(u16, @intCast(alignment)) },
    ) catch @panic("zjolt: out of memory");

    return ptr;
}

fn zjoltReallocate() void {
    //TODO: impliment this
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
