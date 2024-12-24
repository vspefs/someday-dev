const std = @import("std");
const someday = @import("someday");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var config = try someday.Config.init(b.allocator, b.dependency("someday", .{}).builder);
    try config.buildCMake(12);
    try config.buildNinja(12);

    var profile = try someday.Profile.init(.{
        .parallel_jobs = 12,
        .config = &config,
        .use_system_cmake = false,
        .use_system_toolchain = true,
        .use_system_ninja = false,
    });

    const sdl3_package = try someday.addCMakePackage(.{
        .build_as = "sdl3",
        .builder = b,
        .profile = &profile,
        .path = try someday.PackagePath.fromDependency(b.dependency("sdl3", .{})),
    });

    const exe = b.addExecutable(.{
        .name = "someday-example",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    exe.root_module.addImport("sdl3", someday.createModuleFrom(sdl3_package, .{
        .builder = b,
        .include_path = "SDL3/SDL.h",
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    }));
    someday.linkLibraryFrom(sdl3_package, exe, &.{.{
        .name = "SDL3",
        .preferred_link_mode = .dynamic,
    }});
    b.installArtifact(exe);

    const cpp = b.addExecutable(.{
        .name = "someday-example-cpp",
        .optimize = optimize,
        .target = target,
    });

    cpp.linkLibCpp();
    cpp.addCSourceFile(.{
        .file = b.path("src/main.cpp"),
        .flags = &.{"-std=c++26"},
    });
    someday.includeHeadersFrom(sdl3_package, cpp);
    someday.linkLibraryFrom(sdl3_package, cpp, &.{.{
        .name = "SDL3",
        .preferred_link_mode = .dynamic,
    }});
    b.installArtifact(cpp);
}
