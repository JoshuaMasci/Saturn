const std = @import("std");

const HashType = u32;
pub const HashMethod = std.hash.Fnv1a_32;

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

pub const MeshAssetHandle = CreateAssetHandle(.mesh);
pub const TextureAssetHandle = CreateAssetHandle(.texture);
pub const MaterialAssetHandle = CreateAssetHandle(.material);
pub const CubeTextureAssetHandle = CreateAssetHandle(.cube_texture);

pub const AssetType = enum(u8) {
    const Self = @This();

    unknown = 0,

    // Rendering
    mesh,
    texture,
    material,
    cube_texture,

    pub fn getAssetTypesFromExt(ext: []const u8) []const Self {
        if (std.mem.eql(u8, ext, ".mesh")) {
            return &.{.mesh};
        } else if (std.mem.eql(u8, ext, ".tex2d")) {
            return &.{.texture};
        } else if (std.mem.eql(u8, ext, ".mat")) {
            return &.{.material};
        }

        return &.{};
    }
};

pub const RepositorySource = union(enum) {
    directory: std.fs.Dir,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .directory => |*dir| dir.close(),
        }
    }
};

pub const AssetSource = union(enum) {
    source_path: []const u8,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self) {
            .source_path => |path| allocator.free(path),
        }
    }
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
    source: RepositorySource,
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

        return .{
            .allocator = allocator,
            .source_hash = source_hash,
            .source = .{ .directory = asset_dir },
            .map = map,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
            entry.value_ptr.source.deinit(self.allocator);
        }

        self.map.deinit();
        self.source.deinit();
    }

    pub fn getAssetFile(self: Self, handle: AssetHandle) ?std.fs.File {
        if (self.map.getPtr(handle)) |asset| {
            const file = self.source.directory.openFile(asset.source.source_path, .{ .mode = .read_only }) catch return null;
            return file;
        }

        return null;
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
