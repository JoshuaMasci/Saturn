const std = @import("std");
const vk = @import("vulkan");

// List from here: https://www.reddit.com/r/vulkan/comments/4ta9nj/is_there_a_comprehensive_list_of_the_names_and/
//TODO: find a more complete list?
pub const VendorID = enum(u32) {
    AMD = 0x1002,
    ImgTec = 0x1010,
    NVIDIA = 0x10DE,
    ARM = 0x13B5,
    Qualcomm = 0x5143,
    INTEL = 0x8086,
    _,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt; // autofix
        _ = options; // autofix

        if (std.enums.tagName(@This(), self)) |tag_name| {
            return writer.print("{s}", .{tag_name});
        } else {
            return writer.print(" 0x{x}", .{@intFromEnum(self)});
        }
    }
};

pub const MemoryProperties = struct {
    device_local_bytes: u64,
    direct_buffer_upload: bool,
    direct_texture_upload: bool,
};

pub const Queues = struct {
    graphics: ?u32,
    async_compute: ?u32,
    async_transfer: ?u32,
};

pub const Extensions = struct {
    mesh_shader_support: bool,
    raytracing_support: bool,
};

const Self = @This();

name: [256]u8,
device_id: u32,
api_version: [4]u16,
vendor_id: VendorID,
type: vk.PhysicalDeviceType,
memory: MemoryProperties,
queues: Queues,
extensions: Extensions,

pub fn format(
    self: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt; // autofix
    _ = options; // autofix
    return writer.print(
        \\DeviceInfo {{
        \\  name: {s}
        \\  device_id: 0x{x}
        \\  api_version: {}.{}.{}.{}
        \\  vendor_id: {}
        \\  type: {}
        \\  memory: {}
        \\  queues: {}
        \\  extensions: {}
        \\}}
    , .{
        std.mem.sliceTo(&self.name, 0),
        self.device_id,
        self.api_version[0],
        self.api_version[1],
        self.api_version[2],
        self.api_version[3],
        self.vendor_id,
        self.type,
        self.memory,
        self.queues,
        self.extensions,
    });
}

pub fn init(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice) !Self {
    var driver_properties: vk.PhysicalDeviceDriverProperties = .{
        .driver_id = undefined,
        .driver_name = undefined,
        .driver_info = undefined,
        .conformance_version = undefined,
    };
    var properties2: vk.PhysicalDeviceProperties2 = .{
        .p_next = &driver_properties,
        .properties = undefined,
    };
    instance.getPhysicalDeviceProperties2(physical_device, &properties2);

    const extensions_properties: []vk.ExtensionProperties = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device, null, allocator);
    defer allocator.free(extensions_properties);

    //Memory Properties
    const memory: MemoryProperties = MEM_BLK: {
        var device_local_bytes: u64 = 0;
        var direct_buffer_upload = false;

        //TODO: use feature version when this is updated to VK1.4
        const direct_texture_upload = supportsExtension(extensions_properties, "VK_EXT_host_image_copy"); //or (host_image_copy_properties.host_image_copy == vk.TRUE);

        const props = instance.getPhysicalDeviceMemoryProperties(physical_device);
        var device_local_mappable_bytes: u64 = 0;
        heap_loop: for (props.memory_heaps[0..props.memory_heap_count], 0..) |heap, i| {
            if (heap.flags.device_local_bit) {
                device_local_bytes += heap.size;

                //Search if any memory type supports host access
                for (props.memory_types[0..props.memory_type_count]) |mtype| {
                    if (mtype.heap_index == i and (mtype.property_flags.host_visible_bit and mtype.property_flags.host_coherent_bit)) {
                        device_local_mappable_bytes += heap.size;
                        continue :heap_loop;
                    }
                }
            }
        }

        // This is an attempt to determine if the device memory is all host accessable (Likey because the GPU is either itegrated or has reBAR enabled),
        // which should allow may transfers to be done as mem copies instead
        // Older GPUs may only have a small amount of BAR memory, if this is the case buffer allocations will avoid using it and rely on transfer queues as normal
        direct_buffer_upload = device_local_bytes == device_local_mappable_bytes;
        break :MEM_BLK .{
            .device_local_bytes = device_local_bytes,
            .direct_buffer_upload = direct_buffer_upload,
            .direct_texture_upload = direct_texture_upload,
        };
    };

    const queues: Queues = QUE_BLK: {
        const queue_properties = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator);
        defer allocator.free(queue_properties);

        break :QUE_BLK .{
            // Graphics queue must be support compute and transfer
            // This should hold for all desktop devices, I vaugly recall mobile devices that this didn't hold for, if so some rendering code will need to be changed to support this
            .graphics = findQueueFamliyIndex(queue_properties, .{ .graphics_bit = true, .compute_bit = true, .transfer_bit = true }, .{}),
            .async_compute = findQueueFamliyIndex(queue_properties, .{ .compute_bit = true, .transfer_bit = true }, .{ .graphics_bit = true }),
            .async_transfer = findQueueFamliyIndex(queue_properties, .{ .transfer_bit = true }, .{ .graphics_bit = true, .compute_bit = true }),
        };
    };

    const extensions: Extensions = .{
        .mesh_shader_support = supportsExtension(extensions_properties, "VK_EXT_mesh_shader"),
        .raytracing_support = supportsExtension(extensions_properties, "VK_KHR_acceleration_structure") and supportsExtension(extensions_properties, "VK_KHR_ray_query"), //Will not support VK_KHR_ray_tracing_pipeline
    };

    return .{
        .name = properties2.properties.device_name,
        .device_id = properties2.properties.device_id,
        .api_version = versionToArray(@bitCast(properties2.properties.api_version)),
        .vendor_id = @enumFromInt(properties2.properties.vendor_id),
        .type = properties2.properties.device_type,
        .memory = memory,
        .queues = queues,
        .extensions = extensions,
    };
}

fn supportsExtension(properties: []const vk.ExtensionProperties, name: []const u8) bool {
    for (properties) |extension| {
        if (std.mem.eql(u8, extension.extension_name[0..name.len], name)) {
            return true;
        }
    }
    return false;
}

fn findQueueFamliyIndex(properties: []const vk.QueueFamilyProperties, contains: vk.QueueFlags, excludes: vk.QueueFlags) ?u32 {
    // Search for a queue family index that contains the desired flags and doesn't contain any excluded flags
    for (properties, 0..) |queue_family, i| {
        if (queue_family.queue_flags.contains(contains) and queue_family.queue_flags.complement().contains(excludes)) {
            return @intCast(i);
        }
    }
    return null;
}

fn versionToArray(version: vk.Version) [4]u16 {
    return .{ @intCast(version.variant), @intCast(version.major), @intCast(version.minor), @intCast(version.patch) };
}
