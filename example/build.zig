const std = @import("std");
const someday = @import("someday");

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var config = try someday.Config.init(alloc, b.dependency("someday", .{}).builder);
    defer config.deinit();
    try config.buildCMake(12);
    try config.buildNinja(12);

    var profile = try someday.Profile.init(.{
        .parallel_jobs = 12,
        .config = &config,
        .use_system_toolchain = true,
        .use_system_cmake = false,
        .use_system_ninja = false,
    });
    defer profile.deinit();

    const sdl3 = try someday.addCMakePackage(.{
        .profile = &profile,
        .builder = b,
        .header_name = "SDL3/SDL.h",
        .lib_name = "SDL3",
        .path = b.path("deps/sdl3/"),
    });

    const exe = b.addExecutable(.{
        .name = "dev",
        .optimize = .Debug,
        .target = b.host,
        .root_source_file = b.path("src/main.zig"),
    });
    exe.root_module.addImport("sdl3", sdl3);
    b.installArtifact(exe);
}
