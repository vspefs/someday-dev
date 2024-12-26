const std = @import("std");
const someday = @import("../core.zig");

pub const CMakePackageOptions = struct {
    builder: *std.Build,
    profile: *someday.Profile,
    path: someday.PackagePath,
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
    const profile_hash = try options.profile.getProfileHash(alloc);

    const cmd0 = options.builder.addSystemCommand(&.{
        "cmake",
        "-GNinja",
        "-DCMAKE_BUILD_TYPE=Release",
    });
    if (!options.profile.use_system_toolchain) {
        cmd0.addArgs(&.{ "-DCMAKE_C_LINKER_DEPFILE_SUPPORTED=OFF", "-DCMAKE_CXX_LINKER_DEPFILE_SUPPORTED=OFF" });
    }
    const install_path = cmd0.addPrefixedOutputDirectoryArg(
        "-DCMAKE_INSTALL_PREFIX=",
        try std.fs.path.join(alloc, &.{ profile_hash, "sysenv" }),
    );
    switch (options.path) {
        .absolute => |path| cmd0.addArgs(&.{ "-S", path }),
        .lazy_path => |path| cmd0.addPrefixedDirectoryArg("-S", path),
    }
    const build_path = cmd0.addPrefixedOutputDirectoryArg(
        "-B",
        try std.fs.path.join(alloc, &.{ profile_hash, "build", options.build_as }),
    );
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
