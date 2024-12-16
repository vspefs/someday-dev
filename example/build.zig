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

    const sdl3_p = try someday.addCMakePackage(.{
        .build_as = "sdl3",
        .builder = b,
        .profile = &profile,
        .path = try someday.PackagePath.fromDependency(b.dependency("sdl3", .{})),
    });

    const sdl3 = b.addTranslateC(.{
        .link_libc = true,
        .optimize = optimize,
        .root_source_file = sdl3_p.include_path.path(b, "SDL3/SDL.h"),
        .target = target,
    });
    sdl3.addIncludePath(sdl3_p.include_path);

    const exe = b.addExecutable(.{
        .name = "dev",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });
    exe.root_module.addImport("sdl3", sdl3.createModule());
    exe.addLibraryPath(sdl3_p.library_path);
    exe.linkSystemLibrary2("SDL3", .{
        .weak = false,
        .search_strategy = .no_fallback,
        .needed = true,
        .preferred_link_mode = .dynamic,
    });
    sdl3.step.dependOn(sdl3_p.step);
    b.installArtifact(exe);
}
