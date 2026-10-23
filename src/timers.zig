const std = @import("std");
const core = @import("kw-core");
const drivers = @import("drivers.zig");

pub fn @"check_afk */5 * * * * *"(inj: *core.deps.DepCtx, io: std.Io) !void {
    const amqp = try inj.require(drivers.Scheduler(.amqp));
    try amqp.publish(
        .{
            .heartbeat = .{ std.Io.Clock.real.now(io).toMicroseconds(), null },
        },
        .{ .inj = inj },
    );
}
