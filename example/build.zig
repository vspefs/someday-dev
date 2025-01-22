pub fn build(b: *std.Build) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) @panic("memory leak!");

    const alloc = gpa.allocator();

    var config = try someday.Config.init(alloc, b.dependency("someday", .{}));
    defer config.deinit();

    var profile = try someday.Profile.init(.{
        .config = &config,
        .parallel_jobs = 12,
        .usage = .{
            .cmake = .someday,
            .ninja = .someday,
            .toolchain = .zig,
        },
    });
    defer profile.deinit();

    var sdl3 = try someday.CMakePackage.init(.{
        .build_name = "sdl3",
        .profile = &profile,
        .path = try someday.PackagePath.fromDependency(b.dependency("sdl3", .{})),
        .builder = b,
    });
    defer sdl3.build();

    try sdl3.cache.put("CMAKE_BUILD_TYPE", .{ .type = .string, .value = "Release" });

    const mod = b.createModule(.{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .link_libcpp = true,
    });
    mod.addCSourceFile(.{ .file = b.path("src/main.cpp") });

    const exe = b.addExecutable(.{
        .name = "exe",
        .root_module = mod,
    });

    someday.linkLibraryFrom(sdl3, exe, .{
        .name = "SDL3",
        .preferred_link_mode = .dynamic,
    });
    someday.includeHeadersFrom(sdl3, exe);

    const run = b.addRunArtifact(exe);
    const step = b.step("run", "");
    step.dependOn(&run.step);
}

const std = @import("std");
const someday = @import("someday");
