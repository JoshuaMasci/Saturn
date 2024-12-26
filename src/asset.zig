const std = @import("std");

const HashType = u32;
const HashMethod = std.hash.Fnv1a_32;

//TODO: this whole system is a little naive
// Meshes can represent  Render, Physics, or even Audio meshes
// GLTF files can store meshes, textures, materials, animaions, and scenes
// So the asset system needs to allow files to be collections of assets, with unique handles for each sub-asset

//TODO: pack into u64?
pub const AssetHandle = packed struct {
    asset_type: AssetType,
    source_hash: HashType,
    asset_hash: HashType,

    pub fn fromSourcePath(asset_type: AssetType, source_path: []const u8) ?AssetHandle {
        var split = std.mem.split(u8, source_path, ":");
        const source = split.next() orelse return null;
        const path = split.next() orelse return null;
        const source_hash = HashMethod.hash(source);
        const asset_hash = HashMethod.hash(path);
        return .{ .asset_type = asset_type, .source_hash = source_hash, .asset_hash = asset_hash };
    }
};

fn CreateAssetHandle(comptime asset_type: AssetType) type {
    return struct {
        const Self = @This();

        handle: AssetHandle,
        pub fn fromSourcePath(source_path: []const u8) ?Self {
            if (AssetHandle.fromSourcePath(asset_type, source_path)) |handle| {
                return .{ .handle = handle };
            }
            return null;
        }
    };
}

pub const MeshAssetHandle = CreateAssetHandle(.rendering_mesh);
pub const TextureAssetHandle = CreateAssetHandle(.rendering_texture);
pub const MaterialAssetHandle = CreateAssetHandle(.rendering_material);
pub const CubeTextureAssetHandle = CreateAssetHandle(.rendering_cube_texture);

pub const AssetType = enum(u8) {
    const Self = @This();

    unknown = 0,

    // Rendering
    rendering_mesh,
    rendering_texture,
    rendering_material,
    rendering_cube_texture,

    // Physics
    phyiscs_mesh,
    physics_hull,

    // Audio
    audio_stream,

    // Entity
    prefab,
    scene,

    pub fn getAssetTypesFromExt(ext: []const u8) []const Self {
        if (std.mem.eql(u8, ext, ".mesh")) {
            return &.{ .rendering_mesh, .phyiscs_mesh };
        } else if (std.mem.eql(u8, ext, ".png")) {
            return &.{.rendering_texture};
        } else if (std.mem.eql(u8, ext, ".mat")) {
            return &.{.rendering_material};
        }

        return &.{};
    }
};

pub const AssetSource = union(enum) {
    source_path: []const u8,
};

pub const AssetInfo = struct {
    handle: AssetHandle,
    name: []u8,
    source: AssetSource,
};

const AssetMap = std.AutoHashMap(AssetHandle, AssetInfo);
pub const AssetRepository = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    source_hash: HashType,
    map: AssetMap,

    pub fn initFromDir(allocator: std.mem.Allocator, source_hash: HashType, dir_path: []const u8) !Self {
        var map = AssetMap.init(allocator);

        var asset_dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        var walker = try asset_dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind == .file) {
                const asset_hash = HashMethod.hash(entry.path);
                for (AssetType.getAssetTypesFromExt(std.fs.path.extension(entry.path))) |asset_type| {
                    const basename = std.fs.path.basename(entry.path);
                    const name = try allocator.alloc(u8, basename.len);
                    @memcpy(name, basename);

                    const path = try allocator.alloc(u8, entry.path.len);
                    @memcpy(path, entry.path);

                    const asset_handle: AssetHandle = .{ .asset_type = asset_type, .source_hash = source_hash, .asset_hash = asset_hash };
                    try map.putNoClobber(asset_handle, .{ .handle = asset_handle, .name = name, .source = .{ .source_path = path } });
                }
            }
        }

        return .{ .allocator = allocator, .source_hash = source_hash, .map = map };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
            switch (entry.value_ptr.source) {
                .source_path => |path| self.allocator.free(path),
            }
        }

        self.map.deinit();
    }
};

const RepositoryMap = std.AutoHashMap(HashType, AssetRepository);
pub const AssetRegistry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    repositories: RepositoryMap,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .repositories = RepositoryMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.repositories.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.repositories.deinit();
    }

    pub fn addDirectorySource(self: *Self, name: []const u8, dir_path: []const u8) !void {
        const source_hash = HashMethod.hash(name);
        const source = try AssetRepository.initFromDir(self.allocator, source_hash, dir_path);
        try self.repositories.putNoClobber(source_hash, source);
    }

    // Checks if any source contains this handle
    pub fn isAssetHandleValid(self: Self, handle: AssetHandle) bool {
        if (self.repositories.get(handle.source_hash)) |asset_repo| {
            if (asset_repo.map.contains(handle)) {
                return true;
            }
        }
        return false;
    }

    // Returns where this asset can be found
    pub fn getAssetSource(self: Self, handle: AssetHandle) ?AssetSource {
        if (self.repositories.get(handle.source_hash)) |asset_repo| {
            if (asset_repo.map.get(handle)) |info| {
                return info.source;
            }
        }
        return null;
    }
};
