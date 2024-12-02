const std = @import("std");
const someday = @import("someday");

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var config = try someday.Config.init(alloc, b.dependency("someday", .{}).builder);
    defer config.deinit();
    try someday.buildCMake(alloc, config);
    try someday.buildNinja(alloc, config);

    const sdl3 = try someday.addCMakePackage(alloc, .{
        .builder = b,
        .config = config,
        .name = "SDL3",
        .header = "SDL3/SDL.h",
        .path = b.path("deps/sdl3/"),
    });

    const exe = b.addExecutable(.{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .name = "someday-dev",
        .root_source_file = b.path("src/main.zig"),
    });
    exe.root_module.addImport("sdl3", sdl3);
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(&exe.step);

    const step = b.step("run", "run the test code");
    step.dependOn(&run.step);
}
