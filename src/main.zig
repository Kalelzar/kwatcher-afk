const std = @import("std");
const kwatcher = @import("kwatcher");
const afk = @import("kwatcher-afk");

const routes = @import("route.zig");

const Dependencies = struct {
    previous_status: ?afk.schema.AfkStatus = null,

    pub fn status(config: afk.config.Config) !afk.schema.AfkStatus {
        const time = try afk.timeSinceLastInput();
        const s = if (time < config.afk.afk_timeout) afk.schema.AfkStatus.Active else afk.schema.AfkStatus.Inactive;
        return s;
    }

    pub fn statusDiff(
        self: *Dependencies,
        current_status: afk.schema.AfkStatus,
    ) afk.schema.StatusDiff {
        const previous_status = if (self.previous_status) |p| p else current_status;
        const result = afk.schema.StatusDiff{
            .prev = previous_status,
            .current = current_status,
        };
        self.previous_status = current_status;
        return result;
    }
};

const EventProvider = struct {
    pub fn heartbeat(timer: kwatcher.server.Timer) !bool {
        return try timer.ready("heartbeat");
    }

    pub fn afkStatusChange(diff: afk.schema.StatusDiff) bool {
        return diff.hasChanged();
    }

    pub fn disabled() bool {
        return false;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try kwatcher.server.Server(
        "afk",
        "0.1.0",
        Dependencies,
        afk.config.Config,
        routes,
        EventProvider,
    ).init(allocator, Dependencies{});
    defer server.deinit();

    try server.run();
}
