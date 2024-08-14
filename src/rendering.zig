const std = @import("std");
const za = @import("zalgebra");

const gl = @import("zopengl").bindings;

const object_pool = @import("object_pool.zig");
const Transform = @import("transform.zig");
const Camera = @import("camera.zig").Camera;

const ColoredVertex = @import("platform/opengl/vertex.zig").ColoredVertex;
const TexturedVertex = @import("platform/opengl/vertex.zig").TexturedVertex;
const Mesh = @import("platform/opengl/mesh.zig");
const Texture = @import("platform/opengl/texture.zig");
const Shader = @import("platform/opengl/shader.zig");

const StaticMeshPool = object_pool.ObjectPool(u16, Mesh);
pub const StaticMeshHandle = StaticMeshPool.Handle;

const TexturePool = object_pool.ObjectPool(u16, Texture);
pub const TextureHandle = TexturePool.Handle;

pub const Material = struct {
    base_color_texture: ?TextureHandle = null,
    base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

    metallic_roughness_texture: ?TextureHandle = null,
    metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

    emissive_texture: ?TextureHandle = null,
    emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

    occlusion_texture: ?TextureHandle = null,
    normal_texture: ?TextureHandle = null,
};
const MaterialPool = object_pool.ObjectPool(u16, Material);
pub const MaterialHandle = MaterialPool.Handle;

fn read_file_to_string(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    return try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
}

fn create_shader(allocator: std.mem.Allocator, vertex_path: []const u8, fragment_path: []const u8) !Shader {
    const vertex_code = try read_file_to_string(allocator, vertex_path);
    defer allocator.free(vertex_code);

    const fragment_code = try read_file_to_string(allocator, fragment_path);
    defer allocator.free(fragment_code);
    return Shader.init(vertex_code, fragment_code);
}

