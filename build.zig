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

    someday_build_root: []const u8,
    tools_build_path: []const u8,
    tools_install_path: []const u8,
    tools_path: []const u8,

    cmake_src_path: []const u8,
    ninja_src_path: []const u8,

    pub fn init(alloc: std.mem.Allocator, someday_b: *std.Build) !Config {
        const someday_build_root = try someday_b.build_root.handle.realpathAlloc(alloc, ".");
        errdefer alloc.free(someday_build_root);
        const tools_path = try std.fs.path.join(alloc, &.{ someday_build_root, "tools" });
        errdefer alloc.free(tools_path);
        const tools_build_path = try std.fs.path.join(alloc, &.{ someday_build_root, "tools", "build" });
        errdefer alloc.free(tools_build_path);
        const tools_install_path = try std.fs.path.join(alloc, &.{ someday_build_root, "tools", "sysenv" });
        errdefer alloc.free(tools_install_path);
        const cmake_src_path = try someday_b.dependency("cmake", .{}).builder.build_root.handle.realpathAlloc(alloc, ".");
        errdefer alloc.free(cmake_src_path);
        const ninja_src_path = try someday_b.dependency("ninja", .{}).builder.build_root.handle.realpathAlloc(alloc, ".");
        errdefer alloc.free(ninja_src_path);

        var root_dir = try std.fs.openDirAbsolute(someday_build_root, .{});
        try root_dir.makePath(tools_path);
        try root_dir.deleteTree(tools_build_path);
        try root_dir.makePath(tools_build_path);
        try root_dir.makePath(tools_install_path);
        root_dir.close();

        try createZigAlias(tools_path);

        return Config{
            .allocator = alloc,
            .someday_build_root = someday_build_root,
            .tools_build_path = tools_build_path,
            .tools_install_path = tools_install_path,
            .tools_path = tools_path,
            .cmake_src_path = cmake_src_path,
            .ninja_src_path = ninja_src_path,
        };
    }
    pub fn deinit(self: *Config) void {
        self.allocator.free(self.someday_build_root);
        self.allocator.free(self.tools_build_path);
        self.allocator.free(self.tools_install_path);
        self.allocator.free(self.tools_path);
        self.allocator.free(self.cmake_src_path);
        self.allocator.free(self.ninja_src_path);
    }

    pub fn buildCMake(self: *Config, parallel_jobs: u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        if (already_built: {
            std.fs.accessAbsolute(try std.fs.path.join(alloc, &.{ self.tools_install_path, "bin", "cmake" }), .{}) catch break :already_built false;
            break :already_built true;
        }) {
            return;
        }
        var env = try std.process.getEnvMap(alloc);
        defer env.deinit();
        var build_root_dir = try std.fs.openDirAbsolute(self.tools_build_path, .{});
        var build_dir = try build_root_dir.makeOpenPath("cmake", .{});
        build_root_dir.close();
        defer build_dir.close();

        var cmd0 = std.process.Child.init(&.{
            try std.fs.path.join(alloc, &.{ self.cmake_src_path, "bootstrap" }),
            "--prefix=/",
            try std.fmt.allocPrint(alloc, "--parallel={d}", .{parallel_jobs}),
            "--datadir=/share/cmake",
        }, alloc);
        cmd0.cwd_dir = build_dir;
        cmd0.env_map = &env;
        _ = try cmd0.spawnAndWait();

        var cmd1 = std.process.Child.init(&.{
            "make",
            try std.fmt.allocPrint(alloc, "--jobs={d}", .{parallel_jobs}),
        }, alloc);
        cmd1.cwd_dir = build_dir;
        cmd1.env_map = &env;
        _ = try cmd1.spawnAndWait();

        var cmd2 = std.process.Child.init(&.{
            "make",
            try std.mem.concat(alloc, u8, &.{ "DESTDIR=", self.tools_install_path }),
            "install",
        }, alloc);
        cmd2.cwd_dir = build_dir;
        cmd2.env_map = &env;
        _ = try cmd2.spawnAndWait();
    }
    pub fn buildNinja(self: *Config, parallel_jobs: u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        if (already_built: {
            std.fs.accessAbsolute(try std.fs.path.join(alloc, &.{ self.tools_install_path, "bin", "ninja" }), .{}) catch break :already_built false;
            break :already_built true;
        }) {
            return;
        }
        var env = try std.process.getEnvMap(alloc);
        const cmake_path = try std.fs.path.join(alloc, &.{ self.tools_install_path, "bin", "cmake" });
        var build_root_dir = try std.fs.openDirAbsolute(self.tools_build_path, .{});
        var build_dir = try build_root_dir.makeOpenPath("ninja", .{});
        build_root_dir.close();
        defer build_dir.close();

        var cmd0 = std.process.Child.init(&.{
            cmake_path,
            "-B",
            ".",
            "-S",
            self.ninja_src_path,
            try std.mem.concat(alloc, u8, &.{ "-DCMAKE_INSTALL_PREFIX=", self.tools_install_path }),
            "-DCMAKE_BUILD_TYPE=Release",
            "-DBUILD_TESTING=OFF",
        }, alloc);
        cmd0.cwd_dir = build_dir;
        cmd0.env_map = &env;
        _ = try cmd0.spawnAndWait();

        var cmd1 = std.process.Child.init(&.{
            cmake_path,
            "--build",
            ".",
            try std.fmt.allocPrint(alloc, "--parallel={d}", .{parallel_jobs}),
        }, alloc);
        cmd1.cwd_dir = build_dir;
        cmd1.env_map = &env;
        _ = try cmd1.spawnAndWait();

        var cmd2 = std.process.Child.init(&.{
            cmake_path,
            "--install",
            ".",
        }, alloc);
        cmd2.cwd_dir = build_dir;
        cmd2.env_map = &env;
        _ = try cmd2.spawnAndWait();
    }
    fn createZigAlias(path: []const u8) !void {
        var tools_dir = try std.fs.openDirAbsolute(path, .{});
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
    }

    pub fn setZig(self: *const Config, to: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        var dir = try std.fs.openDirAbsolute(to, .{});
        defer dir.close();

        try dir.writeFile(.{ .sub_path = "ar", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "ar" })}) });
        try dir.writeFile(.{ .sub_path = "c++", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "c++" })}) });
        try dir.writeFile(.{ .sub_path = "cc", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "cc" })}) });
        try dir.writeFile(.{ .sub_path = "dlltool", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "dlltool" })}) });
        try dir.writeFile(.{ .sub_path = "lib", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "lib" })}) });
        try dir.writeFile(.{ .sub_path = "objcopy", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "objcopy" })}) });
        try dir.writeFile(.{ .sub_path = "ranlib", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "ranlib" })}) });
        try dir.writeFile(.{ .sub_path = "rc", .data = try std.fmt.allocPrint(alloc,
            \\#!/bin/bash
            \\{s} "$@"
        , .{try std.fs.path.join(alloc, &.{ self.tools_path, "rc" })}) });

        var ar = try dir.openFile("ar", .{});
        try ar.chmod(0o777);
        ar.close();
        var cc = try dir.openFile("cc", .{});
        try cc.chmod(0o777);
        cc.close();
        var cxx = try dir.openFile("c++", .{});
        try cxx.chmod(0o777);
        cxx.close();
        var dlltool = try dir.openFile("dlltool", .{});
        try dlltool.chmod(0o777);
        dlltool.close();
        var lib = try dir.openFile("lib", .{});
        try lib.chmod(0o777);
        lib.close();
        var ranlib = try dir.openFile("ranlib", .{});
        try ranlib.chmod(0o777);
        ranlib.close();
        var objcopy = try dir.openFile("objcopy", .{});
        try objcopy.chmod(0o777);
        objcopy.close();
        var rc = try dir.openFile("rc", .{});
        try rc.chmod(0o777);
        rc.close();
    }
    pub fn setCMake(self: *const Config, to: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        var dir = try std.fs.openDirAbsolute(to, .{});
        defer dir.close();

        dir.symLink(try std.fs.path.join(alloc, &.{ self.tools_install_path, "bin", "cmake" }), "cmake", .{}) catch |err| if (err == error.PathAlreadyExists) {} else return err;

        var cmake = try dir.openFile("cmake", .{});
        try cmake.chmod(0o777);
        cmake.close();
    }
    pub fn setNinja(self: *const Config, to: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        var dir = try std.fs.openDirAbsolute(to, .{});
        defer dir.close();

        dir.symLink(try std.fs.path.join(alloc, &.{ self.tools_install_path, "bin", "ninja" }), "ninja", .{}) catch |err| if (err == error.PathAlreadyExists) {} else return err;

        var ninja = try dir.openFile("ninja", .{});
        try ninja.chmod(0o777);
        ninja.close();
    }
};

