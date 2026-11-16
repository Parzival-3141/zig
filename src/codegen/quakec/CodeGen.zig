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

// The plan here is to allocate stack-frame, global, or constant slots when they are accessed by an AIR instruction.
// The terminology used here is in the context of Zig code, i.e.
// locals means stack local variables, globals means global scope variables, immediate means a constant, etc.

/// In-flight results of lowered AIR instructions. This allows us to track the
/// lifetimes of values used during computation and allocate them to the
/// appropriate memory regions. A memory region may be recycled when its value dies.
live_values: std.AutoArrayHashMapUnmanaged(Air.Inst.Index, ValueSlot) = .empty,

/// List of value slots in the function "stack" frame.
/// @Todo vectors are explicitly ignored for now and will require a refactor.
frame: std.ArrayList(Mir.ValueType) = .empty,
free_frame_slots: std.ArrayList(u32) = .empty,

globals: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void) = .empty,
immediates: std.AutoArrayHashMapUnmanaged(InternPool.Index, f32) = .empty,

statements: std.ArrayList(Mir.Statement) = .empty,

/// Where the result of a lowered AIR instruction currently lives.
// @Todo typed indices?
const ValueSlot = union(enum) {
    /// Value lives in a recyclable frame slot. Usually produced by intermediate
    /// computations. Index into `frame`.
    temp: u32,
    /// Value is a stack allocated variable and is never recycled.
    /// Index into `frame`.
    local: u32,
    /// Value is a global variable and is never recycled.
    /// Index into `globals`.
    // @Note currently unused since we copy on Air.load. Remove this comment when that changes.
    global: u32,

    // Constants are not produced by AIR instructions and are directly
    // returned by resolveOperand.
};

