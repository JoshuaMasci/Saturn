const std = @import("std");

//TODO: don't rely on vulkan definitons
const vk = @import("vulkan");

const Buffer = @import("../vulkan/buffer.zig");
const Image = @import("../vulkan/image.zig");

pub const BufferResourceHandle = u32;
pub const ImageResourceHandle = u32;
pub const RenderPassHandle = u32;

pub const BufferAccess = enum {
    none,
    transfer_read,
    transfer_write,
    shader_read,
    shader_write,
    index_buffer,
    vertex_buffer,
};

pub const BufferResource = struct {
    description: union(enum) {
        new: Buffer.Description,
        imported: struct {
            last_access: BufferAccess,
            buffer: Buffer,
        },
    },
    access_count: u32 = 0,
};

pub const ImageAccess = enum {
    none,
    transfer_read,
    transfer_write,
    shader_sampled_read,
    shader_storage_read,
    shader_storage_write,
    color_attachment_write,
    depth_stencil_attachment_write,

    //TODO: figure out attachment read flags
    //color_attachment_read,
    //depth_stencil_attachment_read,
};

pub const ImageResource = struct {
    description: union(enum) {
        new: Image.Description,
        imported: struct {
            last_access: ImageAccess,
            image: Image,
        },
    },
    access_count: u32 = 0,
};

pub const RenderFunctionData = struct {
    pointer: ?*anyopaque,
    pub fn get(self: @This(), comptime T: type) ?*T {
        return @ptrCast(?*T, @alignCast(@alignOf(T), self.pointer));
    }
};

const RenderFunction = fn (data: *RenderFunctionData) void;

const RenderPass = struct {
    const Self = @This();

    name: std.ArrayList(u8),
    buffer_accesses: std.AutoHashMap(BufferResourceHandle, BufferAccess),
    image_accesses: std.AutoHashMap(ImageResourceHandle, ImageAccess),

    raster_info: ?struct {
        size: [2]u32,
        color_attachments: std.ArrayList(ImageResourceHandle),
        depth_stencil_attachment: ?ImageResourceHandle,
    },

    render_function: ?struct {
        ptr: RenderFunction,
        data: RenderFunctionData,
    },

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        var name_array = std.ArrayList(u8).initCapacity(allocator, name.len) catch {
            std.debug.panic("Failed to allocate name array", .{});
        };
        name_array.appendSlice(name) catch {
            std.debug.panic("Failed to copy pass name", .{});
        };
        return Self{
            .name = name_array,
            .buffer_accesses = std.AutoHashMap(BufferResourceHandle, BufferAccess).init(allocator),
            .image_accesses = std.AutoHashMap(ImageResourceHandle, ImageAccess).init(allocator),
            .raster_info = null,
            .render_function = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.name.deinit();
        self.buffer_accesses.deinit();
        self.image_accesses.deinit();
        if (self.raster_info) |raster_info| {
            raster_info.color_attachments.deinit();
        }
    }
};

