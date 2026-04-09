const std = @import("std");

const zm = @import("zmath");

const Transform = @import("../transform.zig");
const AssetPool = @import("asset_pool.zig");

const InstanceMap = @import("../containers.zig").SlotMap(Instance);
pub const InstanceHandle = InstanceMap.Handle;

pub const Instance = struct {
    pub const Primitive = struct {
        material: AssetPool.MaterialAssetHandle,
    };

    visable: bool,
    transform: Transform,
    mesh: AssetPool.MeshAssetHandle,
    primitives: []Primitive,
};

const Self = @This();

gpa: std.mem.Allocator,
instances: InstanceMap,

pub fn init(gpa: std.mem.Allocator) Self {
    return Self{
        .gpa = gpa,
        .instances = .init(gpa),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.instances.iterator();
    while (iter.nextValue()) |instance| {
        self.gpa.free(instance.primitives);
    }

    self.instances.deinit();
}

pub fn addInstance(self: *Self, visable: bool, transform: Transform, mesh: AssetPool.MeshAssetHandle, materials: []const AssetPool.MaterialAssetHandle) error{OutOfMemory}!InstanceHandle {
    const primitives: []Instance.Primitive = try self.gpa.alloc(Instance.Primitive, materials.len);
    errdefer self.gpa.free(primitives);

    for (primitives, materials) |*primitive, material| {
        primitive.material = material;
    }

    return try self.instances.insert(Instance{
        .visable = visable,
        .transform = transform,
        .mesh = mesh,
        .primitives = primitives,
    });
}

pub fn updateInstance(self: *Self, handle: InstanceHandle, visable: bool, transform: Transform) void {
    if (self.instances.getPtr(handle)) |instance| {
        instance.visable = visable;
        instance.transform = transform;
    }
}

pub fn removeInstance(self: *Self, handle: InstanceHandle) void {
    if (self.instances.remove(handle)) |instance| {
        self.gpa.free(instance.primitives);
    }
}

//TODO: culling and depth sorting
pub fn createBuckets(self: *const Self, gpa: std.mem.Allocator, asset_pool: *const AssetPool) error{OutOfMemory}!RenderBuckets {
    var render_buckets: RenderBuckets = .{ .gpa = gpa };

    var instance_iter = self.instances.iterator();
    while (instance_iter.nextValue()) |instance| {
        if (!instance.visable) continue;

        //Is the mesh loaded on the gpu
        const gpu_mesh = asset_pool.mesh_pool.map.get(instance.mesh) orelse continue;

        const model_matrix = instance.transform.getModelMatrix();

        for (gpu_mesh.cpu_primitives, instance.primitives) |cpu_primitive, scene_primitive| {
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
