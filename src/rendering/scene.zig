const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const Backend = @import("vulkan/backend.zig");

const AssetRegistry = @import("../asset/registry.zig");
const Material = @import("../asset/material.zig");

const Resources = @import("resources.zig");
const rg = @import("vulkan/render_graph.zig");

const Transform = @import("../transform.zig");

const InstanceMap = @import("../containers.zig").HandlePool(SceneInstance);
const FixedArrayList = @import("../fixed_array_list.zig").FixedArrayList;

const MaxPrimitives: comptime_int = 32;
const PrimitiveArray = FixedArrayList(ScenePrimitive, MaxPrimitives);

const GpuArrayList = @import("utils.zig").GpuArrayList;

pub const SceneInstanceHandle = InstanceMap.Handle;
const SceneInstance = struct {
    transform: Transform,
    visable: bool = true,
    mesh: AssetRegistry.Handle,

    instance_index: ?u32 = null,
    primitives: PrimitiveArray = .empty,
};
const ScenePrimitive = struct {
    material_handle: AssetRegistry.Handle,
    primitive_index_index: ?u32 = null,
    alpha_mode: Material.AlphaMode,
};

pub const GpuInstance = extern struct {
    model_matrix: zm.Mat,
    normal_matrix: zm.Mat,
    mesh_index: u32,
    visable: u32,
    pad0: u32 = 0,
    pad1: u32 = 0,
};
pub const GpuPrimitiveInstance = extern struct {
    instance_index: u32,
    primitive_index: u32,
    material_instance_index: u32,
    pad0: u32 = 0,
};

const Self = @This();

// CPU
allocator: std.mem.Allocator,
instances: InstanceMap,

// GPU
backend: *Backend,
scene_instance_buffer: GpuArrayList(GpuInstance),
opaque_primitives_buffer: GpuArrayList(GpuPrimitiveInstance),
alpha_blend_primitives_buffer: GpuArrayList(GpuPrimitiveInstance),
alpha_mask_primitives_buffer: GpuArrayList(GpuPrimitiveInstance),

