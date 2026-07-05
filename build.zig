const std = @import("std");
const builtin = @import("builtin");
const docgen = @import("kw_docgen").build_docgen;
const http_template = @import("kw_http_template").build_templates;

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
    const kw_core = b.dependency("kw_core", .{ .target = target, .optimize = optimize }).module("kw-core");
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
    // 1st Party (kwatcher packages, wired into both the exe and library modules):
    inline for (.{ exe_mod, lib_mod }) |m| {
        m.addImport("kw-core", kw_core);
        m.addImport("kwatcher", kwatcher);
        m.addImport("kw-amqp", kw_amqp);
        m.addImport("kw-cache", kw_cache);
        m.addImport("kw-cron", kw_cron);
        m.addImport("kw-protocol", kw_protocol);
        m.addImport("kw-signal", kw_signal);
    }
    // 3rd Party:
    switch (target.result.os.tag) {
        .windows => {},
        .linux => {
            switch (target.result.cpu.arch) {
                .aarch64 => {
                    lib_mod.addObjectFile(b.path("vendor/libxdmcp/aarch64/libXdmcp.so.6.0.0"));
                    lib_mod.addObjectFile(b.path("vendor/libxau/aarch64/libXau.so.6.0.0"));
                    lib_mod.addObjectFile(b.path("vendor/libxcb/aarch64/libxcb.a"));
                    lib_mod.addObjectFile(b.path("vendor/libxcb/aarch64/libxcb-screensaver.a"));
                },
                .x86_64 => {
                    lib_mod.addObjectFile(b.path("vendor/libxdmcp/x86_64/libXdmcp.so.6.0.0"));
                    lib_mod.addObjectFile(b.path("vendor/libxau/x86_64/libXau.so.6.0.0"));
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

    const app = wireApp(b, target, optimize, ui, build_options, true);

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
    const check = b.step("check", "Build without generating artifacts.");
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

    const kw_docgen_none = b.dependency("kw_docgen_none", .{ .target = gen_target, .optimize = optimize }).module("kw-docgen--none");
    const kw_docgen_amqp = b.dependency("kw_docgen_amqp", .{ .target = gen_target, .optimize = optimize }).module("kw-docgen--amqp");
    const kw_docgen_cron = b.dependency("kw_docgen_cron", .{ .target = gen_target, .optimize = optimize }).module("kw-docgen--cron");

    const entrypoint: ?*std.Build.Module = if (native)
        null
    else
        wireApp(b, b.graph.host, optimize, ui, build_options, false).exe_mod;

    const docs = docgen.wire(b, .{
        .target = gen_target,
        .optimize = optimize,
        .consumer = app.exe_mod,
        .entrypoint = entrypoint,
        .backends = &.{
            .{ .kind = "cron", .module = kw_docgen_cron },
            .{ .kind = "amqp", .module = kw_docgen_amqp },
            .{ .kind = "internal", .module = kw_docgen_none },
            .{ .kind = "signal", .module = kw_docgen_none },
        },
    });

    exe.step.dependOn(&docs.docgen_step.step);
}
