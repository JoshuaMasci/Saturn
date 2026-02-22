const std = @import("std");

//TODO: swap the following for platform agnostic version
const Backend = @import("vulkan/backend.zig");
const BufferHandle = Backend.BufferHandle;
const TextureHandle = Backend.ImageHandle;
const WindowHandle = @import("../platform/sdl3.zig").Window;

pub const Error = error{
    OutOfMemory,
};

pub const QueuePreference = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

pub const Buffer = struct { idx: u32 };
pub const BufferUsage = struct {
    handle: Buffer,
    access: BufferAccess,
};
pub const BufferSource = union(enum) {
    persistent: BufferHandle,
    transient: usize,
};
pub const TransientBufferDesc = struct {
    size: usize,
    //TODO: rest of desc
};

pub const Texture = struct { idx: u32 };
pub const TextureUsage = struct {
    handle: Texture,
    access: TextureAccess,
};
pub const TextureSource = union(enum) {
    persistent: TextureHandle,
    transient: usize,
    window: usize,
};
pub const TransientTextureDesc = struct {
    extent: TextureExtent,
    //TODO: rest of desc
};
pub const WindowTextureDesc = struct {
    handle: WindowHandle,
};
pub const TextureExtent = union(enum) {
    fixed: [2]u32,
    relative: Texture,
};

// pub const BufferReadAccess = packed struct(u32) {
//     vertex: bool = false,
//     index: bool = false,
//     uniform: bool = false,
//     storage: bool = false,
//     indirect: bool = false,
//     transfer_src: bool = false,

//     _padding: u26 = 0,

//     pub fn merge(self: BufferReadAccess, other: BufferReadAccess) BufferReadAccess {
//         return @bitCast(@as(u32, @bitCast(self)) | @as(u32, @bitCast(other)));
//     }
// };

// pub const BufferWriteAccess = enum(u32) {
//     storage,
//     transfer_dst,
// };

// pub const BufferAccess = union(enum) {
//     read: BufferReadAccess,
//     write: BufferWriteAccess,

//     pub fn isWrite(self: BufferAccess) bool {
//         switch (self) {
//             .write => true,
//             .read => false,
//         }
//     }
// };

pub const BufferAccess = packed struct(u32) {
    vertex_read: bool = false,
    index_read: bool = false,
    indirect_read: bool = false,

    compute_uniform_read: bool = false,
    vertex_uniform_read: bool = false,
    fragment_uniform_read: bool = false,

    compute_storage_read: bool = false,
    vertex_storage_read: bool = false,
    fragment_storage_read: bool = false,

    compute_storage_write: bool = false,
    vertex_storage_write: bool = false,
    fragment_storage_write: bool = false,

    transfer_read: bool = false,
    transfer_write: bool = false,

    _padding: u18 = 0,
};

// pub const TextureReadAccess = packed struct(u32) {
//     sampled: bool = false,
//     storage: bool = false,
//     attachment: bool = false,
//     transfer_src: bool = false,

//     _padding: u28 = 0,

//     pub fn merge(self: TextureReadAccess, other: TextureReadAccess) TextureReadAccess {
//         return @bitCast(@as(u32, @bitCast(self)) | @as(u32, @bitCast(other)));
//     }
// };

// pub const TextureWriteAccess = enum(u32) {
//     storage,
//     attachment,
//     transfer_dst,
// };

// pub const TextureAccess = union(enum) {
//     read: TextureReadAccess,
//     write: TextureWriteAccess,

//     pub fn isWrite(self: BufferAccess) bool {
//         switch (self) {
//             .write => true,
//             .read => false,
//         }
//     }
// };

pub const TextureAccess = packed struct(u32) {
    attachment_read: bool = false,
    attachment_write: bool = false,

    compute_sampled_read: bool = false,
    vertex_sampled_read: bool = false,
    fragment_sampled_read: bool = false,

    compute_storage_read: bool = false,
    vertex_storage_read: bool = false,
    fragment_storage_read: bool = false,

    compute_storage_write: bool = false,
    vertex_storage_write: bool = false,
    fragment_storage_write: bool = false,

    transfer_read: bool = false,
    transfer_write: bool = false,

    _padding: u19 = 0,
};

