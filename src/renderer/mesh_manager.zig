usingnamespace @import("../core.zig");
const Device = @import("../vulkan/device.zig").Device;
const Mesh = @import("mesh.zig").Mesh;
const TransferQueue = @import("../transfer_queue.zig").TransferQueue;
const obj = @import("../utils/obj_loader.zig");

//TODO: Replace
const ColorVertex = struct {
    pos: Vector3,
    color: Vector3,
};

pub const MeshManager = struct {
    const Self = @This();

    allocator: *Allocator,
    device: Device,

    id_next: u16 = 0,
    list: std.AutoHashMap(u16, Mesh),
    transfers: TransferQueue,
    delete_list: std.ArrayList(Mesh),

    pub fn init(allocator: *Allocator, device: Device) Self {
        return Self{
            .allocator = allocator,
            .device = device,
            .list = std.AutoHashMap(u16, Mesh).init(allocator),
            .transfers = TransferQueue.init(allocator, device),
            .delete_list = std.ArrayList(Mesh).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.list.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.list.deinit();
        self.transfers.deinit();

        for (self.delete_list.items) |mesh| {
            mesh.deinit();
        }
        self.delete_list.deinit();
    }

    pub fn flush(self: *Self) void {
        for (self.delete_list.items) |mesh| {
            mesh.deinit();
        }
        self.delete_list.clearRetainingCapacity();
        self.transfers.clearResources();
    }

    pub fn load(self: *Self, file_path: []const u8) !u16 {
        var obj_file = try std.fs.cwd().openFile(file_path, std.fs.File.OpenFlags{ .read = true });
        defer obj_file.close();
        var obj_reader = obj_file.reader();
        var obj_mesh = try obj.parseObjFile(self.allocator, obj_reader, .{});
        defer obj_mesh.deinit();

        var vertices = try self.allocator.alloc(ColorVertex, obj_mesh.positions.len);
        defer self.allocator.free(vertices);

        var i: usize = 0;
        while (i < vertices.len) : (i += 1) {
            vertices[i].pos = .{
                .data = obj_mesh.positions[i],
            };
            var uv = obj_mesh.uvs[i];
            vertices[i].color = Vector3.new(uv[0], uv[1], 0.0);
        }

        var mesh = try Mesh.init(ColorVertex, u32, self.device, @intCast(u32, vertices.len), @intCast(u32, obj_mesh.indices.len));
        self.transfers.copyToBuffer(mesh.vertex_buffer, ColorVertex, vertices);
        self.transfers.copyToBuffer(mesh.index_buffer, u32, obj_mesh.indices);

        var id = self.id_next;
        self.id_next += 1;
        try self.list.put(id, mesh);
        return id;
    }

    pub fn free(self: *Self, id: u16) void {
        if (self.list.fetchRemove(id)) |entry| {
            self.delete_list.append(entry.value);
        }
    }

    pub fn get(self: Self, id: u16) ?Mesh {
        return self.list.get(id);
    }
};
