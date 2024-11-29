const std = @import("std");

pub fn build(b: *std.Build) !void {
    const m = b.addModule("someday", .{
        .optimize = .ReleaseSafe,
        .root_source_file = b.path("src/root.zig"),
        .target = b.host,
    });
    m.addAnonymousImport("someday_config", .{
        .root_source_file = try genConfig(b),
    });
}

fn genConfig(b: *std.Build) !std.Build.LazyPath {
    const exe = b.addExecutable(.{
        .name = "gen_config",
        .optimize = .ReleaseSafe,
        .root_source_file = b.path("src/gen_config.zig"),
        .target = b.host,
    });
    const run = b.addRunArtifact(exe);
    const output = run.addOutputFileArg("someday_config.json");
    run.addArg(try b.cache_root.handle.realpathAlloc(b.allocator, "."));
    run.addArg(try b.build_root.handle.realpathAlloc(b.allocator, "."));

    return output;
}
