const std = @import("std");

const vk = @import("vulkan");

const AssetRegistry = @import("../../asset/registry.zig");
const ShaderAsset = @import("../../asset/shader.zig");

pub fn loadGraphicsShader(allocator: std.mem.Allocator, registry: *const AssetRegistry, device: vk.DeviceProxy, handle: AssetRegistry.AssetHandle) !vk.ShaderModule {
    var shader = try registry.loadAsset(ShaderAsset, allocator, handle, .{});
    defer shader.deinit(allocator);

    if (shader.target != .vulkan) {
        return error.InvalidShaderTarget;
    }

    return try device.createShaderModule(&.{
        .flags = .{},
        .code_size = shader.spirv_code.len * @sizeOf(u32), //Code size is in bytes, despite the p_code being a u32ptr
        .p_code = @ptrCast(@alignCast(shader.spirv_code.ptr)),
    }, null);
}
