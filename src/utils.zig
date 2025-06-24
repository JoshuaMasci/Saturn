const std = @import("std");

const TEREBYTE = std.math.pow(usize, 1000, 4);
const GIGABYTE = std.math.pow(usize, 1000, 3);
const MEGABYTE = std.math.pow(usize, 1000, 2);
const KILOBYTE = std.math.pow(usize, 1000, 1);

fn human_readable_bytes(value: usize) usize {
    if (value > TEREBYTE) {
        return value / TEREBYTE;
    } else if (value > GIGABYTE) {
        return value / GIGABYTE;
    } else if (value > MEGABYTE) {
        return value / MEGABYTE;
    } else if (value > KILOBYTE) {
        return value / KILOBYTE;
    } else {
        return value;
    }
}

fn human_readable_unit(value: usize) []const u8 {
    if (value > TEREBYTE) {
        return "TB";
    } else if (value > GIGABYTE) {
        return "GB";
    } else if (value > MEGABYTE) {
        return "MB";
    } else if (value > KILOBYTE) {
        return "KB";
    } else {
        return "B";
    }
}

pub fn format_human_readable_bytes(allocator: std.mem.Allocator, bytes: usize) ?[]u8 {
    const value = human_readable_bytes(bytes);
    const unit = human_readable_unit(bytes);
    return std.fmt.allocPrint(allocator, comptime "{} {s}", .{ value, unit }) catch null;
}

pub fn format_bytes(allocator: std.mem.Allocator, bytes: usize) ![]const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB", "EB" };
    var size = @as(f64, @floatFromInt(bytes));
    var unit_index: usize = 0;

    while (size >= 1024.0 and unit_index < units.len - 1) {
        size /= 1024.0;
        unit_index += 1;
    }

    // Format the float with two decimal places and append the unit
    const formatted = try std.fmt.allocPrint(allocator, "{d:.0} {s}", .{ size, units[unit_index] });
    return formatted;
}
