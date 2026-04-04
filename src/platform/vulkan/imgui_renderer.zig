//TODO: deprecate this once the Saturn Imgui Renderer is implimentated

const std = @import("std");

const saturn = @import("../../root.zig");
const cimgui = @import("../imgui.zig").c;

const Device = @import("device.zig");
const Swapchain = @import("swapchain.zig");
const Texture = @import("texture.zig");

const Self = @This();

pub fn init(device: *Device) !Self {
    const device_api_version = device.instance.getPhysicalDeviceProperties(device.physical_device.handle).api_version;

    var init_info: cimgui.ImGui_ImplVulkan_InitInfo = .{
        .ApiVersion = device_api_version,
        .Instance = @ptrFromInt(@intFromEnum(device.instance.handle)),
        .PhysicalDevice = @ptrFromInt(@intFromEnum(device.physical_device.handle)),
        .Device = @ptrFromInt(@intFromEnum(device.proxy.handle)),
        .QueueFamily = device.graphics_queue.family_index,
        .Queue = @ptrFromInt(@intFromEnum(device.graphics_queue.handle)),
        .UseDynamicRendering = true,
        .MinImageCount = 2,
        .ImageCount = @intCast(3),
        .DescriptorPoolSize = 1024,
    };

    if (!cimgui.cImGui_ImplVulkan_LoadFunctionsEx(device_api_version, Device.getProcAddr, device)) return error.InitializationFailed;

    if (!cimgui.cImGui_ImplVulkan_Init(@ptrCast(&init_info))) return error.InitializationFailed;
    errdefer cimgui.cImGui_ImplVulkan_Shutdown();

    return .{};
}

pub fn deinit(self: Self) void {
    _ = self; // autofix
    cimgui.cImGui_ImplVulkan_Shutdown();
}

pub fn newFrame(self: Self) void {
    _ = self; // autofix
    cimgui.cImGui_ImplVulkan_NewFrame();
}

pub fn rebuild(self: Self, device: *Device, swapchain: *Swapchain) void {
    _ = device; // autofix
    _ = self; // autofix

    const format = Texture.getVkFormat(swapchain.format);
    const usage = Texture.getVkImageUsage(swapchain.usage, true);

    const color_attachments: [1]u32 = .{@intCast(@intFromEnum(format))};

    var pipeline_info: cimgui.struct_ImGui_ImplVulkan_PipelineInfo_t = .{
        .RenderPass = null,
        .Subpass = 0,
        .MSAASamples = 1,
        .PipelineRenderingCreateInfo = .{
            .pNext = null,
            .sType = cimgui.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR,
            .colorAttachmentCount = 1,
            .pColorAttachmentFormats = &color_attachments,
            .depthAttachmentFormat = 0,
        },
        .SwapChainImageUsage = @bitCast(usage),
    };

    cimgui.cImGui_ImplVulkan_CreateMainPipeline(&pipeline_info);

    // var wd: cimgui.ImGui_ImplVulkanH_Window = .{
    //     .Surface = @ptrFromInt(@intFromEnum(swapchain.surface)),
    //     .Swapchain = @ptrFromInt(@intFromEnum(swapchain.handle)),
    //     .SurfaceFormat = .{ .colorSpace = cimgui.VK_COLORSPACE_SRGB_NONLINEAR_KHR, .format = @intCast(@intFromEnum(format)) },
    //     .PresentMode = @intCast(@intFromEnum(swapchain.present_mode)),
    // };
    // _ = wd; // autofix

    // const min_image_count: u32 = @min(3, swapchain.image_count);
    // _ = min_image_count; // autofix

    // cimgui.cImGui_ImplVulkanH_CreateOrResizeWindow(
    //     @ptrFromInt(@intFromEnum(device.instance.handle)),
    //     @ptrFromInt(@intFromEnum(device.physical_device.handle)),
    //     @ptrFromInt(@intFromEnum(device.proxy.handle)),
    //     &wd,
    //     device.graphics_queue.family_index,
    //     null,
    //     @intCast(swapchain.extent.width),
    //     @intCast(swapchain.extent.height),
    //     min_image_count,
    //     0,
    // );
}

pub fn createRenderPass(self: Self, target: saturn.RGTextureHandle, graph: *saturn.RenderGraph) !saturn.RGPassHandle {
    _ = self; // autofix

    const ctx_data = try graph.dupe(Data, .{ .target_index = target.idx });

    const pass = try graph.addGraphicsPass(
        "Main ImGui Pass",
        .{ .color_attachments = &.{.{
            .texture = target,
            .clear = null,
        }} },
        ctx_data,
        emptyGraphicsCallback,
    );
    _ = pass; // autofix

    return error.Error;
}

const Data = struct {
    target_index: u32,
};

fn emptyGraphicsCallback(ctx: ?*anyopaque, cmd: saturn.GraphicsCommandEncoder, target_resolution: [2]u32) void {
    _ = target_resolution; // autofix

    const data: *Data = @ptrCast(@alignCast(ctx.?));
    _ = data; // autofix

    // WARNING: DONT do this in app code
    const command_encoder: *@import("platform.zig").CommandEncoderData = @ptrCast(@alignCast(cmd.ctx));

    cimgui.ImGui_Render();
    const draw_data = cimgui.ImGui_GetDrawData();

    cimgui.cImGui_ImplVulkan_RenderDrawData(draw_data, @ptrFromInt(@intFromEnum(command_encoder.command_buffer.handle)));
}
