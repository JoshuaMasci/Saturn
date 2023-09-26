const std = @import("std");
const Transform = @import("transform.zig");

pub const MeshHandle = u32;
pub const MaterialHandle = u32;

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn load_mesh(self: *Self, file_path: []const u8) !MeshHandle {
        _ = self;
        _ = file_path;
        return 0;
    }
    pub fn unload_mesh(self: *Self, mesh_handle: MeshHandle) void {
        _ = self;
        _ = mesh_handle;
    }

    pub fn load_material(self: *Self, file_path: []const u8) !MaterialHandle {
        _ = self;
        _ = file_path;
        return 0;
    }
    pub fn unload_material(self: *Self, material_handle: MaterialHandle) void {
        _ = self;
        _ = material_handle;
    }

    pub fn create_scene(self: *Self) !Scene {
        return Scene.init(self.allocator);
    }

    pub fn render_scene(self: Self, scene: *Scene, camera: *const Camera) void {
        _ = self;
        _ = scene;
        _ = camera;
    }
};

pub const SceneInstanceHandle = u32;
pub const Scene = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    //objects: std.AutoHashMap(MaterialHandle, std.AutoHashMap(MeshHandle, Transform)),

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn add_instace(self: Self, mesh: MeshHandle, material: MaterialHandle, transform: *const Transform) SceneInstanceHandle {
        _ = self;
        _ = mesh;
        _ = material;
        _ = transform;
        return 0;
    }

    pub fn update_instance(self: Self, instance: SceneInstanceHandle, transform: *const Transform) void {
        _ = self;
        _ = instance;
        _ = transform;
    }

    pub fn remove_instance(self: Self, instance: SceneInstanceHandle) void {
        _ = self;
        _ = instance;
    }
};

pub const FovAxis = enum {
    x,
    y,
};

pub const PerspectiveCamera = struct {
    const Self = @This();

    fov_axis: FovAxis,
    fov: f32,
    near: f32,
    far: f32,

    pub const Default: Self = .{ .fov_axis = .x, .fov = 75.0, .near = 0.1, .far = 1000.0 };
};

pub const Camera = struct {
    data: PerspectiveCamera,
    transform: Transform,
};
