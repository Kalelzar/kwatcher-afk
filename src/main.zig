const std = @import("std");
const kwatcher = @import("kwatcher");
const afk = @import("kwatcher-afk");

const routes = @import("route.zig");

const Dependencies = struct {
    pub fn status(config: afk.config.Config) !afk.schema.AfkStatus {
        const time = try afk.timeSinceLastInput();
        return if (time <= config.afk.afk_timeout) afk.schema.AfkStatus.Active else afk.schema.AfkStatus.Inactive;
    }
};

const EventProvider = struct {
    pub fn heartbeat(timer: kwatcher.server.Timer) !bool {
        return try timer.ready("heartbeat");
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