pub const Pass = struct { idx: u32 };
pub const PassDesc = struct {
    handle: Pass,
    name: []const u8,
    queue: QueuePreference = .graphics,

    //TODO: store these as Hashmaps for faster fetch?
    //TODO: impl both and test perf
    buffer_usages: std.ArrayList(BufferUsage) = .empty,
    texture_usages: std.ArrayList(TextureUsage) = .empty,

    pub fn getBufferAccess(self: *const PassDesc, handle: Buffer) ?BufferAccess {
        for (self.buffer_usages.items) |usage| {
            if (usage.handle.idx == handle.idx) {
                return usage.access;
            }
        }
        return null;
    }

    pub fn getTextureAccess(self: *const PassDesc, handle: Texture) ?BufferAccess {
        for (self.texture_usages.items) |usage| {
            if (usage.handle == handle) {
                return usage.access;
            }
        }
        return null;
    }
};

pub const Desc = struct {
    pub const Self = @This();

    gpa: std.mem.Allocator,

    window_textures: std.ArrayList(WindowTextureDesc) = .empty,
    transient_buffers: std.ArrayList(TransientBufferDesc) = .empty,
    transient_textures: std.ArrayList(TransientTextureDesc) = .empty,

    buffers: std.ArrayList(BufferSource) = .empty,
    textures: std.ArrayList(TextureSource) = .empty,

    passes: std.ArrayList(PassDesc) = .empty,

    pub fn init(gpa: std.mem.Allocator) Self {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Self) void {
        for (self.passes.items) |*pass| {
            self.gpa.free(pass.name);
            pass.buffer_usages.deinit(self.gpa);
            pass.texture_usages.deinit(self.gpa);
        }
        self.passes.deinit(self.gpa);
        self.textures.deinit(self.gpa);
        self.buffers.deinit(self.gpa);
        self.transient_textures.deinit(self.gpa);
        self.transient_buffers.deinit(self.gpa);
        self.window_textures.deinit(self.gpa);
    }

    pub fn createPass(self: *Self, name: []const u8, queue: QueuePreference) Error!Pass {
        const handle = Pass{ .idx = @intCast(self.passes.items.len) };
        try self.passes.append(self.gpa, .{
            .handle = handle,
            .name = try self.gpa.dupe(u8, name),
            .queue = queue,
        });
        return handle;
    }

    pub fn addBufferUsage(self: *Self, pass: Pass, buffer: Buffer, access: BufferAccess) Error!void {
        try self.passes.items[pass.idx].buffer_usages.append(self.gpa, .{ .handle = buffer, .access = access });
    }

    pub fn addTextureUsage(self: *Self, pass: Pass, texture: Texture, access: TextureAccess) Error!void {
        try self.passes.items[pass.idx].texture_usages.append(self.gpa, .{ .handle = texture, .access = access });
    }

    pub fn importBuffer(self: *Self, handle: BufferHandle) Error!Buffer {
        try self.buffers.append(self.gpa, .{ .persistent = handle });
        return Buffer{ .idx = @intCast(self.buffers.items.len - 1) };
    }

    pub fn createTransientBuffer(self: *Self, desc: TransientBufferDesc) Error!Buffer {
        try self.transient_buffers.append(self.gpa, desc);
        const transient_idx = self.transient_buffers.items.len - 1;
        try self.buffers.append(self.gpa, .{ .transient = transient_idx });
        return Buffer{ .idx = @intCast(self.buffers.items.len - 1) };
    }

    pub fn importTexture(self: *Self, handle: TextureHandle) Error!Texture {
        try self.textures.append(self.gpa, .{ .persistent = handle });
        return Texture{ .idx = @intCast(self.textures.items.len - 1) };
    }

    pub fn createTransientTexture(self: *Self, desc: TransientTextureDesc) Error!Texture {
        try self.transient_textures.append(self.gpa, desc);
        const transient_idx = self.transient_textures.items.len - 1;
        try self.textures.append(self.gpa, .{ .transient = transient_idx });
        return Texture{ .idx = @intCast(self.textures.items.len - 1) };
    }

    pub fn acquireWindowTexture(self: *Self, window: WindowHandle) Error!Texture {
        try self.window_textures.append(self.gpa, .{ .handle = window });
        const window_idx = self.window_textures.items.len - 1;
        try self.textures.append(self.gpa, .{ .window = window_idx });
        return Texture{ .idx = @intCast(self.textures.items.len - 1) };
    }
};