pub const Backend = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    skybox_vao: gl.Uint,
    skybox_shader: Shader,
    colored_material_shader: Shader,
    pbr_material_shader: Shader,

    static_meshes: StaticMeshPool,
    textures: TexturePool,
    materials: MaterialPool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var skybox_vao: gl.Uint = undefined;
        gl.genVertexArrays(1, &skybox_vao);
        const skybox_shader: Shader = try create_shader(allocator, "res/shaders/whole_screen.vert", "res/shaders/skybox.frag");
        const colored_material_shader: Shader = try create_shader(allocator, "res/shaders/colored.vert", "res/shaders/colored.frag");
        const pbr_material_shader: Shader = try create_shader(allocator, "res/shaders/pbr_material.vert", "res/shaders/pbr_material.frag");

        return .{
            .skybox_vao = skybox_vao,
            .allocator = allocator,
            .skybox_shader = skybox_shader,
            .colored_material_shader = colored_material_shader,
            .pbr_material_shader = pbr_material_shader,
            .static_meshes = StaticMeshPool.init(allocator),
            .textures = TexturePool.init(allocator),
            .materials = MaterialPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        gl.deleteVertexArrays(1, &self.skybox_vao);
        self.skybox_shader.deinit();
        self.colored_material_shader.deinit();
        self.pbr_material_shader.deinit();

        self.static_meshes.deinit_with_entries();
        self.textures.deinit_with_entries();

        self.materials.deinit();
    }

    pub fn load_static_mesh(self: *Self, mesh: Mesh) !StaticMeshHandle {
        return try self.static_meshes.insert(mesh);
    }
    pub fn unload_static_mesh(self: *Self, mesh_handle: StaticMeshHandle) void {
        if (self.meshes.remove(mesh_handle)) |mesh| {
            mesh.deinit();
        }
    }

    pub fn load_texture(self: *Self, texture: Texture) !TextureHandle {
        return try self.textures.insert(texture);
    }
    pub fn unload_texture(self: *Self, texture_handle: TextureHandle) void {
        if (self.textures.remove(texture_handle)) |texture| {
            texture.deinit();
        }
    }

    pub fn load_material(self: *Self, material: Material) !MaterialHandle {
        return try self.materials.insert(material);
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

    pub fn render_scene(self: Self, window_size: [2]u32, scene: *Scene, scene_camera: *const Camera) void {
        var err: gl.Enum = gl.getError();
        while (err != gl.NO_ERROR) {
            std.log.err("GL Error: {}", .{err});
            err = gl.getError();
        }

        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);
        gl.frontFace(gl.CCW);
        gl.cullFace(gl.BACK);
        gl.viewport(0, 0, @intCast(window_size[0]), @intCast(window_size[1]));

        const width_float: f32 = @floatFromInt(window_size[0]);
        const height_float: f32 = @floatFromInt(window_size[1]);
        const aspect_ratio: f32 = width_float / height_float;

        const view_matrix = scene_camera.transform.get_view_matrix();
        const projection_matrix = scene_camera.data.perspective_gl(aspect_ratio);
        var view_projection_matrix = projection_matrix.mul(view_matrix);

        if (scene.skybox) |skybox_handle| {
            if (self.textures.get(skybox_handle)) |skybox_texture| {
                gl.disable(gl.DEPTH_TEST);
                defer gl.enable(gl.DEPTH_TEST);

                const rotation = Transform{ .rotation = scene_camera.transform.rotation };
                const rotation_view_matrix = rotation.get_view_matrix();
                const inverse_view_projection_matrix = projection_matrix.mul(rotation_view_matrix).inv();

                self.skybox_shader.bind();
                self.skybox_shader.set_uniform_mat4("inverse_view_projection_matrix", &inverse_view_projection_matrix);

                const cube_map_slot = 0;
                self.skybox_shader.set_uniform_int("skybox", cube_map_slot);
                skybox_texture.bind(cube_map_slot);

                gl.bindVertexArray(self.skybox_vao);
                gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
            }
        }

        self.pbr_material_shader.bind();
        self.pbr_material_shader.set_uniform_mat4("view_projection_matrix", &view_projection_matrix);

        var instance_iterator = scene.instances.iterator();
        while (instance_iterator.next()) |instance| {
            const model_matrix = instance.value_ptr.transform.get_model_matrix();
            self.pbr_material_shader.set_uniform_mat4("model_matrix", &model_matrix);
            if (self.materials.get(instance.value_ptr.material)) |material| {
                self.pbr_material_shader.set_uniform_vec4("base_color_factor", za.Vec4.fromArray(material.base_color_factor));
                self.pbr_material_shader.set_uniform_int("base_color_texture_enable", 0);

                if (material.base_color_texture) |texture_handle| {
                    if (self.textures.get(texture_handle)) |texture| {
                        const slot = 0;
                        texture.bind(slot);
                        self.pbr_material_shader.set_uniform_int("base_color_texture", slot);
                        self.pbr_material_shader.set_uniform_int("base_color_texture_enable", 1);
                    }
                }

                if (self.static_meshes.get(instance.value_ptr.mesh)) |mesh| {
                    mesh.draw();
                } else {
                    std.log.warn("Instance {} contains an invalid Mesh {}", .{ instance.handle, instance.value_ptr.mesh });
                }
            } else {
                std.log.warn("Instance {} contains an invalid Material {}", .{ instance.handle, instance.value_ptr.material });
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

    skybox: ?TextureHandle = null,

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

    const vertex_positions = [_][3]f32{
        .{ half_size[0], half_size[1], half_size[2] },
        .{ half_size[0], half_size[1], -half_size[2] },
        .{ half_size[0], -half_size[1], half_size[2] },
        .{ half_size[0], -half_size[1], -half_size[2] },
        .{ -half_size[0], half_size[1], half_size[2] },
        .{ -half_size[0], half_size[1], -half_size[2] },
        .{ -half_size[0], -half_size[1], half_size[2] },
        .{ -half_size[0], -half_size[1], -half_size[2] },
    };

    const vertex_normals = [_][3]f32{
        .{ 1.0, 0.0, 0.0 },
        .{ -1.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, -1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 0.0, 0.0, -1.0 },
    };

    const vertex_uvs = [_][2]f32{
        .{ 0.0, 0.0 },
        .{ 0.0, 1.0 },
        .{ 1.0, 0.0 },
        .{ 1.0, 1.0 },
    };

    _ = vertex_positions;
    _ = vertex_normals;
    _ = vertex_uvs;

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
