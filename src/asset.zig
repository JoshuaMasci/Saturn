const std = @import("std");

const HashType = u32;
const HashMethod = std.hash.Fnv1a_32;

//TODO: pack into u64?
pub const AssetHandle = packed struct {
    type: AssetType,
    source_hash: HashType,
    asset_hash: HashType,
};

pub const MeshAssetHandle = AssetHandle;
pub const TextureAssetHandle = AssetHandle;
pub const MaterialAssetHandle = AssetHandle;

pub const AssetType = enum(u8) {
    invalid = 0,
    mesh,
    texture,
    material,
    prefab,
    scene,
};

pub const AssetInfo = struct {
    handle: AssetHandle,
    name: []u8,
};

pub const AssetSourceType = union(enum) {
    dir: []const u8,
    file: []const u8,
};

const AssetMap = std.AutoHashMap(HashType, AssetInfo);
pub const AssetSource = struct {
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
                const string = try allocator.alloc(u8, entry.path.len);
                @memcpy(string, entry.path);
                const asset_hash = HashMethod.hash(string);
                const asset_handle: AssetHandle = .{ .type = .invalid, .source_hash = source_hash, .asset_hash = asset_hash };
                try map.putNoClobber(asset_hash, .{ .handle = asset_handle, .name = string });
            }
        }

        return .{ .allocator = allocator, .source_hash = source_hash, .map = map };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
        }

        self.map.deinit();
    }
};

const SourceMap = std.AutoHashMap(HashType, AssetSource);
pub const AssetRegistry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    sources: SourceMap,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .sources = SourceMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.sources.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.sources.deinit();
    }

    pub fn addDirectorySource(self: *Self, name: []const u8, dir_path: []const u8) !void {
        const source_hash = HashMethod.hash(name);
        const source = try AssetSource.initFromDir(self.allocator, source_hash, dir_path);
        try self.sources.putNoClobber(source_hash, source);
    }

    pub fn getAssetHandle(self: Self, source_path: []const u8) ?AssetHandle {
        var split = std.mem.split(u8, source_path, ":");
        const source = split.next() orelse return null;
        const path = split.next() orelse return null;

        const source_hash = HashMethod.hash(source);
        const path_hash = HashMethod.hash(path);

        if (self.sources.get(source_hash)) |asset_source| {
            if (asset_source.map.get(path_hash)) |asset| {
                return asset.handle;
            }
        }

        return null;
    }
};

const AssetList = struct {
    const Self = @This();

    mutex: std.Thread.Mutex = .{},
    list: std.ArrayList(*AssetRef),

    pub fn push(self: *Self, ptr: *AssetRef) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.list.append(ptr) catch |err| std.debug.panic("Failed to append to free list: {}", .{err});
    }
};

const ObjectPool = @import("object_pool.zig").ObjectPool;

const AssetState = enum(u8) {
    Unloaded,
    Loading,
    Loaded,
};

const AssetRef = struct {
    const Self = @This();

    handle: AssetHandle,
    state: std.atomic.Value(AssetState),
    ref_count: std.atomic.Value(u16),
    free_list: *AssetList,

    pub fn addRef(self: *Self) *Self {
        self.ref_count.add(1);
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.ref_count.fetchSub(0, .acquire) == 0) {
            self.free_list.push(self);
        }
    }
};

pub const AssetSet = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    asset_map: std.AutoHashMap(AssetHandle, *AssetRef),
    asset_pool: ObjectPool(AssetRef),
    load_list: *AssetList,
    free_list: *AssetList,

    pub fn init(
        allocator: std.mem.Allocator,
    ) !Self {
        var load_list = try allocator.create(AssetList);
        load_list = .{ .list = std.ArrayList(*AssetRef).init(allocator) };
        var free_list = try allocator.create(AssetList);
        free_list = .{ .list = std.ArrayList(*AssetRef).init(allocator) };
        return .{
            .allocator = allocator,
            .asset_map = std.AutoHashMap(AssetHandle, *AssetRef).init(allocator),
            .asset_pool = ObjectPool(AssetRef).init(allocator),
            .load_list = load_list,
            .free_list = free_list,
        };
    }

    pub fn deinit(self: *Self) void {
        self.asset_map.deinit();
        self.asset_pool.deinit();
        self.load_list.list.deinit();
        self.free_list.list.deinit();
        self.allocator.free(self.load_list);
        self.allocator.free(self.free_list);
    }

    pub fn getAsset(self: *Self, asset: AssetHandle) *AssetRef {
        if (self.asset_map.get(asset)) |ref| {
            return ref.addRef();
        }

        const ref = self.asset_pool.new() catch |err| std.debug.panic("Failed to get new AssetRef: {}", .{err});
        ref.* = .{
            .handle = asset,
            .state = .{ .raw = .Loading },
            .ref_count = .{ .raw = 1 },
            .free_list = self.free_list,
        };

        self.asset_map.put(asset, ref) catch |err| std.debug.panic("Failed to append to asset map: {}", .{err});
        self.load_list.push(ref);
        return ref;
    }
};
