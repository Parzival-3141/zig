pub fn storageType(ty: Type) ?Mir.ValueType {
    return switch (ty.toIntern()) {
        .f32_type,
        .bool_type,
        => .float,
        else => null,
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
