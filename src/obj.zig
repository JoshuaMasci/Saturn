const std = @import("std");
const zobj = @import("zobj");

pub const ObjMesh = struct {
    positions: std.ArrayList([3]f32),
    normals: std.ArrayList([3]f32),
    uv0s: std.ArrayList([2]f32),
    indices: std.ArrayList(u32),

    pub fn deinit(self: *@This()) void {
        self.positions.deinit();
        self.normals.deinit();
        self.uv0s.deinit();
        self.indices.deinit();
    }
};

pub fn load_obj_file(allocator: std.mem.Allocator, file_path: []const u8) !ObjMesh {
    const file_buffer = try std.fs.cwd().readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    defer allocator.free(file_buffer);

    var model = try zobj.parseObj(allocator, file_buffer);
    defer model.deinit(allocator);

    var mesh = ObjMesh{
        .positions = std.ArrayList([3]f32).init(allocator),
        .normals = std.ArrayList([3]f32).init(allocator),
        .uv0s = std.ArrayList([2]f32).init(allocator),
        .indices = std.ArrayList(u32).init(allocator),
    };

    for (model.meshes) |obj_mesh| {
        for (obj_mesh.indices) |index| {
            const pos = try extract3f(model.vertices, index.vertex.?);
            try mesh.positions.append(pos);

            const norm = try extract3f(model.normals, index.normal.?);
            try mesh.normals.append(norm);

            const uv = try extract2f(model.tex_coords, index.tex_coord.?);
            try mesh.uv0s.append(uv);
            try mesh.indices.append(@intCast(mesh.positions.items.len - 1));
        }
    }

    return mesh;
}

fn extract3f(data: []const f32, idx: u32) ![3]f32 {
    const base = @as(usize, @intCast(idx)) * 3;
    if (base + 2 >= data.len) {
        return error.IndexOutOfBounds;
    }
    return [3]f32{ data[base], data[base + 1], data[base + 2] };
}

fn extract2f(data: []const f32, idx: u32) ![2]f32 {
    const base = @as(usize, @intCast(idx)) * 2;
    if (base + 1 >= data.len) {
        return error.IndexOutOfBounds;
    }
    return [2]f32{ data[base], data[base + 1] };
}
