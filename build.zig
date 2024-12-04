const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = b;
}

pub const Error = error{
    BuildError,
    OsError,
    NotImplemented,
};

pub const Config = struct {
    allocator: std.mem.Allocator,

    proj_cache_root: []const u8,

    someday_build_root: []const u8,
    tools_build_path: []const u8,
    tools_install_path: []const u8,
    tools_path: []const u8,

    cmake_src_path: []const u8,
    ninja_src_path: []const u8,

    pub fn init(alloc: std.mem.Allocator, someday_b: *std.Build) !Config {
        const proj_cache_root = try someday_b.cache_root.handle.realpathAlloc(alloc, ".");
        const someday_build_root = try someday_b.build_root.handle.realpathAlloc(alloc, ".");

        return Config{
            .allocator = alloc,
            .proj_cache_root = proj_cache_root,
            .someday_build_root = someday_build_root,
            .tools_build_path = try std.fs.path.join(alloc, &.{ someday_build_root, "tools", "build" }),
            .tools_install_path = try std.fs.path.join(alloc, &.{ someday_build_root, "tools", "sysenv" }),
            .tools_path = try std.fs.path.join(alloc, &.{ someday_build_root, "tools" }),
            .cmake_src_path = try someday_b.dependency("cmake", .{}).builder.build_root.handle.realpathAlloc(alloc, "."),
            .ninja_src_path = try someday_b.dependency("ninja", .{}).builder.build_root.handle.realpathAlloc(alloc, "."),
        };
    }
    pub fn deinit(self: *Config) void {
        self.allocator.free(self.proj_cache_root);
        self.allocator.free(self.someday_build_root);
        self.allocator.free(self.tools_build_path);
        self.allocator.free(self.tools_install_path);
        self.allocator.free(self.tools_path);
        self.allocator.free(self.cmake_src_path);
        self.allocator.free(self.ninja_src_path);
    }
};

pub fn buildCMake(alloc: std.mem.Allocator, config: Config) !void {
    // `zig cc` and `zig c++` can't build cmake. Fallback to system environment.
    //var env = try setupZigTools(alloc, config);
    //defer env.deinit();
    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    var someday_dir = try std.fs.openDirAbsolute(config.someday_build_root, .{});
    defer someday_dir.close();

    var build_dir = try someday_dir.makeOpenPath(try std.fs.path.join(alloc, &.{ config.tools_build_path, "cmake" }), .{});
    defer build_dir.close();

    if (already_built: {
        std.fs.accessAbsolute(try std.fs.path.join(alloc, &.{ config.tools_path, "cmake" }), .{}) catch break :already_built false;
        break :already_built true;
    }) {
        return;
    }

    var cmd0 = std.process.Child.init(&.{
        try std.fs.path.join(alloc, &.{ config.cmake_src_path, "bootstrap" }),
        try std.mem.concat(alloc, u8, &.{ "--prefix=", config.tools_install_path }),
        "--parallel=12",
    }, alloc);
    cmd0.cwd_dir = build_dir;
    cmd0.env_map = &env;
    _ = try cmd0.spawnAndWait();

    var cmd1 = std.process.Child.init(&.{
        "make",
        "--jobs=12",
    }, alloc);
    cmd1.cwd_dir = build_dir;
    cmd1.env_map = &env;
    _ = try cmd1.spawnAndWait();

    var cmd2 = std.process.Child.init(&.{
        "make",
        "install",
    }, alloc);
    cmd2.cwd_dir = build_dir;
    cmd2.env_map = &env;
    _ = try cmd2.spawnAndWait();

    try std.fs.symLinkAbsolute(try std.fs.path.join(alloc, &.{ config.tools_install_path, "bin", "cmake" }), try std.fs.path.join(alloc, &.{ config.tools_path, "cmake" }), .{});
}

pub fn buildNinja(alloc: std.mem.Allocator, config: Config) !void {
    // `zig cc` and `zig c++` can't build ninja. Fallback to system environment.
    //var env = try setupZigTools(alloc, config);
    //defer env.deinit();
    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    var someday_dir = try std.fs.openDirAbsolute(config.someday_build_root, .{});
    defer someday_dir.close();

    const cmake_path = try std.fs.path.join(alloc, &.{ config.tools_path, "cmake" });
    const build_path = try std.fs.path.join(alloc, &.{ config.tools_build_path, "ninja" });
    var build_dir = try someday_dir.makeOpenPath(build_path, .{});
    defer build_dir.close();

    if (already_built: {
        std.fs.accessAbsolute(try std.fs.path.join(alloc, &.{ config.tools_path, "ninja" }), .{}) catch break :already_built false;
        break :already_built true;
    }) {
        return;
    }

    var cmd0 = std.process.Child.init(&.{
        cmake_path,
        "-B",
        build_path,
        "-S",
        config.ninja_src_path,
        try std.mem.concat(alloc, u8, &.{ "-DCMAKE_INSTALL_PREFIX=", config.tools_install_path }),
        "-DCMAKE_BUILD_TYPE=Release",
    }, alloc);
    cmd0.cwd_dir = build_dir;
    cmd0.env_map = &env;
    _ = try cmd0.spawnAndWait();

    var cmd1 = std.process.Child.init(&.{
        cmake_path,
        "--build",
        build_path,
        "--parallel=12",
    }, alloc);
    cmd1.cwd_dir = build_dir;
    cmd1.env_map = &env;
    _ = try cmd1.spawnAndWait();

    var cmd2 = std.process.Child.init(&.{
        cmake_path,
        "--install",
        build_path,
    }, alloc);
    cmd2.cwd_dir = build_dir;
    cmd2.env_map = &env;
    _ = try cmd2.spawnAndWait();

    try std.fs.symLinkAbsolute(try std.fs.path.join(alloc, &.{ config.tools_install_path, "bin", "ninja" }), try std.fs.path.join(alloc, &.{ config.tools_path, "ninja" }), .{});
}

