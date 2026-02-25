const std = @import("std");
const vk = @import("vulkan");
const saturn = @import("../../root.zig");

const platform = @import("platform.zig");
const Device = platform.Device;
const QueueFamily = platform.QueueFamily;

const Buffer = @import("buffer.zig");
const Texture = @import("texture.zig");
const Swapchain = @import("swapchain.zig");

pub const BufferResource = struct {
    interface: Buffer,
    queue: ?QueueFamily,
    last_access: ?saturn.BufferAccess = null,
};

pub const TextureResource = struct {
    interface: Texture,
    queue: ?QueueFamily,
    last_access: ?saturn.TextureAccess = null,
    layout: vk.ImageLayout,
};

pub const GraphResources = struct {
    buffers: []BufferResource,
    textures: []TextureResource,

    pub fn deinit(self: *const @This(), tpa: std.mem.Allocator) void {
        tpa.free(self.buffers);
        tpa.free(self.textures);
    }
};

const SwapchainTexture = struct {
    swapchain: *Swapchain,
    index: u32,
    interface: Texture,
    wait_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    resource: saturn.RGTextureHandle,
};

pub const RenderGraphExecutor = struct {
    const Self = @This();

    device: *Device,
    tpa: std.mem.Allocator,
    render_graph: *const saturn.RenderGraph,
    compiled: saturn.RenderGraphCompiled,
    frame_data: *Device.PerFrameData,
    resources: GraphResources,
    swapchain_textures: []SwapchainTexture,

    pub fn init(device: *Device, tpa: std.mem.Allocator, render_graph: *const saturn.RenderGraph) !Self {
        var compiled = try saturn.RenderGraphCompiled.compile(tpa, render_graph);
        errdefer compiled.deinit(tpa);

        const frame_data = device.getNextFrameData();

        if (!frame_data.waitForPrevious(device.device.proxy, device.submit_timeout_ns)) {
            std.log.err("Failed to wait for previous frame fences", .{});
        }

        device.device.descriptor.writeUpdates(tpa) catch return error.Unknown;
        frame_data.reset(device.device);

        const swapchain_textures = try acquireSwapchainImages(device, tpa, frame_data, render_graph);
        errdefer tpa.free(swapchain_textures);

        const resources = try fetchResources(device, tpa, frame_data, render_graph, swapchain_textures);
        errdefer resources.deinit(tpa);

        return .{
            .device = device,
            .tpa = tpa,
            .render_graph = render_graph,
            .compiled = compiled,
            .frame_data = frame_data,
            .resources = resources,
            .swapchain_textures = swapchain_textures,
        };
    }

    pub fn deinit(self: *Self) void {
        self.compiled.deinit(self.tpa);
        self.resources.deinit(self.tpa);
        self.tpa.free(self.swapchain_textures);
    }

    pub fn execute(self: *Self) saturn.Error!void {
        self.recordCommandBuffer() catch return error.Unknown;
        self.present() catch return error.Unknown;
        self.writeLastUsages();
    }

    // ------------------------------------------------------------------
    // Acquire
    // ------------------------------------------------------------------

    fn acquireSwapchainImages(
        device: *Device,
        tpa: std.mem.Allocator,
        frame_data: *Device.PerFrameData,
        render_graph: *const saturn.RenderGraph,
    ) ![]SwapchainTexture {
        const swapchain_textures = try tpa.alloc(SwapchainTexture, render_graph.window_textures.items.len);
        errdefer tpa.free(swapchain_textures);

        for (render_graph.window_textures.items, swapchain_textures) |window, *swapchain_texture| {
            const swapchain = device.swapchains.get(window.handle) orelse return error.Unknown;
            const wait_semaphore = frame_data.semaphore_pool.get() catch return error.Unknown;
            const swapchain_index = swapchain.acquireNextImage(null, wait_semaphore, .null_handle) catch |err| {
                if (err == error.OutOfDateKHR) swapchain.out_of_date = true;
                return error.Unknown;
            };

            swapchain_texture.* = .{
                .swapchain = swapchain,
                .index = swapchain_index,
                .interface = swapchain.textures[swapchain_index],
                .wait_semaphore = wait_semaphore,
                .present_semaphore = swapchain.present_semaphores[swapchain_index],
                .resource = window.texture,
            };
        }

        return swapchain_textures;
    }

    // ------------------------------------------------------------------
    // Resource Fetch
    // ------------------------------------------------------------------

    fn getTextureExtentSize(texture_extent: saturn.RGTextureExtent, textures: []const TextureResource) saturn.TextureExtent {
        return switch (texture_extent) {
            .fixed => |extent| .{ .width = extent[0], .height = extent[1], .depth = 1 },
            .relative => |rel_tex| textures[rel_tex.idx].interface.extent,
        };
    }

    fn fetchResources(
        device: *const Device,
        tpa: std.mem.Allocator,
        frame_data: *Device.PerFrameData,
        render_graph: *const saturn.RenderGraph,
        swapchain_textures: []const SwapchainTexture,
    ) !GraphResources {
        const buffers = try tpa.alloc(BufferResource, render_graph.buffers.items.len);
        errdefer tpa.free(buffers);

        const textures = try tpa.alloc(TextureResource, render_graph.textures.items.len);
        errdefer tpa.free(textures);

        for (render_graph.buffers.items, buffers) |graph_buffer, *resource| {
            resource.* = switch (graph_buffer.source) {
                .persistent => |handle| device.getBufferResource(handle).?,
                .transient => |idx| blk: {
                    const desc = render_graph.transient_buffers.items[idx];
                    const buffer = try Buffer.init(device.device, desc.size, desc.usage, desc.memory);
                    try frame_data.transient_buffers.append(device.gpa, buffer);
                    break :blk .{ .interface = buffer, .queue = null, .last_access = null };
                },
            };
        }

        for (render_graph.textures.items, textures, 0..) |graph_texture, *resource, i| {
            resource.* = switch (graph_texture.source) {
                .persistent => |handle| device.getTextureResource(handle).?,
                .transient => |idx| blk: {
                    const desc = render_graph.transient_textures.items[idx];
                    const texture = try Texture.init(
                        device.device,
                        getTextureExtentSize(desc.extent, textures[0..i]),
                        desc.mip_levels,
                        desc.format,
                        desc.usage,
                        desc.memory,
                    );
                    try frame_data.transient_textures.append(device.gpa, texture);
                    break :blk .{ .interface = texture, .queue = null, .last_access = null, .layout = .undefined };
                },
                .window => |idx| .{
                    .interface = swapchain_textures[idx].interface,
                    .queue = null,
                    .last_access = null,
                    .layout = .undefined,
                },
            };
        }

        return .{ .buffers = buffers, .textures = textures };
    }

    // ------------------------------------------------------------------
    // Barriers
    // ------------------------------------------------------------------

    const BufferStateAccess = struct {
        access: vk.AccessFlags2,
        stage: vk.PipelineStageFlags2,
    };

    fn getBufferStateAccess(access: saturn.BufferAccess) BufferStateAccess {
        return switch (access) {
            .none => .{ .access = .{}, .stage = .{} },
            .vertex_read => .{ .access = .{ .vertex_attribute_read_bit = true }, .stage = .{ .vertex_input_bit = true } },
            .index_read => .{ .access = .{ .index_read_bit = true }, .stage = .{ .index_input_bit = true } },
            .indirect_read => .{ .access = .{ .indirect_command_read_bit = true }, .stage = .{ .draw_indirect_bit = true } },
            .compute_uniform_read => .{ .access = .{ .uniform_read_bit = true }, .stage = .{ .compute_shader_bit = true } },
            .graphics_uniform_read => .{ .access = .{ .uniform_read_bit = true }, .stage = .{ .all_graphics_bit = true } },
            .compute_storage_read => .{ .access = .{ .shader_storage_read_bit = true }, .stage = .{ .compute_shader_bit = true } },
            .graphics_storage_read => .{ .access = .{ .shader_storage_read_bit = true }, .stage = .{ .all_graphics_bit = true } },
            .compute_storage_write => .{ .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true }, .stage = .{ .compute_shader_bit = true } },
            .graphics_storage_write => .{ .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true }, .stage = .{ .all_graphics_bit = true } },
            .transfer_read => .{ .access = .{ .transfer_read_bit = true }, .stage = .{ .all_transfer_bit = true } },
            .transfer_write => .{ .access = .{ .transfer_write_bit = true }, .stage = .{ .all_transfer_bit = true } },
        };
    }

    fn buildBufferBarrier(handle: vk.Buffer, src_access: saturn.BufferAccess, dst_access: saturn.BufferAccess) vk.BufferMemoryBarrier2 {
        const src = getBufferStateAccess(src_access);
        const dst = getBufferStateAccess(dst_access);
        return .{
            .buffer = handle,
            .offset = 0,
            .size = vk.WHOLE_SIZE,
            .src_access_mask = src.access,
            .src_stage_mask = src.stage,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_access_mask = dst.access,
            .dst_stage_mask = dst.stage,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        };
    }

    const TextureStateAccess = struct {
        access: vk.AccessFlags2,
        stage: vk.PipelineStageFlags2,
        layout: vk.ImageLayout,
    };

    fn getTextureStateAccess(access: saturn.TextureAccess, is_color: bool, unified_image_layouts: bool) TextureStateAccess {
        var result: TextureStateAccess = switch (access) {
            .none => .{ .access = .{}, .stage = .{}, .layout = .undefined },
            .attachment_read => if (is_color) .{
                .access = .{ .color_attachment_read_bit = true },
                .stage = .{ .color_attachment_output_bit = true, .fragment_shader_bit = true },
                .layout = .attachment_optimal,
            } else .{
                .access = .{ .depth_stencil_attachment_read_bit = true },
                .stage = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
                .layout = .attachment_optimal,
            },
            .attachment_write => if (is_color) .{
                .access = .{ .color_attachment_write_bit = true },
                .stage = .{ .color_attachment_output_bit = true },
                .layout = .attachment_optimal,
            } else .{
                .access = .{ .depth_stencil_attachment_write_bit = true },
                .stage = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
                .layout = .attachment_optimal,
            },
            .compute_sampled_read => .{ .access = .{ .shader_sampled_read_bit = true }, .stage = .{ .compute_shader_bit = true }, .layout = .shader_read_only_optimal },
            .graphics_sampled_read => .{ .access = .{ .shader_sampled_read_bit = true }, .stage = .{ .all_graphics_bit = true }, .layout = .shader_read_only_optimal },
            .compute_storage_read => .{ .access = .{ .shader_storage_read_bit = true }, .stage = .{ .compute_shader_bit = true }, .layout = .general },
            .graphics_storage_read => .{ .access = .{ .shader_storage_read_bit = true }, .stage = .{ .all_graphics_bit = true }, .layout = .general },
            .compute_storage_write => .{ .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true }, .stage = .{ .compute_shader_bit = true }, .layout = .general },
            .graphics_storage_write => .{ .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true }, .stage = .{ .all_graphics_bit = true }, .layout = .general },
            .transfer_read => .{ .access = .{ .transfer_read_bit = true }, .stage = .{ .all_transfer_bit = true }, .layout = .transfer_src_optimal },
            .transfer_write => .{ .access = .{ .transfer_write_bit = true }, .stage = .{ .all_transfer_bit = true }, .layout = .transfer_dst_optimal },
        };
        if (access != .none and unified_image_layouts) result.layout = .general;
        return result;
    }

    fn buildTextureBarrier(
        device: *const Device,
        texture: Texture,
        src_access: saturn.TextureAccess,
        dst_access: saturn.TextureAccess,
    ) vk.ImageMemoryBarrier2 {
        const aspect_mask = Texture.getFormatAspectMask(texture.format);
        const is_color = aspect_mask.color_bit;
        const unified = device.device.extensions.unified_image_layouts;
        const src = getTextureStateAccess(src_access, is_color, unified);
        const dst = getTextureStateAccess(dst_access, is_color, unified);
        return .{
            .image = texture.handle,
            .subresource_range = .{
                .aspect_mask = aspect_mask,
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
            .src_access_mask = src.access,
            .src_stage_mask = src.stage,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .old_layout = src.layout,
            .dst_access_mask = dst.access,
            .dst_stage_mask = dst.stage,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .new_layout = dst.layout,
        };
    }

    fn emitBarriers(
        self: *Self,
        command_buffer: vk.CommandBufferProxy,
        compiled_pass: saturn.RenderGraphCompiled.Pass,
    ) !void {
        const DEBUG_FULL_PIPELINE_BARRIER = false;

        var memory_barriers: std.ArrayList(vk.MemoryBarrier2) = .empty;
        defer memory_barriers.deinit(self.tpa);
        var buffer_barriers: std.ArrayList(vk.BufferMemoryBarrier2) = .empty;
        defer buffer_barriers.deinit(self.tpa);
        var texture_barriers: std.ArrayList(vk.ImageMemoryBarrier2) = .empty;
        defer texture_barriers.deinit(self.tpa);

        if (DEBUG_FULL_PIPELINE_BARRIER) {
            try memory_barriers.append(self.tpa, .{
                .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                .src_stage_mask = .{ .all_commands_bit = true },
                .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                .dst_stage_mask = .{ .all_commands_bit = true },
            });
        }

        const dst_pass = &self.render_graph.passes.items[compiled_pass.handle.idx];

        // Barriers for resources with no prior pass (cross-frame dependencies)
        for (compiled_pass.first_usages.items) |first_usage| {
            switch (first_usage) {
                .buffer => |handle| {
                    const buffer = &self.resources.buffers[handle.idx];
                    if (buffer.last_access) |src_access| {
                        if (dst_pass.getBufferAccess(handle)) |dst_access| {
                            try buffer_barriers.append(self.tpa, buildBufferBarrier(buffer.interface.handle, src_access, dst_access));
                        }
                    }
                },
                .texture => |handle| {
                    const texture = &self.resources.textures[handle.idx];
                    if (dst_pass.getTextureAccess(handle)) |dst_access| {
                        try texture_barriers.append(self.tpa, buildTextureBarrier(self.device, texture.interface, texture.last_access orelse .none, dst_access));
                    }
                },
            }
        }

        // Barriers for pass-to-pass dependencies within this frame
        for (compiled_pass.pass_dependencies.items) |pass_dep| {
            const src_pass = &self.render_graph.passes.items[pass_dep.pass.idx];
            for (pass_dep.dependencies.items) |dep| {
                switch (dep) {
                    .buffer => |handle| {
                        const buffer = &self.resources.buffers[handle.idx];
                        if (src_pass.getBufferAccess(handle)) |src_access| {
                            if (dst_pass.getBufferAccess(handle)) |dst_access| {
                                try buffer_barriers.append(self.tpa, buildBufferBarrier(buffer.interface.handle, src_access, dst_access));
                            }
                        }
                    },
                    .texture => |handle| {
                        const texture = &self.resources.textures[handle.idx];
                        if (src_pass.getTextureAccess(handle)) |src_access| {
                            if (dst_pass.getTextureAccess(handle)) |dst_access| {
                                try texture_barriers.append(self.tpa, buildTextureBarrier(self.device, texture.interface, src_access, dst_access));
                            }
                        }
                    },
                }
            }
        }

        const dep_info: vk.DependencyInfo = .{
            .memory_barrier_count = @intCast(memory_barriers.items.len),
            .p_memory_barriers = memory_barriers.items.ptr,
            .buffer_memory_barrier_count = @intCast(buffer_barriers.items.len),
            .p_buffer_memory_barriers = buffer_barriers.items.ptr,
            .image_memory_barrier_count = @intCast(texture_barriers.items.len),
            .p_image_memory_barriers = texture_barriers.items.ptr,
        };

        const total = dep_info.memory_barrier_count + dep_info.buffer_memory_barrier_count + dep_info.image_memory_barrier_count;
        if (total > 0) command_buffer.pipelineBarrier2(&dep_info);
    }

    // ------------------------------------------------------------------
    // Record
    // ------------------------------------------------------------------

    //TODO: multi queue recording
    fn recordCommandBuffer(self: *Self) !void {
        const fence = try self.frame_data.fence_pool.get();
        try self.frame_data.frame_wait_fences.append(self.device.gpa, fence);

        const command_buffer_handle = try self.frame_data.graphics_command_pool.get();
        const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.device.proxy.wrapper);

        var data: platform.CommandEncoderData = .{
            .tpa = self.tpa,
            .command_buffer = command_buffer,
            .device = self.device,
            .graph_resources = self.resources,
        };

        try command_buffer.beginCommandBuffer(&.{});

        for (self.compiled.passes.items) |compiled_pass| {
            const pass = self.render_graph.passes.items[compiled_pass.handle.idx];

            if (self.device.device.debug) {
                const label = try self.tpa.dupeZ(u8, pass.name);
                command_buffer.beginDebugUtilsLabelEXT(&.{ .p_label_name = label, .color = .{ 1.0, 0.0, 1.0, 1.0 } });
            }
            defer if (self.device.device.debug) command_buffer.endDebugUtilsLabelEXT();

            try self.emitBarriers(command_buffer, compiled_pass);

            if (pass.render_target) |render_target| {
                self.beginRenderPass(command_buffer, render_target);
            }

            if (pass.callback) |pass_callback| {
                switch (pass_callback.callback) {
                    .transfer => |callback| {
                        callback(pass_callback.ctx, .{ .ctx = &data, .vtable = &platform.TransferCommandEncoder.Vtable });
                    },
                    .compute => |callback| {
                        callback(pass_callback.ctx, .{ .ctx = &data, .vtable = &platform.ComputeCommandEncoder.Vtable });
                    },
                    .graphics => |callback| {
                        if (pass.render_target == null) @panic("Graphics Pass must have a render_target set");
                        callback(pass_callback.ctx, .{ .ctx = &data, .vtable = &platform.GraphicsCommandEncoder.Vtable });
                    },
                }
            }

            if (pass.render_target != null) {
                command_buffer.endRendering();
            }
        }

        try self.emitSwapchainTransitions(command_buffer);
        try command_buffer.endCommandBuffer();

        // Build semaphore arrays and submit
        const wait_semaphores = try self.tpa.alloc(vk.Semaphore, self.swapchain_textures.len);
        defer self.tpa.free(wait_semaphores);
        const wait_stages = try self.tpa.alloc(vk.PipelineStageFlags, self.swapchain_textures.len);
        defer self.tpa.free(wait_stages);
        const signal_semaphores = try self.tpa.alloc(vk.Semaphore, self.swapchain_textures.len);
        defer self.tpa.free(signal_semaphores);

        for (self.swapchain_textures, 0..) |sc, i| {
            wait_semaphores[i] = sc.wait_semaphore;
            wait_stages[i] = .{ .all_commands_bit = true };
            signal_semaphores[i] = sc.present_semaphore;
        }

        const submit_info = vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&command_buffer_handle),
            .wait_semaphore_count = @intCast(wait_semaphores.len),
            .p_wait_semaphores = wait_semaphores.ptr,
            .p_wait_dst_stage_mask = wait_stages.ptr,
            .signal_semaphore_count = @intCast(signal_semaphores.len),
            .p_signal_semaphores = signal_semaphores.ptr,
        };

        try self.device.device.proxy.queueSubmit(self.device.device.graphics_queue.handle, 1, @ptrCast(&submit_info), fence);
    }

    fn emitSwapchainTransitions(self: *Self, command_buffer: vk.CommandBufferProxy) !void {
        const barriers = try self.tpa.alloc(vk.ImageMemoryBarrier2, self.swapchain_textures.len);
        defer self.tpa.free(barriers);

        for (self.swapchain_textures, barriers) |sc, *barrier| {
            var src_access: saturn.TextureAccess = .none;
            if (self.render_graph.textures.items[sc.resource.idx].last_usage) |last_pass| {
                if (self.render_graph.passes.items[last_pass.idx].getTextureAccess(sc.resource)) |access| {
                    src_access = access;
                }
            }
            const src = getTextureStateAccess(src_access, true, self.device.device.extensions.unified_image_layouts);
            barrier.* = .{
                .image = sc.interface.handle,
                .old_layout = src.layout,
                .new_layout = .present_src_khr,
                .src_access_mask = src.access,
                .src_stage_mask = src.stage,
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .base_mip_level = 0,
                    .level_count = 1,
                },
            };
        }

        command_buffer.pipelineBarrier2(&.{
            .image_memory_barrier_count = @intCast(barriers.len),
            .p_image_memory_barriers = barriers.ptr,
        });
    }

    fn beginRenderPass(self: *Self, command_buffer: vk.CommandBufferProxy, render_target: saturn.RGRenderTarget) void {
        const unified_image_layouts = self.device.device.extensions.unified_image_layouts;

        const color_attachments = self.tpa.alloc(vk.RenderingAttachmentInfo, render_target.color_attachemnts.len) catch @panic("Failed to alloc");
        defer self.tpa.free(color_attachments);

        var render_area_extent: vk.Extent2D = .{ .width = 0, .height = 0 };

        for (color_attachments, render_target.color_attachemnts) |*vk_attachment, attachment| {
            const texture = self.resources.textures[attachment.texture.idx].interface;
            render_area_extent = .{ .width = texture.extent.width, .height = texture.extent.height };

            vk_attachment.* = .{
                .image_view = texture.view_handle,
                .image_layout = if (unified_image_layouts) .general else .color_attachment_optimal,
                .resolve_mode = .{},
                .resolve_image_layout = .undefined,
                .load_op = if (attachment.clear != null) .clear else .load,
                .store_op = .store,
                .clear_value = if (attachment.clear) |c| .{ .color = .{ .float_32 = c } } else .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
            };
        }

        var depth_attachment: vk.RenderingAttachmentInfo = undefined;
        if (render_target.depth_attachment) |attachment| {
            const texture = self.resources.textures[attachment.texture.idx].interface;
            render_area_extent = .{ .width = texture.extent.width, .height = texture.extent.height };

            depth_attachment = .{
                .image_view = texture.view_handle,
                .image_layout = if (unified_image_layouts) .general else .depth_stencil_attachment_optimal,
                .resolve_mode = .{},
                .resolve_image_layout = .undefined,
                .load_op = if (attachment.clear != null) .clear else .load,
                .store_op = .store,
                .clear_value = if (attachment.clear) |c| .{ .depth_stencil = .{ .depth = c, .stencil = 0 } } else .{ .depth_stencil = .{ .depth = 0, .stencil = 0 } },
            };
        }

        const render_area: vk.Rect2D = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = render_area_extent,
        };
        command_buffer.beginRendering(&.{
            .render_area = render_area,
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = @intCast(color_attachments.len),
            .p_color_attachments = color_attachments.ptr,
            .p_depth_attachment = if (render_target.depth_attachment != null) &depth_attachment else null,
            .p_stencil_attachment = null,
        });
        const viewport: vk.Viewport = .{
            .width = @floatFromInt(render_area.extent.width),
            .height = @floatFromInt(render_area.extent.height),
            .x = 0.0,
            .y = 0.0,
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        command_buffer.setViewport(0, 1, @ptrCast(&viewport));
        command_buffer.setScissor(0, 1, @ptrCast(&render_area));
    }

    // ------------------------------------------------------------------
    // Present
    // ------------------------------------------------------------------

    fn present(self: *Self) !void {
        for (self.swapchain_textures) |sc| {
            sc.swapchain.queuePresent(
                self.device.device.graphics_queue.handle,
                sc.index,
                sc.present_semaphore,
            ) catch |err| switch (err) {
                error.OutOfDateKHR => sc.swapchain.out_of_date = true,
                else => return error.Unknown,
            };
        }
    }

    // ------------------------------------------------------------------
    // Last Usage Writeback
    // ------------------------------------------------------------------

    /// Write the final access state for each persistent resource back into
    /// the per-frame tracking maps so the next frame can read them as
    /// cross-frame `last_access` when building barriers.
    fn writeLastUsages(self: *Self) void {
        for (self.render_graph.buffers.items, 0..) |graph_buffer, idx| {
            const handle = switch (graph_buffer.source) {
                .persistent => |h| h,
                .transient => continue,
            };

            const rg_handle = saturn.RGBufferHandle{ .idx = @intCast(idx) };

            var last_access: ?saturn.BufferAccess = null;
            var i: usize = self.compiled.passes.items.len;
            while (i > 0) {
                i -= 1;
                const compiled_pass = &self.compiled.passes.items[i];
                const pass = &self.render_graph.passes.items[compiled_pass.handle.idx];
                if (pass.getBufferAccess(rg_handle)) |access| {
                    last_access = access;
                    break;
                }
            }

            if (last_access) |access| {
                self.frame_data.buffer_access.put(handle, access) catch {
                    std.log.err("writeLastUsages: failed to store buffer access for handle {}", .{handle});
                };
            }
        }

        for (self.render_graph.textures.items, 0..) |graph_texture, idx| {
            const handle = switch (graph_texture.source) {
                .persistent => |h| h,
                .transient, .window => continue,
            };

            const rg_handle = saturn.RGTextureHandle{ .idx = @intCast(idx) };

            var last_access: ?saturn.TextureAccess = null;
            var i: usize = self.compiled.passes.items.len;
            while (i > 0) {
                i -= 1;
                const compiled_pass = &self.compiled.passes.items[i];
                const pass = &self.render_graph.passes.items[compiled_pass.handle.idx];
                if (pass.getTextureAccess(rg_handle)) |access| {
                    last_access = access;
                    break;
                }
            }

            if (last_access) |access| {
                self.frame_data.texture_access.put(handle, access) catch {
                    std.log.err("writeLastUsages: failed to store texture access for handle {}", .{handle});
                };
            }
        }
    }
};
