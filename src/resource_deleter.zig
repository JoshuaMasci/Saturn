const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

pub fn ResourceDeleter(comptime T: type) type {
    return struct {
        const Self = @This();

        resource_frames: std.ArrayList(std.ArrayList(T)),

        pub fn init(
            allocator: *Allocator,
            frames_in_flight: u32,
        ) !Self {
            var resource_frames = try std.ArrayList(std.ArrayList(T)).initCapacity(allocator, frames_in_flight);
            var i: u32 = 0;
            while (i < frames_in_flight) : (i += 1) {
                resource_frames.appendAssumeCapacity(std.ArrayList(T).init(allocator));
            }
            return Self{
                .resource_frames = resource_frames,
            };
        }

        pub fn deinit(self: *Self) void {
            var i: u32 = 0;
            while (i < self.resource_frames.items.len) : (i += 1) {
                self.flush(i);
                self.resource_frames.items[i].deinit();
            }
            self.resource_frames.deinit();
        }

        pub fn flush(self: *Self, frame_index: u32) void {
            for (self.resource_frames.items[frame_index].items) |*resource| {
                resource.deinit();
            }
            self.resource_frames.items[frame_index].clearRetainingCapacity();
        }

        pub fn append(self: *Self, frame_index: u32, resource: T) void {
            self.resource_frames.items[frame_index].append(resource) catch panic("Failed to append resource to delete list!", .{});
        }
    };
}
