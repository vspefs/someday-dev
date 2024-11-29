const std = @import("std");
const someday = @import("root.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const output_file = try std.fs.cwd().createFile(args[1], .{});
    defer output_file.close();

    const ret = someday.Config{
        .proj_cache_root = args[2],

        .someday_build_root = args[3],
        .tools_build_path = try std.fs.path.join(allocator, &.{ args[3], "tools", "build" }),
        .tools_install_path = try std.fs.path.join(allocator, &.{ args[3], "tools", "sysenv" }),
        .tools_path = try std.fs.path.join(allocator, &.{ args[3], "tools" }),

        .cmake_src_path = try std.fs.path.join(allocator, &.{ args[3], "deps", "cmake" }),
        .ninja_src_path = try std.fs.path.join(allocator, &.{ args[3], "deps", "ninja" }),
    };
    try output_file.writeAll(try std.json.stringifyAlloc(allocator, ret, .{}));

    return std.process.cleanExit();
}
