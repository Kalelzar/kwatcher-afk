const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.afk);
const core = @import("kw-core");
const kwatcher = @import("kwatcher");
const amqp = @import("kw-amqp");
const cache = @import("kw-cache");
const protocol = @import("kw-protocol");
const afk = @import("kwatcher-afk");
pub const drivers = @import("drivers.zig");

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

pub const FallbackConfig = struct {
    driver: drivers.drivers.DriverConfig(),
    afk: afk.config.Config,
    protocols: struct {
        client_registration: protocol.client_registration.Config = .{},
    } = .{},
};

const SingletonDependencies = struct {
    state: ?afk.State = null,

    pub fn stateFac(self: *SingletonDependencies) !*afk.State {
        if (self.state) |*s| {
            return s;
        } else {
            self.state = try .init();
            return &self.state.?;
        }
    }

    pub fn status(config: *afk.config.Config, state: *afk.State) !afk.schema.AfkStatus {
        const time = try afk.timeSinceLastInput(state);
        const s = if (time < config.afk_timeout) afk.schema.AfkStatus.Active else afk.schema.AfkStatus.Inactive;
        return s;
    }
};

var config_slot: FallbackConfig = undefined;

pub fn juicyMain(allocator: std.mem.Allocator) !void {
    // TODO: Extract this to driver?
    if (comptime builtin.os.tag == .linux) {
        var mask = std.posix.sigemptyset();
        std.posix.sigaddset(&mask, std.posix.SIG.INT);
        std.posix.sigaddset(&mask, std.posix.SIG.TERM);
        std.posix.sigprocmask(std.posix.SIG.BLOCK, &mask, null);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try core.metrics.initialize(allocator, "test", "0.0.0", "test", .{});
    defer core.metrics.deinitialize();

    var singleton = SingletonDependencies{};
    defer if (singleton.state) |*s| s.deinit();

    const memcache = cache.context.memory;

    const AfkCache = memcache.Container(memcache.Cache(afk.schema.AfkStatusEntry, .{u8})
        .key(.afk_status)
        .evict(.none)
        .residency(.{ .unlimited = {} })
        .expiration(.{ .unlimited = {} }));

    var c = AfkCache{};

    config_slot = try core.config.findConfigFile(FallbackConfig, arena.allocator(), "afk_v2") orelse {
        std.log.err("Could not load config!", .{});
        return error.MissingConfig;
    };

    const deps = core.deps.DependencyContainer(FallbackConfig)
        .new(drivers.drivers, allocator)
        .with(.all, kwatcher.default.withDefault(&config_slot, .{
            .name = "afk",
            .version = "1.0.0",
        }), allocator)
        .with(.amqp, protocol.deps(drivers.drivers, drivers.Context, drivers.protocols), allocator)
        .with(.all, kwatcher.default.config(afk.config.Config, "afk"), allocator)
        .with(.amqp, amqp.defaultFor(drivers.drivers, drivers.Context), allocator)
        .static(.amqp, &singleton)
        .static(.amqp, &c);

    var server = try kwatcher.server.Server(@TypeOf(deps), drivers.drivers)
        .init(allocator, deps, 2);
    defer server.deinit();

    try server.start();
}

pub fn main() !void {
    if (comptime builtin.mode == .Debug) {
        var gpa = std.heap.GeneralPurposeAllocator(.{
            .stack_trace_frames = 10,
        }).init;
        const allocator = gpa.allocator();
        try juicyMain(allocator);
        _ = gpa.detectLeaks();
    } else {
        const alloc = std.heap.smp_allocator;
        try juicyMain(alloc);
    }
}
