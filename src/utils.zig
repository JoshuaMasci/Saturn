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
