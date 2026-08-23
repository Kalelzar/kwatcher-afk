const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const core = @import("kw-core");
const amqp = @import("kw-amqp");
const cron = @import("kw-cron");
const signal = @import("kw-signal");
const protocol = @import("kw-protocol");
const amqp_routes = @import("route.zig");
const cron_routes = @import("timers.zig");

/// UI-only packages — the modules are only wired into ui builds, so the
/// `@import`s must live behind the comptime gate.
const auth_oidc = if (build_options.ui) @import("kw-auth-oidc") else struct {};
const client = if (build_options.ui) @import("kw-http-client") else struct {};

/// True while the docgen generator introspects the app: the `.private`
/// category (and its statics) must not be registered then.
pub const is_docgen = @import("kw-gen--docs").isDocgen;

pub const Context = struct {
    id: u64 = 0,
    client: protocol.client_registration.registry = .{
        .assigned_id = null,
        .state = .unregistered,
    },
    /// OIDC egress fragment: the spread segment in `auth_oidc.egress.Routes`
    /// resolves `oidc.well_known_path` (filled from config at startup).
    oidc: (if (build_options.ui) auth_oidc.egress.Context else struct {}) = .{},

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

const base_cron_routes = core.meta.flatten(
    &.{
        cron.From(cron_routes),
        protocol.use(
            cron,
            protocols,
            Context,
        ),
        cron.From(amqp.Replay),
    },
);

const cron_driver = cron.Driver
    .new(.cron)
    .listen(true)
    .jobs(1)
    // The packaged discovery/JWKS refresh rides along in ui builds (it
    // requires the egress scheduler shim bridge — `auth_oidc.egress.deps`
    // in main.zig).
    .routes(if (build_options.ui)
        base_cron_routes ++ cron.From(auth_oidc.Timers)
    else
        base_cron_routes)
    .build();

/// Hoisted so the driver and the process-wide block mask
/// (`signal.blockRouted` in `juicyMain`) share one source of truth.
pub const signal_routes = signal.From(signal.default.Shutdown);

const signal_driver = signal.Driver
    .new(.signal)
    .listen(true)
    .jobs(1)
    .routes(signal_routes)
    .build();

/// The OIDC egress driver: discovery + JWKS fetches as recorded events
/// feeding the process-wide DiscoveryStore the verification middleware
/// reads (see `auth_oidc.egress`). One job — the IdP is low-traffic.
/// UI-only: the private introspect mount is afk's only authed surface.
const oidc_driver = if (build_options.ui) client.Driver
    .new(.oidc)
    .config("driver.oidc")
    .listen(true)
    .jobs(1)
    .routes(client.From(auth_oidc.egress.Routes, Context))
    .error_handler(client.DefaultErrorHandler)
    .build() else {};

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
/// branch only, so ui-less builds need none of those modules wired. Every inner route
/// (fragments, actions, renderers) goes behind the OIDC bearer middleware via the
/// "introspect" scheme; shells and the login flows stay open.
pub const introspection = if (build_options.ui)
    @import("kw-introspect").MountWith(
        @import("kw-gen--docs"),
        .{ @import("kw-introspect--http"), @import("kw-introspect--cron") },
        .{ .auth = "introspect" },
    )
else
    NoopMount;

const base_lifecycle = core.meta.flatten(&.{
    // Boot scan of the kwev recordings for unrouted events to replay.
    core.lifecycle.From(amqp.ReplayLifecycle),
    protocol.use(
        struct {
            pub const kind = .internal;
        },
        protocols,
        Context,
    ),
});

const base_registry = core.DriverRegistry
    .new()
    .client(core.schema.Client.V1{ .name = "afk", .version = "1.0.0" })
    // The packaged OIDC warm-up (ui builds) cold-starts the discovery/JWKS
    // chain on START instead of waiting for the first cron refresh.
    .lifecycle(if (build_options.ui)
        base_lifecycle ++ core.lifecycle.From(auth_oidc.Lifecycle)
    else
        base_lifecycle)
    .registerHandler(cron_driver)
    .registerHandler(amqp_driver);

// The signal driver is POSIX-only: its listener thread is a sigtimedwait
// loop, which nothing outside linux can serve. Registering it is what
// instantiates that loop, so gating the registration keeps it out of
// non-linux binaries while the routes above stay declared either way.
const with_signal = if (builtin.os.tag == .linux)
    base_registry.registerHandler(signal_driver)
else
    base_registry;

const with_oidc = if (build_options.ui)
    with_signal.registerHandler(oidc_driver)
else
    with_signal;

// The private introspection mount is appended only in ui runtime builds, not during
// docgen (the UI is generated *from* the docs); `register` handles the docgen gating.
pub const drivers = introspection.register(with_oidc);

pub const Scheduler = drivers.SchedulerMap();
