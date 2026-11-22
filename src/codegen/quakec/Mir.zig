//! Machine Intermediate Representation.
//! This representation is produced by QuakeC CodeGen

const std = @import("std");
const qcvm = @import("qcvm");
const InternPool = @import("../../InternPool.zig");
const Value = @import("../../Value.zig");

num_params: u8,
statements: []const Statement,

// The Wasm backend encodes these inside the instruction stream, which the linker lowers while iterating the stream.
// This is opposed to storing them separately, which we do here. We could do it the other way, since we always add the
// registers before they're needed, but it's fine, at least for now.

/// Stack local variables/temporaries
locals: []const ValueType,

pub fn deinit(mir: *@This(), gpa: std.mem.Allocator) void {
    gpa.free(mir.statements);
    gpa.free(mir.locals);
    mir.* = undefined;
}

pub const Statement = struct {
    op: Opcode,
    args: [3]Arg = @splat(.void),

    pub const Arg = union(enum) {
        void: void,
        /// index of statement for calculating a jump offset
        jump_to_stmt: u32,
        /// index into locals
        local: u32,
        /// Global scope variables
        global: InternPool.Nav.Index,
        immediate: Value,
    };
};

pub const ValueType = qcvm.ValueType;
pub const Opcode = qcvm.Opcode;
