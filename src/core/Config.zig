pub const ZigToolPaths = struct {
    allocator: Allocator,

    ar: []const u8,
    cc: []const u8,
    @"c++": []const u8,
    dlltool: []const u8,
    lib: []const u8,
    ranlib: []const u8,
    objcopy: []const u8,
    rc: []const u8,

    pub fn init(alloc: Allocator, root_dir: Dir) !ZigToolPaths {
        var ret: ZigToolPaths = undefined;
        ret.allocator = alloc;

        const root_path = try root_dir.realpathAlloc(alloc, ".");
        defer alloc.free(root_path);

        const tool_list = comptime [_][]const u8{ "ar", "cc", "c++", "dlltool", "lib", "ranlib", "objcopy", "rc" };
        inline for (tool_list) |tool| {
            const tool_name = try addBatPostfixIfOnWindows(alloc, tool);
            defer alloc.free(tool_name);
            @field(ret, tool) = try path.join(alloc, &.{ root_path, "zig", tool_name });
        }

        return ret;
    }
    pub fn deinit(self: ZigToolPaths) void {
        const tool_list = comptime [_][]const u8{ "ar", "cc", "c++", "dlltool", "lib", "ranlib", "objcopy", "rc" };
        inline for (tool_list) |tool| {
            self.allocator.free(@field(self, tool));
        }
    }
};

arena: ArenaAllocator,
gpa: Allocator,

root_dir: Dir,
tools_dir: Dir,

someday_builder: *std.Build,

zig_tool_paths: ZigToolPaths,
cmake_path: []const u8,
cmake_step: *Step,
ninja_path: []const u8,
ninja_step: *Step,

pub fn init(alloc: Allocator, dep_someday: *Dependency) !Config {
    var tmp_arena = ArenaAllocator.init(alloc);
    defer tmp_arena.deinit();
    const tmp_alloc = tmp_arena.allocator();

    var config_arena = ArenaAllocator.init(alloc);
    const config_alloc = config_arena.allocator();

    var root = try dep_someday.builder.build_root.handle.makeOpenPath(".someday", .{});
    errdefer root.close();
    var tools = try root.makeOpenPath("tools", .{});
    errdefer tools.close();

    {
        var zig = try tools.makeOpenPath("zig", .{});
        defer zig.close();
        const tool_list = comptime [_][]const u8{ "ar", "cc", "c++", "dlltool", "lib", "ranlib", "objcopy", "rc" };

        inline for (tool_list) |tool| {
            const file = try zig.createFile(try addBatPostfixIfOnWindows(tmp_alloc, tool), .{});
            defer file.close();
            try file.writeAll(try allocPrint(tmp_alloc, if (builtin.os.tag == .windows)
                \\@echo off
                \\{s} {s} %*
            else
                \\#!/bin/sh
                \\{s} {s} "$@"
            , .{ dep_someday.builder.graph.zig_exe, try addExePostfixIfOnWindows(tmp_alloc, tool) }));
            if (builtin.os.tag != .windows) {
                try file.chmod(0o777);
            }
        }
    }

    const cmake_path = try path.join(config_alloc, &.{
        try tools.realpathAlloc(tmp_alloc, "."),
        "cmake",
        "bin",
        try addExePostfixIfOnWindows(tmp_alloc, "cmake"),
    });
    const cmake_step = dep_someday.builder.addSystemCommand(&.{ dep_someday.builder.graph.zig_exe, "build", "install", "-p" });
    cmake_step.addArg(try path.join(tmp_alloc, &.{
        try tools.realpathAlloc(tmp_alloc, "."),
        "cmake",
    }));
    cmake_step.setCwd(dep_someday.builder.dependency("cmake", .{}).path("."));

    const ninja_path = try path.join(config_alloc, &.{
        try tools.realpathAlloc(tmp_alloc, "."),
        "ninja",
        "bin",
        try addExePostfixIfOnWindows(tmp_alloc, "ninja"),
    });
    const ninja_step = dep_someday.builder.addSystemCommand(&.{ dep_someday.builder.graph.zig_exe, "build", "install", "-p" });
    ninja_step.addArg(try path.join(tmp_alloc, &.{
        try tools.realpathAlloc(tmp_alloc, "."),
        "ninja",
    }));
    ninja_step.setCwd(dep_someday.builder.dependency("ninja", .{}).path("."));

    return .{
        .arena = config_arena,
        .gpa = alloc,
        .root_dir = root,
        .tools_dir = tools,

        .someday_builder = dep_someday.builder,

        .zig_tool_paths = try ZigToolPaths.init(alloc, tools),
        .cmake_path = cmake_path,
        .cmake_step = &cmake_step.step,
        .ninja_path = ninja_path,
        .ninja_step = &ninja_step.step,
    };
}
pub fn deinit(self: *Config) void {
    self.zig_tool_paths.deinit();
    self.arena.deinit();
    self.root_dir.close();
    self.tools_dir.close();
}

pub fn addRunCMake(self: Config) *Run {
    const cmd = self.someday_builder.addSystemCommand(&.{self.cmake_path});
    cmd.step.dependOn(self.cmake_step);
    return cmd;
}
pub fn addRunNinja(self: Config) *Run {
    const cmd = self.someday_builder.addSystemCommand(&.{self.ninja_path});
    cmd.step.dependOn(self.ninja_step);
    return cmd;
}

fn addExePostfixIfOnWindows(alloc: Allocator, original: []const u8) ![]const u8 {
    if (builtin.os.tag == .windows) {
        return try allocPrint(alloc, "{s}.exe", .{original});
    } else {
        return try alloc.dupe(u8, original);
    }
}
fn addBatPostfixIfOnWindows(alloc: Allocator, original: []const u8) ![]const u8 {
    if (builtin.os.tag == .windows) {
        return try allocPrint(alloc, "{s}.bat", .{original});
    } else {
        return try alloc.dupe(u8, original);
    }
}

const Config = @This();

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Step = std.Build.Step;
const Run = Step.Run;
const Dependency = std.Build.Dependency;
const allocPrint = std.fmt.allocPrint;
const Dir = std.fs.Dir;
const path = std.fs.path;

const std = @import("std");
const builtin = @import("builtin");
