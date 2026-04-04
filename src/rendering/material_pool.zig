const std = @import("std");

const saturn = @import("../root.zig");
const TransferQueue = @import("transfer_queue.zig");
const AssetRegistry = @import("../asset/registry.zig");
const CpuMaterial = @import("material.zig");

const GpuPool = @import("gpu_pool.zig").GpuPool;

// pub const ShaderHandle = u16;
// pub const MaterialHandle = struct {
//     shader: ShaderHandle,
//     material_offset: u16,
// };

pub const MaterialInstanceData = extern struct {
    base_color_factor: [4]f32 = @splat(1.0),
};

pub const Material = struct {
    legacy_pipeline: ?saturn.GraphicsPipelineHandle = null,

    instance_data: GpuPool(GpuMaterial),

    fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, instance_count: usize) saturn.Error!Material {
        var instance_data: GpuPool(GpuMaterial) = try .init(gpa, device, "material_instance_data", instance_count, .{ .storage = true, .transfer_dst = true, .device_address = true }, std.mem.zeroes(GpuMaterial));
        errdefer instance_data.deinit();

        return .{
            .instance_data = instance_data,
        };
    }

    fn deinit(self: *Material) void {
        self.instance_data.deinit();
    }
};

const Self = @This();

gpa: std.mem.Allocator,
device: saturn.DeviceInterface,

opaque_material: Material,

pub fn init(
    gpa: std.mem.Allocator,
    device: saturn.DeviceInterface,
    max_instance_count: usize,
) saturn.Error!Self {
    var opaque_material: Material = try .init(gpa, device, max_instance_count);
    errdefer opaque_material.deinit();

    return .{
        .gpa = gpa,
        .device = device,

        .opaque_material = opaque_material,
    };
}

pub fn deinit(self: *Self) void {
    self.opaque_material.deinit();
}

pub fn flush(self: *Self, transfer_queue: *TransferQueue) !void {
    try self.opaque_material.instance_data.flush(transfer_queue);
}

pub fn add(self: *Self, mat: CpuMaterial) ?u32 {
    if (mat.alpha_mode != .@"opaque") {
        return null;
    }

    const gpu_mat: GpuMaterial = .{
        .alpha_mode = @intCast(@intFromEnum(mat.alpha_mode)),
        .alpha_cutoff = mat.alpha_cutoff,
        .base_color_texture = mat.base_color_texture orelse 0,
        .metallic_roughness_texture = mat.metallic_roughness_texture orelse 0,

        .emissive_texture = mat.emissive_texture orelse 0,
        .occlusion_texture = mat.occlusion_texture orelse 0,
        .normal_texture = mat.normal_texture orelse 0,

        .base_color_factor = mat.base_color_factor,
        .metallic_roughness_factor_pad2 = .{ mat.metallic_roughness_factor[0], mat.metallic_roughness_factor[1], 0.0, 0.0 },
        .emissive_factor_pad = .{ mat.emissive_factor[0], mat.emissive_factor[1], mat.emissive_factor[2], 0.0 },
    };

    return self.opaque_material.instance_data.create(gpu_mat) catch null;
}

pub const GpuMaterial = extern struct {
    const ExpectedSize: usize = @sizeOf([4]f32) * 5;
    comptime {
        if (@sizeOf(GpuMaterial) != ExpectedSize) {
            @compileError("GpuMaterial is incorrect size");
        }
    }

    // Block 1 (Vec4 size)
    alpha_mode: i32,
    alpha_cutoff: f32,
    base_color_texture: u32,
    metallic_roughness_texture: u32,

    // Block 2 (Vec4 size)
    emissive_texture: u32,
    occlusion_texture: u32,
    normal_texture: u32,
    pad0: u32 = 0,

    // Block 3 (3 * Vec4 size)
    base_color_factor: [4]f32,
    metallic_roughness_factor_pad2: [4]f32,
    emissive_factor_pad: [4]f32,
};
