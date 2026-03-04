const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hpack_mod = b.addModule("hpack", .{
        .root_source_file = b.path("src/hpack.zig"),
        .target = target,
    });

    const example_exe = b.addExecutable(.{
        .name = "h2c-client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/h2c_client.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hpack", .module = hpack_mod },
            },
        }),
    });

    b.installArtifact(example_exe);

    const example_run = b.addRunArtifact(example_exe);
    example_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        example_run.addArgs(args);
    }

    const example_step = b.step("example", "Run the h2c client example");
    example_step.dependOn(&example_run.step);

    const example_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/h2c_client.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hpack", .module = hpack_mod },
            },
        }),
    });

    const run_example_tests = b.addRunArtifact(example_tests);
    const hpack_tests = b.addTest(.{
        .root_module = hpack_mod,
    });
    const run_hpack_tests = b.addRunArtifact(hpack_tests);

    const test_step = b.step("test", "Run project tests");
    test_step.dependOn(&run_hpack_tests.step);
    test_step.dependOn(&run_example_tests.step);
}
