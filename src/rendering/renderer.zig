const std = @import("std");
const za = @import("zalgebra");
const global = @import("../global.zig");

const gl = @import("zopengl").bindings;

const Transform = @import("../transform.zig");
const Camera = @import("../camera.zig").Camera;
const RenderScene = @import("scene.zig").RenderScene;

const ColoredVertex = @import("opengl/vertex.zig").ColoredVertex;
const TexturedVertex = @import("opengl/vertex.zig").TexturedVertex;
const Mesh = @import("opengl/mesh.zig");
const Texture = @import("opengl/texture.zig");
const Shader = @import("opengl/shader.zig");
const Material = @import("types.zig").Material;

const MeshAsset = @import("../asset/mesh.zig");
const TextureAsset = @import("../asset/texture_2d.zig");

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

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    skybox_vao: gl.Uint,
    skybox_shader: Shader,
    colored_material_shader: Shader,
    pbr_material_shader: Shader,

    texture_map: std.AutoHashMap(TextureAsset.Registry.Handle, Texture),
    //cube_texture_map: std.AutoHashMap(u32, Texture),
    static_mesh_map: std.AutoHashMap(MeshAsset.Registry.Handle, Mesh),
    //material_map: std.AutoHashMap(u32, Material),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var skybox_vao: gl.Uint = undefined;
        gl.genVertexArrays(1, &skybox_vao);
        const skybox_shader: Shader = try create_shader(allocator, "assets/shaders/whole_screen.vert", "assets/shaders/skybox.frag");
        const colored_material_shader: Shader = try create_shader(allocator, "assets/shaders/colored.vert", "assets/shaders/colored.frag");
        const pbr_material_shader: Shader = try create_shader(allocator, "assets/shaders/pbr_material.vert", "assets/shaders/pbr_material.frag");

        return .{
            .skybox_vao = skybox_vao,
            .allocator = allocator,
            .skybox_shader = skybox_shader,
            .colored_material_shader = colored_material_shader,
            .pbr_material_shader = pbr_material_shader,

            .texture_map = std.AutoHashMap(TextureAsset.Registry.Handle, Texture).init(allocator),
            //.cube_texture_map = std.AutoHashMap(asset.CubeTextureAssetHandle, Texture).init(allocator),
            .static_mesh_map = std.AutoHashMap(MeshAsset.Registry.Handle, Mesh).init(allocator),
            //.material_map = std.AutoHashMap(asset.MaterialAssetHandle, Material).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        gl.deleteVertexArrays(1, &self.skybox_vao);
        self.skybox_shader.deinit();
        self.colored_material_shader.deinit();
        self.pbr_material_shader.deinit();

        self.texture_map.deinit();
        //self.cube_texture_map.deinit();
        self.static_mesh_map.deinit();
        //self.material_map.deinit();
    }

    pub fn clearFramebuffer(self: *Self) void {
        _ = self;
        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }

    pub fn renderScene(self: *Self, window_size: [2]u32, scene: *const RenderScene, camera: struct {
        transform: Transform,
        camera: Camera,
    }) void {
        var gl_err: gl.Enum = gl.getError();
        while (gl_err != gl.NO_ERROR) {
            std.log.err("GL Error: {}", .{gl_err});
            gl_err = gl.getError();
        }

        gl.enable(gl.DEPTH_TEST);
        gl.enable(gl.CULL_FACE);
        gl.depthFunc(gl.LESS);
        gl.frontFace(gl.CCW);
        gl.cullFace(gl.BACK);
        gl.viewport(0, 0, @intCast(window_size[0]), @intCast(window_size[1]));

        const width_float: f32 = @floatFromInt(window_size[0]);
        const height_float: f32 = @floatFromInt(window_size[1]);
        const aspect_ratio: f32 = width_float / height_float;

        const view_matrix = camera.transform.get_view_matrix();
        const projection_matrix = camera.camera.projection_gl(aspect_ratio);
        var view_projection_matrix = projection_matrix.mul(view_matrix);

        // if (scene.skybox) |skybox_handle| {
        //     if (self.cube_texture_map.get(skybox_handle)) |skybox_texture| {
        //         gl.disable(gl.DEPTH_TEST);
        //         defer gl.enable(gl.DEPTH_TEST);

        //         const rotation = Transform{ .rotation = camera.transform.rotation };
        //         const rotation_view_matrix = rotation.get_view_matrix();
        //         const inverse_view_projection_matrix = projection_matrix.mul(rotation_view_matrix).inv();

        //         self.skybox_shader.bind();
        //         self.skybox_shader.set_uniform_mat4("inverse_view_projection_matrix", &inverse_view_projection_matrix);

        //         const cube_map_slot = 0;
        //         self.skybox_shader.set_uniform_int("skybox", cube_map_slot);
        //         skybox_texture.bind(cube_map_slot);

        //         gl.bindVertexArray(self.skybox_vao);
        //         gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        //     }
        // }

        const grid_texture_handle = TextureAsset.Registry.Handle.fromRepoPath("engine:textures/grid.tex2d").?;
        std.debug.assert(global.assets.textures.isValid(grid_texture_handle));
        if (!self.texture_map.contains(grid_texture_handle)) {
            if (global.assets.textures.loadAsset(self.allocator, grid_texture_handle)) |texture| {
                defer texture.deinit(self.allocator);

                const size = .{ texture.width, texture.height };
                const format: Texture.Format = switch (texture.format) {
                    .r8 => .{ .load = .r, .store = .r, .layout = .u8 },
                    .rg8 => .{ .load = .rg, .store = .rg, .layout = .u8 },
                    .rgba8 => .{ .load = .rgba, .store = .rgba, .layout = .u8 },
                };

                const gpu_texture = Texture.init_2d(size, format, .{}, texture.data);
                self.texture_map.put(grid_texture_handle, gpu_texture) catch |err| {
                    gpu_texture.deinit();
                    std.log.err("Failed to appeded texture to list {}", .{err});
                };
            } else |err| {
                std.log.err("Failed to load texture {}", .{err});
            }
        }
        const grid_texture_opt = self.texture_map.get(grid_texture_handle);

        self.pbr_material_shader.bind();
        self.pbr_material_shader.set_uniform_mat4("view_projection_matrix", &view_projection_matrix);

        for (scene.static_meshes.items, 0..) |static_mesh, i| {
            if (static_mesh.component.visable == false) {
                continue;
            }

            if (!self.static_mesh_map.contains(static_mesh.component.mesh)) {
                if (global.assets.meshes.loadAsset(self.allocator, static_mesh.component.mesh)) |mesh| {
                    defer mesh.deinit(self.allocator);
                    const gpu_mesh = Mesh.init(&mesh);
                    self.static_mesh_map.put(static_mesh.component.mesh, gpu_mesh) catch |err| {
                        gpu_mesh.deinit();
                        std.log.err("Failed to appeded static mesh to list {}", .{err});
                    };
                } else |err| {
                    std.log.err("Failed to load static mesh {}", .{err});
                }
            }

            if (self.static_mesh_map.getPtr(static_mesh.component.mesh)) |mesh| {
                const model_matrix = static_mesh.transform.get_model_matrix();
                self.pbr_material_shader.set_uniform_mat4("model_matrix", &model_matrix);
                self.pbr_material_shader.set_uniform_vec4("base_color_factor", za.Vec4.ONE);

                if (grid_texture_opt) |grid_texture| {
                    const TextureSlot = 0;
                    grid_texture.bind(TextureSlot);
                    self.pbr_material_shader.set_uniform_int("base_color_texture", TextureSlot);
                    self.pbr_material_shader.set_uniform_int("base_color_texture_enable", 1);
                } else {
                    self.pbr_material_shader.set_uniform_int("base_color_texture_enable", 0);
                }

                mesh.draw();
            } else {
                std.log.warn("Instance {} contains an invalid Mesh {}", .{ i, static_mesh.component.mesh });
            }
        }
    }
};
