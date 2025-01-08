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

pub fn callMethodOnFields(
    comptime method_name: []const u8,
    self: anytype,
) void {
    const self_type = unwrapPointerType(@TypeOf(self)) orelse @compileError("self must be an ptr type");
    inline for (std.meta.fields(self_type)) |struct_field| {
        const field_type = unwrapOptionalType(struct_field.type) orelse @compileError("Field must be an optional type");
        const field_opt: *struct_field.type = &@field(self, struct_field.name);
        if (field_opt.*) |*field| {
            if (unwrapPointerType(field_type)) |base_field_type| {
                const function = @field(base_field_type, method_name);
                function(field.*);
            } else {
                const function = @field(field_type, method_name);
                function(field);
            }
        }
    }
}

pub fn callMethodWithArgsOnFields(
    comptime method_name: []const u8,
    comptime Args: type,
    self: anytype,
    args: Args,
) void {
    const self_type = unwrapPointerType(@TypeOf(self)) orelse @compileError("self must be an ptr type");
    inline for (std.meta.fields(self_type)) |struct_field| {
        const field_type = unwrapOptionalType(struct_field.type) orelse @compileError("Field must be an optional type");
        const field_opt: *struct_field.type = &@field(self, struct_field.name);
        if (field_opt.*) |*field| {
            if (unwrapPointerType(field_type)) |base_field_type| {
                const function = @field(base_field_type, method_name);
                function(field.*, args);
            } else {
                const function = @field(field_type, method_name);
                function(field, args);
            }
        }
    }
}

fn unwrapOptionalType(comptime T: type) ?type {
    switch (@typeInfo(T)) {
        .Optional => |option| return option.child,
        else => return null,
    }
}

fn unwrapPointerType(comptime T: type) ?type {
    switch (@typeInfo(T)) {
        .Pointer => |pointer| return pointer.child,
        else => return null,
    }
}
