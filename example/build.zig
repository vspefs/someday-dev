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
    const sdl3_m = someday.createModuleFrom(sdl3_package, .{
        .builder = b,
        .include_path = "SDL3/SDL.h",
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "someday-example",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });
    exe.root_module.addImport("sdl3", sdl3_m);
    someday.linkPackage(exe, sdl3_package, &.{.{
        .name = "SDL3",
        .preferred_link_mode = .dynamic,
    }});
    b.installArtifact(exe);
}
