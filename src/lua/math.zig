const std = @import("std");

const zlua = @import("zlua");
const zm = @import("zmath");

pub fn addBindings(lua: *zlua.Lua) !void {
    try lua.newMetatable("vec4");

    lua.pushFunction(zlua.wrap(newVector));
    lua.setGlobal("new");

    lua.pushFunction(zlua.wrap(getX));
    lua.setGlobal("getX");

    lua.pushFunction(zlua.wrap(getY));
    lua.setGlobal("getY");

    lua.pushFunction(zlua.wrap(getZ));
    lua.setGlobal("getZ");

    lua.pushFunction(zlua.wrap(getW));
    lua.setGlobal("getW");
}

fn newVector(lua: *zlua.Lua) !i32 {
    const arg_count: usize = @intCast(lua.getTop());
    var vector: zm.Vec = @splat(0.0);

    if (arg_count > 4) {
        return error.TooManyArguments;
    }

    const element_count: usize = @min(arg_count, 4);
    for (0..element_count) |i| {
        const index: i32 = @intCast(i);
        vector[i] = @floatCast(try lua.toNumber(index + 1));
    }

    try lua.pushAny(vector);

    return 1;
}

fn getX(lua: *zlua.Lua) !i32 {
    const vector = try lua.toAny(zm.Vec, 1);
    lua.pushNumber(@floatCast(vector[0]));
    return 1;
}

fn getY(lua: *zlua.Lua) !i32 {
    const vector = try lua.toAny(zm.Vec, 1);
    lua.pushNumber(@floatCast(vector[1]));
    return 1;
}

fn getZ(lua: *zlua.Lua) !i32 {
    const vector = try lua.toAny(zm.Vec, 1);
    lua.pushNumber(@floatCast(vector[2]));
    return 1;
}

fn getW(lua: *zlua.Lua) !i32 {
    const vector = try lua.toAny(zm.Vec, 1);
    lua.pushNumber(@floatCast(vector[3]));
    return 1;
}
