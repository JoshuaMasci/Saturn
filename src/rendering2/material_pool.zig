const std = @import("std");

const saturn = @import("../root.zig");
const TransferQueue = @import("transfer_queue.zig");
const AssetRegistry = @import("../asset/registry.zig");

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

    instance_data: GpuPool(MaterialInstanceData),

    fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, instance_count: usize) saturn.Error!Material {
        var instance_data: GpuPool(MaterialInstanceData) = try .init(gpa, device, "material_instance_data", instance_count, .{ .storage = true, .transfer_dst = true, .device_address = true }, .{});
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
