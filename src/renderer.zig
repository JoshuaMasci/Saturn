const std = @import("std");
const zm = @import("zmath");

const Transform = @import("transform.zig");
const ColoredVertex = @import("opengl/vertex.zig").ColoredVertex;
const Mesh = @import("opengl/mesh.zig");
const Shader = @import("opengl/shader.zig");

pub const MeshHandle = u32;
pub const MaterialHandle = u32;

pub const Material = struct {};

fn read_file_to_string(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    return try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
}

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    colored_mesh_shader: Shader,

    next_mesh_handle: MeshHandle,
    meshes: std.AutoHashMap(MeshHandle, Mesh),

    next_material_handle: MaterialHandle,
    materials: std.AutoHashMap(MaterialHandle, void),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var vertex_code = try read_file_to_string(allocator, "res/shaders/colored.vert");
        defer allocator.free(vertex_code);

        var fragment_code = try read_file_to_string(allocator, "res/shaders/colored.frag");
        defer allocator.free(fragment_code);

        return .{
            .allocator = allocator,

            .colored_mesh_shader = Shader.init(vertex_code, fragment_code),

            .next_mesh_handle = 1,
            .meshes = std.AutoHashMap(MeshHandle, Mesh).init(allocator),

            .next_material_handle = 1,
            .materials = std.AutoHashMap(MaterialHandle, void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.colored_mesh_shader.deinit();

        var mesh_iterator = self.meshes.iterator();
        while (mesh_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.meshes.deinit();
        self.materials.deinit();
    }

    pub fn load_mesh(self: *Self, file_path: []const u8) !MeshHandle {
        _ = file_path;

        var mesh_handle = self.next_mesh_handle;
        self.next_mesh_handle += 1;

        var mesh = genBoxMesh([3]f32{ 1.0, 1.0, 1.0 }, [3]f32{ 1.0, 1.0, 1.0 });
        try self.meshes.put(mesh_handle, mesh);

        return mesh_handle;
    }
    pub fn unload_mesh(self: *Self, mesh_handle: MeshHandle) void {
        if (self.meshes.remove(mesh_handle)) |mesh| {
            mesh.deinit();
        }
    }

    pub fn load_material(self: *Self, file_path: []const u8) !MaterialHandle {
        _ = self;
        _ = file_path;

        return 0;
    }
    pub fn unload_material(self: *Self, material_handle: MaterialHandle) void {
        if (self.materials.remove(material_handle)) |material| {
            material.deinit();
        }
    }

    pub fn create_scene(self: *Self) Scene {
        return Scene.init(self.allocator);
    }

    pub fn render_scene(self: Self, scene: *Scene, camera: *const Camera) void {
        var width: u32 = 2560;
        var height: u32 = 1372;
        var width_float: f32 = @floatFromInt(width);
        var height_float: f32 = @floatFromInt(height);
        var aspect_ratio: f32 = width_float / height_float;

        var view_matrix = camera.transform.view_matrix();
        var projection_matrix = camera.data.perspective(aspect_ratio);
        //var view_projection_matrix = zm.mul(projection_matrix, view_matrix);
        var view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        self.colored_mesh_shader.bind();
        self.colored_mesh_shader.set_uniform_mat4("view_projection_matrix", &view_projection_matrix);

        var instance_iterator = scene.instances.iterator();
        while (instance_iterator.next()) |instance| {
            if (self.meshes.get(instance.value_ptr.mesh)) |mesh| {
                self.colored_mesh_shader.set_uniform_mat4("model_matrix", &instance.value_ptr.transform.model_matrix());
                mesh.draw();
            } else {
                std.log.warn("Instance {} contains an invalid Mesh {}", .{ instance.key_ptr, instance.value_ptr.mesh });
            }
        }
    }
};

pub const SceneInstanceHandle = u32;
pub const Scene = struct {
    const Self = @This();
    const InstanceMap = std.AutoHashMap(SceneInstanceHandle, struct { mesh: MeshHandle, material: MaterialHandle, transform: Transform });

    allocator: std.mem.Allocator,

    next_handle: SceneInstanceHandle,
    instances: InstanceMap,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,

            .next_handle = 0,
            .instances = InstanceMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.instances.deinit();
    }

    pub fn add_instace(self: *Self, mesh: MeshHandle, material: MaterialHandle, transform: *const Transform) !SceneInstanceHandle {
        var handle = self.next_handle;
        self.next_handle += 1;

        try self.instances.put(handle, .{
            .mesh = mesh,
            .material = material,
            .transform = transform.*,
        });

        return handle;
    }

    pub fn update_instance(self: *Self, instance: SceneInstanceHandle, transform: *const Transform) void {
        if (self.instances.getPtr(instance)) |instance_entry| {
            instance_entry.transform = transform.*;
        } else {
            std.log.err("Scene doesn't contain SceneInstanceHandle({})", .{instance});
        }
    }

    pub fn remove_instance(self: Self, instance: SceneInstanceHandle) void {
        if (!self.instances.remove(instance)) {
            std.log.err("Scene doesn't contain SceneInstanceHandle({})", .{instance});
        }
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

    pub fn perspective(self: Self, aspect_ratio: f32) zm.Mat {
        var fov = switch (self.fov_axis) {
            .x => std.math.atan(std.math.tan(self.fov / 2.0) * aspect_ratio) * 2.0,
            .y => self.fov,
        };
        return zm.perspectiveFovRhGl(fov, aspect_ratio, self.near, self.far);
    }
};

pub const Camera = struct {
    const Self = @This();

    data: PerspectiveCamera,
    transform: Transform,
};

fn genBoxMesh(size: [3]f32, color: [3]f32) Mesh {
    var half_size = [3]f32{ size[0] * 0.5, size[1] * 0.5, size[2] * 0.5 };

    var vertices = [_]ColoredVertex{
        ColoredVertex.new([_]f32{ half_size[0], half_size[1], half_size[2] }, color),
        ColoredVertex.new([_]f32{ half_size[0], half_size[1], -half_size[2] }, color),
        ColoredVertex.new([_]f32{ half_size[0], -half_size[1], half_size[2] }, color),
        ColoredVertex.new([_]f32{ half_size[0], -half_size[1], -half_size[2] }, color),
        ColoredVertex.new([_]f32{ -half_size[0], half_size[1], half_size[2] }, color),
        ColoredVertex.new([_]f32{ -half_size[0], half_size[1], -half_size[2] }, color),
        ColoredVertex.new([_]f32{ -half_size[0], -half_size[1], half_size[2] }, color),
        ColoredVertex.new([_]f32{ -half_size[0], -half_size[1], -half_size[2] }, color),
    };

    var indices = [_]u32{
        0, 2, 3, 0, 3, 1,
        5, 7, 6, 5, 6, 4,
        0, 1, 5, 0, 5, 4,
        6, 7, 3, 6, 3, 2,
        4, 6, 2, 4, 2, 0,
        1, 3, 7, 1, 7, 5,
    };

    return Mesh.init(ColoredVertex, u32, &vertices, &indices);
}
