const std = @import("std");
const builtin = @import("builtin");

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
    });

    const kwatcher_afk_exe = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Artifacts:
    const exe = b.addExecutable(.{
        .name = "kwatcher-afk",
        .root_module = kwatcher_afk_exe,
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
    const kw = b.dependency("kwatcher", .{
        .target = target,
        .optimize = optimize,
        .lib = true,
        .example = false,
        .dump = false,
    });
    const kwatcher = kw.module("kwatcher");
    // 3rd Party:
    // Imports:
    // Internal:
    kwatcher_afk_exe.addImport("kwatcher", kwatcher);
    kwatcher_afk_exe.addImport("kwatcher-afk", kwatcher_afk_library);
    // 1st Party:
    kwatcher_afk_library.addImport("kwatcher", kwatcher);
    // 3rd Party:
    switch (builtin.target.os.tag) {
        .windows => {
            kwatcher_afk_library.linkSystemLibrary("user32", .{ .preferred_link_mode = .dynamic });
        },
        else => std.log.warn("Afk tracking functionality is currently stubbed on systems other than Windows.", .{}),
    }
}
