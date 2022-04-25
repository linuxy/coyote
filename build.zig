const std = @import("std");

const pkgs = struct {
    const jinja = std.build.Pkg{
        .name = "jinja",
        .path = .{ .path = "./vendor/jinja2.zig" },
    };
    const iwnet = std.build.Pkg{
        .name = "iwnet",
        .path = .{ .path = "./vendor/iwnet.zig" },
    };
    const coyote = std.build.Pkg{
        .name = "coyote",
        .path = .{ .path = "./src/coyote.zig" },
        .dependencies = &[_]std.build.Pkg{ pkgs.iwnet, pkgs.jinja },
    };
};

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("echo", "examples/coyote_template.zig");
    exe.setBuildMode(mode);
    exe.addPackage(pkgs.jinja);
    exe.addPackage(pkgs.iwnet);
    exe.addPackage(pkgs.coyote);
    exe.addIncludeDir("/usr/include/python3.9");
    exe.linkSystemLibrary("python3.9");

    exe.addLibraryPath("./vendor/iwnet/build/src");
    exe.addLibraryPath("./vendor/iwnet/build/lib");
    exe.linkSystemLibrary("iwnet-1");
    exe.linkSystemLibrary("iowow-1");

    exe.linkLibC();
    exe.install();
}
