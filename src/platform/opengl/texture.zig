const std = @import("std");
const gl = @import("zopengl").bindings;

const Self = @This();

texture: gl.Uint,
size: [2]u32,
target: gl.Enum,

pub const PixelFormat = enum {
    R,
    RG,
    RGB,
    RGBA,

    fn to_gl(self: @This()) gl.Enum {
        return switch (self) {
            .R => gl.RED,
            .RG => gl.RG,
            .RGB => gl.RGB,
            .RGBA => gl.RGBA,
        };
    }
};

pub const PixelType = enum {
    u8,

    fn to_gl(self: @This()) gl.Enum {
        return switch (self) {
            .u8 => gl.UNSIGNED_BYTE,
        };
    }
};

pub const Format = struct {
    load: PixelFormat = .RGBA,
    store: PixelFormat = .RGBA,
    layout: PixelType = .u8,
    mips: bool = true,
};

pub const Filtering = enum {
    Linear,
    Nearest,

    fn to_gl(self: @This()) gl.Int {
        return switch (self) {
            .Linear => gl.LINEAR,
            .Nearest => gl.NEAREST,
        };
    }
};

pub const MipFiltering = enum {
    Linear,
    Nearest,
    Nearest_Mip_Nearest,
    Linear_Mip_Nearest,
    Nearest_Mip_Linear,
    Linear_Mip_Linear,

    fn to_gl(self: @This()) gl.Int {
        return switch (self) {
            .Linear => gl.LINEAR,
            .Nearest => gl.NEAREST,
            .Nearest_Mip_Nearest => gl.NEAREST_MIPMAP_NEAREST,
            .Linear_Mip_Nearest => gl.LINEAR_MIPMAP_NEAREST,
            .Nearest_Mip_Linear => gl.NEAREST_MIPMAP_LINEAR,
            .Linear_Mip_Linear => gl.LINEAR_MIPMAP_LINEAR,
        };
    }
};

pub const AddressMode = enum {
    Clamp_To_Edge,
    Mirrored_Repeat,
    Repeat,

    fn to_gl(self: @This()) gl.Int {
        return switch (self) {
            .Clamp_To_Edge => gl.CLAMP_TO_EDGE,
            .Mirrored_Repeat => gl.MIRRORED_REPEAT,
            .Repeat => gl.REPEAT,
        };
    }
};

pub const Sampler = struct {
    min: MipFiltering = .Linear,
    mag: Filtering = .Linear,
    address_mode_u: AddressMode = .Repeat,
    address_mode_v: AddressMode = .Repeat,
};

pub fn init_2d(
    size: [2]u32,
    data: []u8,
    format: Format,
    sampler: Sampler,
) Self {
    var texture: gl.Uint = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, sampler.min.to_gl());
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, sampler.mag.to_gl());
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, sampler.address_mode_u.to_gl());
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, sampler.address_mode_v.to_gl());

    gl.texImage2D(gl.TEXTURE_2D, 0, format.load.to_gl(), @intCast(size[0]), @intCast(size[1]), 0, format.store.to_gl(), format.layout.to_gl(), data.ptr);

    if (format.mips) {
        gl.generateMipmap(gl.TEXTURE_2D);
    }

    return .{
        .texture = texture,
        .size = size,
        .target = gl.TEXTURE_2D,
    };
}

pub fn init_cube(
    size: u32,
    face_data: [6][]u8,
    format: Format,
    filter: Filtering,
) Self {
    var texture: gl.Uint = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_CUBE_MAP, texture);

    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, filter.to_gl());
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, filter.to_gl());
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_BORDER);

    for (face_data, 0..) |data, i| {
        const face_offset: gl.Enum = @intCast(i);
        const face: gl.Enum = gl.TEXTURE_CUBE_MAP_POSITIVE_X + face_offset;
        gl.texImage2D(face, 0, format.load.to_gl(), @intCast(size), @intCast(size), 0, format.store.to_gl(), format.layout.to_gl(), data.ptr);
    }

    if (format.mips) {
        gl.generateMipmap(gl.TEXTURE_CUBE_MAP);
    }

    return .{
        .texture = texture,
        .size = .{ size, size },
        .target = gl.TEXTURE_CUBE_MAP,
    };
}

pub fn deinit(self: Self) void {
    gl.deleteTextures(1, &self.texture);
}

pub fn bind(self: Self, slot: u32) void {
    gl.activeTexture(gl.TEXTURE0 + slot);
    gl.bindTexture(self.target, self.texture);
}
