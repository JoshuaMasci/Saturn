const std = @import("std");

const physics = @import("physics");
const vk = @import("vulkan");
const zm = @import("zmath");

const AssetRegistry = @import("../asset/registry.zig");
const c = @import("../platform/sdl3.zig").c;
const Window = @import("../platform/sdl3.zig").Window;
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const Device = @import("vulkan/device.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");

const DrawMeshData = struct {
    mesh: MeshPrimitive,
    model_matrix: zm.Mat,
    color: zm.Vec,
};

const MeshPrimitive = struct {
    vertex_buffer: Device.BufferHandle,
    index_buffer: ?Device.BufferHandle,

    vertex_count: u32,
    index_count: u32,
};

pub const BuildCommandBufferData = struct {
    camera: Camera,
    camera_transform: Transform,

    wireframe_mesh_graphics_pipeline: vk.Pipeline,

    draw_wireframe_meshs: []const DrawMeshData,
};

const Self = @This();

allocator: std.mem.Allocator,
device: *Device,

solid_mesh_graphics_pipeline: vk.Pipeline,
wireframe_mesh_graphics_pipeline: vk.Pipeline,

meshes: std.AutoArrayHashMap(physics.MeshPrimitive, MeshPrimitive),

//Frame Draw Data
draw_wireframe_meshs: std.ArrayList(DrawMeshData),

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Device,
    color_format: vk.Format,
    depth_format: vk.Format,
    pipeline_layout: vk.PipelineLayout,
) !Self {
    const vertex_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/physics_mesh.vert.asset"));
    defer device.device.proxy.destroyShaderModule(vertex_shader, null);

    const fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/physics_mesh.frag.asset"));
    defer device.device.proxy.destroyShaderModule(fragment_shader, null);

    const bindings = [_]vk.VertexInputBindingDescription{
        .{
            .binding = 0,
            .stride = @sizeOf(physics.Vertex),
            .input_rate = .vertex,
        },
    };

    const attributes = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(physics.Vertex, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(physics.Vertex, "normal"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(physics.Vertex, "uv"),
        },
        .{
            .binding = 0,
            .location = 3,
            .format = .r8g8b8a8_unorm,
            .offset = @offsetOf(physics.Vertex, "color"),
        },
    };

    const wireframe_mesh_graphics_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        .{
            .color_format = color_format,
            .depth_format = depth_format,
            .cull_mode = .{},
            .polygon_mode = .line,
            .enable_depth_test = false,
            .enable_depth_write = false,
        },
        .{ .bindings = &bindings, .attributes = &attributes },
        vertex_shader,
        fragment_shader,
    );

    return .{
        .allocator = allocator,
        .device = device,
        .meshes = std.AutoArrayHashMap(physics.MeshPrimitive, MeshPrimitive).init(allocator),
        .solid_mesh_graphics_pipeline = .null_handle,
        .wireframe_mesh_graphics_pipeline = wireframe_mesh_graphics_pipeline,
        .draw_wireframe_meshs = std.ArrayList(DrawMeshData).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.wireframe_mesh_graphics_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.solid_mesh_graphics_pipeline, null);

    for (self.meshes.values()) |mesh| {
        self.device.destroyBuffer(mesh.vertex_buffer);
        if (mesh.index_buffer) |index_buffer| {
            self.device.destroyBuffer(index_buffer);
        }
    }
    self.meshes.deinit();

    self.draw_wireframe_meshs.deinit();
}

pub fn buildFrame(self: *Self, world: *physics.World, camera_transform: physics.Transform, ignore_list: []const physics.Body) void {
    self.draw_wireframe_meshs.clearRetainingCapacity();

    physics.debugRendererBuildFrame(world, camera_transform, ignore_list);
}

pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    color_target: rg.RenderGraphTextureHandle,
    depth_target: rg.RenderGraphTextureHandle,
    camera: Camera,
    camera_transform: Transform,
    render_graph: *rg.RenderGraph,
) !void {
    var render_pass = try rg.RenderPass.init(temp_allocator, "Debug Physics Pass");
    try render_pass.addColorAttachment(.{
        .texture = color_target,
        .clear = null,
        .store = true,
    });
    render_pass.addDepthAttachment(.{
        .texture = depth_target,
        .clear = null,
        .store = true,
    });

    const scene_build_data = try temp_allocator.create(BuildCommandBufferData);
    scene_build_data.* = .{
        .camera = camera,
        .camera_transform = camera_transform,
        .wireframe_mesh_graphics_pipeline = self.wireframe_mesh_graphics_pipeline,
        .draw_wireframe_meshs = try temp_allocator.dupe(DrawMeshData, self.draw_wireframe_meshs.items),
    };
    render_pass.addBuildFn(buildCommandBuffer, scene_build_data);

    try render_graph.render_passes.append(render_pass);
}

const PushData = extern struct {
    view_projection_matrix: zm.Mat,
    model_matrix: zm.Mat,
    base_color_factor: zm.Vec,
};

pub fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = resources; // autofix

    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));

    const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
    const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = data.camera_transform.getViewMatrix();
    var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
    projection_matrix[1][1] *= -1.0;
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

    command_buffer.bindPipeline(.graphics, data.wireframe_mesh_graphics_pipeline);

    const viewport = vk.Viewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(raster_pass_extent.?.width),
        .height = @floatFromInt(raster_pass_extent.?.height),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };
    command_buffer.setViewport(0, 1, (&viewport)[0..1]);
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = raster_pass_extent.?,
    };
    command_buffer.setScissor(0, 1, (&scissor)[0..1]);

    for (data.draw_wireframe_meshs) |draw| {
        const push_data = PushData{
            .view_projection_matrix = view_projection_matrix,
            .model_matrix = draw.model_matrix,
            .base_color_factor = draw.color,
        };
        command_buffer.pushConstants(device.bindless_layout, .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true }, 0, @sizeOf(PushData), &push_data);

        drawPrimitive(device, command_buffer, draw.mesh);
    }
}