pub const RenderGraph = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffers: std.ArrayList(BufferResource),
    images: std.ArrayList(ImageResource),
    passes: std.ArrayList(RenderPass),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffers = std.ArrayList(BufferResource).init(allocator),
            .images = std.ArrayList(ImageResource).init(allocator),
            .passes = std.ArrayList(RenderPass).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffers.deinit();
        self.images.deinit();
        for (self.passes.items) |*pass| {
            pass.deinit();
        }
        self.passes.deinit();
    }

    pub fn createBuffer(self: *Self, buffer_description: Buffer.Description) BufferResourceHandle {
        var handle = @intCast(BufferResourceHandle, self.buffers.items.len);
        self.buffers.append(.{
            .description = .{ .new = buffer_description },
        }) catch {
            std.debug.panic("Failed to append new buffer resource", .{});
        };
        return handle;
    }

    pub fn importBuffer(self: *Self, buffer: Buffer, last_access: BufferAccess) BufferResourceHandle {
        var handle = @intCast(BufferResourceHandle, self.buffers.items.len);
        self.buffers.append(.{
            .description = .{ .imported = .{
                .last_access = last_access,
                .buffer = buffer,
            } },
        }) catch {
            std.debug.panic("Failed to append imported buffer resource", .{});
        };
        return handle;
    }

    pub fn createImage(self: *Self, image_description: Image.Description) ImageResourceHandle {
        var handle = @intCast(ImageResourceHandle, self.images.items.len);
        self.images.append(.{
            .description = .{ .new = image_description },
        }) catch {
            std.debug.panic("Failed to append new image resource", .{});
        };
        return handle;
    }

    pub fn importImage(self: *Self, image: Image, last_access: ImageAccess) ImageResourceHandle {
        var handle = @intCast(ImageResourceHandle, self.images.items.len);
        self.images.append(.{
            .description = .{ .imported = .{
                .last_access = last_access,
                .image = image,
            } },
        }) catch {
            std.debug.panic("Failed to append imported image resource", .{});
        };
        return handle;
    }

    pub fn createRenderPass(self: *Self, name: []const u8) RenderPassHandle {
        var handle = @intCast(RenderPassHandle, self.passes.items.len);
        self.passes.append(RenderPass.init(self.allocator, name)) catch {
            std.debug.panic("Failed to append new render pass", .{});
        };
        return handle;
    }

    pub fn addBufferAccess(self: *Self, render_pass: RenderPassHandle, buffer: BufferResourceHandle, access_type: BufferAccess) void {
        if (self.passes.items.len <= render_pass) {
            std.debug.panic("Tried to write to invalid RenderPass id: {}", .{render_pass});
        }

        if (self.passes.items.len <= buffer) {
            std.debug.panic("Tried to use an invalid BufferResource id: {}", .{buffer});
        }

        self.buffers.items[buffer].access_count += 1;
        self.passes.items[render_pass].buffer_accesses.put(buffer, access_type) catch {
            std.debug.panic("Failed to append new buffer access", .{});
        };
    }

    pub fn addImageAccess(self: *Self, render_pass: RenderPassHandle, image: ImageResourceHandle, access_type: ImageAccess) void {
        if (self.passes.items.len <= render_pass) {
            std.debug.panic("Tried to write to invalid RenderPass id: {}", .{render_pass});
        }

        if (self.passes.items.len <= image) {
            std.debug.panic("Tried to use an invalid ImageResource id: {}", .{image});
        }

        self.images.items[image].access_count += 1;
        self.passes.items[render_pass].image_accesses.put(image, access_type) catch {
            std.debug.panic("Failed to append new image access", .{});
        };
    }

    pub fn addRaster(self: *Self, render_pass: RenderPassHandle, color_attachments: []const ImageResourceHandle, depth_stencil_attachment: ?ImageResourceHandle) void {
        if (self.passes.items.len <= render_pass) {
            std.debug.panic("Tried to write to invalid RenderPass id: {}", .{render_pass});
        }

        if (self.passes.items[render_pass].raster_info) |_| {
            std.debug.panic("RenderPass id: {} already has a RasterInfo", .{render_pass});
        }

        var framebuffer_size: ?[2]u32 = null;

        for (color_attachments) |attachment, i| {
            self.addImageAccess(render_pass, attachment, .color_attachment_write);
            framebuffer_size = validateAttachmentSize(framebuffer_size, getImageSize(&self.images.items[attachment])) catch {
                std.debug.panic("Framebuffer color attachment {} in pass {} doesn't match others", .{ i, render_pass });
            };
        }

        if (depth_stencil_attachment) |attachment| {
            self.addImageAccess(render_pass, attachment, .depth_stencil_attachment_write);
            framebuffer_size = validateAttachmentSize(framebuffer_size, getImageSize(&self.images.items[attachment])) catch {
                std.debug.panic("Framebuffer depth stencil attachment in pass {} doesn't match others", .{render_pass});
            };
        }

        var color_attachments_list = std.ArrayList(ImageResourceHandle).initCapacity(self.allocator, color_attachments.len) catch {
            std.debug.panic("Failed to allocate color attachments array", .{});
        };
        color_attachments_list.appendSlice(color_attachments) catch {
            std.debug.panic("Failed to copy color attachments array", .{});
        };

        self.passes.items[render_pass].raster_info = .{
            .size = framebuffer_size.?,
            .color_attachments = color_attachments_list,
            .depth_stencil_attachment = depth_stencil_attachment,
        };
    }

    pub fn addRenderFunction(self: *Self, render_pass: RenderPassHandle, function: RenderFunction, data: ?*anyopaque) void {
        if (self.passes.items.len <= render_pass) {
            std.debug.panic("Tried to write to invalid RenderPass id: {}", .{render_pass});
        }

        if (self.passes.items[render_pass].render_function) |_| {
            std.debug.panic("RenderPass id: {} already has a RenderFunction", .{render_pass});
        }

        self.passes.items[render_pass].render_function = .{
            .ptr = function,
            .data = .{ .pointer = data },
        };
    }
};

fn getImageSize(image_description: *ImageResource) [2]u32 {
    return switch (image_description.description) {
        .new => |description| description.size,
        .imported => |imported_image| imported_image.image.description.size,
    };
}

fn validateAttachmentSize(current_size: ?[2]u32, attachment_size: [2]u32) !?[2]u32 {
    if (current_size) |size| {
        if (size[0] != attachment_size[0] or size[1] != attachment_size[1]) {
            return error.NonMatchingAttachmentSize;
        } else {
            return current_size;
        }
    } else {
        return attachment_size;
    }
}
