const std = @import("std");

pub const Config = struct {};

pub const Mesh = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    positions: [][3]f32,
    normals: [][3]f32,
    uvs: [][2]f32,
    indices: []u32,
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.positions);
        self.allocator.free(self.normals);
        self.allocator.free(self.uvs);
        self.allocator.free(self.indices);
    }
};

const Index = struct {
    position: u32,
    normal: u32,
    uv: u32,
};

pub fn parseObjFile(
    allocator: std.mem.Allocator,
    reader: anytype,
    comptime config: Config,
) !Mesh {
    var buffer: [1024]u8 = undefined;

    var obj_positions = std.ArrayList([3]f32).init(allocator);
    defer obj_positions.deinit();

    var obj_normals = std.ArrayList([3]f32).init(allocator);
    defer obj_normals.deinit();

    var obj_uvs = std.ArrayList([2]f32).init(allocator);
    defer obj_uvs.deinit();

    var obj_indices = std.ArrayList(Index).init(allocator);
    defer obj_indices.deinit();

    //Read mesh data from file
    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line_with_white_space| {
        var line = std.mem.trimLeft(u8, line_with_white_space, " \t");

        //Filter out comments
        if (line[0] != '#') {
            var line_split = std.mem.tokenize(line, " ");
            var op = line_split.next().?;
            //std.log.info("{s}.{}", .{ op, op.len });
            if (std.mem.eql(u8, op, "o")) {
                std.log.info("Object: {s}", .{line_split.next().?});
            } else if (std.mem.eql(u8, op, "v")) {
                var value1 = try std.fmt.parseFloat(f32, line_split.next().?);
                var value2 = try std.fmt.parseFloat(f32, line_split.next().?);
                var value3 = try std.fmt.parseFloat(f32, line_split.next().?);
                try obj_positions.append([3]f32{ value1, value2, value3 });
            } else if (std.mem.eql(u8, op, "vn")) {
                var value1 = try std.fmt.parseFloat(f32, line_split.next().?);
                var value2 = try std.fmt.parseFloat(f32, line_split.next().?);
                var value3 = try std.fmt.parseFloat(f32, line_split.next().?);
                try obj_normals.append([3]f32{ value1, value2, value3 });
            } else if (std.mem.eql(u8, op, "vt")) {
                var value1 = try std.fmt.parseFloat(f32, line_split.next().?);
                var value2 = try std.fmt.parseFloat(f32, line_split.next().?);
                try obj_uvs.append([2]f32{ value1, value2 });
            } else if (std.mem.eql(u8, op, "f")) {
                //TODO: Triangulate Ngons
                var index1 = try parseIndex(line_split.next().?);
                var index2 = try parseIndex(line_split.next().?);
                var index3 = try parseIndex(line_split.next().?);
                try obj_indices.appendSlice(&[_]Index{ index1, index2, index3 });
            } else if (std.mem.eql(u8, op, "s")) {
                //Do nothing
            }
        }
    }

    std.log.info("Positions: {}", .{obj_positions.items.len});
    std.log.info("Normals: {}", .{obj_normals.items.len});
    std.log.info("Uvs: {}", .{obj_uvs.items.len});
    std.log.info("Indices: {}", .{obj_indices.items.len});

    //Reorder to indexed arrays and remove duplicate vertices
    var positions = std.ArrayList([3]f32).init(allocator);
    var normals = std.ArrayList([3]f32).init(allocator);
    var uvs = std.ArrayList([2]f32).init(allocator);
    var indices = try std.ArrayList(u32).initCapacity(allocator, obj_indices.items.len);

    var vertex_to_index_map = std.AutoHashMap(Index, u32).init(allocator);
    defer vertex_to_index_map.deinit();

    var reused_vertices: usize = 0;

    for (obj_indices.items) |index| {
        if (vertex_to_index_map.get(index)) |resuse_index| {
            try indices.append(resuse_index);
            reused_vertices += 1;
        } else {
            var new_index = @intCast(u32, positions.items.len);
            try positions.append(obj_positions.items[index.position - 1]);
            try normals.append(obj_normals.items[index.normal - 1]);
            try uvs.append(obj_uvs.items[index.uv - 1]);
            try vertex_to_index_map.put(index, new_index);
            try indices.append(new_index);
        }
    }

    std.log.info("Reused {} vertices!", .{reused_vertices});

    return Mesh{
        .allocator = allocator,
        .positions = positions.toOwnedSlice(),
        .normals = normals.toOwnedSlice(),
        .uvs = uvs.toOwnedSlice(),
        .indices = indices.toOwnedSlice(),
    };
}

fn parseIndex(index_string: []const u8) !Index {
    var line_split = std.mem.tokenize(index_string, "/");
    var position = try std.fmt.parseInt(u32, line_split.next().?, 10);
    var uv = try std.fmt.parseInt(u32, line_split.next().?, 10);
    var normal = try std.fmt.parseInt(u32, line_split.next().?, 10);
    return Index{
        .position = position,
        .uv = uv,
        .normal = normal,
    };
}
