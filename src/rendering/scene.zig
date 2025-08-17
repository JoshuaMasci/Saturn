const std = @import("std");

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

pub const SceneStaticMesh = struct {
    transform: Transform,
    component: StaticMeshComponent,
};

pub const RenderScene = struct {
    const Self = @This();

    skybox: ?CubeTextureAssetHandle = null,
    static_meshes: std.ArrayList(SceneStaticMesh),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .static_meshes = std.ArrayList(SceneStaticMesh).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.static_meshes.deinit();
    }

    pub fn clear(self: *Self) void {
        self.skybox = null;
        self.static_meshes.clearRetainingCapacity();
    }

    pub fn dupe(self: Self, allocator: std.mem.Allocator) !Self {
        var new_self = self;
        new_self.static_meshes = try std.ArrayList(SceneStaticMesh).initCapacity(allocator, self.static_meshes.items.len);
        new_self.static_meshes.appendSliceAssumeCapacity(self.static_meshes.items);
        return new_self;
    }
};
