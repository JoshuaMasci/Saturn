const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
const InstanceDispatch = @import("instance.zig").InstanceDispatch;

const Self = @This();

allocator: std.mem.Allocator,
pdevice: vk.PhysicalDevice,
handle: vk.Device,
graphics_queue_index: u32,
graphics_queue: vk.Queue,
memory_properties: vk.PhysicalDeviceMemoryProperties,
instance: *InstanceDispatch,
base: *DeviceBase,
sync2: *Sync2,
dynamic_rendering: *DynamicRendering,

pub fn init(
    allocator: std.mem.Allocator,
    instance_dispatch: InstanceDispatch,
    pdevice: vk.PhysicalDevice,
    graphics_queue_index: u32,
) !Self {
    var device_extensions = std.ArrayList([*:0]const u8).init(allocator);
    defer device_extensions.deinit();
    try device_extensions.append(vk.extension_info.khr_swapchain.name);

    // const should_raytrace: bool = false;
    // if (should_raytrace) {
    //     try device_extensions.append(vk.extension_info.khr_acceleration_structure.name);
    //     try device_extensions.append(vk.extension_info.khr_ray_tracing_pipeline.name);
    //     try device_extensions.append(vk.extension_info.khr_ray_query.name);
    // }

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

    //Features
    var sync2_feature = vk.PhysicalDeviceSynchronization2Features{
        .synchronization_2 = vk.TRUE,
    };
    var dynamic_rendering_feature = vk.PhysicalDeviceDynamicRenderingFeatures{
        .p_next = &sync2_feature,
        .dynamic_rendering = vk.TRUE,
    };

    var handle = try instance_dispatch.createDevice(pdevice, &.{
        .p_next = &dynamic_rendering_feature,
        .flags = .{},
        .queue_create_info_count = 1,
        .p_queue_create_infos = &qci,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
        .enabled_extension_count = @intCast(u32, device_extensions.items.len),
        .pp_enabled_extension_names = device_extensions.items.ptr,
        .p_enabled_features = null,
    }, null);

    var instance: *InstanceDispatch = try allocator.create(InstanceDispatch);
    instance.* = instance_dispatch;

    var base: *DeviceBase = try allocator.create(DeviceBase);
    base.* = try DeviceBase.load(handle, instance_dispatch.dispatch.vkGetDeviceProcAddr);

    var graphics_queue = base.getDeviceQueue(handle, graphics_queue_index, 0);

    var memory_properties = instance_dispatch.getPhysicalDeviceMemoryProperties(pdevice);

    var sync2 = try allocator.create(Sync2);
    sync2.* = try Sync2.load(handle, instance_dispatch.dispatch.vkGetDeviceProcAddr);

    var dynamic_rendering = try allocator.create(DynamicRendering);
    dynamic_rendering.* = try DynamicRendering.load(handle, instance_dispatch.dispatch.vkGetDeviceProcAddr);

    return Self{
        .allocator = allocator,
        .pdevice = pdevice,
        .handle = handle,
        .graphics_queue_index = graphics_queue_index,
        .graphics_queue = graphics_queue,
        .memory_properties = memory_properties,
        .instance = instance,
        .base = base,
        .sync2 = sync2,
        .dynamic_rendering = dynamic_rendering,
    };
}

pub fn deinit(self: *Self) void {
    self.base.destroyDevice(self.handle, null);
    self.allocator.destroy(self.instance);
    self.allocator.destroy(self.base);
    self.allocator.destroy(self.sync2);
    self.allocator.destroy(self.dynamic_rendering);
}

pub fn waitIdle(self: Self) void {
    self.base.deviceWaitIdle(self.handle) catch panic("Failed to deviceWaitIdle", .{});
}

pub fn getMemoryProperties(self: Self) vk.PhysicalDeviceMemoryProperties {
    return self.memory_properties;
}

