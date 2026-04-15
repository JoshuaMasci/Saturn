const std = @import("std");

const saturn = @import("../root.zig");

const AssetRegistry = @import("../asset/registry.zig");
const ShaderAsset = @import("../asset/shader.zig");

pub fn loadShader(gpa: std.mem.Allocator, device: saturn.DeviceInterface, registry: *const AssetRegistry, handle: AssetRegistry.Handle) !saturn.ShaderHandle {
    var shader_asset = try registry.loadAsset(ShaderAsset, gpa, handle, .{});
    defer shader_asset.deinit(gpa);

    return try device.createShaderModule(.{ .code = shader_asset.spirv_code });
}
