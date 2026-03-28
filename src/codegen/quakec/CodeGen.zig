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
// I'm not 100% sure how InternPool works, but I think it stored deduplicated Values and Types.
// Note that Values can hold types! E.g. `const c = u8;` is represented by a Value of "u8" of Type "type".
// Specifically, `Value{ .ip_index = .u8_type }` and `Type{ .ip_index = .type_type }`

// Air.Ref.toIndex() returns non-null if the Ref references an Air instruction. Used when working with the result of an instruction.
// Air.Ref.toInterned() returns non-null if the Ref references a value stored in InternPool. Used when working with a constant value.

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
// this file. It matches the style of the other backends, but it's unecessary and I don't like it.k

pt: Zcu.PerThread,
func_index: InternPool.Index,

num_params: u8 = 0,
locals: std.AutoArrayHashMapUnmanaged(Air.Inst.Index, QValueType) = .empty,
immediates: std.AutoArrayHashMapUnmanaged(InternPool.Index, f32) = .empty,

statements: std.ArrayList(Statement) = .empty,

/// Used for tracking loaded values used in upcoming instructions.
/// Use fetchRemove when accessing a value.
live_values: std.AutoHashMapUnmanaged(Air.Inst.Index, Value) = .empty,

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
    std.debug.assert(lf.tag == .quakec); // or do dev.check(.quakec_backend) instead?

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
                var stmt: Statement = .{ .op = .store_f };
                // @Incomplete I don't think .store is limited to stack locals!
                // stmt.args[0] = index of global that holds the variable, which must be resolved in link phase
                // stmt.args[1] = index of global that holds the value, which must be resolved in link phase
                // For now these must directly hold intermediate values which represent the above final values.

                if (bin_op.lhs.toIndex()) |air_inst_idx| {
                    log.debug("lhs = %{d}: {f}", .{
                        @intFromEnum(air_inst_idx),
                        ptr_ty.fmt(pt),
                    });
                    const local_ty = function.locals.get(air_inst_idx).?; // @Todo handle storing to other globals besides locals
                    assert(local_ty == .float); // @Todo handle all QC types
                    stmt.op = .store_f;
                    stmt.args[1] = .{ .local = @intCast(function.locals.getIndex(air_inst_idx).?) };
                } else {
                    const val: Value = .fromInterned(bin_op.lhs.toInterned().?);
                    return function.fail("@Todo store to global value: lhs = <{f}, {f}>", .{
                        val.typeOf(zcu).fmt(pt),
                        val.fmtValue(pt),
                    });
                }

                if (bin_op.rhs.toIndex()) |air_inst_idx| {
                    return function.fail("@Todo store instruction result: rhs = {f}", .{air_inst_idx});
                } else {
                    const val: Value = .fromInterned(bin_op.rhs.toInterned().?);
                    log.debug("rhs = <{f}, {f}>", .{
                        val.typeOf(zcu).fmt(pt),
                        val.fmtValue(pt),
                    });

                    assert(try function.getQCType(val.typeOf(zcu)) == .float); // @Todo handle all QC types
                    const resolved_value: f32 = val.toFloat(f32, zcu);

                    const gop = try function.immediates.getOrPut(zcu.gpa, val.toIntern());
                    if (gop.found_existing) {
                        assert(gop.value_ptr.* == resolved_value);
                    } else {
                        gop.value_ptr.* = resolved_value;
                    }

                    stmt.args[0] = .{ .immediate = @intCast(gop.index) };
                }

                try function.statements.append(zcu.gpa, stmt);
            },
            .load => {
                const ty_op = air_data[@intFromEnum(inst_idx)].ty_op;
                const ptr_ty = air.typeOf(ty_op.operand, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                _ = ptr_info; // autofix
                // operand is a pointer to a local or global register

                // assert(ip.typeOf(ptr_info.child).eql(ty_op.ty.toType(), zcu));
                // ty_op.operand.toIndex().?

                if (function.live_values.fetchRemove(inst_idx)) |dst_val| {
                    _ = dst_val; // autofix
                }
                @panic("@Todo");
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
        .num_params = function.num_params,
    };
    errdefer mir.deinit(zcu.gpa);
    mir.statements = try function.statements.toOwnedSlice(zcu.gpa);
    mir.locals = try zcu.gpa.dupe(QValueType, function.locals.values());
    mir.immediates = try zcu.gpa.dupe(f32, function.immediates.values());
    return mir;
}

fn deinit(cg: *CodeGen) void {
    const gpa = cg.pt.zcu.gpa;
    cg.statements.deinit(gpa);
    cg.locals.deinit(gpa);
    cg.immediates.deinit(gpa);
    cg.live_values.deinit(gpa);
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
