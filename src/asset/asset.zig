pub const GUID = u64;

pub const BaseMeta = struct {
    guid: GUID,
    type: []const u8,
};
