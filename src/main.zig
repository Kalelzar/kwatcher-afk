const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const log = std.log.scoped(.afk);
const core = @import("kw-core");
const kwatcher = @import("kwatcher");
const amqp = @import("kw-amqp");
const cache = @import("kw-cache");
const cron = @import("kw-cron");
const protocol = @import("kw-protocol");
const signal = @import("kw-signal");
const afk = @import("kwatcher-afk");
pub const drivers = @import("drivers.zig");

/// UI-only packages — only wired into ui builds, so the `@import`s must
/// live behind the comptime gate.
const auth_oidc = if (build_options.ui) @import("kw-auth-oidc") else struct {};
const client = if (build_options.ui) @import("kw-http-client") else struct {};

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

/// Only present in ui builds — the introspection mount's cors config. The `@import` in the
/// dead branch is never analyzed, so ui-less builds don't need `kw-http` wired at all.
const MiddlewareConfig = if (build_options.ui) struct {
    cors: @import("kw-http").middleware.Cors.Config = .{ .allowed_origins = &.{} },
} else struct {};

pub const FallbackConfig = struct {
    server: kwatcher.server.Config,
    driver: drivers.drivers.DriverConfig(),
    afk: afk.config.Config,
    middleware: MiddlewareConfig = .{},
    protocols: struct {
        client_registration: protocol.client_registration.Config = .{},
    } = .{},
    /// IntrospectUI-only knobs: the UI is its own application with its own
    /// OIDC client/audience. The section (and its types) only exists in ui
    /// builds — the config parser rejects unknown fields, so the ui-less
    /// config file simply omits it.
    introspect: (if (!build_options.ui) struct {} else struct {
        auth: auth_oidc.Settings = .{
            .well_known = "https://auth.kalelzar.xyz/realms/local/.well-known/openid-configuration",
            .audience = "kw-introspect",
        },
        /// Public OIDC client for the UI's login button (must allow the
        /// `/_introspect/login/callback` redirect). Null hides the button.
        auth_client_id: ?[]const u8 = "kw-introspect",
    }) = .{},
};

/// The private introspection mount's security registries. Static storage
/// (the registered pointers must outlive every request scope), gated on ui
/// builds because the types only exist there. Runtime values are filled
/// from config in juicyMain. afk exposes no application auth schemes, so
/// the scheme/login-client registries stay empty — only the UI's own
/// "introspect" scheme is populated.
const IntrospectSecurity = if (build_options.ui) struct {
    const security = @import("kw-introspect").security;
    var auth_schemes: security.AuthSchemesCtx = .{};
    var login_clients: security.LoginClientsCtx = .{};
    var ui_auth: security.UiAuthCtx = .{ .ui = .{
        .scheme = .{ .name = "introspect", .well_known = "" },
        .client_id = null,
    } };
} else struct {};

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
    // Block the signals owned by the signal driver process-wide BEFORE any
    // thread spawns, so every runtime thread inherits the block and the
    // driver's dedicated sigtimedwait thread is their sole consumer. The
    // mask is derived from the driver's routes, so it can never drift.
    if (comptime builtin.os.tag == .linux) {
        signal.blockRouted(drivers.signal_routes);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try core.metrics.initialize(allocator, "afk", "1.0.0", "afk", .{});
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

    // The ui build reads its own config (with the private mount + cors + introspect
    // sections); the config parser rejects unknown fields, so the two variants use
    // separate files.
    const config_name = if (build_options.ui) "afk_v2.debug" else "afk_v2";
    config_slot = try core.config.findConfigFile(FallbackConfig, arena.allocator(), config_name) orelse {
        std.log.err("Could not load config!", .{});
        return error.MissingConfig;
    };

    // The shared route context: the OIDC egress fragment resolves its
    // discovery path off it (filled from config before anything runs).
    var ctx: drivers.Context = .{};
    defer ctx.deinit(allocator);
    // The OIDC discovery/JWKS store: written only by the egress driver,
    // read by the introspect mount's verification middleware.
    var oidc_store = if (comptime build_options.ui) auth_oidc.DiscoveryStoreCtx{} else {};
    if (comptime build_options.ui) {
        oidc_store.store.alloc = allocator;
        ctx.oidc.well_known_path = auth_oidc.egress.pathOf(config_slot.introspect.auth.well_known);
    }

    const base_deps = core.deps.DependencyContainer(FallbackConfig)
        .new(drivers.drivers, allocator)
        .with(.all, kwatcher.default.withDefault(&config_slot, .{
            .name = "afk",
            .version = "1.0.0",
        }), allocator)
        .with(.amqp, protocol.deps(drivers.drivers, drivers.Context, drivers.protocols), allocator)
        .with(.amqp, amqp.defaultFor(drivers.drivers, drivers.Context), allocator)
        .with(.all, kwatcher.default.config(afk.config.Config, "afk"), allocator)
        .with(.all, kwatcher.default.config(kwatcher.server.Config, "server"), allocator);

    // The type-erased cron scheduler shim (drives the Timers tab) and the OIDC
    // egress driver's config/transport plus the egress scheduler shim bridge the
    // packaged refresh timer resolves. `cron.defaultFor` has no docgen/ui gate of
    // its own, so everything is gated here rather than relying on the mount's
    // no-op behaviour.
    const with_egress = if (comptime build_options.ui)
        base_deps
            .with(.cron, cron.defaultFor(drivers.drivers), allocator)
            .with(.oidc, client.defaultFor(drivers.drivers, drivers.Context), allocator)
            .with(.oidc, auth_oidc.egress.deps(drivers.drivers), allocator)
            .static(.all, &oidc_store)
    else
        base_deps;

    // The app statics come AFTER every defaultFor: static resolution is
    // last-registration-wins per type, and each driver's defaultFor carries
    // its own default-constructed Context — the app's `ctx` (with the OIDC
    // discovery path filled in) must shadow those, not the other way around.
    const with_statics = with_egress
        .static(.all, &ctx)
        .static(.amqp, &singleton)
        .static(.amqp, &c);

    const with_mount = if (comptime build_options.ui)
        with_statics.with(.private, drivers.introspection.deps, allocator)
    else
        with_statics;

    // The private mount enforces the UI's own "introspect" scheme and carries
    // the scheme/login-client registries the Auth tab and login flows read.
    // Gated harder than the mount deps: during docgen the `.private` category
    // does not exist, and `.static` has no internal no-op.
    const deps = if (comptime build_options.ui and !drivers.is_docgen) blk: {
        IntrospectSecurity.ui_auth.ui.scheme.well_known = config_slot.introspect.auth.well_known;
        IntrospectSecurity.ui_auth.ui.client_id = config_slot.introspect.auth_client_id;

        break :blk with_mount
            .with(.private, auth_oidc.extension("introspect.auth"), allocator)
            .static(.private, &IntrospectSecurity.auth_schemes)
            .static(.private, &IntrospectSecurity.login_clients)
            .static(.private, &IntrospectSecurity.ui_auth);
    } else with_mount;

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