pub const Profile = struct {
    pub const Options = struct {
        parallel_jobs: ?u8 = null,
        config: *Config,
        use_system_toolchain: bool = false,
        use_system_cmake: bool = false,
        use_system_ninja: bool = false,
    };

    parallel_jobs: ?u8,
    config: *Config,

    use_system_toolchain: bool,
    use_system_cmake: bool,
    use_system_ninja: bool,

    env_dir: std.fs.Dir,

    pub fn init(options: Options) !Profile {
        var arena = std.heap.ArenaAllocator.init(options.config.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const hash_int = blk: {
            var int: u8 = 0;
            int += (options.parallel_jobs orelse 0) * 10;
            int += (if (options.use_system_cmake) 4 else 0);
            int += (if (options.use_system_ninja) 2 else 0);
            int += (if (options.use_system_toolchain) 1 else 0);
            break :blk int;
        };
        const profile_hash = try std.fmt.allocPrint(alloc, "{d}", .{hash_int});

        var root = try std.fs.openDirAbsolute(options.config.tools_path, .{});
        const profile_dir = try root.makeOpenPath(profile_hash, .{});
        const profile_path = try profile_dir.realpathAlloc(alloc, ".");
        root.close();

        if (!options.use_system_toolchain) try options.config.setZig(profile_path);
        if (!options.use_system_cmake) try options.config.setCMake(profile_path);
        if (!options.use_system_ninja) try options.config.setNinja(profile_path);

        return Profile{
            .parallel_jobs = options.parallel_jobs,
            .config = options.config,
            .use_system_toolchain = options.use_system_toolchain,
            .use_system_cmake = options.use_system_cmake,
            .use_system_ninja = options.use_system_ninja,
            .env_dir = profile_dir,
        };
    }
    pub fn deinit(self: *Profile) void {
        self.env_dir.close();
    }

    /// Set the environment map according to the profile.
    ///
    /// `some_run.env_map = &some_env_map;` does not work because `some_env_map` we get in build.zig does not live long enough.
    /// And I can't find any std.Build function that dupes the map.
    pub fn setEnvMap(self: *Profile, to: *std.Build.Step.Run) !void {
        var arena = std.heap.ArenaAllocator.init(self.config.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const old_path = blk: {
            var env = try std.process.getEnvMap(alloc);
            defer env.deinit();
            break :blk try alloc.dupe(u8, env.get("PATH") orelse "");
        };
        const new_path = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ try self.env_dir.realpathAlloc(alloc, "."), old_path });
        to.setEnvironmentVariable("PATH", new_path);

        if (!self.use_system_toolchain) {
            const cc_path = try self.env_dir.realpathAlloc(alloc, "cc");
            const cxx_path = try self.env_dir.realpathAlloc(alloc, "c++");
            to.setEnvironmentVariable("CC", cc_path);
            to.setEnvironmentVariable("CXX", cxx_path);
        }
    }
};

