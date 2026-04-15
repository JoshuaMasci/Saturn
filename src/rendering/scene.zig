const std = @import("std");

const zm = @import("zmath");

const Transform = @import("../transform.zig");
const AssetPool = @import("asset_pool.zig");
const Material = @import("../asset/material.zig");
const CpuMaterial = @import("material.zig");

const TransferQueue = @import("transfer_queue.zig");
const GpuPool = @import("gpu_pool.zig").GpuPool;
const SlotMap = @import("../containers.zig").SlotMap;

pub const StaticMeshInstanceMap = SlotMap(StaticMeshInstance);
pub const StaticMeshInstanceHandle = StaticMeshInstanceMap.Handle;

pub const StaticMeshInstance = struct {
    pub const Primitive = struct {
        material: AssetPool.MaterialAssetHandle,
        alpha_mode: Material.AlphaMode,
        primitive_index: u32,
    };

    visible: bool,
    transform: Transform,
    mesh: AssetPool.MeshAssetHandle,

    instance_index: u32,

    primitives: std.ArrayList(Primitive) = .empty,
};

pub const GpuInstance = extern struct {
    model_matrix: zm.Mat = zm.identity(),
    normal_matrix: zm.Mat = zm.identity(),
    mesh_index: u32 = 0,
    visible: u32 = 0,
    pad0: u32 = 0,
    pad1: u32 = 0,
};

pub const GpuPrimitiveInstance = extern struct {
    visible: u32 = 0,
    instance_index: u32 = 0,
    primitive_index: u32 = 0,
    material_instance_index: u32 = 0,
};

//TODO: create render_buckets based on shader/permunatation settings
pub const PrimitiveInstances = struct {
    opaque_primitives: GpuPool(GpuPrimitiveInstance),
    alpha_mask_primitives: GpuPool(GpuPrimitiveInstance),
    alpha_blend_primitives: GpuPool(GpuPrimitiveInstance),

    pub fn getPool(self: *PrimitiveInstances, alpha_mode: Material.AlphaMode) *GpuPool(GpuPrimitiveInstance) {
        return switch (alpha_mode) {
            .@"opaque" => &self.opaque_primitives,
            .mask => &self.alpha_mask_primitives,
            .blend => &self.alpha_blend_primitives,
        };
    }
};

const Self = @This();

gpa: std.mem.Allocator,

asset_pool: *const AssetPool,

static_mesh_instances: StaticMeshInstanceMap = .empty,

gpu_instances: GpuPool(GpuInstance),
primtive_instances: PrimitiveInstances,

pub fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, asset_pool: *const AssetPool, instance_count: usize) saturn.Error!Self {
    var gpu_instances: GpuPool(GpuInstance) = try .init(
        gpa,
        device,
        "instance_data",
        instance_count,
        .{ .storage = true, .transfer_dst = true, .device_address = true },
        .{},
    );
    errdefer gpu_instances.deinit();

    var opaque_primitives: GpuPool(GpuPrimitiveInstance) = try .init(
        gpa,
        device,
        "opaque_primitives",
        instance_count,
        .{ .storage = true, .transfer_dst = true, .device_address = true },
        .{},
    );
    errdefer opaque_primitives.deinit();

    var alpha_mask_primitives: GpuPool(GpuPrimitiveInstance) = try .init(
        gpa,
        device,
        "alpha_mask_primitives",
        instance_count,
        .{ .storage = true, .transfer_dst = true, .device_address = true },
        .{},
    );
    errdefer alpha_mask_primitives.deinit();

    var alpha_blend_primitives: GpuPool(GpuPrimitiveInstance) = try .init(
        gpa,
        device,
        "alpha_blend_primitives",
        instance_count,
        .{ .storage = true, .transfer_dst = true, .device_address = true },
        .{},
    );
    errdefer alpha_blend_primitives.deinit();

    return Self{
        .gpa = gpa,
        .asset_pool = asset_pool,
        .gpu_instances = gpu_instances,
        .primtive_instances = .{
            .opaque_primitives = opaque_primitives,
            .alpha_mask_primitives = alpha_mask_primitives,
            .alpha_blend_primitives = alpha_blend_primitives,
        },
    };
}

pub fn deinit(self: *Self) void {
    var sm_iter = self.static_mesh_instances.iterator();
    while (sm_iter.nextValue()) |instance| {
        instance.primitives.deinit(self.gpa);
    }
    self.static_mesh_instances.deinit(self.gpa);

    self.gpu_instances.deinit();
    self.primtive_instances.opaque_primitives.deinit();
    self.primtive_instances.alpha_mask_primitives.deinit();
    self.primtive_instances.alpha_blend_primitives.deinit();
}

pub fn addTransfers(self: *Self, transfer_queue: *TransferQueue) !void {
    try self.gpu_instances.addTransfers(transfer_queue);
    try self.primtive_instances.opaque_primitives.addTransfers(transfer_queue);
    try self.primtive_instances.alpha_mask_primitives.addTransfers(transfer_queue);
    try self.primtive_instances.alpha_blend_primitives.addTransfers(transfer_queue);
}

