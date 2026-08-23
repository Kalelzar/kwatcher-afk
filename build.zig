const std = @import("std");
const builtin = @import("builtin");
const docgen = @import("kw_docgen").build_docgen;
const http_template = @import("kw_http_template").build_templates;
const zettel = @import("zettel");

const App = struct {
    exe_mod: *std.Build.Module,
    lib_mod: *std.Build.Module,
};

/// Build the app module graph (library + exe) for the given target. Called once for the
/// installed target and, on cross builds, a second time for the build host so the docgen
/// generators have a host-runnable copy of the app to introspect. Only the primary call
/// may expose the public "kwatcher_afk" module (`expose_lib`).
fn wireApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ui: bool,
    build_options: *std.Build.Module,
    expose_lib: bool,
    check_step: ?*std.Build.Step,
) App {
    const lib_opts = std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .linux,
    };
    const lib_mod = if (expose_lib)
        b.addModule("kwatcher_afk", lib_opts)
    else
        b.createModule(lib_opts);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .linux,
    });

    // Dependencies:
    // 1st Party:
    const kw_core_dep = b.dependency("kw_core", .{ .target = target, .optimize = optimize });
    const kw_core = kw_core_dep.module("kw-core");
    const kwatcher = b.dependency("kwatcher", .{ .target = target, .optimize = optimize }).module("kwatcher");
    const kw_amqp = b.dependency("kw_amqp", .{ .target = target, .optimize = optimize }).module("kw-amqp");
    const kw_cache = b.dependency("kw_cache", .{ .target = target, .optimize = optimize }).module("kw-cache");
    const kw_cron = b.dependency("kw_cron", .{ .target = target, .optimize = optimize }).module("kw-cron");
    const kw_protocol = b.dependency("kw_protocol", .{ .target = target, .optimize = optimize }).module("kw-protocol");
    const kw_signal = b.dependency("kw_signal", .{ .target = target, .optimize = optimize }).module("kw-signal");
    // Imports:
    // Internal:
    exe_mod.addImport("kwatcher-afk", lib_mod);
    // The entrypoint copy is built explicitly (not derived), so the options module must be
    // wired here rather than relying on `deriveEntrypoint`'s import mirroring.
    exe_mod.addImport("build_options", build_options);
    // zettel schema codegen: schema/afk.ztl -> the afk-schema module,
    // compiled against kw-core's schema sources via --import so the whole
    // tree shares one Context/ZettelError.
    // Debug for build speed: the schema compiler runs in ~50ms on these
    // inputs, while a ReleaseSafe build of it costs ~50s of LLVM at the
    // head of the build graph — and must stay in lockstep with kw-core's
    // zettel dependency so the two instantiations dedup into one.
    const zettel_dep = b.dependency("zettel", .{ .optimize = .Debug });
    const core_schema = zettel.SchemaImport{
        .name = "kw-core-schema",
        .dir = kw_core_dep.namedLazyPath("schema-dir"),
        .module = kw_core_dep.module("kw-core-schema"),
    };
    const afk_schema = zettel.schemaModule(b, zettel_dep, .{
        .source_dir = b.path("schema"),
        .root_module = "kwatcher:afk",
        .imports = &.{core_schema},
        .check_step = check_step,
        .target = target,
        .optimize = optimize,
    });
    // 1st Party (kwatcher packages, wired into both the exe and library modules):
    inline for (.{ exe_mod, lib_mod }) |m| {
        m.addImport("kw-core", kw_core);
        m.addImport("kwatcher", kwatcher);
        m.addImport("kw-amqp", kw_amqp);
        m.addImport("kw-cache", kw_cache);
        m.addImport("kw-cron", kw_cron);
        m.addImport("kw-protocol", kw_protocol);
        m.addImport("kw-signal", kw_signal);
        m.addImport("afk-schema", afk_schema);
    }
    // 3rd Party: the whole X stack links statically (libxcb + its Xau/Xdmcp
    // auth deps) — shared objects would break static-linking targets (the CI
    // container is musl) and drag runtime .so dependencies into the binary.
    switch (target.result.os.tag) {
        .windows => {},
        .linux => {
            switch (target.result.cpu.arch) {
                .aarch64 => {
                    lib_mod.addObjectFile(b.path("vendor/libxdmcp/aarch64/libXdmcp.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxau/aarch64/libXau.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxcb/aarch64/libxcb.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxcb/aarch64/libxcb-screensaver.a"));
                },
                .x86_64 => {
                    lib_mod.addObjectFile(b.path("vendor/libxdmcp/x86_64/libXdmcp.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxau/x86_64/libXau.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxcb/x86_64/libxcb.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxcb/x86_64/libxcb-screensaver.a"));
                },
                else => std.log.warn("Unsupported arch", .{}),
            }
        },
        else => std.log.warn("Afk tracking functionality is currently stubbed on systems other than Windows.", .{}),
    }

    if (ui) {
        // Runtime-facing introspection UI modules: the generic core, the HTTP backend that
        // renders the UI itself, and the cron backend for the Timers tab.
        const kw_docgen_dep = b.dependency("kw_docgen", .{ .target = target, .optimize = optimize });
        const kw_docgen_http_dep = b.dependency("kw_docgen_http", .{ .target = target, .optimize = optimize });
        const kw_docgen_cron_dep = b.dependency("kw_docgen_cron", .{ .target = target, .optimize = optimize });
        const kw_http = b.dependency("kw_http", .{ .target = target, .optimize = optimize }).module("kw-http");
        // The introspect mount's OIDC verification: the auth-oidc middleware
        // plus the http-client egress driver that feeds its discovery store.
        const kw_auth_oidc = b.dependency("kw_auth_oidc", .{ .target = target, .optimize = optimize }).module("kw-auth-oidc");
        const kw_http_client = b.dependency("kw_http_client", .{ .target = target, .optimize = optimize }).module("kw-http-client");
        const kw_introspect = kw_docgen_dep.module("kw-introspect");
        const kw_introspect_http = kw_docgen_http_dep.module("kw-introspect--http");
        const kw_introspect_cron = kw_docgen_cron_dep.module("kw-introspect--cron");

        // One shared zmpl-backed template module covering every contributing package's
        // templates, so all `WithTemplates` lookups (core + http + cron prefixes) resolve.
        const kw_http_template = http_template.wire(b, .{
            .target = target,
            .optimize = optimize,
            .sources = &.{
                http_template.packageSource(kw_docgen_dep, "core", &.{"templates"}),
                http_template.packageSource(kw_docgen_http_dep, "http", &.{"templates"}),
                http_template.packageSource(kw_docgen_cron_dep, "cron", &.{"templates"}),
            },
        });
        kw_introspect.addImport("kw-http-template", kw_http_template);
        kw_introspect_http.addImport("kw-http-template", kw_http_template);
        kw_introspect_cron.addImport("kw-http-template", kw_http_template);

        exe_mod.addImport("kw-http", kw_http);
        exe_mod.addImport("kw-auth-oidc", kw_auth_oidc);
        exe_mod.addImport("kw-http-client", kw_http_client);
        exe_mod.addImport("kw-introspect", kw_introspect);
        exe_mod.addImport("kw-introspect--http", kw_introspect_http);
        exe_mod.addImport("kw-introspect--cron", kw_introspect_cron);
    }

    return .{ .exe_mod = exe_mod, .lib_mod = lib_mod };
}

