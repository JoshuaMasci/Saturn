const std = @import("std");

const vk = @import("vulkan");

const imgui = @import("../imgui.zig").c;
const sdl3 = @import("../platform/sdl3.zig");
const Backend = @import("vulkan/backend.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");

const Self = @This();

allocator: std.mem.Allocator,
device: *Backend,

pub fn init(
    allocator: std.mem.Allocator,
    device: *Backend,
    color_format: vk.Format,
) !Self {
    if (!imgui.cImGui_ImplVulkan_LoadFunctionsEx(@bitCast(vk.API_VERSION_1_3), loader, @ptrFromInt(@intFromEnum(device.instance.instance.handle)))) return error.ImGuiVulkanLoadFailure;

    var init_info = imgui.ImGui_ImplVulkan_InitInfo{};
    init_info.Instance = @ptrFromInt(@intFromEnum(device.instance.instance.handle));
    init_info.PhysicalDevice = @ptrFromInt(@intFromEnum(device.device.physical_device.handle));
    init_info.Device = @ptrFromInt(@intFromEnum(device.device.proxy.handle));
    init_info.QueueFamily = device.device.graphics_queue.family_index;
    init_info.Queue = @ptrFromInt(@intFromEnum(device.device.graphics_queue.handle));
    init_info.MinImageCount = 3;
    init_info.ImageCount = 8;

    init_info.DescriptorPoolSize = 1024;
    init_info.UseDynamicRendering = true;

    const color_format_slice: []const vk.Format = &.{color_format};
    init_info.PipelineRenderingCreateInfo = .{
        .sType = imgui.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = @ptrCast(color_format_slice.ptr),
    };

    if (!imgui.cImGui_ImplVulkan_Init(&init_info)) return error.ImGuiVulkanInitFailure;
    errdefer imgui.cImGui_ImplVulkan_Shutdown();

    return .{
        .allocator = allocator,
        .device = device,
    };
}

pub fn deinit(self: *Self) void {
    _ = self; // autofix

    imgui.cImGui_ImplVulkan_Shutdown();
}

pub fn createRenderPass(self: *Self, temp_allocator: std.mem.Allocator, target: rg.RenderGraphTextureHandle, render_graph: *rg.RenderGraph) !void {
    _ = self; // autofix

    var render_pass = try rg.RenderPass.init(temp_allocator, "Imgui Pass");
    try render_pass.addColorAttachment(.{ .texture = target });

    render_pass.addBuildFn(buildCommandBuffer, null);

    try render_graph.render_passes.append(render_graph.allocator, render_pass);
}

fn buildCommandBuffer(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = build_data; // autofix
    _ = resources; // autofix
    _ = device; // autofix
    _ = raster_pass_extent; // autofix

    imgui.ImGui_Render();
    const draw_data = imgui.ImGui_GetDrawData();
    imgui.cImGui_ImplVulkan_RenderDrawData(draw_data, @ptrFromInt(@intFromEnum(command_buffer.handle)));
}

fn loader(name: [*c]const u8, instance: ?*anyopaque) callconv(.c) ?*const fn () callconv(.c) void {
    const vkGetInstanceProcAddr: imgui.PFN_vkGetInstanceProcAddr = @ptrCast(sdl3.Vulkan.getProcInstanceFunction());
    const func = vkGetInstanceProcAddr.?(@ptrCast(instance), name);
    return func;
}
