const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_dep = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    const sqlite_mod = sqlite_dep.module("sqlite");

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/framework.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("sqlite", sqlite_mod);
    lib_mod.link_libc = true;

    _ = b.addModule("zig-server", .{
        .root_source_file = b.path("src/framework.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zig-server",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("sqlite", sqlite_mod);
    exe_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_cmd.step);

    const examples = [_]struct { name: []const u8, path: []const u8, needs_sqlite: bool }{
        .{ .name = "ex-resource",      .path = "examples/01_resource.zig",        .needs_sqlite = false },
        .{ .name = "ex-mount",         .path = "examples/02_mount.zig",           .needs_sqlite = false },
        .{ .name = "ex-middleware",    .path = "examples/03_middleware.zig",      .needs_sqlite = false },
        .{ .name = "ex-cors",          .path = "examples/04_cors.zig",            .needs_sqlite = false },
        .{ .name = "ex-rate-limit",   .path = "examples/05_rate_limit.zig",      .needs_sqlite = false },
        .{ .name = "ex-version",       .path = "examples/06_version.zig",         .needs_sqlite = false },
        .{ .name = "ex-comprehensive", .path = "examples/07_comprehensive.zig",   .needs_sqlite = false },
        .{ .name = "ex-path-patterns", .path = "examples/08_path_patterns.zig",   .needs_sqlite = false },
        .{ .name = "ex-reverse-routing", .path = "examples/09_reverse_routing.zig", .needs_sqlite = false },
        .{ .name = "ex-custom-matchers", .path = "examples/10_custom_matchers.zig", .needs_sqlite = false },
        .{ .name = "ex-global-middleware", .path = "examples/11_global_middleware.zig", .needs_sqlite = false },
        .{ .name = "ex-openapi",       .path = "examples/12_openapi_swagger.zig", .needs_sqlite = false },
        .{ .name = "ex-context",       .path = "examples/13_context_responses.zig", .needs_sqlite = false },
        .{ .name = "ex-db",            .path = "examples/14_db.zig",              .needs_sqlite = true },
        .{ .name = "ex-server",        .path = "examples/15_server.zig",          .needs_sqlite = false },
        .{ .name = "ex-cookies-form",  .path = "examples/16_cookies_form.zig",   .needs_sqlite = false },
    };
    inline for (examples) |ex| {
        const ex_mod = b.createModule(.{
            .root_source_file = b.path(ex.path),
            .target = target,
            .optimize = optimize,
        });
        ex_mod.addImport("zig-server", lib_mod);
        if (ex.needs_sqlite) {
            ex_mod.addImport("sqlite", sqlite_mod);
            ex_mod.link_libc = true;
        }
        const ex_exe = b.addExecutable(.{
            .name = ex.name,
            .root_module = ex_mod,
        });
        b.installArtifact(ex_exe);
        const run_ex = b.addRunArtifact(ex_exe);
        const step = b.step(ex.name, "Run " ++ ex.path);
        step.dependOn(&run_ex.step);
    }

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("sqlite", sqlite_mod);
    test_mod.link_libc = true;

    const test_exe = b.addTest(.{
        .root_module = test_mod,
    });

    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}
