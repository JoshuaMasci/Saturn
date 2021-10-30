const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
const InstanceDispatch = @import("instance.zig").InstanceDispatch;

pub const Device = struct {
    const Self = @This();

    allocator: *Allocator,
    pdevice: vk.PhysicalDevice,
    handle: vk.Device,
    dispatch: *DeviceDispatch,

    pub fn init(
        allocator: *Allocator,
        instance_dispatch: InstanceDispatch,
        pdevice: vk.PhysicalDevice,
        graphics_queue_index: u32,
    ) !Self {
        const required_device_extensions = [_][]const u8{vk.extension_info.khr_swapchain.name};

        const props = instance_dispatch.getPhysicalDeviceProperties(pdevice);
        std.log.info("Device: \n\tName: {s}\n\tDriver: {}\n\tType: {}", .{ props.device_name, props.driver_version, props.device_type });

        const priority = [_]f32{1};
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .flags = .{},
                .queue_family_index = graphics_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        var handle = try instance_dispatch.createDevice(pdevice, .{
            .flags = .{},
            .queue_create_info_count = 1,
            .p_queue_create_infos = &qci,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = required_device_extensions.len,
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &required_device_extensions),
            .p_enabled_features = null,
        }, null);

        var dispatch: *DeviceDispatch = try allocator.create(DeviceDispatch);
        dispatch.* = try DeviceDispatch.load(handle, instance_dispatch.dispatch.vkGetDeviceProcAddr);

        return Self{
            .allocator = allocator,
            .pdevice = pdevice,
            .handle = handle,
            .dispatch = dispatch,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatch.destroyDevice(self.handle, null);
        self.allocator.destroy(self.dispatch);
    }

    pub fn waitIdle(self: Self) void {
        self.dispatch.deviceWaitIdle(self.handle) catch panic("Failed to deviceWaitIdle", .{});
    }
};

//TODO Split wrappers by extension maybe?
pub const DeviceDispatch = vk.DeviceWrapper(.{
    .DestroyDevice,
    .GetDeviceQueue,
    .CreateSemaphore,
    .CreateFence,
    .CreateImageView,
    .DestroyImageView,
    .DestroySemaphore,
    .DestroyFence,
    .GetSwapchainImagesKHR,
    .CreateSwapchainKHR,
    .DestroySwapchainKHR,
    .AcquireNextImageKHR,
    .DeviceWaitIdle,
    .WaitForFences,
    .ResetFences,
    .QueueSubmit,
    .QueuePresentKHR,
    .CreateCommandPool,
    .DestroyCommandPool,
    .AllocateCommandBuffers,
    .FreeCommandBuffers,
    .QueueWaitIdle,
    .CreateDescriptorSetLayout,
    .DestroyDescriptorSetLayout,
    .CreateDescriptorPool,
    .DestroyDescriptorPool,
    .AllocateDescriptorSets,
    .CreateShaderModule,
    .DestroyShaderModule,
    .CreatePipelineLayout,
    .DestroyPipelineLayout,
    .CreateRenderPass,
    .DestroyRenderPass,
    .CreateGraphicsPipelines,
    .DestroyPipeline,
    .CreateFramebuffer,
    .DestroyFramebuffer,
    .BeginCommandBuffer,
    .EndCommandBuffer,
    .AllocateMemory,
    .FreeMemory,
    .CreateBuffer,
    .DestroyBuffer,
    .GetBufferMemoryRequirements,
    .MapMemory,
    .UnmapMemory,
    .BindBufferMemory,
    .CmdBeginRenderPass,
    .CmdEndRenderPass,
    .CmdBindPipeline,
    .CmdDraw,
    .CmdSetViewport,
    .CmdSetScissor,
    .CmdBindVertexBuffers,
    .CmdBindIndexBuffer,
    .CmdCopyBuffer,
    .CmdPipelineBarrier,
    .CmdBindDescriptorSets,
    .CmdPushConstants,
    .CmdDrawIndexed,
    .CreateImage,
    .DestroyImage,
    .GetImageMemoryRequirements,
});
