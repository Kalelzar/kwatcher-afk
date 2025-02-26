const std = @import("std");
const kwatcher = @import("kwatcher");

pub const Config = struct {
    afk: struct {
        afk_timeout: u64 = 15 * std.time.s_per_min,
    } = .{},
};

pub const FullConfig = kwatcher.meta.MergeStructs(kwatcher.config.BaseConfig, Config);
