const std = @import("std");
const kwatcher = @import("kwatcher");

pub const AfkStatus = enum {
    Active,
    Inactive,
};

pub const StatusDiff = struct {
    prev: AfkStatus,
    current: AfkStatus,
    timestamp: i64,
    pub fn hasChanged(self: *const StatusDiff) bool {
        return self.prev != self.current;
    }
};

pub const AfkHeartbeatProperties = kwatcher.schema.Schema(
    1,
    "afk",
    struct {
        status: AfkStatus,
    },
);

pub const AfkStatusChangeProperties = kwatcher.schema.Schema(
    1,
    "afk.status-change",
    struct {
        diff: StatusDiff,
    },
);
