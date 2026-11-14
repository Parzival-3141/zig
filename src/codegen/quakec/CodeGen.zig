//! QuakeC codegen.
//! This lowers AIR into MIR.

const std = @import("std");
const link = @import("../../link.zig");
const codegen = @import("../../codegen.zig");

const log = std.log.scoped(.codegen);
const assert = std.debug.assert;

const CodeGen = @This();
const Mir = @import("Mir.zig");
const Zcu = @import("../../Zcu.zig");
const Air = @import("../../Air.zig");
const Type = @import("../../Type.zig");
const Value = @import("../../Value.zig");
const InternPool = @import("../../InternPool.zig");

// Value represents a compile-time known value, such as an integer, struct, etc.
// Type represents a compile-time known type, such as u8 (all types are compile-time known).
// Both are actually indexes into InternPool, with the index value being one of the known InternPool.Index tag values.
// I'm not 100% sure how InternPool works, but I think it stores deduplicated Values and Types.
// Note that Values can hold types! E.g. `const c = u8;` is represented by a Value of "u8" of Type "type".
// Specifically, `Value{ .ip_index = .u8_type }` and `Type{ .ip_index = .type_type }`

// Air.Ref.toIndex() returns non-null if the Ref references an Air instruction. Used when working with the result of an instruction.
// Air.Ref.toInterned() returns non-null if the Ref references a value stored in InternPool. Used when working with a constant value.

// NAVs are Named Addressable Values. They may be mutable or constant.
// UAVs are Unnamed Addressable Values. They are all constant.

pub fn legalizeFeatures(_: *const std.Target) ?*const Air.Legalize.Features {
    // @Todo after the implementation here has stabalized, consider what features
    // can be enabled.
    return null;
    // return comptime &.initMany(&.{
    //     .expand_intcast_safe,
    //     .expand_int_from_float_safe,
    //     .expand_int_from_float_optimized_safe,
    //     .expand_add_safe,
    //     .expand_sub_safe,
    //     .expand_mul_safe,
    // });
}

// @Cleanup while our CodeGen is a file struct, it's never actually instantiated anywhere outside
// this file. It matches the style of the other backends, but it's unecessary and I don't like it.

pt: Zcu.PerThread,
func_index: InternPool.Index,

num_params: u8 = 0,
locals: std.AutoArrayHashMapUnmanaged(Air.Inst.Index, QValueType) = .empty,
immediates: std.AutoArrayHashMapUnmanaged(InternPool.Index, f32) = .empty,
globals: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void) = .empty,

statements: std.ArrayList(Statement) = .empty,

// @Incomplete
// Need to track addressable variables besides immediates or locals.
// Wasm backend handles this with a pool of WValues, representing in flight values from the AIR stream, used for lowering to MIR.
// Aarch64 does something similar with its live_values field.

/// Used for tracking loaded values used in upcoming instructions.
loaded_values: std.AutoHashMapUnmanaged(Air.Inst.Index, QValue) = .empty,

const QValueType = Mir.ValueType;
const QValue = Mir.QValue;
const Statement = Mir.Statement;

