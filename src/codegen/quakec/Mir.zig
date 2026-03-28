//! Machine Intermediate Representation.
//! This representation is produced by QuakeC CodeGen

const std = @import("std");
const InternPool = @import("../../InternPool.zig");

num_params: u8,
statements: []const Statement,

locals: []const ValueType,
immediates: []const f32, // @Todo handle other QC types

pub const QValue = union(enum) {
    void: void,
    local: u32, // index into locals
    immediate: u32, // index into immediates
    constant_float: f32,
};

pub const Statement = struct {
    op: Opcode,
    args: [3]QValue = @splat(.void),
};

pub fn deinit(mir: *@This(), gpa: std.mem.Allocator) void {
    gpa.free(mir.statements);
    gpa.free(mir.locals);
    gpa.free(mir.immediates);
    mir.* = undefined;
}

// pub const Statement = extern struct {
//     op: Opcode,
//     args: [3]i16,
// };

pub const ValueType = enum(u15) {
    void,
    string,
    float,
    vector,
    entity,
    field, // field offset?
    function,
    // pointer, // unused
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
