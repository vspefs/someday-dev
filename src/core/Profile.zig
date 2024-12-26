const std = @import("std");
const someday = @import("../core.zig");

pub const Profile = struct {
    pub const Options = struct {
        parallel_jobs: ?u8 = null,
        config: *someday.Config,
        use_system_toolchain: bool = false,
        use_system_cmake: bool = false,
        use_system_ninja: bool = false,
    };

    parallel_jobs: ?u8,
    config: *someday.Config,

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

    pub fn getProfileHash(self: *const Profile, alloc: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(alloc, "{d}", .{hash: {
            var int: u8 = 0;
            int += (self.parallel_jobs orelse 0) * 10;
            int += (if (self.use_system_cmake) 4 else 0);
            int += (if (self.use_system_ninja) 2 else 0);
            int += (if (self.use_system_toolchain) 1 else 0);
            break :hash int;
        }});
    }
};
