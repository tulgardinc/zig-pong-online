const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig14test",
        .root_module = exe_mod,
    });

    const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
    const raylib = raylib_dep.artifact("raylib");

    exe.linkLibrary(raylib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

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
