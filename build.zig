const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const server_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/server_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const client_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/client_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_exe = b.addExecutable(.{
        .name = "pongserver",
        .root_module = server_exe_mod,
    });

    const client_exe = b.addExecutable(.{
        .name = "pong",
        .root_module = client_exe_mod,
    });

    const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
    const raylib = raylib_dep.artifact("raylib");

    server_exe.linkLibrary(raylib);
    b.installArtifact(server_exe);

    client_exe.linkLibrary(raylib);
    if (target.result.os.tag == .windows) {
        client_exe.subsystem = .Windows;
    }
    b.installArtifact(client_exe);

    const run_cmd = b.addRunArtifact(client_exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_exe = b.addTest(
        .{
            .name = "zigtest",
            .root_module = b.createModule(
                .{
                    .root_source_file = b.path("src/serializer.zig"),
                    .target = target,
                    .optimize = optimize,
                },
            ),
            .filters = b.args orelse &.{},
        },
    );

    test_exe.linkLibrary(raylib);
    test_exe.linkLibC();

    const run_test = b.addRunArtifact(test_exe);

    if (b.args) |args| {
        run_test.addArgs(args);
    }

    const test_step = b.step("test", "test the app");
    test_step.dependOn(&run_test.step);
}