pub fn generate(
    lf: *link.File,
    pt: Zcu.PerThread,
    src_loc: Zcu.LazySrcLoc,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) codegen.CodeGenError!Mir {
    _ = src_loc; // autofix
    std.debug.assert(lf.tag == .quakec); // @Cleanup or do dev.check(.quakec_backend) instead?

    const live = liveness.*.?;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    // @Cleanup
    // air.dump(pt, live);
    // std.debug.print("starting codegen:\n", .{});

    var function: CodeGen = .{
        .func_index = func_index,
        .pt = pt,
    };
    defer function.deinit();

    // genBody
    const air_tags: []const Air.Inst.Tag = air.instructions.items(.tag);
    const air_data: []const Air.Inst.Data = air.instructions.items(.data);
    for (air.getMainBody()) |inst_idx| {
        if (live.isUnused(inst_idx) and !air.mustLower(inst_idx, &pt.zcu.intern_pool))
            continue;

        // @Cleanup
        air.dumpInst(inst_idx, pt, live);
        std.debug.print("\n", .{});

        switch (air_tags[@intFromEnum(inst_idx)]) {
            else => |air_tag| return function.fail("unimplemented air: {t}", .{air_tag}),
            .alloc => {
                const ty = air_data[@intFromEnum(inst_idx)].ty;
                const tgt_ty = ty.childType(pt.zcu);

                const qc_ty = try function.getQCType(tgt_ty);
                try function.locals.putNoClobber(zcu.gpa, inst_idx, qc_ty);
            },
            .dbg_stmt, .dbg_empty_stmt => {}, // ignored, quakec doesn't support debug info
            .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline => {}, // ignored, quakec doesn't support debug info
            // @Todo globaldefs functionally act as debug symbols. Generate them for .dbg_* locals? Or for Debug & ReleaseSafe modes?
            .store, .store_safe => {
                // I'm assuming that air instruction arguments that use/reference the "result" of previous instructions need to be dereferenced, implying that I need to track those results in CodeGen so they can be used later. That explains the hashmaps and "resolveInst" funcs used in other backends.

                // I can't construct global data here since codegen runs on individual functions. That needs to be handled by the linker. So, I need to generate MIR with enough metadata to reconstruct/allocate globals. That probably means working with the linker to keep global references in sync so they can be resolved at link time. Kinda like relocations.

                const bin_op = air_data[@intFromEnum(inst_idx)].bin_op;
                const ptr_ty = air.typeOf(bin_op.lhs, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);

                if (ptr_info.packed_offset.host_size != 0) return function.fail("QuakeC backend does not support non-ABI-aligned pointers", .{});
                if (bin_op.rhs.toInterned()) |intern| if (ip.isUndef(intern)) continue; // skip store of undefined. If this store is part of a declaration then the linker will ensure the variable is zeroed.

                assert(ptr_info.child == .f32_type); // @Todo handle all QC types
                const stmt = try function.statements.addOne(zcu.gpa);
                stmt.* = .{ .op = .store_f };
                // stmt.args[0] = index of global that holds the variable, which must be resolved in link phase
                // stmt.args[1] = index of global that holds the value, which must be resolved in link phase
                // For now these must directly hold intermediate values which represent the above final values.

                if (bin_op.lhs.toIndex()) |air_inst_idx| {
                    // lhs is the address of a local variable, the result of an air instruction
                    log.debug("lhs = {f}: {f}", .{ air_inst_idx, ptr_ty.fmt(pt) });
                    const local_ty = function.locals.get(air_inst_idx).?; // @Todo handle storing to other registers besides locals, like .load-ed values.
                    assert(local_ty == .float); // @Todo handle all QC types
                    stmt.args[1] = .{ .local = @intCast(function.locals.getIndex(air_inst_idx).?) };
                } else {
                    // lhs is the address of a global variable, a constant Value
                    const val: Value = .fromInterned(bin_op.lhs.toInterned().?);
                    log.debug("lhs = <{f}, {f}>", .{ ptr_ty.fmt(pt), val.fmtValue(pt) });

                    assert(ptr_ty.isSinglePointer(zcu)); // @Todo is it possible to lower stores to other pointer types?
                    const nav_idx = Value.pointerNav(val, zcu).?;
                    const nav = ip.getNav(nav_idx);
                    assert(nav.typeOf(ip) == .f32_type); // @Todo handle all QC types
                    const gop = try function.globals.getOrPut(zcu.gpa, nav_idx);
                    stmt.args[1] = .{ .global = @intCast(gop.index) };
                }

                if (bin_op.rhs.toIndex()) |air_inst_idx| {
                    // rhs is the result of an air instruction
                    const loaded_value = function.loaded_values.get(air_inst_idx).?;
                    log.debug("rhs = {f}: {t}", .{ air_inst_idx, loaded_value });
                    switch (loaded_value) {
                        .void, .immediate => unreachable,
                        .local, .global => {},
                    }
                    stmt.args[0] = loaded_value;
                } else {
                    // rhs is a constant Value
                    const val: Value = .fromInterned(bin_op.rhs.toInterned().?);
                    log.debug("rhs = <{f}, {f}>", .{ val.typeOf(zcu).fmt(pt), val.fmtValue(pt) });

                    assert(try function.getQCType(val.typeOf(zcu)) == .float); // @Todo handle all QC types
                    const resolved_value: f32 = val.toFloat(f32, zcu);

                    const gop = try function.immediates.getOrPutValue(zcu.gpa, val.toIntern(), resolved_value);
                    stmt.args[0] = .{ .immediate = @intCast(gop.index) };
                }
            },
            .load => {
                const ty_op = air_data[@intFromEnum(inst_idx)].ty_op;
                const ptr_ty = air.typeOf(ty_op.operand, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                // operand is a pointer to a local or global register

                // In the general case we don't actually emit an instruction for loads.
                // The load_* statements are only used for loading values from entities;
                // otherwise, the global offset is stored directly in a statement's arguments.
                // @Todo entity field loads

                if (ptr_info.packed_offset.host_size != 0) return function.fail("QuakeC backend does not support non-ABI-aligned pointers", .{});

                // @Cleanup probably unecessary but for my own sanity
                assert(Type.fromInterned(ptr_info.child).eql(ty_op.ty.toType(), zcu));

                // @Incomplete
                // I don't want to allocate a local for every intermediate value. That means having some sort of register allocator (here register meaning QC globals).
                // That probably means refactoring how registers are tracked and stored; probably close to how the Wasm or Aarch64 backends do it (pool of live values).
                // Using a register allocator for locals across functions would be neat. Functions that are guaranteed not to share the same callstack can share local
                // registers, saving memory.

                // actually, how are locals allocated in qcc?

                // Track the instruction as being live, so it can be fetched in subsequent instructions (like store).
                if (ty_op.operand.toIndex()) |air_inst_idx| {
                    // @Incomplete if air_inst_idx isnt a local but a live_value, then this will not work.
                    // the fix would be to add locals to loaded_values in .alloc
                    const local_idx: u32 = @intCast(function.locals.getIndex(air_inst_idx).?);
                    try function.loaded_values.put(zcu.gpa, inst_idx, .{ .local = local_idx });
                } else {
                    const ptr_val: Value = .fromInterned(ty_op.operand.toInterned().?);
                    if (ptr_val.pointerNav(zcu)) |nav_idx| {
                        const gop = try function.globals.getOrPut(zcu.gpa, nav_idx);
                        const global_idx: u32 = @intCast(gop.index);
                        try function.loaded_values.put(zcu.gpa, inst_idx, .{ .global = global_idx });
                    } else {
                        // is this even possible?
                        @panic("@Todo .load non-global");
                    }
                }
            },
            .add, .sub, .mul => |op| {
                // Both lhs and rhs are the same type (either float or int).
                // They are either an air_inst_idx or a Value, neither are pointers.
                const bin_op = air_data[@intFromEnum(inst_idx)].bin_op;
                // @Todo assert both operands are floats
                const stmt = try function.statements.addOne(zcu.gpa);
                stmt.* = .{ .op = switch (op) {
                    .add => .add_f,
                    .sub => .sub_f,
                    .mul => .mul_f,
                    else => unreachable,
                } };

                if (bin_op.lhs.toIndex()) |air_inst_idx| {
                    const value: QValue = if (function.locals.getIndex(air_inst_idx)) |local_idx|
                        .{ .local = @intCast(local_idx) }
                    else
                        function.loaded_values.get(air_inst_idx).?;
                    switch (value) {
                        .void, .immediate => unreachable,
                        .local, .global => {},
                    }
                    stmt.args[0] = value;
                } else {
                    const val: Value = .fromInterned(bin_op.lhs.toInterned().?);
                    assert(try function.getQCType(val.typeOf(zcu)) == .float); // @Todo handle all QC types
                    const resolved_value: f32 = val.toFloat(f32, zcu);

                    const gop = try function.immediates.getOrPutValue(zcu.gpa, val.toIntern(), resolved_value);
                    stmt.args[0] = .{ .immediate = @intCast(gop.index) };
                }

                if (bin_op.rhs.toIndex()) |air_inst_idx| {
                    const value: QValue = if (function.locals.getIndex(air_inst_idx)) |local_idx|
                        .{ .local = @intCast(local_idx) }
                    else
                        function.loaded_values.get(air_inst_idx).?;
                    switch (value) {
                        .void, .immediate => unreachable,
                        .local, .global => {},
                    }
                    stmt.args[1] = value;
                } else {
                    const val: Value = .fromInterned(bin_op.rhs.toInterned().?);
                    assert(try function.getQCType(val.typeOf(zcu)) == .float); // @Todo handle all QC types
                    const resolved_value: f32 = val.toFloat(f32, zcu);

                    const gop = try function.immediates.getOrPutValue(zcu.gpa, val.toIntern(), resolved_value);
                    stmt.args[1] = .{ .immediate = @intCast(gop.index) };
                }

                // output register
                // @Todo here we're indescriminantly allocating a new local for the result,
                // which is incredibly wasteful since the result will probably be used only once.
                // Instead we should allocate from a pool of locals, reusing them when they're no longer needed.
                // In other words, a register allocator.
                const gop = try function.locals.getOrPutValue(zcu.gpa, inst_idx, .float);
                assert(!gop.found_existing);
                stmt.args[2] = .{ .local = @intCast(gop.index) };
                try function.loaded_values.putNoClobber(zcu.gpa, inst_idx, stmt.args[2]);
            },
            .ret, .ret_safe => {
                const un_op = air_data[@intFromEnum(inst_idx)].un_op;
                if (un_op != .void_value) return function.fail("@Todo handle return values", .{});
                try function.statements.append(zcu.gpa, .{ .op = .@"return" });
            },
        }
    }

    var mir: Mir = .{
        .statements = &.{}, // assigned after errdefer
        .locals = &.{}, // assigned after errdefer
        .immediates = &.{}, // assigned after errdefer
        .globals = &.{}, // assigned after errdefer
        .num_params = function.num_params,
    };
    errdefer mir.deinit(zcu.gpa);
    mir.statements = try function.statements.toOwnedSlice(zcu.gpa);
    mir.locals = try zcu.gpa.dupe(QValueType, function.locals.values());
    mir.immediates = try zcu.gpa.dupe(f32, function.immediates.values());
    mir.globals = try zcu.gpa.dupe(InternPool.Nav.Index, function.globals.keys());
    return mir;
}

fn deinit(cg: *CodeGen) void {
    const gpa = cg.pt.zcu.gpa;
    cg.statements.deinit(gpa);
    cg.locals.deinit(gpa);
    cg.immediates.deinit(gpa);
    cg.globals.deinit(gpa);
    cg.loaded_values.deinit(gpa);
    cg.* = undefined;
}

fn getQCType(cg: CodeGen, ty: Type) !QValueType {
    return switch (ty.toIntern()) {
        .f32_type => .float,
        else => cg.fail("invalid type: {f}", .{ty.fmt(cg.pt)}),
    };
}

fn isValidQCType(ty: Type) bool {
    return switch (ty.toIntern()) {
        .f32_type => true,
        else => false,
    };
}

fn fail(cg: CodeGen, comptime fmt: []const u8, args: anytype) error{ OutOfMemory, CodegenFail } {
    const zcu = cg.pt.zcu;
    const func = zcu.funcInfo(cg.func_index);
    return zcu.codegenFail(func.owner_nav, fmt, args);
}
