const std = @import("std");

var input_dir: std.fs.Dir = undefined;
var output_dir: std.fs.Dir = undefined;

pub fn main() !void {
    const base_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    const arena_allocator = arena.allocator();

    var args = std.process.args();
    _ = args.next() orelse std.debug.panic("Failed to read process name, honestly IDK how this happens", .{});
    const input_path = args.next() orelse std.debug.panic("Failed to read input path", .{});
    const output_path = args.next() orelse std.debug.panic("Failed to read output path", .{});

    std.log.info("Input Dir: {s}", .{input_path});
    std.log.info("Output Dir: {s}", .{output_path});

    try std.fs.cwd().makePath(output_path);

    input_dir = try std.fs.cwd().openDir(input_path, .{ .iterate = true });
    defer input_dir.close();

    output_dir = try std.fs.cwd().openDir(output_path, .{});
    defer output_dir.close();

    var walker = try input_dir.walk(base_allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        _ = arena.reset(.retain_capacity); // I don't care if it failes for some reason, we'll just waste some memory as a treat
        if (entry.kind == .file) {
            const file_ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, file_ext, ".obj")) {
                if (processObj(arena_allocator, entry.path)) {
                    std.log.info("Processed Obj Mesh {s}", .{entry.path});
                } else |err| {
                    std.log.err("Failed to processed Obj Mesh {s} -> {}", .{ entry.path, err });
                }
            } else if (std.mem.eql(u8, file_ext, ".png")) {
                if (processStb(arena_allocator, entry.path)) {
                    std.log.info("Processed Texture {s}", .{entry.path});
                } else |err| {
                    std.log.err("Failed to processed Texture {s} -> {}", .{ entry.path, err });
                }
            } else if (std.mem.eql(u8, file_ext, ".mat")) {
                if (processMaterial(arena_allocator, entry.path)) {
                    std.log.info("Processed Material {s}", .{entry.path});
                } else |err| {
                    std.log.err("Failed to processed Material {s} -> {}", .{ entry.path, err });
                }
            }
        }
    }
}

pub fn replaceExt(allocator: std.mem.Allocator, path: []const u8, new_ext: []const u8) ![]const u8 {
    const current_ext = std.fs.path.extension(path);
    if (current_ext.len == 0) {
        unreachable;
    } else {
        const base_path_len = path.len - current_ext.len;
        const new_len = base_path_len + new_ext.len;
        var new_path = try allocator.alloc(u8, new_len);
        std.mem.copyForwards(u8, new_path, path[0..base_path_len]);
        std.mem.copyForwards(u8, new_path[base_path_len..], new_ext);
        return new_path;
    }
}

pub fn makePath(dir: std.fs.Dir, file_path: []const u8) void {
    if (std.fs.path.dirname(file_path)) |dir_path| {
        dir.makePath(dir_path) catch return;
    }
}

pub fn processObj(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const obj = @import("asset/obj.zig");
    const processed_mesh = try obj.loadObjMesh(allocator, input_dir, file_path);

    const new_path = try replaceExt(allocator, file_path, ".mesh");
    defer allocator.free(new_path);

    makePath(output_dir, new_path);
    const output_file = try output_dir.createFile(new_path, .{});
    defer output_file.close();

    try processed_mesh.serialize(output_file.writer());
}

pub fn processStb(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const stbi = @import("asset/stbi.zig");
    const texture = try stbi.loadTexture2d(allocator, input_dir, file_path);

    const new_path = try replaceExt(allocator, file_path, ".tex2d");
    defer allocator.free(new_path);

    makePath(output_dir, new_path);
    const output_file = try output_dir.createFile(new_path, .{});
    defer output_file.close();

    try texture.serialize(output_file.writer());
}

pub fn processMaterial(allocator: std.mem.Allocator, file_path: []const u8) !void {
    _ = allocator; // autofix
    makePath(output_dir, file_path);
    const output_file = try output_dir.createFile(file_path, .{});
    defer output_file.close();
    try output_file.writeAll(&.{ 1, 2, 3, 4, 5, 6, 7, 8 }); //TODO: write actual data
}