pub fn createStaticMeshInstance(self: *Self, visible: bool, transform: Transform, mesh: AssetPool.MeshAssetHandle, materials: []const AssetPool.MaterialAssetHandle) error{OutOfMemory}!StaticMeshInstanceHandle {
    const mesh_asset = self.asset_pool.mesh_assets.get(mesh).?;
    const cpu_mesh = mesh_asset.cpu.?; //IDK what to do if it isn't loaded yet
    std.debug.assert(cpu_mesh.primitives.len == materials.len);

    const instance_index = try self.gpu_instances.alloc();
    errdefer self.gpu_instances.free(instance_index);

    var static_mesh_instance: StaticMeshInstance = .{
        .visible = visible,
        .transform = transform,
        .mesh = mesh,
        .instance_index = instance_index,
        .primitives = try .initCapacity(self.gpa, materials.len),
    };
    errdefer {
        for (static_mesh_instance.primitives.items) |primitive| {
            self.primtive_instances.getPool(primitive.alpha_mode).free(primitive.primitive_index);
        }
        static_mesh_instance.primitives.deinit(self.gpa);
    }

    for (materials, 0..) |material, i| {
        const material_asset = self.asset_pool.material_assets.get(material).?;
        const cpu_material = material_asset.cpu.?;
        const material_gpu = material_asset.gpu.?;

        const pool = self.primtive_instances.getPool(cpu_material.alpha_mode);

        const primitive_index = try pool.create(.{
            .visible = 1,
            .instance_index = instance_index,
            .material_instance_index = material_gpu,
            .primitive_index = @intCast(i),
        });
        static_mesh_instance.primitives.appendAssumeCapacity(.{
            .material = material,
            .alpha_mode = cpu_material.alpha_mode,
            .primitive_index = primitive_index,
        });
    }

    const handle = try self.static_mesh_instances.insert(self.gpa, static_mesh_instance);

    self.updateStaticMeshGPU(handle);

    return handle;
}

pub fn updateStaticMeshInstance(self: *Self, handle: StaticMeshInstanceHandle, visible: bool, transform: Transform) void {
    if (self.static_mesh_instances.getPtr(handle)) |static_mesh_instance| {
        if ((!static_mesh_instance.transform.eql(&transform)) or (static_mesh_instance.visible != visible)) {
            static_mesh_instance.visible = visible;
            static_mesh_instance.transform = transform;
            self.updateStaticMeshGPU(handle);
        }
    }
}

fn updateStaticMeshGPU(self: *Self, handle: StaticMeshInstanceHandle) void {
    const static_mesh_instance = self.static_mesh_instances.getPtr(handle).?;
    const model_matrix = static_mesh_instance.transform.getModelMatrix();
    const normal_matrix = static_mesh_instance.transform.getNormalMatrix();
    self.gpu_instances.stage(static_mesh_instance.instance_index, .{
        .model_matrix = model_matrix,
        .normal_matrix = normal_matrix,
        .visible = @intFromBool(static_mesh_instance.visible),
        .mesh_index = static_mesh_instance.mesh,
    });
}

//TODO: culling and depth sorting
pub fn createBuckets(self: *const Self, gpa: std.mem.Allocator, asset_pool: *const AssetPool) error{OutOfMemory}!RenderBuckets {
    var render_buckets: RenderBuckets = .{ .gpa = gpa };

    var instance_iter = self.static_mesh_instances.iterator();
    while (instance_iter.nextValue()) |instance| {
        if (!instance.visible) continue;

        //Is the mesh loaded on the gpu
        const gpu_mesh = asset_pool.mesh_pool.map.get(instance.mesh) orelse continue;

        const model_matrix = instance.transform.getModelMatrix();

        for (gpu_mesh.cpu_primitives, instance.primitives.items) |cpu_primitive, scene_primitive| {
            const material_asset = asset_pool.material_assets.get(scene_primitive.material) orelse continue;
            const cpu_mat = material_asset.cpu orelse continue;
            const gpu_mat = material_asset.gpu orelse continue;

            try switch (cpu_mat.alpha_mode) {
                .@"opaque" => render_buckets.opaque_instances,
                .mask => render_buckets.alpha_mask_instances,
                .blend => render_buckets.alpha_blend_instances,
            }.append(gpa, .{
                .culling_sphere = .initWorld(cpu_primitive.sphere_pos_radius, &instance.transform),
                .draw_data = .{
                    .index_count = cpu_primitive.index_count,
                    .instance_count = 1,
                    .first_index = @intCast(gpu_mesh.indices.offset + cpu_primitive.index_offset),
                    .vertex_offset = @intCast(gpu_mesh.vertices.offset + cpu_primitive.vertex_offset),
                    .first_instance = 0,
                },
                .model_matrix = model_matrix,
                .material_index = gpu_mat,
            });
        }
    }

    return render_buckets;
}

const saturn = @import("../root.zig");
const Sphere = @import("culling.zig").Sphere;

pub const InstanceDrawData = struct {
    culling_sphere: Sphere,
    draw_data: saturn.IndirectDrawIndexedCommand,
    model_matrix: zm.Mat, //TODO: replace with an index into a buffer
    material_index: u32,
};

pub const RenderBuckets = struct {
    gpa: std.mem.Allocator,
    opaque_instances: std.ArrayList(InstanceDrawData) = .empty,
    alpha_mask_instances: std.ArrayList(InstanceDrawData) = .empty,
    alpha_blend_instances: std.ArrayList(InstanceDrawData) = .empty,

    pub fn depthSort(self: *RenderBuckets, camera_pos: zm.Vec) void {
        std.mem.sort(InstanceDrawData, self.alpha_blend_instances.items, camera_pos, compareInstances);
        std.mem.sort(InstanceDrawData, self.alpha_mask_instances.items, camera_pos, compareInstances);
    }

    pub fn deinit(self: RenderBuckets) void {
        self.opaque_instances.deinit(self.gpa);
        self.alpha_mask_instances.deinit(self.gpa);
        self.alpha_mask_instances.deinit(self.gpa);
    }
};

fn compareInstances(camera_pos: zm.Vec, a: InstanceDrawData, b: InstanceDrawData) bool {
    const a_dis = zm.length3(camera_pos - a.model_matrix[3]);
    const b_dis = zm.length3(camera_pos - b.model_matrix[3]);
    return a_dis[0] > b_dis[0];
}
