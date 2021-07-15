const std = @import("std");

const glfw = @import("glfw_platform.zig");

const vk = @import("vulkan");
const VK_API_VERSION_1_2 = vk.makeApiVersion(0, 1, 2, 0);

const BaseDispatch = vk.BaseWrapper(.{
    .CreateInstance,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .DestroyInstance,
    .CreateDevice,
    .DestroySurfaceKHR,
    .EnumeratePhysicalDevices,
    .GetPhysicalDeviceProperties,
    .EnumerateDeviceExtensionProperties,
    .GetPhysicalDeviceSurfaceFormatsKHR,
    .GetPhysicalDeviceSurfacePresentModesKHR,
    .GetPhysicalDeviceSurfaceCapabilitiesKHR,
    .GetPhysicalDeviceQueueFamilyProperties,
    .GetPhysicalDeviceSurfaceSupportKHR,
    .GetPhysicalDeviceMemoryProperties,
    .GetDeviceProcAddr,
});

pub fn main() !void {
    std.log.info("Hello App", .{});

    glfw.init();
    defer glfw.deinit();

    var window = glfw.createWindow(1600, 900, "Saturn V0.0");
    defer glfw.destoryWindow(window);
    //glfw.setMouseCaptured(window, true);
    glfw.maximizeWindow(window);

    const saturn_name = "saturn";
    const saturn_version = vk.makeApiVersion(0, 0, 0, 0);

    const app_info = vk.ApplicationInfo{
        .p_application_name = saturn_name,
        .application_version = saturn_version,
        .p_engine_name = saturn_name,
        .engine_version = saturn_version,
        .api_version = VK_API_VERSION_1_2,
    };

    var base_dispatch = BaseDispatch.load(glfw.glfwGetInstanceProcAddress);

    while (glfw.shouldCloseWindow(window)) {
        glfw.update();
    }
}
