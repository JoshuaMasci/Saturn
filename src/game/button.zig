const std = @import("std");
pub const Universe = @import("../entity/universe.zig");
pub const Entity = @import("../entity/entity.zig");

pub const AirLockComponent = @import("airlock.zig").AirLockComponent;

pub const global = @import("../global.zig");

pub const ButtonComponent = struct {
    target: ?Entity.Handle = null,

    pub fn pressButton(self: @This(), universe: *Universe) void {
        const target_handle = self.target orelse return;
        const target_entity = universe.entities.get(target_handle) orelse return;
        const target_airlock = target_entity.systems.get(AirLockComponent) orelse return;
        target_airlock.moveEntites(global.global_allocator, target_entity);
    }
};
