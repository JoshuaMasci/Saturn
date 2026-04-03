const std = @import("std");

const MAGIC: [8]u8 = .{ 'S', '-', 'A', 'S', 'S', 'E', 'T', 'S' };
const VERSION: usize = 1;

pub const HeaderV1 = extern struct {
    magic: [8]u8 = MAGIC,
    version: usize = VERSION,
    atype: AssetType,

    pub fn validMagic(self: HeaderV1) bool {
        return std.mem.eql(u8, &MAGIC, &self.magic);
    }

    pub fn validVersion(self: HeaderV1) bool {
        return self.version == VERSION;
    }

    pub fn valid(self: HeaderV1) bool {
        return self.validMagic() and self.validVersion();
    }
};

pub const AssetType = @import("type.zig").AssetType;
