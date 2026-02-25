const std = @import("std");

pub fn deinit(mir: *@This(), gpa: std.mem.Allocator) void {
    _ = mir; // autofix
    _ = gpa; // autofix
}
