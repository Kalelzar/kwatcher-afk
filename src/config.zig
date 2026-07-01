const std = @import("std");

pub const Config = struct {
    afk_timeout: u64 = 15 * std.time.s_per_min,
};
