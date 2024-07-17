const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const is_root = b.pkg_hash.len == 0;

    const target: Build.ResolvedTarget = if (is_root) b.standardTargetOptions(.{}) else b.resolveTargetQuery(.{});
    const optimize: std.builtin.OptimizeMode = if (is_root) b.standardOptimizeOption(.{}) else .Debug;

    const test_step = b.step("test", "Run all tests.");
    const unit_test_step = b.step("unit-test", "Run unit tests.");

    test_step.dependOn(unit_test_step);

    const inkuery_mod = b.addModule("inkuery", .{
        .root_source_file = b.path("src/inkuery.zig"),
    });
    _ = inkuery_mod;

    const unit_tests_exe = b.addTest(.{
        .root_source_file = b.path("src/inkuery.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (is_root) b.installArtifact(unit_tests_exe);
    const unit_tests_run = b.addRunArtifact(unit_tests_exe);
    unit_test_step.dependOn(&unit_tests_run.step);
}
