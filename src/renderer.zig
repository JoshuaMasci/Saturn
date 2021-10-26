usingnamespace @import("core.zig");

const glfw = @import("glfw/platform.zig");
extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *glfw.c.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

const vk = @import("vulkan");
usingnamespace @import("vulkan/instance.zig");
usingnamespace @import("vulkan/device.zig");
usingnamespace @import("vulkan/swapchain.zig");

const imgui = @import("Imgui.zig");
const resources = @import("resources");

const ColorVertex = struct {
    const Self = @This();

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Self),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @byteOffsetOf(Self, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @byteOffsetOf(Self, "color"),
        },
    };

    pos: Vector3,
    color: Vector3,
};

pub const vertices = [_]ColorVertex{
    .{ .pos = Vector3.new(0, -0.75, 0.0), .color = Vector3.new(1, 0, 0) },
    .{ .pos = Vector3.new(-0.75, 0.75, 0.0), .color = Vector3.new(0, 1, 0) },
    .{ .pos = Vector3.new(0.75, 0.75, 0.0), .color = Vector3.new(0, 0, 1) },
};

pub const Renderer = struct {
    const Self = @This();

    allocator: *Allocator,
    instance: Instance,
    device: Device,
    surface: vk.SurfaceKHR,

    graphics_queue: vk.Queue,
    graphics_command_pool: vk.CommandPool,

    //TODO: multiple frames in flight
    device_frame: DeviceFrame,

    pub fn init(allocator: *Allocator, window: *glfw.c.GLFWwindow) !Self {
        var instance = try Instance.init(allocator, "Saturn Editor", AppVersion(0, 0, 0, 0));
        var selected_device = instance.pdevices[0];
        var selected_queue_index: u32 = 0;
        var device = try Device.init(allocator, instance.dispatch, selected_device, selected_queue_index);
        var surface = try createSurface(instance.handle, window);

        var graphics_queue = device.dispatch.getDeviceQueue(device.handle, selected_queue_index, 0);
        var graphics_command_pool = try device.dispatch.createCommandPool(
            device.handle,
            .{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = selected_queue_index,
            },
            null,
        );

        var device_frame = try DeviceFrame.init(device, graphics_command_pool);

        return Self{
            .allocator = allocator,
            .instance = instance,
            .device = device,
            .surface = surface,
            .graphics_queue = graphics_queue,
            .graphics_command_pool = graphics_command_pool,
            .device_frame = device_frame,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device_frame.deinit();
        self.device.dispatch.destroyCommandPool(self.device.handle, self.graphics_command_pool, null);
        self.device.deinit();
        self.instance.dispatch.destroySurfaceKHR(self.instance.handle, self.surface, null);
        self.instance.deinit();
    }

    pub fn render(self: *Self) void {}
};

fn createSurface(instance: vk.Instance, window: *glfw.c.GLFWwindow) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance, window, null, &surface) != .success) {
        return error.SurfaceCreationFailed;
    }
    return surface;
}

const DeviceFrame = struct {
    const Self = @This();
    device: Device,
    frame_done_fence: vk.Fence,
    image_ready_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    command_buffer: vk.CommandBuffer,

    fn init(
        device: Device,
        pool: vk.CommandPool,
    ) !Self {
        var frame_done_fence = try device.dispatch.createFence(device.handle, .{
            .flags = .{ .signaled_bit = true },
        }, null);

        var image_ready_semaphore = try device.dispatch.createSemaphore(device.handle, .{
            .flags = .{},
        }, null);

        var present_semaphore = try device.dispatch.createSemaphore(device.handle, .{
            .flags = .{},
        }, null);

        var command_buffer: vk.CommandBuffer = undefined;
        try device.dispatch.allocateCommandBuffers(device.handle, .{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &command_buffer));

        return Self{
            .device = device,
            .frame_done_fence = frame_done_fence,
            .image_ready_semaphore = image_ready_semaphore,
            .present_semaphore = present_semaphore,
            .command_buffer = command_buffer,
        };
    }

    fn deinit(self: Self) void {
        self.device.dispatch.destroyFence(self.device.handle, self.frame_done_fence, null);
        self.device.dispatch.destroySemaphore(self.device.handle, self.image_ready_semaphore, null);
        self.device.dispatch.destroySemaphore(self.device.handle, self.present_semaphore, null);
    }
};
