const std = @import("std");

const saturn = @import("../root.zig");
const AssetRegistry = @import("../asset/registry.zig");
const CpuTexture = @import("../asset/texture.zig");
const TransferQueue = @import("transfer_queue.zig");

pub const TextureEntry = struct {
    const Gpu = extern struct {
        loaded: u32,
        sampled_binding: u32,
        width: u32,
        height: u32,
        depth: u32,
        mip_count: u32,
        format: u32,
        _padding: u32,
    };

    gpu_handle: saturn.TextureHandle,
    width: u32,
    height: u32,
    depth: u32,
    mip_count: u32,
    format: saturn.TextureFormat,
    sampled_binding: u32,

    fn getGpuEntry(self: TextureEntry) Gpu {
        return .{
            .loaded = 1,
            .sampled_binding = self.sampled_binding,
            .width = self.width,
            .height = self.height,
            .depth = self.depth,
            .mip_count = self.mip_count,
            .format = @intFromEnum(self.format),
            ._padding = 0,
        };
    }
};

const Self = @This();

device: saturn.DeviceInterface,
texture_info_buffer: saturn.BufferHandle,
max_texture_count: usize,

pub fn init(
    device: saturn.DeviceInterface,
    max_texture_count: usize,
) !Self {
    const texture_info_buffer = try device.createBuffer(.{
        .name = "texture_info_buffer",
        .size = @sizeOf(TextureEntry.Gpu) * max_texture_count,
        .usage = .{ .storage = true, .transfer_dst = true, .device_address = true },
        .memory = .gpu_only,
    });
    errdefer device.destroyBuffer(texture_info_buffer);

    return .{
        .device = device,
        .texture_info_buffer = texture_info_buffer,
        .max_texture_count = max_texture_count,
    };
}

pub fn deinit(self: *Self) void {
    self.device.destroyBuffer(self.texture_info_buffer);
}

pub fn createTexture(self: *Self, cpu_texture: *const CpuTexture, sampler: saturn.SamplerHandle) !TextureEntry {
    const texture_format: saturn.TextureFormat = switch (cpu_texture.format) {
        .r8 => .rgba8_unorm,
        .rg8 => .rgba8_unorm,
        .rgba8 => .rgba8_unorm,
    };

    const mip_levels = 1;

    const gpu_handle = try self.device.createTexture(.{
        .name = cpu_texture.name,
        .extent = .{ .width = cpu_texture.width, .height = cpu_texture.height, .depth = cpu_texture.depth },
        .mip_levels = mip_levels,
        .format = texture_format,
        .usage = .{ .sampled = true, .transfer_dst = true },
        .memory = .gpu_only,
        .sampler = sampler,
    });

    const info = self.device.getTextureInfo(gpu_handle).?;
    const sampled_binding = info.sampled orelse 0;

    return TextureEntry{
        .gpu_handle = gpu_handle,
        .width = cpu_texture.width,
        .height = cpu_texture.height,
        .depth = cpu_texture.depth,
        .mip_count = mip_levels,
        .format = texture_format,
        .sampled_binding = sampled_binding,
    };
}

pub fn destroyTexture(self: *Self, texture_entry: TextureEntry) void {
    self.device.destroyTexture(texture_entry.gpu_handle);
}

pub fn uploadTextureData(self: *Self, transfer_queue: *TransferQueue, texture_index: u32, cpu_texture: *const CpuTexture, texture_entry: TextureEntry) !void {
    if (texture_index >= self.max_texture_count) {
        return error.TextureIndexOutOfBounds;
    }

    const texture_info = texture_entry.getGpuEntry();
    const texture_info_offset = texture_index * @sizeOf(TextureEntry.Gpu);

    try transfer_queue.addBulkBufferUpload(&.{
        .{ .dst = self.texture_info_buffer, .offset = texture_info_offset, .data = std.mem.asBytes(&texture_info) },
    });

    try transfer_queue.addTextureUpload(texture_entry.gpu_handle, cpu_texture.data);
}
