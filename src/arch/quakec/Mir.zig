//! Machine Intermediate Representation.
//! This representation is produced by QuakeC CodeGen

pub fn deinit(mir: *@This(), gpa: std.mem.Allocator) void {
    _ = mir; // autofix
    _ = gpa; // autofix
}

const std = @import("std");