pub fn init(allocator: std.mem.Allocator, backend: *Backend) !Self {
    const buffer_capacity = 256;

    const buffer_usage: vk.BufferUsageFlags = .{
        .vertex_buffer_bit = true,
        .index_buffer_bit = true,
        .transfer_dst_bit = true,
        .shader_device_address_bit = true,
    };

    var scene_instance_buffer = try GpuArrayList(GpuInstance).init(allocator, backend, "scene_instance_buffer", buffer_usage, buffer_capacity);
    errdefer scene_instance_buffer.deinit();

    var opaque_primitives_buffer = try GpuArrayList(GpuPrimitiveInstance).init(allocator, backend, "opaque_primitives_buffer", buffer_usage, buffer_capacity);
    errdefer opaque_primitives_buffer.deinit();

    var alpha_blend_primitives_buffer = try GpuArrayList(GpuPrimitiveInstance).init(allocator, backend, "alpha_blend_primitives_buffer", buffer_usage, buffer_capacity);
    errdefer alpha_blend_primitives_buffer.deinit();

    var alpha_mask_primitives_buffer = try GpuArrayList(GpuPrimitiveInstance).init(allocator, backend, "alpha_mask_primitives_buffer", buffer_usage, buffer_capacity);
    errdefer alpha_mask_primitives_buffer.deinit();

    return .{
        .allocator = allocator,
        .instances = InstanceMap.init(allocator),

        .backend = backend,
        .scene_instance_buffer = scene_instance_buffer,
        .opaque_primitives_buffer = opaque_primitives_buffer,
        .alpha_blend_primitives_buffer = alpha_blend_primitives_buffer,
        .alpha_mask_primitives_buffer = alpha_mask_primitives_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.instances.deinit();
    self.scene_instance_buffer.deinit();
    self.opaque_primitives_buffer.deinit();
    self.alpha_blend_primitives_buffer.deinit();
    self.alpha_mask_primitives_buffer.deinit();
}

fn getPrimitiveBuffer(self: *Self, alpha_mode: Material.AlphaMode) *GpuArrayList(GpuPrimitiveInstance) {
    return switch (alpha_mode) {
        .alpha_opaque => &self.opaque_primitives_buffer,
        .alpha_blend => &self.alpha_blend_primitives_buffer,
        .alpha_mask => &self.alpha_mask_primitives_buffer,
    };
}

pub fn addInstance(
    self: *Self,
    resources: *const Resources,
    instance: struct {
        transform: Transform,
        visable: bool = true,
        mesh: AssetRegistry.Handle,
        materials: []const AssetRegistry.Handle,
    },
) !SceneInstanceHandle {
    const mesh_asset = resources.meshes.map.get(instance.mesh).?;

    const instance_index: u32 = @intCast(try self.scene_instance_buffer.push(.{
        .model_matrix = instance.transform.getModelMatrix(),
        .normal_matrix = instance.transform.getNormalMatrix(),
        .mesh_index = mesh_asset.index,
        .visable = @intFromBool(instance.visable),
    }));

    var primitives: PrimitiveArray = .empty;

    const primitives_count = @min(instance.materials.len, mesh_asset.cpu_primitives.len);
    for (instance.materials[0..primitives_count], 0..) |material_handle, primitive_index| {
        const material = resources.material_map.get(material_handle).?;
        const material_index = material.buffer_index.?;
        const alpha_mode = material.material.alpha_mode;

        const primitive_buffer = self.getPrimitiveBuffer(alpha_mode);
        const primitive_gpu_index: u32 = @intCast(try primitive_buffer.push(.{
            .instance_index = instance_index,
            .primitive_index = @intCast(primitive_index),
            .material_instance_index = material_index,
        }));

        primitives.add(.{
            .material_handle = material_handle,
            .primitive_index_index = primitive_gpu_index,
            .alpha_mode = material.material.alpha_mode,
        });
    }

    const handle = try self.instances.insert(.{
        .transform = instance.transform,
        .visable = instance.visable,
        .mesh = instance.mesh,
        .instance_index = instance_index,
        .primitives = primitives,
    });

    return handle;
}

pub fn removeInstance(self: *Self, handle: SceneInstanceHandle) !void {
    const instance = self.instances.remove(handle) orelse return;

    // Remove primitives from GPU buffer
    for (instance.primitives.slice()) |primitive| {
        if (primitive.primitive_index_index) |gpu_index| {
            const primitive_buffer = self.getPrimitiveBuffer(primitive.alpha_mode);
            if (try primitive_buffer.swapRemove(gpu_index)) |swapped_index| {
                // Update any instance that had its primitive swapped
                self.updateSwappedPrimitiveIndex(primitive.alpha_mode, swapped_index, gpu_index);
            }
        }
    }

    // Remove instance from GPU buffer
    if (instance.instance_index) |gpu_index| {
        if (try self.scene_instance_buffer.swapRemove(gpu_index)) |swapped_index| {
            // Update any instance that had its index swapped
            self.updateSwappedInstanceIndex(swapped_index, gpu_index);
        }
    }
}

fn updateSwappedInstanceIndex(self: *Self, old_index: u32, new_index: u32) void {
    var iter = self.instances.iterator();
    while (iter.next_value()) |instance| {
        if (instance.instance_index == old_index) {
            instance.instance_index = new_index;

            // Update all primitives that reference this instance
            for (instance.primitives.slice()) |primitive| {
                if (primitive.primitive_index_index) |gpu_index| {
                    const primitive_buffer = self.getPrimitiveBuffer(primitive.alpha_mode);

                    // Update the GPU buffer with new instance index
                    var gpu_primitive = primitive_buffer.cpu.items[gpu_index];
                    gpu_primitive.instance_index = new_index;

                    const byte_offset = gpu_index * @sizeOf(GpuPrimitiveInstance);
                    const item_bytes = std.mem.asBytes(&gpu_primitive);
                    self.backend.getTransferQueue().writeBuffer(primitive_buffer.gpu, byte_offset, item_bytes.*) catch |err| {
                        std.log.err("Failed to update primitive instance index: {}", .{err});
                    };
                }
            }
            break;
        }
    }
}

fn updateSwappedPrimitiveIndex(self: *Self, alpha_mode: Material.AlphaMode, old_index: u32, new_index: u32) void {
    var iter = self.instances.iterator();
    while (iter.next_value()) |instance| {
        for (instance.primitives.slice()) |*primitive| {
            if (primitive.alpha_mode == alpha_mode and primitive.primitive_index_index == old_index) {
                primitive.primitive_index_index = new_index;
                return;
            }
        }
    }
}

pub fn updateInstanceTransform(self: *Self, handle: SceneInstanceHandle, transform: Transform, resources: *const Resources) !void {
    if (self.instances.getPtr(handle)) |instance| {
        instance.transform = transform;

        if (instance.instance_index) |gpu_index| {
            const mesh_asset = resources.meshes.map.get(instance.mesh).?;

            const gpu_instance = GpuInstance{
                .model_matrix = transform.getModelMatrix(),
                .normal_matrix = transform.getNormalMatrix(),
                .mesh_index = mesh_asset.index,
                .visable = @intFromBool(instance.visable),
            };

            const byte_offset = gpu_index * @sizeOf(GpuInstance);
            const item_bytes = std.mem.asBytes(&gpu_instance);
            try self.backend.getTransferQueue().writeBuffer(self.scene_instance_buffer.gpu, byte_offset, item_bytes.*);
        }
    } else {
        std.log.err("Invalid instance handle {}", .{handle});
    }
}