pub fn generate(
    lf: *link.File,
    pt: Zcu.PerThread,
    src_loc: Zcu.LazySrcLoc,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) codegen.CodeGenError!Mir {
    _ = src_loc; // autofix
    assert(lf.tag == .quakec); // @Cleanup or do dev.check(.quakec_backend) instead?

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
                const qc_ty = try function.getQCType(ty.childType(pt.zcu));

                const slot = try function.frameAlloc(qc_ty, .local);
                try function.live_values.put(zcu.gpa, inst_idx, .{ .local = slot });
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

                const rhs = try function.resolveOperand(bin_op.rhs);
                const lhs = try function.resolvePtrOperand(bin_op.lhs);
                log.debug("lhs = {t}, rhs = {t}", .{ lhs, rhs });

                try function.statements.append(zcu.gpa, .{
                    .op = .store_f,
                    .args = .{ rhs, lhs, .void },
                });

                if (live.operandDies(inst_idx, 0)) try function.killValue(bin_op.lhs);
                if (live.operandDies(inst_idx, 1)) try function.killValue(bin_op.rhs);
            },
            .load => {
                // operand is a pointer to a local or global register
                const ty_op = air_data[@intFromEnum(inst_idx)].ty_op;
                const ptr_ty = air.typeOf(ty_op.operand, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                // @Cleanup probably unecessary but for my own sanity
                assert(Type.fromInterned(ptr_info.child).eql(ty_op.ty.toType(), zcu));

                if (ptr_info.packed_offset.host_size != 0) return function.fail("QuakeC backend does not support non-ABI-aligned pointers", .{});

                const qc_ty = try function.getQCType(ty_op.ty.toType());

                const src = try function.resolvePtrOperand(ty_op.operand);

                if (live.isUnused(inst_idx)) {
                    // Unused mustLower load (e.g. volatile): @Todo perform the
                    // read once discard targets are representable (needs a
                    // Mir.QValue variant resolving to OFS_NULL; note a 3-word
                    // discard must NOT target OFS_NULL, it would clobber
                    // OFS_RETURN). For now emit nothing.
                } else {
                    // Move policy: copy the value into a temp slot so nothing
                    // can clobber the in-flight value before its last use
                    // (e.g. a later store to the source, or a builtin writing
                    // a global).
                    // @UpgradePath alias + materialize-on-hazard removes the move.
                    const slot = try function.frameAlloc(qc_ty, .temp);
                    try function.statements.append(zcu.gpa, .{
                        .op = .store_f,
                        .args = .{ src, .{ .local = slot }, .void },
                    });
                    try function.live_values.put(zcu.gpa, inst_idx, .{ .temp = slot });
                }

                if (live.operandDies(inst_idx, 0)) try function.killValue(ty_op.operand);
            },
            .add, .sub, .mul => |op| {
                // Both operands are the same type as the result (float for now).
                // They are either the result of an air instruction or a constant,
                // never pointers.
                const bin_op = air_data[@intFromEnum(inst_idx)].bin_op;
                const qc_ty = try function.getQCType(air.typeOf(bin_op.lhs, ip));

                const a = try function.resolveOperand(bin_op.lhs);
                const b = try function.resolveOperand(bin_op.rhs);

                // Free dying operands before allocating the result so chained
                // ops (a*b*c) reuse the dying slot. Safe since the VM reads a/b
                // before writing c, so c == a or c == b is fine.
                // @Todo check that assumption holds on popular quake source ports
                if (live.operandDies(inst_idx, 0)) try function.killValue(bin_op.lhs);
                if (live.operandDies(inst_idx, 1)) try function.killValue(bin_op.rhs);

                const slot = try function.frameAlloc(qc_ty, .temp);
                try function.statements.append(zcu.gpa, .{
                    .op = switch (op) {
                        .add => .add_f,
                        .sub => .sub_f,
                        .mul => .mul_f,
                        else => unreachable,
                    },
                    .args = .{ a, b, .{ .local = slot } },
                });
                try function.live_values.put(zcu.gpa, inst_idx, .{ .temp = slot });
            },
            .cmp_gt, .cmp_gte, .cmp_lt, .cmp_lte => |op| {
                const bin_op = air_data[@intFromEnum(inst_idx)].bin_op;

                const a = try function.resolveOperand(bin_op.lhs);
                const b = try function.resolveOperand(bin_op.rhs);

                if (live.operandDies(inst_idx, 0)) try function.killValue(bin_op.lhs);
                if (live.operandDies(inst_idx, 1)) try function.killValue(bin_op.rhs);

                const slot = try function.frameAlloc(.float, .temp);
                try function.statements.append(zcu.gpa, .{
                    .op = switch (op) {
                        .cmp_gt => .gt,
                        .cmp_gte => .ge,
                        .cmp_lt => .lt,
                        .cmp_lte => .le,
                        else => unreachable,
                    },
                    .args = .{ a, b, .{ .local = slot } },
                });
                try function.live_values.put(zcu.gpa, inst_idx, .{ .temp = slot });
            },
            .bitcast => {
                const ty_op = air_data[@intFromEnum(inst_idx)].ty_op;
                // bitcasts are essentially a no-op since all lowered types are the same size.
                // We only validate the cast makes sense here.
                // @Todo I'm not 100% sure this correct behavior
                const wanted_ty = ty_op.ty.toType();
                const wanted_bitsize = wanted_ty.bitSize(zcu);
                if (wanted_bitsize > 32) return function.fail(
                    "@bitCast()-ing values greater than the word size is unsupported (size: {d})",
                    .{wanted_bitsize},
                );

                // we still need to track the value though
                if (live.operandDies(inst_idx, 0)) try function.killValue(ty_op.operand);
                const slot = try function.frameAlloc(.float, .temp);
                try function.live_values.put(zcu.gpa, inst_idx, .{ .temp = slot });
            },
            .float_from_int => {
                const ty_op = air_data[@intFromEnum(inst_idx)].ty_op;
                // float_from_int is also essentially a no-op since ints aren't allowed yet anyway.
                // We only validate the cast makes sense here.
                const ty = ty_op.ty.toInterned().?;
                if (ty != .f32_type) return function.fail(
                    "only f32s are supported, got {f}",
                    .{Type.fromInterned(ty).fmt(pt)},
                );

                // we still need to track the value though
                if (live.operandDies(inst_idx, 0)) try function.killValue(ty_op.operand);
                const slot = try function.frameAlloc(.float, .temp);
                try function.live_values.put(zcu.gpa, inst_idx, .{ .temp = slot });
            },
            .ret, .ret_safe => {
                const un_op = air_data[@intFromEnum(inst_idx)].un_op;
                if (un_op != .void_value) return function.fail("@Todo handle return values", .{});
                // Void functions end with `done`, matching qcc: a bare
                // `return` copies 3 words from args[0] to OFS_RETURN, which is
                // meaningless for void functions (and overlaps OFS_RETURN when
                // args[0] is OFS_NULL).
                try function.statements.append(zcu.gpa, .{ .op = .done });
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
    mir.locals = try zcu.gpa.dupe(Mir.ValueType, function.frame.items);
    mir.immediates = try zcu.gpa.dupe(f32, function.immediates.values());
    mir.globals = try zcu.gpa.dupe(InternPool.Nav.Index, function.globals.keys());
    return mir;
}

fn deinit(cg: *CodeGen) void {
    const gpa = cg.pt.zcu.gpa;
    cg.statements.deinit(gpa);
    cg.live_values.deinit(gpa);
    cg.frame.deinit(gpa);
    cg.free_frame_slots.deinit(gpa);
    cg.immediates.deinit(gpa);
    cg.globals.deinit(gpa);
    cg.* = undefined;
}

fn getQCType(cg: CodeGen, ty: Type) !Mir.ValueType {
    return switch (ty.toIntern()) {
        .f32_type => .float,
        // @Todo handle all QC types
        else => cg.fail("unsupported quakec backend type: {f}", .{ty.fmt(cg.pt)}),
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

/// Resolves an AIR operand to a MIR statement argument. Instruction results
/// come from `live_values` and constants are interned into `immediates`.
fn resolveOperand(cg: *CodeGen, ref: Air.Inst.Ref) !Mir.QValue {
    if (ref.toIndex()) |inst_idx| {
        const in_flight = cg.live_values.get(inst_idx) orelse
            return cg.fail("internal error: no live value for %{d}", .{@intFromEnum(inst_idx)});
        return toStmtArg(in_flight);
    }
    const zcu = cg.pt.zcu;
    const val: Value = .fromInterned(ref.toInterned().?);
    _ = try cg.getQCType(val.typeOf(zcu)); // @Todo handle all QC types
    const gop = try cg.immediates.getOrPutValue(zcu.gpa, val.toIntern(), val.toFloat(f32, zcu));
    return .{ .immediate = @intCast(gop.index) };
}

/// Resolves an AIR pointer operand to a MIR statement argument.
/// Returns the slot of the pointee.
fn resolvePtrOperand(cg: *CodeGen, ref: Air.Inst.Ref) !Mir.QValue {
    if (ref.toIndex()) |inst_idx| {
        const in_flight = cg.live_values.get(inst_idx) orelse
            return cg.fail(
                "internal error: no live value for pointer operand %{d}",
                .{@intFromEnum(inst_idx)},
            );
        return switch (in_flight) {
            .temp, .local => |slot| .{ .local = slot },
            else => cg.fail("@Todo pointer operand does not point to a local", .{}),
        };
    }
    const zcu = cg.pt.zcu;
    const ip = &zcu.intern_pool;
    const ptr_val: Value = .fromInterned(ref.toInterned().?);
    assert(ptr_val.typeOf(zcu).isSinglePointer(zcu)); // @Todo is it possible to lower stores to other pointer types?
    const nav_idx = Value.pointerNav(ptr_val, zcu) orelse
        return cg.fail("@Todo pointer operand does not point to a global", .{});
    _ = try cg.getQCType(.fromInterned(ip.getNav(nav_idx).typeOf(ip))); // @Todo handle all QC types
    const gop = try cg.globals.getOrPut(zcu.gpa, nav_idx);
    return .{ .global = @intCast(gop.index) };
}

fn toStmtArg(in_flight: ValueSlot) Mir.QValue {
    return switch (in_flight) {
        .temp => |slot| .{ .local = slot },
        .local => |slot| .{ .local = slot },
        .global => |slot| .{ .global = slot },
    };
}

/// Kills a live value and recycles its slot if it's a temp.
/// Call this only after the operand has been resolved into a statement argument,
/// and the instruction has died as per its Liveness.
///
/// Passing an interned Value or an already killed live value is a no-op.
fn killValue(cg: *CodeGen, operand: Air.Inst.Ref) !void {
    const inst_idx = operand.toIndex() orelse return;
    const entry = cg.live_values.fetchSwapRemove(inst_idx) orelse return;
    switch (entry.value) {
        .temp => |slot| try cg.free_frame_slots.append(cg.pt.zcu.gpa, slot),
        .local, .global => {},
    }
}

/// Returns a frame slot for a value to live in.
/// If in temp mode: allocates or reuses a recyclable slot for an intermediate value.
/// If in local mode: allocates a permanent slot for a variable, doesn't reuse slots.
/// @Todo vectors are explicitly ignored for now and will require a refactor.
fn frameAlloc(cg: *CodeGen, ty: Mir.ValueType, mode: enum { local, temp }) !u32 {
    assert(ty != .vector);
    if (mode == .temp) {
        if (cg.free_frame_slots.pop()) |slot| {
            cg.frame.items[slot] = ty;
            return slot;
        }
    }
    try cg.frame.append(cg.pt.zcu.gpa, ty);
    return @intCast(cg.frame.items.len - 1);
}
