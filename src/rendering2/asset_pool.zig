const std = @import("std");

const zm = @import("zmath");

const saturn = @import("../root.zig");
const SlotMap = @import("../containers.zig").SlotMap;

const AssetRegistry = @import("../asset/registry.zig");
const CpuMesh = @import("../asset/mesh.zig");
const CpuTexture = @import("../asset/texture.zig");
const CpuMaterial = @import("material.zig"); //Converts from Raw AssetHandle to TextureAssetHandle

const MeshPool = @import("mesh_pool.zig");
const TexturePool = @import("texture_pool.zig");

const TransferQueue = @import("transfer_queue.zig");

pub const MeshAsset = struct {
    asset_handle: ?AssetRegistry.Handle,
    cpu: ?CpuMesh = null,
    gpu: ?MeshPool.MeshEntry = null,
};
pub const MeshAssetMap = SlotMap(MeshAsset);
pub const MeshAssetHandle = MeshAssetMap.Handle;

pub const TextureAsset = struct {
    asset_handle: ?AssetRegistry.Handle,
    cpu: ?CpuTexture = null,
    gpu: ?TexturePool.TextureEntry = null,
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
mesh_pool: MeshPool,
mesh_gpu_load_list: std.ArrayList(MeshAssetHandle) = .empty,

texture_handles: std.AutoHashMap(AssetRegistry.Handle, TextureAssetHandle),
texture_assets: SlotMap(TextureAsset),
texture_pool: TexturePool,
texture_gpu_load_list: std.ArrayList(TextureAssetHandle) = .empty,
default_sampler: saturn.SamplerHandle,

material_handles: std.AutoHashMap(AssetRegistry.Handle, MaterialAssetHandle),
material_assets: SlotMap(MaterialAsset),

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    gpu_device: saturn.DeviceInterface,
) !Self {
    const BytesPerGibibyte: usize = 1024 * 1024 * 1024;
    const GeometryAllocationSize = BytesPerGibibyte * 1;
    const MaxMeshCount = 4096;
    const MaxTextureCount = 2048;

    const default_sampler = try gpu_device.createSampler(.{
        .name = "default_linear_sampler",
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
    });
    errdefer gpu_device.destroySampler(default_sampler);

    return .{
        .allocator = allocator,
        .registry = registry,
        .gpu_device = gpu_device,

        .mesh_handles = .init(allocator),
        .mesh_assets = .init(allocator),
        .mesh_pool = try .init(gpu_device, .fromTotalBytes(GeometryAllocationSize), MaxMeshCount),

        .texture_handles = .init(allocator),
        .texture_assets = .init(allocator),
        .texture_pool = try .init(gpu_device, MaxTextureCount),
        .default_sampler = default_sampler,

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
    self.mesh_pool.deinit();
    self.mesh_gpu_load_list.deinit(self.allocator);
    self.texture_gpu_load_list.deinit(self.allocator);

    var texture_iter = self.texture_assets.iterator();
    while (texture_iter.nextValue()) |asset| {
        if (asset.cpu) |cpu| {
            cpu.deinit(self.allocator);
        }

        if (asset.gpu) |gpu| {
            self.texture_pool.destroyTexture(gpu);
        }
    }
    self.texture_handles.deinit();
    self.texture_assets.deinit();
    self.texture_pool.deinit();
    self.gpu_device.destroySampler(self.default_sampler);

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

    try self.mesh_gpu_load_list.append(self.allocator, mesh_asset_handle);

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
        if (asset.cpu != null) continue;

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
        if (asset.cpu != null) continue;

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
            if (asset.cpu != null) continue;

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

pub fn loadAllGpu(self: *Self) void {
    var mesh_iter = self.mesh_assets.iterator();
    while (mesh_iter.next()) |entry| {
        if (entry.value_ptr.gpu == null) {
            if (entry.value_ptr.cpu) |cpu_mesh| {
                if (entry.handle.index >= self.mesh_pool.max_mesh_count) {
                    std.log.err("Mesh handle index ({}) exceeds maximum mesh count ({})", .{ entry.handle.index, self.mesh_pool.max_mesh_count });
                    continue;
                }
                entry.value_ptr.gpu = self.mesh_pool.addMesh(&cpu_mesh) catch @panic("");
                self.mesh_gpu_load_list.append(self.allocator, entry.handle) catch @panic("");
            }
        }
    }

    // Load textures to GPU
    var texture_iter = self.texture_assets.iterator();
    while (texture_iter.next()) |entry| {
        if (entry.value_ptr.gpu == null) {
            if (entry.value_ptr.cpu) |cpu_texture| {
                if (entry.handle.index >= self.texture_pool.max_texture_count) {
                    std.log.err("Texture handle index ({}) exceeds maximum texture count ({})", .{ entry.handle.index, self.texture_pool.max_texture_count });
                    continue;
                }

                entry.value_ptr.gpu = self.texture_pool.createTexture(&cpu_texture, self.default_sampler) catch |err| {
                    std.log.err("Failed to create texture {s} {}", .{ cpu_texture.name, err });
                    continue;
                };

                self.texture_gpu_load_list.append(self.allocator, entry.handle) catch continue;
            } else {
                std.log.debug("Texture {} has no CPU data, skipping GPU upload", .{entry.value_ptr.asset_handle.?});
            }
        }
    }
}

pub fn addTransfers(self: *Self, transfer_queue: *TransferQueue) !void {
    if (self.mesh_gpu_load_list.items.len != 0) {
        const MAX_MESH_UPLOADS = 100;

        const upload_count: usize = @min(self.mesh_gpu_load_list.items.len, MAX_MESH_UPLOADS);
        const start = self.mesh_gpu_load_list.items.len - upload_count;
        const end = start + upload_count;

        //std.log.info("Mesh Upload Total({}) Start({}) End({})", .{ self.mesh_gpu_load_list.items.len, start, end });

        for (self.mesh_gpu_load_list.items[start..end]) |handle| {
            if (self.mesh_assets.getPtr(handle)) |asset| {
                const cpu_asset = asset.cpu.?;
                const gpu_asset = asset.gpu.?;
                try self.mesh_pool.uploadMeshData(transfer_queue, handle.index, &cpu_asset, gpu_asset);
            }
        }
        self.mesh_gpu_load_list.shrinkRetainingCapacity(start);
    }

    if (self.texture_gpu_load_list.items.len != 0) {
        const MAX_TEXTURE_UPLOADS = 100;

        const upload_count: usize = @min(self.texture_gpu_load_list.items.len, MAX_TEXTURE_UPLOADS);
        const start = self.texture_gpu_load_list.items.len - upload_count;
        const end = start + upload_count;

        //std.log.info("Texture Upload Total({}) Start({}) End({})", .{ self.texture_gpu_load_list.items.len, start, end });

        for (self.texture_gpu_load_list.items[start..end]) |handle| {
            if (self.texture_assets.getPtr(handle)) |asset| {
                const cpu_asset = asset.cpu.?;
                const gpu_asset = asset.gpu.?;
                try self.texture_pool.uploadTextureData(transfer_queue, handle.index, &cpu_asset, gpu_asset);
            }
        }
        self.texture_gpu_load_list.shrinkRetainingCapacity(start);
    }
}
