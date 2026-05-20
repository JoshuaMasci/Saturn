//Wrapper around thread pool that manages error collection and std.Progress

const std = @import("std");

pub fn Task(comptime T: type, comptime run: anytype) type {
    return struct {
        fn runTask(pool: *Self, name: []const u8, data: *anyopaque, prog_node: ?std.Progress.Node) void {
            const child_node: ?std.Progress.Node = if (prog_node) |node| node.start(name, 0) else null;
            defer if (child_node) |node| node.end();

            const ReturnType = @typeInfo(@TypeOf(run)).@"fn".return_type orelse void;
            const can_error = switch (@typeInfo(ReturnType)) {
                .error_union => true,
                else => false,
            };

            const t_data: *T = @ptrCast(@alignCast(data));

            if (can_error) {
                run(pool, name, t_data, child_node) catch |err| {
                    pool.err_mutex.lock();
                    defer pool.err_mutex.unlock();

                    const task_name = pool.gpa.dupe(u8, name) catch return;
                    pool.err_list.append(pool.gpa, .{
                        .name = task_name,
                        .err = err,
                    }) catch return;
                };
            } else {
                run(pool, name, t_data, child_node);
            }
        }
    };
}

pub const InitOptions = struct {
    n_jobs: ?usize = null,
};

pub fn TaskContext(comptime T: type) type {
    return struct {
        name: []const u8,
        data: T,

        pool: *Self,
        progress_node: ?std.Progress.Node,
    };
}

const ErrorEntry = struct {
    name: []const u8,
    err: anyerror,
};

const ErrorList = std.ArrayList(ErrorEntry);

const Self = @This();

gpa: std.mem.Allocator,
inner: *std.Thread.Pool,

// Mutex protects the error list, which may be appended from many threads.
err_mutex: std.Thread.Mutex = .{},
err_list: ErrorList = .empty,

pub fn init(gpa: std.mem.Allocator, opts: InitOptions) !Self {
    const pool: *std.Thread.Pool = try gpa.create(std.Thread.Pool);
    errdefer gpa.destroy(pool);

    try pool.init(.{ .allocator = gpa, .n_jobs = opts.n_jobs });

    return .{
        .gpa = gpa,
        .inner = pool,
    };
}

pub fn deinit(self: *Self) void {
    self.inner.deinit();
    self.gpa.destroy(self.inner);
    self.err_list.deinit(self.gpa);
}

pub fn logErrors(self: *Self) void {
    self.err_mutex.lock();
    defer self.err_mutex.unlock();

    for (self.err_list.items) |err| {
        std.log.err("Task {s} errored {}", .{ err.name, err.err });
        self.gpa.free(err.name);
    }

    self.err_list.clearRetainingCapacity();
}

pub fn spawn(
    self: *Self,
    comptime T: type,
    wg: *std.Thread.WaitGroup,
    name: []const u8,
    data: T,
    progress_node: ?std.Progress.Node,
    comptime run: anytype,
) !void {
    const Ctx = TaskContext(T);

    // Allocate the context on the heap so it outlives the caller's frame.
    const ctx = try self.allocator.create(Ctx);
    ctx.* = .{
        .name = try self.allocator.dupe(u8, name),
        .data = data,
        .pool = self,
        .progress_node = progress_node,
    };

    const Runner = struct {
        fn runTask(c: *Ctx) void {
            const child_node: ?std.Progress.Node = if (progress_node) |node| node.start(c.name, 0) else null;
            defer if (child_node) |node| node.end();

            c.progress_node = child_node;

            const ReturnType = @typeInfo(@TypeOf(run)).@"fn".return_type orelse void;
            const can_error = switch (@typeInfo(ReturnType)) {
                .error_union => true,
                else => false,
            };

            if (can_error) {
                run(c.pool, c.name, c.data, c.progress_node) catch |err| {
                    c.pool.err_mutex.lock();
                    defer c.pool.err_mutex.unlock();

                    const task_name = c.pool.gpa.dupe(u8, c.name) catch return;
                    c.pool.err_list.append(c.pool.gpa, .{
                        .name = task_name,
                        .err = err,
                    }) catch return;
                };
            } else {
                run(c.pool, c.name, c.data, c.progress_node);
            }

            ctx.pool.gpa.free(c.name);
            ctx.pool.gpa.destroy(c);
        }
    };

    self.inner.spawnWg(wg, Runner.runTask, .{ctx});
}
