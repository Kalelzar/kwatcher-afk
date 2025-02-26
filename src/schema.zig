const std = @import("std");
const kwatcher = @import("kwatcher");

pub const AfkStatus = enum {
    Active,
    Inactive,
};

pub const AfkHeartbeatProperties = kwatcher.schema.Schema(
    1,
    "afk",
    struct {
        status: AfkStatus,
    },
);
