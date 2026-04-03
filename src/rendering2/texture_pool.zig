const std = @import("std");

const saturn = @import("../root.zig");
const CpuTexture = @import("../asset/texture.zig");
const TransferQueue = @import("transfer_queue.zig");

const GpuPool = @import("gpu_pool.zig").GpuPool;

pub const TextureHandle = u32;

pub const TextureInfo = struct {
    const Gpu = extern struct {
        loaded: u32 = 0,
        sampled_binding: u32 = 0,
        width: u32 = 0,
        height: u32 = 0,
        depth: u32 = 0,
        mip_count: u32 = 0,
        format: u32 = 0,
        _padding: u32 = 0,
    };

    gpu_handle: saturn.TextureHandle,

    fn getGpu(self: TextureInfo, device: saturn.DeviceInterface) Gpu {
        const info = device.getTextureInfo(self.gpu_handle) orelse return .{};

        return .{
            .loaded = 1,
            .sampled_binding = info.sampled orelse 0,
            .width = info.extent.width,
            .height = info.extent.height,
            .depth = info.extent.depth,
            .mip_count = info.mip_levels,
            .format = @intFromEnum(info.format),
        };
    }
};

const Self = @This();

gpa: std.mem.Allocator,
device: saturn.DeviceInterface,

info_buffer: GpuPool(TextureInfo.Gpu),

map: std.AutoHashMapUnmanaged(TextureHandle, TextureInfo) = .empty,

pub fn init(
    gpa: std.mem.Allocator,
    device: saturn.DeviceInterface,
    max_texture_count: usize,
) !Self {
    var info_buffer: GpuPool(TextureInfo.Gpu) = try .init(gpa, device, "texture_info_buffer", max_texture_count, .{ .storage = true, .transfer_dst = true, .device_address = true }, .{});
    errdefer info_buffer.deinit();

    return .{
        .gpa = gpa,
        .device = device,

        .info_buffer = info_buffer,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.map.valueIterator();
    while (iter.next()) |info| {
        self.device.destroyTexture(info.gpu_handle);
    }
    self.map.deinit(self.gpa);
    self.info_buffer.deinit();
}

pub fn create(self: *Self) error{OutOfMemory}!TextureHandle {
    return try self.info_buffer.alloc();
}

pub fn destroy(self: *Self, handle: TextureHandle) void {
    self.unload(handle);
    self.info_buffer.free(handle);
}

pub fn load(self: *Self, transfer_queue: *TransferQueue, handle: TextureHandle, cpu_texture: *const CpuTexture, sampler: ?saturn.SamplerHandle) saturn.Error!void {
    std.debug.assert(!self.map.contains(handle));

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
    errdefer self.device.destroyTexture(gpu_handle);

    const info: TextureInfo = .{
        .gpu_handle = gpu_handle,
    };
    errdefer self.info_buffer.stage(handle, .{});

    self.info_buffer.stage(handle, info.getGpu(self.device));

    try self.map.put(self.gpa, handle, info);
    try transfer_queue.addTextureUpload(info.gpu_handle, cpu_texture.data);
}

pub fn unload(self: *Self, handle: TextureHandle) void {
    if (self.map.fetchRemove(handle)) |entry| {
        self.device.destroyTexture(entry.value.gpu_handle);
        self.info_buffer.stage(handle, .{});
    }
}
