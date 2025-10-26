const std = @import("std");
const log = std.log.scoped(.afk);
const kwatcher = @import("kwatcher");
const afk = @import("kwatcher-afk");

const routes = @import("route.zig");

pub const std_options = std.Options{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .dependency, .level = .info },
        .{ .scope = .server, .level = .info },
        .{ .scope = .amqp_client, .level = .info },
        .{ .scope = .circuit_breaker_client, .level = .warn },
        .{ .scope = .intern_fmt_cache, .level = .warn },
        .{ .scope = .replay, .level = .info },
        .{ .scope = .client, .level = .info },
        .{ .scope = .afk, .level = .info },
    },
};

const SingletonDependencies = struct {
    previous_status: ?afk.schema.AfkStatus = null,

    pub fn status(config: afk.config.Config) !afk.schema.AfkStatus {
        const time = try afk.timeSinceLastInput();
        const s = if (time < config.afk.afk_timeout) afk.schema.AfkStatus.Active else afk.schema.AfkStatus.Inactive;
        return s;
    }
};

const ScopedDependencies = struct {
    status_diff: ?afk.schema.StatusDiff = null,
    prev_cache: ?afk.schema.AfkStatus = null,

    pub fn construct(self: *ScopedDependencies, parent: *SingletonDependencies, status: afk.schema.AfkStatus) void {
        const previous_status = if (parent.previous_status) |p| p else status;
        self.prev_cache = previous_status;
    }

    pub fn diff(self: *ScopedDependencies, parent: *SingletonDependencies, current_status: afk.schema.AfkStatus) afk.schema.StatusDiff {
        if (self.status_diff) |d| {
            return d;
        }

        const previous_status = if (self.prev_cache) |p| p else current_status;
        const result = afk.schema.StatusDiff{
            .prev = previous_status,
            .current = current_status,
            .timestamp = std.time.timestamp(),
        };
        parent.previous_status = current_status;

        const epoch = std.time.epoch.EpochSeconds{
            .secs = @intCast(std.time.timestamp()),
        };
        const epoch_day = epoch.getEpochDay();
        const epoch_year = epoch_day.calculateYearDay();

        if (result.hasChanged()) {
            log.info(
                "[{d:04}-{d:02}-{d:02}T{d:02}:{d:02}:{d:02}] Status changed: {t} -> {t}",
                .{
                    epoch_year.year,
                    epoch_year.calculateMonthDay().month,
                    epoch_year.calculateMonthDay().day_index,
                    epoch.getDaySeconds().getHoursIntoDay(),
                    epoch.getDaySeconds().getMinutesIntoHour(),
                    epoch.getDaySeconds().getSecondsIntoMinute(),
                    result.prev,
                    result.current,
                },
            );
        }

        self.status_diff = result;

        return result;
    }
};

const EventProvider = struct {
    pub fn heartbeat(timer: kwatcher.Timer) !bool {
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

    var singleton = SingletonDependencies{};
    var server = try kwatcher.server.Server(
        "afk",
        "0.1.3",
        SingletonDependencies,
        ScopedDependencies,
        afk.config.Config,
        struct {},
        routes,
        EventProvider,
    ).init(
        allocator,
        &singleton,
    );
    defer server.deinit();

    try server.start();
}
