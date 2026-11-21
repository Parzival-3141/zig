//! Machine Intermediate Representation.
//! This representation is produced by QuakeC CodeGen

const std = @import("std");
const InternPool = @import("../../InternPool.zig");

num_params: u8,
statements: []const Statement,

// The Wasm backend encodes these inside the instruction stream, which the linker lowers while iterating the stream.
// This is opposed to storing them separately, which we do here. We could do it the other way, since we always add the
// registers before they're needed, but it's fine, at least for now.

/// Stack local variables/temporaries
locals: []const ValueType,
/// Global scope variables
globals: []const InternPool.Nav.Index,
immediates: []const f32, // @Todo handle other QC types

pub fn deinit(mir: *@This(), gpa: std.mem.Allocator) void {
    gpa.free(mir.statements);
    gpa.free(mir.locals);
    gpa.free(mir.immediates);
    gpa.free(mir.globals);
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
        /// index into immediates
        immediate: u32,
        /// index into globals
        global: u32,
    };
};

pub const ValueType = enum(u15) {
    void,
    string,
    float,
    vector,
    entity,
    field,
    function,
    pointer,
};

pub const Opcode = enum(u16) {
    done,
    mul_f,
    mul_v,
    mul_fv,
    mul_vf,
    div_f,
    add_f,
    add_v,
    sub_f,
    sub_v,

    eq_f,
    eq_v,
    eq_s,
    eq_e,
    eq_fnc,

    ne_f,
    ne_v,
    ne_s,
    ne_e,
    ne_fnc,

    le,
    ge,
    lt,
    gt,

    load_f,
    load_v,
    load_s,
    load_ent,
    load_fld,
    load_fnc,

    address,

    store_f,
    store_v,
    store_s,
    store_ent,
    store_fld,
    store_fnc,

    storep_f,
    storep_v,
    storep_s,
    storep_ent,
    storep_fld,
    storep_fnc,

    @"return",
    not_f,
    not_v,
    not_s,
    not_ent,
    not_fnc,
    @"if",
    ifnot,
    call0,
    call1,
    call2,
    call3,
    call4,
    call5,
    call6,
    call7,
    call8,
    state,
    goto,
    @"and",
    @"or",

    bitand,
    bitor,
};
