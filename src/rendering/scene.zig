const std = @import("std");

const zm = @import("zmath");

const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");

const CubeTextureAssetHandle = u32;

pub const MaterialArray = struct {
    const Self = @This();
    const BufferSize = 32;

    buffer: [BufferSize]AssetRegistry.Handle,
    len: usize,

    pub fn init() Self {
        return .{ .buffer = undefined, .len = 0 };
    }

    pub fn fromSlice(src: []const AssetRegistry.Handle) Self {
        std.debug.assert(src.len <= BufferSize);
        var buffer: [BufferSize]AssetRegistry.Handle = .{AssetRegistry.Handle{ .repo_hash = 0, .asset_hash = 42 }} ** BufferSize;
        std.mem.copyForwards(AssetRegistry.Handle, &buffer, src);

        return .{
            .buffer = buffer,
            .len = src.len,
        };
    }

    pub fn constSlice(self: *const Self) []const AssetRegistry.Handle {
        return self.buffer[0..self.len];
    }
};

pub const StaticMeshComponent = struct {
    visable: bool = true,
    mesh: AssetRegistry.Handle,
    materials: MaterialArray,
};

pub const SceneMesh = struct {
    transform: Transform,
    component: StaticMeshComponent,
};

pub const RenderScene = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    skybox: ?CubeTextureAssetHandle = null,
    meshes: std.ArrayList(SceneMesh) = .empty,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.meshes.deinit(self.allocator);
    }

    pub fn clear(self: *Self) void {
        self.skybox = null;
        self.meshes.clearRetainingCapacity();
    }

    pub fn dupe(self: Self, allocator: std.mem.Allocator) !Self {
        var new_self = self;
        new_self.meshes = try std.ArrayList(SceneMesh).initCapacity(allocator, self.meshes.items.len);
        new_self.meshes.appendSliceAssumeCapacity(self.meshes.items);
        return new_self;
    }
};

pub const GpuInstace = struct {
    model_matrix: zm.Mat,
    mesh_index: u32,
    primitive_offset: u32,
    primitive_count: u32,
    pad0: u32,
    material_indexs: [8]u8,
};

pub const Scene = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
};
