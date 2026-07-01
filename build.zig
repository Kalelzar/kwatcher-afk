const std = @import("std");
const builtin = @import("builtin");
const docgen = @import("kw_docgen").build_docgen;

pub fn build(b: *std.Build) !void {
    // Options
    const build_all = b.option(bool, "all", "Build all components. You can still disable individual components") orelse false;
    const build_exe = b.option(bool, "exe", "Build the application executable") orelse build_all;
    const build_static_library = b.option(bool, "lib", "Build a static library object") orelse build_all;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const kwatcher_afk_library = b.addModule("kwatcher_afk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .linux,
    });

    const kwatcher_afk_exe = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .linux,
    });

    // Artifacts:
    const exe = b.addExecutable(.{
        .name = "kwatcher-afk",
        .root_module = kwatcher_afk_exe,
        .use_llvm = true, // Due to https://github.com/ziglang/zig/issues/24181
    });
    if (build_exe) {
        b.installArtifact(exe);
    }

    const lib = b.addLibrary(.{
        .name = "lib-kwatcher-afk",
        .root_module = kwatcher_afk_library,
        .linkage = .static,
    });
    if (build_static_library) {
        b.installArtifact(lib);
    }

    const tests = b.addTest(.{
        .root_module = kwatcher_afk_library,
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

    // Dependencies:
    // 1st Party:
    const kw_core = b.dependency("kw_core", .{ .target = target, .optimize = optimize }).module("kw-core");
    const kwatcher = b.dependency("kwatcher", .{ .target = target, .optimize = optimize }).module("kwatcher");
    const kw_amqp = b.dependency("kw_amqp", .{ .target = target, .optimize = optimize }).module("kw-amqp");
    const kw_cache = b.dependency("kw_cache", .{ .target = target, .optimize = optimize }).module("kw-cache");
    const kw_cron = b.dependency("kw_cron", .{ .target = target, .optimize = optimize }).module("kw-cron");
    const kw_protocol = b.dependency("kw_protocol", .{ .target = target, .optimize = optimize }).module("kw-protocol");
    const kw_signal = b.dependency("kw_signal", .{ .target = target, .optimize = optimize }).module("kw-signal");
    // 3rd Party:
    // Imports:
    // Internal:
    kwatcher_afk_exe.addImport("kwatcher-afk", kwatcher_afk_library);
    // 1st Party (kwatcher packages, wired into both the exe and library modules):
    inline for (.{ kwatcher_afk_exe, kwatcher_afk_library }) |m| {
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
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxdmcp/aarch64/libXdmcp.so.6.0.0"));
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxau/aarch64/libXau.so.6.0.0"));
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxcb/aarch64/libxcb.a"));
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxcb/aarch64/libxcb-screensaver.a"));
                },
                .x86_64 => {
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxdmcp/x86_64/libXdmcp.so.6.0.0"));
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxau/x86_64/libXau.so.6.0.0"));
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxcb/x86_64/libxcb.a"));
                    kwatcher_afk_library.addObjectFile(b.path("vendor/libxcb/x86_64/libxcb-screensaver.a"));
                },
                else => std.log.warn("Unsupported arch", .{}),
            }
        },
        else => std.log.warn("Afk tracking functionality is currently stubbed on systems other than Windows.", .{}),
    }

    // Docgen: wired after the exe module's imports are in place so the helper can
    // mirror them onto the host-target entrypoint it derives internally. Generates
    // an AsyncAPI doc for the amqp driver; cron has no documentation backend.
    const kw_docgen_none = b.dependency("kw_docgen_none", .{ .target = target, .optimize = optimize }).module("kw-docgen--none");
    const kw_docgen_amqp = b.dependency("kw_docgen_amqp", .{ .target = target, .optimize = optimize }).module("kw-docgen--amqp");

    const docs = docgen.wire(b, .{
        .target = target,
        .optimize = optimize,
        .consumer = kwatcher_afk_exe,
        .backends = &.{
            .{ .kind = "cron", .module = kw_docgen_none },
            .{ .kind = "amqp", .module = kw_docgen_amqp },
            .{ .kind = "internal", .module = kw_docgen_none },
            .{ .kind = "signal", .module = kw_docgen_none },
        },
    });

    exe.step.dependOn(&docs.docgen_step.step);
}
