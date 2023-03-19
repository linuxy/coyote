const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const iwnet = build_iwnet(b);

    const exe = b.addExecutable(.{
        .root_source_file = .{ .path = "examples/coyote_template.zig"},
        .optimize = optimize,
        .target = target,
        .name = "example_template",
    });

    exe.addAnonymousModule("mustache", .{ 
        .source_file = .{ .path = "./vendor/mustache/src/mustache.zig" },
    });

    exe.addAnonymousModule("iwnet", .{ 
        .source_file = .{ .path = "./vendor/iwnet.zig" },
    });

    exe.addAnonymousModule("zq", .{ 
        .source_file = .{ .path = "./vendor/zq/src/zq.zig" },
    });

    const zig_iwnet = b.createModule(.{ .source_file = .{ .path = "./vendor/iwnet.zig" } });
    const zig_mustache = b.createModule(.{ .source_file = .{ .path = "./vendor/mustache/src/mustache.zig" } });
    const zig_zq = b.createModule(.{ .source_file = .{ .path = "./vendor/zq/src/zq.zig" } });

    exe.addAnonymousModule("coyote", .{ 
        .source_file = .{ .path = "./src/coyote.zig" },
        .dependencies = &[_]std.Build.ModuleDependency {
            .{ .name = "iwnet", .module = zig_iwnet },
            .{ .name = "mustache", .module = zig_mustache },
            .{ .name = "zq", .module = zig_zq },
        },
    });

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
