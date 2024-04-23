const std = @import("std");
const zm = @import("zmath");
const gl = @import("zopengl").bindings;

const object_pool = @import("../object_pool.zig");
const Transform = @import("../transform.zig");
const Camera = @import("../camera.zig").Camera;

const ColoredVertex = @import("opengl/vertex.zig").ColoredVertex;
const Mesh = @import("opengl/mesh.zig");
const Shader = @import("opengl/shader.zig");

const StaticMeshPool = object_pool.ObjectPool(u16, Mesh);
pub const StaticMeshHandle = StaticMeshPool.Handle;

pub const Material = struct {};
const MaterialPool = object_pool.ObjectPool(u16, Material);
pub const MaterialHandle = u32;

fn read_file_to_string(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    return try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
}

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    colored_mesh_shader: Shader,

    static_meshes: StaticMeshPool,
    materials: MaterialPool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const vertex_code = try read_file_to_string(allocator, "res/shaders/colored.vert");
        defer allocator.free(vertex_code);

        const fragment_code = try read_file_to_string(allocator, "res/shaders/colored.frag");
        defer allocator.free(fragment_code);

        return .{
            .allocator = allocator,

            .colored_mesh_shader = Shader.init(vertex_code, fragment_code),

            .static_meshes = StaticMeshPool.init(allocator),
            .materials = MaterialPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.colored_mesh_shader.deinit();

        var mesh_iterator = self.static_meshes.iterator();
        while (mesh_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.static_meshes.deinit();
        self.materials.deinit();
    }

    pub fn load_static_mesh(self: *Self, file_path: []const u8) !StaticMeshHandle {
        _ = file_path;

        const mesh = genBoxMesh([3]f32{ 1.0, 1.0, 1.0 }, [3]f32{ 1.0, 1.0, 1.0 });
        return try self.static_meshes.insert(mesh);
    }
    pub fn unload_static_mesh(self: *Self, mesh_handle: StaticMeshHandle) void {
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

    pub fn clear_framebuffer(self: *Self) void {
        _ = self;
        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }

    pub fn render_scene(self: Self, window_size: [2]i32, scene: *Scene, scene_camera: *const Camera) void {
        gl.viewport(0, 0, window_size[0], window_size[1]);

        const width_float: f32 = @floatFromInt(window_size[0]);
        const height_float: f32 = @floatFromInt(window_size[1]);
        const aspect_ratio: f32 = width_float / height_float;

        const view_matrix = scene_camera.transform.view_matrix();
        const projection_matrix = scene_camera.data.perspective_gl(aspect_ratio);
        var view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        self.colored_mesh_shader.bind();
        self.colored_mesh_shader.set_uniform_mat4("view_projection_matrix", &view_projection_matrix);

        var instance_iterator = scene.instances.iterator();
        while (instance_iterator.next()) |instance| {
            if (self.static_meshes.get(instance.value_ptr.mesh)) |mesh| {
                self.colored_mesh_shader.set_uniform_mat4("model_matrix", &instance.value_ptr.transform.model_matrix());
                mesh.draw();
            } else {
                std.log.warn("Instance {} contains an invalid Mesh {}", .{ instance.handle, instance.value_ptr.mesh });
            }
        }
    }
};

const SceneInstanceMap = object_pool.ObjectPool(u16, struct { mesh: StaticMeshHandle, material: MaterialHandle, transform: Transform });
pub const SceneInstanceHandle = SceneInstanceMap.Handle;

pub const Scene = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    instances: SceneInstanceMap,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .instances = SceneInstanceMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.instances.deinit();
    }

    pub fn add_instace(self: *Self, mesh: StaticMeshHandle, material: MaterialHandle, transform: *const Transform) !SceneInstanceHandle {
        return try self.instances.insert(.{
            .mesh = mesh,
            .material = material,
            .transform = transform.*,
        });
    }

    pub fn update_instance(self: *Self, instance: SceneInstanceHandle, transform: *const Transform) void {
        if (self.instances.getPtr(instance)) |instance_entry| {
            instance_entry.transform = transform.*;
        } else {
            std.log.err("Scene doesn't contain SceneInstanceHandle({})", .{instance});
        }
    }

    pub fn remove_instance(self: *Self, instance: SceneInstanceHandle) !void {
        if (try self.instances.remove(instance) == null) {
            std.log.err("Scene doesn't contain SceneInstanceHandle({})", .{instance});
        }
    }
};

fn genBoxMesh(size: [3]f32, color: [3]f32) Mesh {
    const half_size = [3]f32{ size[0] * 0.5, size[1] * 0.5, size[2] * 0.5 };

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
