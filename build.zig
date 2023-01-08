const std = @import("std");

const pkgs = struct {
    const mustache = std.build.Pkg{
        .name = "mustache",
        .source = .{ .path = "./vendor/mustache/src/mustache.zig" },
    };
    const iwnet = std.build.Pkg{
        .name = "iwnet",
        .source = .{ .path = "./vendor/iwnet.zig" },
    };
    const zq = std.build.Pkg{
        .name = "zq",
        .source = .{ .path = "./vendor/zq/src/zq.zig" },
    };
    const coyote = std.build.Pkg{
        .name = "coyote",
        .source = .{ .path = "./src/coyote.zig" },
        .dependencies = &[_]std.build.Pkg{ pkgs.iwnet, pkgs.mustache, pkgs.zq },
    };
};

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const iwnet = build_iwnet(b);

    const exe = b.addExecutable("example_template", "examples/coyote_template.zig");
    exe.setBuildMode(mode);
    exe.addPackage(pkgs.mustache);
    exe.addPackage(pkgs.iwnet);
    exe.addPackage(pkgs.zq);
    exe.addPackage(pkgs.coyote);

    exe.addLibraryPath("./vendor/iwnet/build/src");
    exe.addLibraryPath("./vendor/iwnet/build/lib");
    exe.addLibraryPath("./vendor/iwnet/build/lib64");
    exe.linkSystemLibrary("iwnet-1");
    exe.linkSystemLibrary("iowow-1");

    exe.linkLibC();
    exe.install();

    const make_step = b.step("iwnet", "Make iwnet libraries");
    make_step.dependOn(&iwnet.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn build_iwnet(b: *std.build.Builder) *std.build.RunStep {
    const mkdir = b.addSystemCommand(
        &[_][]const u8{
            "mkdir",
            "-p",
            "./vendor/iwnet/build",
        },
    );
    const cmake = b.addSystemCommand(
        &[_][]const u8{
            "cmake",
            "-S./vendor/iwnet/",
            "-B./vendor/iwnet/build",
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
        },
    );
    const make = b.addSystemCommand(
        &[_][]const u8{
            "make",
            "-j4",
            "-C./vendor/iwnet/build",
        },
    );
    cmake.step.dependOn(&mkdir.step);
    make.step.dependOn(&cmake.step);
    return make;
}
