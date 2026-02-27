const std = @import("std");

const zm = @import("zmath");

const saturn = @import("../root.zig");
const SlotMap = @import("../containers.zig").SlotMap;

const AssetRegistry = @import("../asset/registry.zig");
const CpuMesh = @import("../asset/mesh.zig");
const CpuTexture = @import("../asset/texture.zig");
const CpuMaterial = @import("material.zig"); //Converts from Raw AssetHandle to TextureAssetHandle

pub const MeshAsset = struct {
    asset_handle: ?AssetRegistry.Handle,
    cpu: ?CpuMesh = null,
    gpu: ?void = null,
};
pub const MeshAssetMap = SlotMap(MeshAsset);
pub const MeshAssetHandle = MeshAssetMap.Handle;

pub const TextureAsset = struct {
    asset_handle: ?AssetRegistry.Handle,
    cpu: ?CpuTexture = null,
    gpu: ?void = null,
};
pub const TextureAssetMap = SlotMap(TextureAsset);
pub const TextureAssetHandle = TextureAssetMap.Handle;

pub const MaterialAsset = struct {
    asset_handle: ?AssetRegistry.Handle,
    cpu: ?CpuMaterial = null,
    gpu: ?void = null,
};
pub const MaterialAssetMap = SlotMap(MaterialAsset);
pub const MaterialAssetHandle = MaterialAssetMap.Handle;

const Self = @This();

allocator: std.mem.Allocator,
registry: *const AssetRegistry,
gpu_device: saturn.DeviceInterface,

mesh_handles: std.AutoHashMap(AssetRegistry.Handle, MeshAssetHandle),
mesh_assets: SlotMap(MeshAsset),

texture_handles: std.AutoHashMap(AssetRegistry.Handle, TextureAssetHandle),
texture_assets: SlotMap(TextureAsset),

material_handles: std.AutoHashMap(AssetRegistry.Handle, MaterialAssetHandle),
material_assets: SlotMap(MaterialAsset),

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    gpu_device: saturn.DeviceInterface,
) Self {
    return .{
        .allocator = allocator,
        .registry = registry,
        .gpu_device = gpu_device,

        .mesh_handles = .init(allocator),
        .mesh_assets = .init(allocator),

        .texture_handles = .init(allocator),
        .texture_assets = .init(allocator),

        .material_handles = .init(allocator),
        .material_assets = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var mesh_iter = self.mesh_assets.iterator();
    while (mesh_iter.nextValue()) |asset| {
        if (asset.cpu) |cpu| {
            cpu.deinit(self.allocator);
        }

        if (asset.gpu) |gpu| {
            _ = gpu; // autofix
        }
    }
    self.mesh_handles.deinit();
    self.mesh_assets.deinit();

    var texture_iter = self.texture_assets.iterator();
    while (texture_iter.nextValue()) |asset| {
        if (asset.cpu) |cpu| {
            cpu.deinit(self.allocator);
        }

        if (asset.gpu) |gpu| {
            _ = gpu; // autofix
        }
    }
    self.texture_handles.deinit();
    self.texture_assets.deinit();

    var material_iter = self.material_assets.iterator();
    while (material_iter.nextValue()) |asset| {
        if (asset.cpu) |cpu| {
            cpu.deinit(self.allocator);
        }

        if (asset.gpu) |gpu| {
            _ = gpu; // autofix
        }
    }
    self.material_handles.deinit();
    self.material_assets.deinit();
}

pub fn flush(self: *Self) void {
    _ = self; // autofix
    // TOOD: upload cpu and gpu assets
    // TODO: maybe mark all for reload
}

pub fn getMeshAsset(self: *Self, asset_handle: AssetRegistry.Handle) error{OutOfMemory}!MeshAssetHandle {
    if (self.mesh_handles.get(asset_handle)) |mesh_asset_handle| {
        return mesh_asset_handle;
    }

    //TODO: check asset type first

    const mesh_asset: MeshAsset = .{
        .asset_handle = asset_handle,
    };

    const mesh_asset_handle = try self.mesh_assets.insert(mesh_asset);
    errdefer _ = self.mesh_assets.remove(mesh_asset_handle);

    try self.mesh_handles.put(asset_handle, mesh_asset_handle);

    return mesh_asset_handle;
}

pub fn getTextureAsset(self: *Self, asset_handle: AssetRegistry.Handle) error{OutOfMemory}!TextureAssetHandle {
    if (self.texture_handles.get(asset_handle)) |texture_asset_handle| {
        return texture_asset_handle;
    }

    //TODO: check asset type first

    const texture_asset: TextureAsset = .{
        .asset_handle = asset_handle,
    };

    const texture_asset_handle = try self.texture_assets.insert(texture_asset);
    errdefer _ = self.texture_assets.remove(texture_asset_handle);

    try self.texture_handles.put(asset_handle, texture_asset_handle);

    return texture_asset_handle;
}

pub fn getMaterialAsset(self: *Self, asset_handle: AssetRegistry.Handle) error{OutOfMemory}!MaterialAssetHandle {
    if (self.material_handles.get(asset_handle)) |material_asset_handle| {
        return material_asset_handle;
    }

    //TODO: check asset type first

    const material_asset: MaterialAsset = .{
        .asset_handle = asset_handle,
    };

    const material_asset_handle = try self.material_assets.insert(material_asset);
    errdefer _ = self.material_assets.remove(material_asset_handle);

    try self.material_handles.put(asset_handle, material_asset_handle);

    return material_asset_handle;
}

pub fn loadAllCpu(self: *Self) void {
    var mesh_iter = self.mesh_assets.iterator();
    while (mesh_iter.nextValue()) |asset| {
        if (asset.asset_handle) |asset_handle| {
            if (self.registry.loadAsset(
                CpuMesh,
                self.allocator,
                asset_handle,
                .{
                    .load_meshlets = false,
                },
            )) |mesh| {
                asset.cpu = mesh;
            } else |err| {
                std.log.err("Failed to load mesh {} {}", .{ asset_handle, err });
            }
        }
    }

    //Mat first, so it populates textures
    var material_iter = self.material_assets.iterator();
    while (material_iter.nextValue()) |asset| {
        if (asset.asset_handle) |asset_handle| {
            if (CpuMaterial.load(
                self.allocator,
                self,
                asset_handle,
                .{},
            )) |material| {
                asset.cpu = material;
            } else |err| {
                std.log.err("Failed to load material {} {}", .{ asset_handle, err });
            }
        }
    }

    var texture_iter = self.texture_assets.iterator();
    while (texture_iter.nextValue()) |asset| {
        if (asset.asset_handle) |asset_handle| {
            if (self.registry.loadAsset(
                CpuTexture,
                self.allocator,
                asset_handle,
                .{},
            )) |texture| {
                asset.cpu = texture;
            } else |err| {
                std.log.err("Failed to load texture {} {}", .{ asset_handle, err });
            }
        }
    }
}