pub const DeviceBase = vk.DeviceWrapper(.{
    .allocateCommandBuffers = true,
    .allocateDescriptorSets = true,
    .allocateMemory = true,
    .beginCommandBuffer = true,
    .bindBufferMemory = true,
    .bindBufferMemory2 = true,
    .bindImageMemory = true,
    .bindImageMemory2 = true,
    .cmdBeginQuery = true,
    .cmdBeginRenderPass = true,
    .cmdBeginRenderPass2 = true,
    .cmdBindDescriptorSets = true,
    .cmdBindIndexBuffer = true,
    .cmdBindPipeline = true,
    .cmdBindVertexBuffers = true,
    .cmdBlitImage = true,
    .cmdClearAttachments = true,
    .cmdClearColorImage = true,
    .cmdClearDepthStencilImage = true,
    .cmdCopyBuffer = true,
    .cmdCopyBufferToImage = true,
    .cmdCopyImage = true,
    .cmdCopyImageToBuffer = true,
    .cmdCopyQueryPoolResults = true,
    .cmdDispatch = true,
    .cmdDispatchBase = true,
    .cmdDispatchIndirect = true,
    .cmdDraw = true,
    .cmdDrawIndexed = true,
    .cmdDrawIndexedIndirect = true,
    .cmdDrawIndexedIndirectCount = true,
    .cmdDrawIndirect = true,
    .cmdDrawIndirectCount = true,
    .cmdEndQuery = true,
    .cmdEndRenderPass = true,
    .cmdEndRenderPass2 = true,
    .cmdExecuteCommands = true,
    .cmdFillBuffer = true,
    .cmdNextSubpass = true,
    .cmdNextSubpass2 = true,
    .cmdPipelineBarrier = true,
    .cmdPushConstants = true,
    .cmdResetEvent = true,
    .cmdResetQueryPool = true,
    .cmdResolveImage = true,
    .cmdSetBlendConstants = true,
    .cmdSetDepthBias = true,
    .cmdSetDepthBounds = true,
    .cmdSetDeviceMask = true,
    .cmdSetEvent = true,
    .cmdSetLineWidth = true,
    .cmdSetScissor = true,
    .cmdSetStencilCompareMask = true,
    .cmdSetStencilReference = true,
    .cmdSetStencilWriteMask = true,
    .cmdSetViewport = true,
    .cmdUpdateBuffer = true,
    .cmdWaitEvents = true,
    .cmdWriteTimestamp = true,
    .createBuffer = true,
    .createBufferView = true,
    .createCommandPool = true,
    .createComputePipelines = true,
    .createDescriptorPool = true,
    .createDescriptorSetLayout = true,
    .createDescriptorUpdateTemplate = true,
    .createEvent = true,
    .createFence = true,
    .createFramebuffer = true,
    .createGraphicsPipelines = true,
    .createImage = true,
    .createImageView = true,
    .createPipelineCache = true,
    .createPipelineLayout = true,
    .createQueryPool = true,
    .createRenderPass = true,
    .createRenderPass2 = true,
    .createSampler = true,
    .createSamplerYcbcrConversion = true,
    .createSemaphore = true,
    .createShaderModule = true,
    .destroyBuffer = true,
    .destroyBufferView = true,
    .destroyCommandPool = true,
    .destroyDescriptorPool = true,
    .destroyDescriptorSetLayout = true,
    .destroyDescriptorUpdateTemplate = true,
    .destroyDevice = true,
    .destroyEvent = true,
    .destroyFence = true,
    .destroyFramebuffer = true,
    .destroyImage = true,
    .destroyImageView = true,
    .destroyPipeline = true,
    .destroyPipelineCache = true,
    .destroyPipelineLayout = true,
    .destroyQueryPool = true,
    .destroyRenderPass = true,
    .destroySampler = true,
    .destroySamplerYcbcrConversion = true,
    .destroySemaphore = true,
    .destroyShaderModule = true,
    .deviceWaitIdle = true,
    .endCommandBuffer = true,
    .flushMappedMemoryRanges = true,
    .freeCommandBuffers = true,
    .freeDescriptorSets = true,
    .freeMemory = true,
    .getBufferDeviceAddress = true,
    .getBufferMemoryRequirements = true,
    .getBufferMemoryRequirements2 = true,
    .getBufferOpaqueCaptureAddress = true,
    .getDescriptorSetLayoutSupport = true,
    .getDeviceGroupPeerMemoryFeatures = true,
    .getDeviceMemoryCommitment = true,
    .getDeviceMemoryOpaqueCaptureAddress = true,
    .getDeviceQueue = true,
    .getEventStatus = true,
    .getFenceStatus = true,
    .getImageMemoryRequirements = true,
    .getImageMemoryRequirements2 = true,
    .getImageSparseMemoryRequirements = true,
    .getImageSparseMemoryRequirements2 = true,
    .getImageSubresourceLayout = true,
    .getPipelineCacheData = true,
    .getQueryPoolResults = true,
    .getRenderAreaGranularity = true,
    .getSemaphoreCounterValue = true,
    .invalidateMappedMemoryRanges = true,
    .mapMemory = true,
    .mergePipelineCaches = true,
    .queueBindSparse = true,
    .queueSubmit = true,
    .queueWaitIdle = true,
    .resetCommandBuffer = true,
    .resetCommandPool = true,
    .resetDescriptorPool = true,
    .resetEvent = true,
    .resetFences = true,
    .resetQueryPool = true,
    .setEvent = true,
    .signalSemaphore = true,
    .trimCommandPool = true,
    .unmapMemory = true,
    .updateDescriptorSetWithTemplate = true,
    .updateDescriptorSets = true,
    .waitForFences = true,
    .waitSemaphores = true,

    //Swapchain Ext
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .getSwapchainImagesKHR = true,
    .acquireNextImageKHR = true,
    .queuePresentKHR = true,
});

pub const Sync2 = vk.DeviceWrapper(.{
    .cmdPipelineBarrier2 = true,
    .cmdResetEvent2 = true,
    .cmdSetEvent2 = true,
    .cmdWaitEvents2 = true,
    .cmdWriteTimestamp2 = true,
    .queueSubmit2 = true,
});

pub const DynamicRendering = vk.DeviceWrapper(.{
    .cmdBeginRendering = true,
    .cmdEndRendering = true,
});
