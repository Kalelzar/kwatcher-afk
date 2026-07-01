const std = @import("std");
const core = @import("kw-core");
const kw_cache = @import("kw-cache");
const afk = @import("kwatcher-afk");
const drivers = @import("drivers.zig");

const id: struct { u8 } = .{0};

pub fn @"publish:heartbeat amq.direct/heartbeat"(
    ctx: struct { i64, ?afk.schema.AfkStatus },
    user_info: *core.schema.UserInfo,
    client_info: core.schema.ClientInfo,
    status: afk.schema.AfkStatus,
    cache: kw_cache.Cache(afk.schema.AfkStatusEntry),
    inj: *core.deps.DepCtx,
) !core.schema.Heartbeat.V1(afk.schema.AfkHeartbeatProperties) {
    const ts = ctx.@"0";
    const override_status = ctx.@"1" orelse status;

    const cached = cache.get(id) catch |e| switch (e) {
        error.CacheMiss => afk.schema.AfkStatusEntry{ .status = override_status, .timestamp = ts - 1 },
        else => return e,
    };

    if (ts >= cached.timestamp) {
        _ = try cache.push(.{ .status = override_status, .timestamp = ts }, id);
    }

    if (ts - cached.timestamp > std.time.us_per_s * 300) {
        const amqp = try inj.require(drivers.Scheduler(.amqp));
        std.log.warn("Timeskip! Missing {d}us worth of events. Applying correction.", .{ts - cached.timestamp});
        try amqp.publish(
            .{ .heartbeat = .{ cached.timestamp + std.time.us_per_s * 5, .Inactive } },
            .{ .inj = inj },
        );
        try amqp.publish(
            .{ .heartbeat = .{ ts - std.time.us_per_s * 5, .Inactive } },
            .{ .inj = inj },
        );
    }

    if (ctx.@"1" == null and cached.status != override_status) {
        const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(@divFloor(ts, std.time.us_per_s)) };
        const year_day = epoch.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_secs = epoch.getDaySeconds();
        std.log.info(
            "[{d:04}-{d:02}-{d:02}T{d:02}:{d:02}:{d:02}] Status changed: {t} -> {t}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                day_secs.getHoursIntoDay(),
                day_secs.getMinutesIntoHour(),
                day_secs.getSecondsIntoMinute(),
                cached.status,
                override_status,
            },
        );

        const amqp = try inj.require(drivers.Scheduler(.amqp));
        try amqp.publish(
            .{
                .afkStatusChange = .{.{
                    .prev = cached.status,
                    .current = override_status,
                    .timestamp = ts,
                }},
            },
            .{ .inj = inj },
        );
    }

    return .{
        .timestamp = ts,
        .event = "afk-status",
        .user = user_info.v1(),
        .client = client_info.v1(),
        .properties = .{
            .status = override_status,
        },
    };
}

pub fn @"publish!:afkStatusChange amq.direct/afk-status"(
    ctx: struct { afk.schema.StatusDiff },
    user_info: *core.schema.UserInfo,
    client_info: core.schema.ClientInfo,
) core.schema.Heartbeat.V1(afk.schema.AfkStatusChangeProperties) {
    return .{
        .timestamp = std.time.microTimestamp(),
        .event = "afk-status-change",
        .user = user_info.v1(),
        .client = client_info.v1(),
        .properties = .{
            .diff = ctx.@"0",
        },
    };
}
