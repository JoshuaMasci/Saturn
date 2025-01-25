pub const TypeId = *const struct {
    _: u8,
};

pub inline fn typeId(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = @typeName(T);
        }
        var id: @typeInfo(TypeId).Pointer.child = undefined;
    }.id;
}