pub fn drawPrimitive(
    device: *Device,
    command_buffer: vk.CommandBufferProxy,
    primitive: anytype, // Your primitive struct
) void {
    const vertex_buffer = device.buffers.get(primitive.vertex_buffer) orelse return;

    const vertex_buffers = [_]vk.Buffer{vertex_buffer.handle};
    const vertex_offsets = [_]vk.DeviceSize{0};

    command_buffer.bindVertexBuffers(0, 1, &vertex_buffers, &vertex_offsets);

    if (primitive.index_buffer) |index_buffer_handle| {
        const index_buffer = device.buffers.get(index_buffer_handle) orelse return;

        command_buffer.bindIndexBuffer(index_buffer.handle, 0, .uint32);
        command_buffer.drawIndexed(primitive.index_count, 1, 0, 0, 0);
    } else {
        command_buffer.draw(primitive.vertex_count, 1, 0, 0);
    }
}

pub fn getDebugRendererData(self: *Self) physics.DebugRendererCallbacks {
    return .{
        .ptr = self,
        .draw_line = drawLineCallback,
        .draw_triangle = drawTriangleCallback,
        .draw_text = drawText3DCallback,
        .create_triangle_mesh = createTriangleMeshCallback,
        .create_indexed_mesh = createIndexedMeshCallback,
        .draw_geometry = drawGeometryCallback,
        .free_mesh = freeMeshPrimitive,
    };
}

fn drawLineCallback(ptr: ?*anyopaque, data: physics.DrawLineData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    //TODO: implement this
}

fn drawTriangleCallback(ptr: ?*anyopaque, data: physics.DrawTriangleData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    //TODO: implement this

}

fn drawText3DCallback(ptr: ?*anyopaque, data: physics.DrawTextData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    //TODO: implement this
}

fn createTriangleMeshCallback(ptr: ?*anyopaque, id: physics.MeshPrimitive, triangles: [*c]const physics.Triangle, triangle_count: usize) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));

    const triange_slice: []const physics.Triangle = triangles[0..triangle_count];

    const vertex_buffer = self.device.createBufferWithData(.{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(triange_slice)) catch |err| {
        std.log.err("Failed to create vertex buffer: {}", .{err});
        return;
    };

    const primitive: MeshPrimitive = .{
        .vertex_buffer = vertex_buffer,
        .index_buffer = null,
        .vertex_count = @intCast(triange_slice.len * 3),
        .index_count = 0,
    };
    self.meshes.put(id, primitive) catch |err| std.debug.panic("Failed to put mesh into map: {}", .{err});
}

fn createIndexedMeshCallback(ptr: ?*anyopaque, id: physics.MeshPrimitive, vertices: [*c]const physics.Vertex, vertex_count: usize, indices: [*c]const u32, index_count: usize) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));

    const vertices_slice: []const physics.Vertex = vertices[0..vertex_count];
    const index_slice: []const u32 = indices[0..index_count];

    const vertex_buffer = self.device.createBufferWithData(.{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(vertices_slice)) catch |err| {
        std.log.err("Failed to create vertex buffer: {}", .{err});
        return;
    };

    const index_buffer = self.device.createBufferWithData(.{ .index_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(index_slice)) catch |err| {
        std.log.err("Failed to create index buffer: {}", .{err});
        return;
    };

    const primitive: MeshPrimitive = .{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .vertex_count = @intCast(vertices_slice.len),
        .index_count = @intCast(index_slice.len),
    };
    self.meshes.put(id, primitive) catch |err| std.debug.panic("Failed to put mesh into map: {}", .{err});
}

fn drawGeometryCallback(ptr: ?*anyopaque, data: physics.DrawGeometryData) callconv(.C) void {
    //TODO: implement this
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));

    const color = zm.f32x4(@floatFromInt(data.color.r), @floatFromInt(data.color.g), @floatFromInt(data.color.b), @floatFromInt(data.color.a)) / zm.splat(zm.Vec, 255.0);
    const model_matrix = zm.matFromArr(data.model_matrix);

    const mesh = self.meshes.get(data.mesh) orelse return;

    const draw_data: DrawMeshData = .{
        .color = color,
        .mesh = mesh,
        .model_matrix = model_matrix,
    };

    const DrawModeSolid: u32 = @intFromEnum(physics.DrawMode.solid);
    if (data.draw_mode == DrawModeSolid) {
        //self.draw_solid_meshs.append(draw_data) catch |err| std.debug.panic("Failed to append to draw list: {}", .{err});
    } else {
        self.draw_wireframe_meshs.append(draw_data) catch |err| std.debug.panic("Failed to append to draw list: {}", .{err});
    }
}

fn freeMeshPrimitive(ptr: ?*anyopaque, id: physics.MeshPrimitive) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.meshes.fetchSwapRemove(id)) |entry| {
        const mesh = entry.value;
        self.device.destroyBuffer(mesh.vertex_buffer);
        if (mesh.index_buffer) |index_buffer| {
            self.device.destroyBuffer(index_buffer);
        }
    }
}
