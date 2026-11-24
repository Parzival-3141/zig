pub fn storageType(ty: Type, ip: *const InternPool) ?Mir.ValueType {
    return switch (ty.toIntern()) {
        .f32_type,
        .bool_type,
        => .float,
        _ => |idx| blk: {
            const unwrapped = idx.unwrap(ip);
            break :blk switch (unwrapped.getTag(ip)) {
                .type_function => if (ip.indexToFuncType(idx).?.is_var_args) null else .function,
                else => null,
            };
        },
        else => null,
    };
}

/// Storage size in words (32bits)
pub fn storageSize(qc_ty: Mir.ValueType) u8 {
    return switch (qc_ty) {
        .void => 0,
        .string,
        .float,
        .entity,
        .field,
        .function,
        .pointer,
        => 1,
        .vector => 3,
        _ => unreachable,
    };
}

pub fn floatFromValue(val: Value, ip: *const InternPool) f32 {
    return switch (val.toIntern()) {
        .bool_true => 1.0,
        .bool_false => 0.0,
        else => |val_idx| switch (ip.indexToKey(val_idx)) {
            .float => |float| switch (float.storage) {
                inline else => |x| @floatCast(x),
            },
            else => |key| std.debug.panic("@Incomplete unimplemented value type: {}", .{key}),
        },
    };
}

const InternPool = @import("../../InternPool.zig");
const Type = @import("../../Type.zig");
const Value = @import("../../Value.zig");
const Mir = @import("Mir.zig");
const std = @import("std");