pub fn build(b: *std.Build) !void {
    // Options
    const build_all = b.option(bool, "all", "Build all components. You can still disable individual components") orelse false;
    const build_exe = b.option(bool, "exe", "Build the application executable") orelse build_all;
    const build_static_library = b.option(bool, "lib", "Build a static library object") orelse build_all;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ui = b.option(bool, "ui", "Build the private introspection UI into the binary") orelse (optimize == .Debug);

    const opts = b.addOptions();
    opts.addOption(bool, "ui", ui);
    const build_options = opts.createModule();

    // Created before wireApp so the zettel schema check can hang off it;
    // the artifact dependencies are attached below.
    const check = b.step("check", "Build without generating artifacts.");

    const app = wireApp(b, target, optimize, ui, build_options, true, check);

    // Artifacts:
    const exe = b.addExecutable(.{
        .name = "kwatcher-afk",
        .root_module = app.exe_mod,
        .use_llvm = true, // Due to https://github.com/ziglang/zig/issues/24181
    });
    if (build_exe) {
        b.installArtifact(exe);
    }

    const lib = b.addLibrary(.{
        .name = "lib-kwatcher-afk",
        .root_module = app.lib_mod,
        .linkage = .static,
    });
    if (build_static_library) {
        b.installArtifact(lib);
    }

    const tests = b.addTest(.{
        .root_module = app.lib_mod,
        .use_llvm = true, // Due to https://github.com/ziglang/zig/issues/24181
    });

    const run_tests = b.addRunArtifact(tests);

    const install_docs = b.addInstallDirectory(
        .{
            .source_dir = lib.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        },
    );

    const fmt = b.addFmt(.{
        .paths = &.{
            "src/",
            "build.zig",
            "build.zig.zon",
        },
        .check = true,
    });

    // Steps:
    check.dependOn(&lib.step);
    check.dependOn(&exe.step);

    const test_step = b.step("test", "Run the unit tests.");
    test_step.dependOn(&run_tests.step);
    // - fmt
    const fmt_step = b.step("fmt", "Check formatting");
    fmt_step.dependOn(&fmt.step);
    check.dependOn(fmt_step);
    b.getInstallStep().dependOn(fmt_step);
    // - docs
    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&install_docs.step);
    docs_step.dependOn(&lib.step);

    // Docgen generator graph. The generators run on the build host and `@import` the app to
    // introspect its drivers, so everything they compile against must be host-runnable. When
    // building natively the installed app graph already satisfies that and `docgen.wire`
    // derives the entrypoint from it; for any `-Dtarget`/`-Dcpu` override a dedicated host
    // copy of the app (and host-target backends) is built purely for the generators.
    const native = target.query.isNative();
    const gen_target = if (native) target else b.graph.host;

    const kw_docgen_amqp = b.dependency("kw_docgen_amqp", .{ .target = gen_target, .optimize = optimize }).module("kw-docgen--amqp");
    const kw_docgen_cron = b.dependency("kw_docgen_cron", .{ .target = gen_target, .optimize = optimize }).module("kw-docgen--cron");

    const entrypoint: ?*std.Build.Module = if (native)
        null
    else
        wireApp(b, b.graph.host, optimize, ui, build_options, false, null).exe_mod;

    const docs = docgen.wire(b, .{
        .target = gen_target,
        .optimize = optimize,
        .consumer = app.exe_mod,
        .entrypoint = entrypoint,
        // Kinds without a backend entry (internal, signal) are skipped by the
        // generator — no placeholder backends needed.
        .backends = &.{
            .{ .kind = "cron", .module = kw_docgen_cron },
            .{ .kind = "amqp", .module = kw_docgen_amqp },
        },
    });

    exe.step.dependOn(&docs.docgen_step.step);

    // The docgen-package test suite compiles the whole app graph; it used to
    // gate the generator exe serially, now it runs as a parallel sibling and
    // still fails the build on regression.
    b.getInstallStep().dependOn(docs.docgen_tests);

    // ZPack layout locking (zettel's ZPACK.md §9): ztl-lock-all / ztl-lock
    // -Dschema=name:version / ztl-verify. The last is the pre-push gate —
    // it fails when a locked schema's wire layout drifts from zettel.lock
    // or a schema version is unlocked. kw-core's schemas are foreign here
    // and stay kw-core's to lock.
    const zettel_dep = b.dependency("zettel", .{ .optimize = .Debug });
    const kw_core_dep = b.dependency("kw_core", .{ .target = target, .optimize = optimize });
    zettel.addLockSteps(b, zettel_dep, .{
        .source_dir = b.path("schema"),
        .root_module = "kwatcher:afk",
        .imports = &.{.{
            .name = "kw-core-schema",
            .dir = kw_core_dep.namedLazyPath("schema-dir"),
            .module = kw_core_dep.module("kw-core-schema"),
        }},
    });
}
