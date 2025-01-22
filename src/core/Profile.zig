pub const Options = struct {
    config: *Config,
    parallel_jobs: ?u8 = null,
    usage: Usage = .{},
};
pub const Usage = struct {
    pub const GeneralToolUsage = enum {
        system,
        someday,
    };
    pub const CompileToolchainUsage = enum {
        system,
        zig,
    };
    cmake: GeneralToolUsage = .system,
    ninja: GeneralToolUsage = .system,
    toolchain: CompileToolchainUsage = .zig,
};

config: *Config,
parallel_jobs: ?u8,
usage: Usage,
profile_hash: []const u8,

pub fn init(options: Options) !Profile {
    const alloc = options.config.gpa;

    return .{
        .config = options.config,
        .parallel_jobs = options.parallel_jobs,
        .usage = options.usage,
        .profile_hash = try allocPrint(alloc, "{d}", .{hash: {
            var int: u8 = 0;
            int += (options.parallel_jobs orelse 0) * 10;
            int += (if (options.usage.cmake == .system) 4 else 0);
            int += (if (options.usage.ninja == .system) 2 else 0);
            int += (if (options.usage.toolchain == .system) 1 else 0);
            break :hash int;
        }}),
    };
}
pub fn deinit(self: *Profile) void {
    self.config.gpa.free(self.profile_hash);
}

const Profile = @This();
const Dir = std.fs.Dir;
const allocPrint = std.fmt.allocPrint;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const std = @import("std");
const Config = @import("Config.zig");
const builtin = @import("builtin");
