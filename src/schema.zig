const std = @import("std");
const core = @import("kw-core");

pub const AfkStatus = enum {
    Active,
    Inactive,
};

pub const AfkStatusEntry = struct {
    status: AfkStatus,
    timestamp: i64,
};

pub const StatusDiff = struct {
    prev: AfkStatus,
    current: AfkStatus,
    timestamp: i64,
    pub fn hasChanged(self: *const StatusDiff) bool {
        return self.prev != self.current;
    }
};

pub const AfkHeartbeatProperties = core.schema.Schema(
    1,
    "afk",
    struct {
        status: AfkStatus,
    },
);

pub const AfkStatusChangeProperties = core.schema.Schema(
    1,
    "afk.status-change",
    struct {
        diff: StatusDiff,
    },
);
