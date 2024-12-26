const std = @import("std");
const za = @import("zalgebra");

const gl = @import("zopengl").bindings;

const asset = @import("../asset.zig");
const Transform = @import("../transform.zig");
const Camera = @import("../camera.zig").Camera;
const RenderScene = @import("scene.zig").RenderScene;

const ColoredVertex = @import("../platform/opengl/vertex.zig").ColoredVertex;
const TexturedVertex = @import("../platform/opengl/vertex.zig").TexturedVertex;
const Mesh = @import("../platform/opengl/mesh.zig");
const Texture = @import("../platform/opengl/texture.zig");
const Shader = @import("../platform/opengl/shader.zig");
const Material = @import("types.zig").Material;

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

    texture_map: std.AutoHashMap(asset.TextureAssetHandle, Texture),
    cube_texture_map: std.AutoHashMap(asset.CubeTextureAssetHandle, Texture),
    static_mesh_map: std.AutoHashMap(asset.MeshAssetHandle, Mesh),
    material_map: std.AutoHashMap(asset.MaterialAssetHandle, Material),

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

            .texture_map = std.AutoHashMap(asset.TextureAssetHandle, Texture).init(allocator),
            .cube_texture_map = std.AutoHashMap(asset.CubeTextureAssetHandle, Texture).init(allocator),
            .static_mesh_map = std.AutoHashMap(asset.MeshAssetHandle, Mesh).init(allocator),
            .material_map = std.AutoHashMap(asset.MaterialAssetHandle, Material).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        gl.deleteVertexArrays(1, &self.skybox_vao);
        self.skybox_shader.deinit();
        self.colored_material_shader.deinit();
        self.pbr_material_shader.deinit();

        self.texture_map.deinit();
        self.cube_texture_map.deinit();
        self.static_mesh_map.deinit();
        self.material_map.deinit();
    }

    pub fn clearFramebuffer(self: *Self) void {
        _ = self;
        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }

    pub fn renderScene(self: Self, window_size: [2]u32, scene: *const RenderScene, scene_camera: *const Camera) void {
        var err: gl.Enum = gl.getError();
        while (err != gl.NO_ERROR) {
            std.log.err("GL Error: {}", .{err});
            err = gl.getError();
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

        const view_matrix = scene_camera.transform.get_view_matrix();
        const projection_matrix = scene_camera.data.perspective_gl(aspect_ratio);
        var view_projection_matrix = projection_matrix.mul(view_matrix);

        if (scene.skybox) |skybox_handle| {
            if (self.cube_texture_map.get(skybox_handle)) |skybox_texture| {
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

        // var instance_iterator = scene.instances.iterator();
        // while (instance_iterator.next()) |instance| {
        //     const model_matrix = instance.value_ptr.transform.get_model_matrix();
        //     self.pbr_material_shader.set_uniform_mat4("model_matrix", &model_matrix);
        //     if (self.materials.get(instance.value_ptr.material)) |material| {
        //         self.pbr_material_shader.set_uniform_vec4("base_color_factor", za.Vec4.fromArray(material.base_color_factor));
        //         self.pbr_material_shader.set_uniform_int("base_color_texture_enable", 0);

        //         if (material.base_color_texture) |texture_handle| {
        //             if (self.textures.get(texture_handle)) |texture| {
        //                 const slot = 0;
        //                 texture.bind(slot);
        //                 self.pbr_material_shader.set_uniform_int("base_color_texture", slot);
        //                 self.pbr_material_shader.set_uniform_int("base_color_texture_enable", 1);
        //             }
        //         }

        //         if (self.static_meshes.get(instance.value_ptr.mesh)) |mesh| {
        //             mesh.draw();
        //         } else {
        //             std.log.warn("Instance {} contains an invalid Mesh {}", .{ instance.handle, instance.value_ptr.mesh });
        //         }
        //     } else {
        //         std.log.warn("Instance {} contains an invalid Material {}", .{ instance.handle, instance.value_ptr.material });
        //     }
        // }
    }
};
