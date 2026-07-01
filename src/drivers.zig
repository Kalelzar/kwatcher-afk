const std = @import("std");
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

pub const drivers = core.DriverRegistry
    .new()
    .registerHandler(cron_driver)
    .registerHandler(amqp_driver)
    .registerHandler(signal_driver);

pub const Scheduler = drivers.SchedulerMap();
