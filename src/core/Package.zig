const std = @import("std");
const tellme = @import("../../build.zig").tellme_for_someday;

pub const Package = struct {
    pub const LinkOptions = struct {
        name: []const u8,
        needed: bool = true,
        weak: bool = false,
        use_pkg_config: std.Build.Module.SystemLib.UsePkgConfig = .no,
        preferred_link_mode: std.builtin.LinkMode = .dynamic,
        search_strategy: std.Build.Module.SystemLib.SearchStrategy = .no_fallback,
    };
    pub const CreateModuleOptions = struct {
        builder: *std.Build,
        include_path: []const u8,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        link_libc: bool = true,
        use_clang: bool = true,
    };
    include_path: tellme.a.FieldOf(std.Build.LazyPath),
    library_path: tellme.a.FieldOf(std.Build.LazyPath),
    step: tellme.a.FieldOf(*std.Build.Step),
};

pub fn includeHeadersFrom(pkg: anytype, to: *std.Build.Step.Compile) void {
    const p = tellme.that(&pkg, Package);
    to.addIncludePath(p.include_path.*);
    to.step.dependOn(p.step.*);
}

pub fn createModuleFrom(pkg: anytype, options: Package.CreateModuleOptions) *std.Build.Module {
    const p = tellme.that(&pkg, Package);
    const tc = options.builder.addTranslateC(.{
        .link_libc = options.link_libc,
        .use_clang = options.use_clang,
        .target = options.target,
        .optimize = options.optimize,
        .root_source_file = p.include_path.*.path(options.builder, options.include_path),
    });
    tc.addIncludePath(p.include_path.*);
    tc.step.dependOn(p.step.*);
    return tc.createModule();
}

pub fn linkLibraryFrom(pkg: anytype, to: *std.Build.Step.Compile, library: Package.LinkOptions) void {
    const p = tellme.that(&pkg, Package);
    to.addLibraryPath(p.library_path.*);
    to.linkSystemLibrary2(library.name, .{
        .needed = library.needed,
        .weak = library.weak,
        .use_pkg_config = library.use_pkg_config,
        .preferred_link_mode = library.preferred_link_mode,
        .search_strategy = library.search_strategy,
    });
    to.step.dependOn(p.step.*);
}

pub fn linkLibrariesFrom(pkg: anytype, to: *std.Build.Step.Compile, libraries: []const Package.LinkOptions) void {
    const p = tellme.that(&pkg, Package);
    to.addLibraryPath(p.library_path.*);
    for (libraries) |library| {
        to.linkSystemLibrary2(library.name, .{
            .needed = library.needed,
            .weak = library.weak,
            .use_pkg_config = library.use_pkg_config,
            .preferred_link_mode = library.preferred_link_mode,
            .search_strategy = library.search_strategy,
        });
    }
    to.step.dependOn(p.step.*);
}

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