pub const Compiled = struct {
    pub const CompiledPass = struct {
        handle: Pass,
        first_usages: Dependencies = .empty,

        pass_dependencies: std.ArrayList(struct {
            pass: Pass,
            dependecies: Dependencies,
        }) = .empty,
        last_usages: Dependencies = .empty,
    };

    pub const ResourceInfo = struct {
        access_count: usize = 0,
        first_sorted_access: ?usize = null,
        last_sorted_access: ?usize = null,
    };

    passes: std.ArrayList(CompiledPass) = .empty,
    buffers: std.ArrayList(ResourceInfo) = .empty,
    textures: std.ArrayList(ResourceInfo) = .empty,

    pub fn deinit(self: *Compiled, gpa: std.mem.Allocator) void {
        for (self.passes.items) |*pass| {
            pass.first_usages.deinit(gpa);
            pass.pass_dependencies.deinit(gpa);
            pass.last_usages.deinit(gpa);
        }
        self.passes.deinit(gpa);
        self.buffers.deinit(gpa);
        self.textures.deinit(gpa);
    }

    pub fn compile(tpa: std.mem.Allocator, render_graph: *const Desc) !Compiled {
        const last_buffer_access = try tpa.alloc(?Pass, render_graph.buffers.items.len);
        defer tpa.free(last_buffer_access);
        @memset(last_buffer_access, null);

        const last_texture_access = try tpa.alloc(?Pass, render_graph.textures.items.len);
        defer tpa.free(last_texture_access);
        @memset(last_texture_access, null);

        // Build graph
        var graph: DependencyGraph = .init(tpa);
        defer graph.deinit();

        for (render_graph.passes.items) |pass| {
            try graph.nodes.put(tpa, pass.handle, .{ .pass = pass.handle });

            for (pass.buffer_usages.items) |buffer_access| {
                try graph.addDependency(last_buffer_access[buffer_access.handle.idx], pass.handle, .{ .buffer = buffer_access.handle });
                last_buffer_access[buffer_access.handle.idx] = pass.handle;
            }

            for (pass.texture_usages.items) |texture_access| {
                try graph.addDependency(last_texture_access[texture_access.handle.idx], pass.handle, .{ .texture = texture_access.handle });
                last_texture_access[texture_access.handle.idx] = pass.handle;
            }
        }

        // Optimize Graph
        // TODO: eleminate read -> read barriers

        const reorder_graph: bool = true;

        var pass_execute_order: std.ArrayList(Pass) = try .initCapacity(tpa, render_graph.passes.items.len);
        defer pass_execute_order.deinit(tpa);

        // Topological Sort (kahn's algorithm)
        if (reorder_graph) {
            var node_degrees: std.ArrayList(struct {
                handle: Pass,
                in_degree: u32,
            }) = try .initCapacity(tpa, render_graph.passes.items.len);
            defer node_degrees.deinit(tpa);

            var q: std.ArrayList(Pass) = try .initCapacity(tpa, render_graph.passes.items.len);
            defer q.deinit(tpa);

            for (graph.nodes.values()) |node| {
                node_degrees.appendAssumeCapacity(.{
                    .handle = node.pass,
                    .in_degree = @intCast(node.pass_dependencies.count()),
                });
            }

            for (node_degrees.items) |node| {
                if (node.in_degree == 0) {
                    q.appendAssumeCapacity(node.handle);
                }
            }

            while (q.items.len > 0) {
                const top = q.orderedRemove(0);

                pass_execute_order.appendAssumeCapacity(top);

                for (graph.nodes.values(), node_degrees.items) |node, *node_degree| {
                    if (node_degree.in_degree != 0) {
                        if (node.pass_dependencies.contains(top)) {
                            node_degree.in_degree -= 1;

                            if (node_degree.in_degree == 0) {
                                q.appendAssumeCapacity(node.pass);
                            }
                        }
                    }
                }
            }
        } else {
            for (graph.nodes.values()) |node| {
                pass_execute_order.appendAssumeCapacity(node.pass);
            }
        }

        var result: Compiled = .{};
        errdefer result.deinit(tpa);

        result.buffers = try .initCapacity(tpa, render_graph.buffers.items.len);
        result.buffers.appendNTimesAssumeCapacity(.{}, result.buffers.capacity);

        result.textures = try .initCapacity(tpa, render_graph.textures.items.len);
        result.textures.appendNTimesAssumeCapacity(.{}, result.textures.capacity);

        for (pass_execute_order.items) |pass_handle| {
            if (graph.nodes.getPtr(pass_handle)) |node| {
                var result_pass: CompiledPass = .{ .handle = pass_handle };
                result_pass.first_usages = try node.first_usages.clone(tpa);

                var iter = node.pass_dependencies.iterator();
                while (iter.next()) |entry| {
                    try result_pass.pass_dependencies.append(tpa, .{
                        .pass = entry.key_ptr.*,
                        .dependecies = try entry.value_ptr.clone(tpa),
                    });
                }

                for (last_buffer_access, 0..) |last_pass, i| {
                    if (last_pass != null and last_pass.?.idx == pass_handle.idx) {
                        try result_pass.last_usages.append(tpa, .{ .buffer = .{ .idx = @intCast(i) } });
                    }
                }

                for (last_texture_access, 0..) |last_pass, i| {
                    if (last_pass != null and last_pass.?.idx == pass_handle.idx) {
                        try result_pass.last_usages.append(tpa, .{ .texture = .{ .idx = @intCast(i) } });
                    }
                }

                try result.passes.append(tpa, result_pass);
            }
        }

        return result;
    }
};