pub const PackagePathTag = enum {
    lazy_path,
    absolute,
};

pub const PackagePath = union(PackagePathTag) {
    lazy_path: std.Build.LazyPath,
    absolute: []const u8,

    pub fn fromDependency(dep: *std.Build.Dependency) !PackagePath {
        return .{ .lazy_path = dep.path(".") };
    }
    pub fn fromTree(path: std.Build.LazyPath) !PackagePath {
        return .{ .lazy_path = path };
    }
};

pub const CMakePackageOptions = struct {
    builder: *std.Build,
    profile: *Profile,
    path: PackagePath,
    build_as: []const u8,
};

pub const CMakePackageCppOptions = struct {};

pub const CMakePackage = struct {
    include_path: std.Build.LazyPath,
    library_path: std.Build.LazyPath,
    step: *std.Build.Step,
};

pub fn addCMakePackage(options: CMakePackageOptions) !CMakePackage {
    var arena = std.heap.ArenaAllocator.init(options.profile.config.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const cmd0 = options.builder.addSystemCommand(&.{
        "cmake",
        "-GNinja",
        "-DCMAKE_BUILD_TYPE=Release",
    });
    const install_path = cmd0.addPrefixedOutputDirectoryArg("-DCMAKE_INSTALL_PREFIX=", "sysenv");
    switch (options.path) {
        .absolute => |path| cmd0.addArgs(&.{ "-S", path }),
        .lazy_path => |path| cmd0.addPrefixedDirectoryArg("-S", path),
    }
    const build_path = cmd0.addPrefixedOutputDirectoryArg("-B", try std.fs.path.join(alloc, &.{ "build", options.build_as }));
    try options.profile.setEnvMap(cmd0);

    const cmd1 = options.builder.addSystemCommand(&.{
        "cmake",
        "--build",
    });
    cmd1.addDirectoryArg(build_path);
    try options.profile.setEnvMap(cmd1);
    cmd1.step.dependOn(&cmd0.step);

    const cmd2 = options.builder.addSystemCommand(&.{
        "cmake",
        "--install",
    });
    cmd2.addDirectoryArg(build_path);
    try options.profile.setEnvMap(cmd2);
    cmd2.step.dependOn(&cmd1.step);

    const include_path = install_path.path(options.builder, "include");
    const library_path = install_path.path(options.builder, "lib");

    return .{
        .include_path = include_path,
        .library_path = library_path,
        .step = &cmd2.step,
    };
}
