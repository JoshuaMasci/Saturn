const std = @import("std");

pub const WorldData = struct {};

pub const World = struct {
    data: WorldData,
    entity_pools: void,
};
