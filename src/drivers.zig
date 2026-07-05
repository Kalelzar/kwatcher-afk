const std = @import("std");
const build_options = @import("build_options");
const core = @import("kw-core");
const amqp = @import("kw-amqp");
const cron = @import("kw-cron");
const signal = @import("kw-signal");
const protocol = @import("kw-protocol");
const amqp_routes = @import("route.zig");
const cron_routes = @import("timers.zig");

pub const Context = struct {
    id: u64 = 0,
    client: protocol.client_registration.registry = .{
        .assigned_id = null,
        .state = .unregistered,
    },

    pub fn deinit(self: *Context, alloc: std.mem.Allocator) void {
        if (self.client.assigned_id) |ai| {
            alloc.free(ai);
        }
    }
};

pub const protocols: []const protocol.Kind = &.{.client_registration};

const amqp_driver = amqp.Driver
    .new(.amqp)
    .config("driver.amqp")
    .listen(true)
    .jobs(1)
    .routes(core.meta.flatten(
        &.{
            amqp.From(amqp_routes, Context),
            protocol.use(
                amqp,
                protocols,
                Context,
            ),
        },
    ))
    .build();

const cron_driver = cron.Driver
    .new(.cron)
    .listen(true)
    .jobs(1)
    .routes(core.meta.flatten(
        &.{
            cron.From(cron_routes),
            protocol.use(
                cron,
                protocols,
                Context,
            ),
        },
    ))
    .build();

const signal_driver = signal.Driver
    .new(.signal)
    .listen(true)
    .jobs(1)
    .routes(signal.From(signal.default.Shutdown))
    .build();

/// Stand-in for the introspection mount when the UI is compiled out — mirrors
/// `private_mount.zig`'s `register`/`deps` shape so the wiring below stays unconditional.
const NoopMount = struct {
    pub fn register(comptime base: core.DriverRegistry) core.DriverRegistry {
        return base;
    }

    pub const deps = struct {
        pub fn apply(
            dephub: anytype,
            comptime category: anytype,
            allocator: std.mem.Allocator,
            comptime Config: type,
        ) Return(category, Config, @TypeOf(dephub)) {
            _ = allocator;
            return dephub;
        }

        pub fn Return(comptime category: anytype, comptime Config: type, comptime DH: type) type {
            _ = category;
            _ = Config;
            return DH;
        }
    };
};

/// The private introspection-UI mount (a second `.private` HTTP driver) with the docs
/// manifest and the http/cron backends threaded in. The `@import`s live in the taken
/// branch only, so ui-less builds need none of those modules wired.
pub const introspection = if (build_options.ui)
    @import("kw-introspect").Mount(
        @import("kw-gen--docs"),
        .{ @import("kw-introspect--http"), @import("kw-introspect--cron") },
    )
else
    NoopMount;

const base_registry = core.DriverRegistry
    .new()
    .registerHandler(cron_driver)
    .registerHandler(amqp_driver)
    .registerHandler(signal_driver);

// The private introspection mount is appended only in ui runtime builds, not during
// docgen (the UI is generated *from* the docs); `register` handles the docgen gating.
pub const drivers = introspection.register(base_registry);

pub const Scheduler = drivers.SchedulerMap();
