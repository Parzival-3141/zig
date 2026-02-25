const std = @import("std");
const link = @import("../../link.zig");
const codegen = @import("../../codegen.zig");

const Mir = @import("Mir.zig");
const Zcu = @import("../../Zcu.zig");
const Air = @import("../../Air.zig");
const InternPool = @import("../../InternPool.zig");

pub fn legalizeFeatures(_: *const std.Target) *const Air.Legalize.Features {
    return comptime &.initEmpty();
}

pub fn generate(
    lf: *link.File,
    pt: Zcu.PerThread,
    src_loc: Zcu.LazySrcLoc,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) codegen.CodeGenError!Mir {
    _ = lf; // autofix
    _ = pt; // autofix
    _ = src_loc; // autofix
    _ = func_index; // autofix
    _ = air; // autofix
    _ = liveness; // autofix
    @panic("@Todo");
}