// As Zig can't build CMake and Ninja, this function is currently of no use.
// `buildCMake()` and `buildNinja()` currently rely on system compilers.
pub fn setupZigTools(alloc: std.mem.Allocator, config: Config) !std.process.EnvMap {
    var someday_dir = try std.fs.openDirAbsolute(config.someday_build_root, .{});
    defer someday_dir.close();
    var tools_dir = try someday_dir.makeOpenPath(config.tools_path, .{});
    defer tools_dir.close();

    try tools_dir.writeFile(.{ .sub_path = "ar", .data = 
    \\#!/bin/bash
    \\zig ar "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "cc", .data = 
    \\#!/bin/bash
    \\zig cc "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "c++", .data = 
    \\#!/bin/bash
    \\zig c++ "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "dlltool", .data = 
    \\#!/bin/bash
    \\zig dlltool "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "lib", .data = 
    \\#!/bin/bash
    \\zig lib "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "ranlib", .data = 
    \\#!/bin/bash
    \\zig ranlib "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "objcopy", .data = 
    \\#!/bin/bash
    \\zig objcopy "$@"
    });
    try tools_dir.writeFile(.{ .sub_path = "rc", .data = 
    \\#!/bin/bash
    \\zig rc "$@"
    });

    var ar = try tools_dir.openFile("ar", .{});
    try ar.chmod(0o777);
    ar.close();
    var cc = try tools_dir.openFile("cc", .{});
    try cc.chmod(0o777);
    cc.close();
    var cxx = try tools_dir.openFile("c++", .{});
    try cxx.chmod(0o777);
    cxx.close();
    var dlltool = try tools_dir.openFile("dlltool", .{});
    try dlltool.chmod(0o777);
    dlltool.close();
    var lib = try tools_dir.openFile("lib", .{});
    try lib.chmod(0o777);
    lib.close();
    var ranlib = try tools_dir.openFile("ranlib", .{});
    try ranlib.chmod(0o777);
    ranlib.close();
    var objcopy = try tools_dir.openFile("objcopy", .{});
    try objcopy.chmod(0o777);
    objcopy.close();
    var rc = try tools_dir.openFile("rc", .{});
    try rc.chmod(0o777);
    rc.close();

    var env = try std.process.getEnvMap(alloc);
    try env.put("PATH", try std.mem.concat(alloc, u8, &.{ config.tools_path, ":", env.get("PATH") orelse return Error.OsError }));
    try env.put("CC", try std.fs.path.join(alloc, &.{ config.tools_path, "cc" }));
    try env.put("CXX", try std.fs.path.join(alloc, &.{ config.tools_path, "c++" }));
    return env;
}

pub const CMakePackageOptions = struct {
    builder: *std.Build,
    config: Config,
    name: []const u8,
    header: []const u8,
    path: std.Build.LazyPath,
};

pub fn addCMakePackage(alloc: std.mem.Allocator, options: CMakePackageOptions) !*std.Build.Module {
    var env = try setupZigTools(alloc, options.config);
    defer env.deinit();

    const cmake_path = try std.fs.path.join(alloc, &.{ options.config.tools_path, "cmake" });

    const cmd0 = options.builder.addSystemCommand(&.{ cmake_path, "-G", "Ninja", "-D", "CMAKE_BUILD_TYPE=Release" });
    cmd0.addPrefixedDirectoryArg("-S", options.path);
    const build_path = cmd0.addPrefixedOutputDirectoryArg("-B", try std.fs.path.join(alloc, &.{ "someday", "build", options.name }));
    const install_path = cmd0.addPrefixedOutputDirectoryArg("-DCMAKE_INSTALL_PREFIX=", try std.fs.path.join(alloc, &.{ "someday", "sysenv" }));

    const cmd1 = options.builder.addSystemCommand(&.{cmake_path});
    cmd1.addArg("--build");
    cmd1.addDirectoryArg(build_path);
    cmd1.addArgs(&.{ "--config", "Release", "--parallel" });

    const cmd2 = options.builder.addSystemCommand(&.{cmake_path});
    cmd2.addArg("--install");
    cmd2.addDirectoryArg(build_path);
    cmd2.addArgs(&.{ "--config", "Release" });

    const tc = options.builder.addTranslateC(.{
        .link_libc = true,
        .optimize = .ReleaseSafe,
        .target = options.builder.host,
        .root_source_file = try install_path.join(alloc, try std.fs.path.join(alloc, &.{ "include", options.header })),
    });
    tc.addIncludePath(try install_path.join(alloc, try std.fs.path.join(alloc, &.{"include"})));

    const m = tc.createModule();
    m.addLibraryPath(try install_path.join(alloc, try std.fs.path.join(alloc, &.{"lib"})));
    m.linkSystemLibrary(options.name, .{
        .needed = true,
        .preferred_link_mode = .dynamic,
        .search_strategy = .paths_first,
    });

    cmd1.step.dependOn(&cmd0.step);
    cmd2.step.dependOn(&cmd1.step);
    tc.step.dependOn(&cmd2.step);

    return m;
}
