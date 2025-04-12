pub const TypeId = *const struct {
    _: u8,
};

pub inline fn typeId(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = @typeName(T);
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}
