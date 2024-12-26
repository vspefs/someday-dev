const std = @import("std");

pub const tellme_for_someday = @import("tellme");
pub usingnamespace @import("src/core.zig");
pub usingnamespace @import("src/ext.zig");

pub fn build(b: *std.Build) !void {
    _ = b;
}
