const std = @import("std");

const AssetRegistry = @import("asset/registry.zig");

pub var global_allocator: std.mem.Allocator = undefined;

pub var asset_registry: *AssetRegistry = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    global_allocator = allocator;

    asset_registry = try allocator.create(AssetRegistry);
    asset_registry.* = .init(allocator);
}

pub fn deinit() void {
    asset_registry.deinit();
    global_allocator.destroy(asset_registry);

    global_allocator = undefined;
}