pub const Dependency = union(enum) {
    buffer: Buffer,
    texture: Texture,
};

pub const Dependencies = std.ArrayList(Dependency);

pub const Node = struct {
    pass: Pass,
    first_usages: Dependencies = .empty,
    pass_dependencies: std.AutoArrayHashMapUnmanaged(Pass, Dependencies) = .empty,

    pub fn init(pass: Pass) Node {
        return .{
            .pass = pass,
        };
    }

    pub fn deinit(self: *Node, gpa: std.mem.Allocator) void {
        self.first_usages.deinit(gpa);
        for (self.pass_dependencies.values()) |*dependencies| {
            dependencies.deinit(gpa);
        }
        self.pass_dependencies.deinit(gpa);
    }
};

pub const DependencyGraph = struct {
    gpa: std.mem.Allocator,
    nodes: std.AutoArrayHashMapUnmanaged(Pass, Node) = .empty,

    pub fn init(gpa: std.mem.Allocator) DependencyGraph {
        return .{
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        for (self.nodes.values()) |*node| {
            node.deinit(self.gpa);
        }
        self.nodes.deinit(self.gpa);
    }

    pub fn addNode(
        self: *DependencyGraph,
        pass: Pass,
    ) !void {
        try self.nodes.put(self.gpa, pass, .{ .pass = pass });
    }

    pub fn addDependency(self: *DependencyGraph, src_opt: ?Pass, dst: Pass, dependency: Dependency) !void {
        const dst_node = self.nodes.getPtr(dst).?;

        if (src_opt) |src| {
            if (!dst_node.pass_dependencies.contains(src)) {
                try dst_node.pass_dependencies.put(self.gpa, src, .empty);
            }
            const src_dependencies = dst_node.pass_dependencies.getPtr(src).?;
            try src_dependencies.append(self.gpa, dependency);
        } else {
            try dst_node.first_usages.append(self.gpa, dependency);
        }
    }
};
