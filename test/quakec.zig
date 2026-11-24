//! Behavior test harness for the QuakeC backend.

const std = @import("std");

/// A named global value. `val` is a string instead of an f32
/// to avoid needlessly converting to and from strings/floats.
/// Take care that values are not affected by precision loss
/// during parsing!
const Value = struct { name: []const u8, val: []const u8 };

inline fn v(name: []const u8, val: []const u8) Value {
    return .{ .name = name, .val = val };
}

const Case = struct {
    inputs: []const Value = &.{},
    expects: []const Value,
};

const CaseSet = struct {
    name: []const u8,
    source: []const u8,
    cases: []const Case,
    disabled: bool = false,
    /// True if the compile is expected to fail. The case asserts the exit code and
    /// (optionally) an error-message substring. No runner steps are registered.
    expect_compile_error: bool = false,
    error_substring: ?[]const u8 = null,
};

/// Behavior test cases.
pub const case_sets = [_]CaseSet{
    // ---------------------------------------------------------------- batch 1
    .{
        .name = "arith-noncommutative",
        .source =
        \\var in_a: f32 = 0;
        \\var out_sub: f32 = 0;
        \\var out_rsub: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_sub = in_a - 1;
        \\    out_rsub = 1 - in_a;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_sub", "3"), v("out_rsub", "-3") } },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_sub", "0"), v("out_rsub", "0") } },
            .{ .inputs = &.{v("in_a", "-1")}, .expects = &.{ v("out_sub", "-2"), v("out_rsub", "2") } },
        },
    },
    .{
        .name = "arith-negation",
        .source =
        \\var in_a: f32 = 0;
        \\var out_neg: f32 = 0;
        \\var out_dneg: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_neg = -in_a;
        \\    out_dneg = -(-in_a);
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_neg", "-4"), v("out_dneg", "4") } },
            .{ .inputs = &.{v("in_a", "-4")}, .expects = &.{ v("out_neg", "4"), v("out_dneg", "-4") } },
            .{ .inputs = &.{v("in_a", "2.5")}, .expects = &.{ v("out_neg", "-2.5"), v("out_dneg", "2.5") } },
        },
    },
    .{
        .name = "arith-chained",
        .source =
        \\var in_a: f32 = 0;
        \\var out_sibling: f32 = 0;
        \\var out_deep: f32 = 0;
        \\var out_cube: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_sibling = (in_a + 1) * (in_a + 2);
        \\    out_deep = (in_a * 2 + 3) * 4 - 5;
        \\    out_cube = in_a * in_a * in_a;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_sibling", "12"), v("out_deep", "23"), v("out_cube", "8") } },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_sibling", "6"), v("out_deep", "15"), v("out_cube", "1") } },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{ v("out_sibling", "2"), v("out_deep", "7"), v("out_cube", "0") } },
        },
    },
    .{
        .name = "arith-accumulate",
        .source =
        \\var in_a: f32 = 0;
        \\var out_acc: f32 = 0;
        \\var out_self: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var s: f32 = 0;
        \\    s += in_a;
        \\    s += in_a;
        \\    s += in_a;
        \\    out_acc = s;
        \\    var t: f32 = in_a;
        \\    t = t * t;
        \\    t = t + t;
        \\    out_self = t;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_acc", "6"), v("out_self", "8") } },
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{ v("out_acc", "9"), v("out_self", "18") } },
            .{ .inputs = &.{v("in_a", "-2")}, .expects = &.{ v("out_acc", "-6"), v("out_self", "8") } },
        },
    },
    .{
        .name = "arith-live-temps",
        .source =
        \\var in_a: f32 = 0;
        \\var out_many: f32 = 0;
        \\var out_recycle: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const a: f32 = in_a + 1;
        \\    const b: f32 = in_a + 2;
        \\    const c: f32 = in_a + 3;
        \\    const d: f32 = in_a + 4;
        \\    const e: f32 = in_a + 5;
        \\    const f: f32 = in_a + 6;
        \\    out_many = a + b + c + d + e + f;
        \\    const g: f32 = in_a + 1;
        \\    const s: f32 = g * 2;
        \\    const h: f32 = in_a + 3;
        \\    const t: f32 = h * 2;
        \\    out_recycle = s + t;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_many", "27"), v("out_recycle", "12") } },
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_many", "33"), v("out_recycle", "16") } },
        },
    },
    .{
        .name = "arith-exact",
        .source =
        \\var in_a: f32 = 0;
        \\var out_add: f32 = 0;
        \\var out_mul: f32 = 0;
        \\var out_fold: f32 = 0;
        \\var out_sq: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_add = in_a + 0.25;
        \\    out_mul = in_a * 0.5;
        \\    out_fold = in_a + 1.5 * 2;
        \\    out_sq = in_a * in_a;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_add", "4.25"), v("out_mul", "2"), v("out_fold", "7"), v("out_sq", "16") } },
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{ v("out_add", "3.25"), v("out_mul", "1.5"), v("out_fold", "6"), v("out_sq", "9") } },
            .{ .inputs = &.{v("in_a", "0.5")}, .expects = &.{ v("out_add", "0.75"), v("out_mul", "0.25"), v("out_fold", "3.5"), v("out_sq", "0.25") } },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{ v("out_add", "0.25"), v("out_mul", "0"), v("out_fold", "3"), v("out_sq", "0") } },
        },
    },
    // ---------------------------------------------------------------- batch 2
    .{
        .name = "cmp-boundaries",
        .source =
        \\var in_a: f32 = 0;
        \\var out_gt: f32 = 0;
        \\var out_gte: f32 = 0;
        \\var out_lt: f32 = 0;
        \\var out_le: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_gt = if (in_a > 2) 1 else 2;
        \\    out_gte = if (in_a >= 2) 1 else 2;
        \\    out_lt = if (in_a < 2) 1 else 2;
        \\    out_le = if (in_a <= 2) 1 else 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_gt", "2"), v("out_gte", "1"), v("out_lt", "2"), v("out_le", "1") } },
            .{ .inputs = &.{v("in_a", "1.5")}, .expects = &.{ v("out_gt", "2"), v("out_gte", "2"), v("out_lt", "1"), v("out_le", "1") } },
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{ v("out_gt", "1"), v("out_gte", "1"), v("out_lt", "2"), v("out_le", "2") } },
        },
    },
    .{
        .name = "cmp-mirrored",
        .source =
        \\var in_a: f32 = 0;
        \\var out_lt: f32 = 0;
        \\var out_gt: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_lt = if (2 < in_a) 1 else 2;
        \\    out_gt = if (2 > in_a) 1 else 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{ v("out_lt", "1"), v("out_gt", "2") } },
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_lt", "2"), v("out_gt", "2") } },
        },
    },
    .{
        .name = "cmp-range",
        .source =
        \\var in_a: f32 = 0;
        \\var out_r: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_r = if (in_a > 2) 1 else if (in_a < 2) 2 else 3;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{v("out_r", "1")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out_r", "2")} },
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{v("out_r", "3")} },
        },
    },
    // ---------------------------------------------------------------- batch 3
    .{
        .name = "branch-cond-live",
        .source =
        \\var in_a: f32 = 0;
        \\var out_then: f32 = 0;
        \\var out_else: f32 = 0;
        \\var out_elseonly: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_then = if (in_a > 2) in_a + in_a else 7;
        \\    out_else = if (in_a > 2) 7 else in_a + in_a;
        \\    out_elseonly = if (in_a > 2) 1 else in_a + 5;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_then", "8"), v("out_else", "7"), v("out_elseonly", "1") } },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_then", "7"), v("out_else", "2"), v("out_elseonly", "6") } },
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_then", "7"), v("out_else", "4"), v("out_elseonly", "7") } },
        },
    },
    .{
        .name = "branch-merge",
        .source =
        \\var in_a: f32 = 0;
        \\var out_add: f32 = 0;
        \\var out_mul: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_add = if (in_a > 2) in_a + 1 else in_a + 2;
        \\    out_mul = if (in_a > 2) in_a * 2 else in_a * 3;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{ v("out_add", "4"), v("out_mul", "6") } },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_add", "3"), v("out_mul", "3") } },
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_add", "5"), v("out_mul", "8") } },
        },
    },
    .{
        .name = "branch-create-both",
        .source =
        \\var in_a: f32 = 0;
        \\var out_inner: f32 = 0;
        \\var out_sum: f32 = 0;
        \\var u: f32 = 0;
        \\var s: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 2) {
        \\        out_inner = in_a + 4;
        \\        u = in_a * 2;
        \\        s = 1;
        \\    } else {
        \\        out_inner = 0;
        \\        u = in_a * 3;
        \\        s = 2;
        \\    }
        \\    out_sum = s + u;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_inner", "8"), v("out_sum", "9") } },
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_inner", "0"), v("out_sum", "8") } },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_inner", "0"), v("out_sum", "5") } },
        },
    },
    .{
        .name = "branch-nested",
        .source =
        \\var in_a: f32 = 0;
        \\var out_sel: f32 = 0;
        \\var out_u: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 0) {
        \\        if (in_a > 1) {
        \\            out_sel = 1;
        \\            out_u = in_a * 2;
        \\        } else {
        \\            out_sel = 2;
        \\            out_u = in_a * 3;
        \\        }
        \\    } else {
        \\        out_sel = 3;
        \\        out_u = in_a;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_sel", "1"), v("out_u", "8") } },
            .{ .inputs = &.{v("in_a", "0.5")}, .expects = &.{ v("out_sel", "2"), v("out_u", "1.5") } },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{ v("out_sel", "3"), v("out_u", "0") } },
        },
    },
    .{
        .name = "branch-one-armed",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var s: f32 = 7;
        \\    if (in_a > 2) {
        \\        s = in_a + 1;
        \\    }
        \\    out = s;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "5")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "7")} },
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{v("out", "7")} },
        },
    },
    .{
        .name = "branch-return-else",
        .source =
        \\var in_a: f32 = 0;
        \\var out_pre: f32 = 0;
        \\var out_post: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 2) {
        \\        out_pre = 1;
        \\    } else {
        \\        out_pre = 2;
        \\        return;
        \\    }
        \\    out_post = 3;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_pre", "1"), v("out_post", "3") } },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{ v("out_pre", "2"), v("out_post", "0") } },
        },
    },
    .{
        .name = "branch-nested-return",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 2) {
        \\        if (in_a > 3) {
        \\            out = 1;
        \\            return;
        \\        }
        \\        out = 2;
        \\        return;
        \\    }
        \\    out = 3;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "1")} },
            .{ .inputs = &.{v("in_a", "2.5")}, .expects = &.{v("out", "2")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "3")} },
        },
    },
    .{
        .name = "branch-comptime",
        .source =
        \\var in_a: f32 = 0;
        \\var out_false: f32 = 0;
        \\var out_folded: f32 = 0;
        \\var out_true: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const one: f32 = 1;
        \\    out_false = if (false) 100 else in_a + 1;
        \\    out_folded = if (one > 0) in_a else 0;
        \\    out_true = if (true) in_a + 1 else 100;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_false", "5"), v("out_folded", "4"), v("out_true", "5") } },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{ v("out_false", "1"), v("out_folded", "0"), v("out_true", "1") } },
        },
    },
    // ---------------------------------------------------------------- batch 4
    .{
        .name = "global-nav-init",
        .source =
        \\var in_a: f32 = 0;
        \\var out_keep: f32 = 99;
        \\var out_res: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 100) {
        \\        out_keep = out_keep + 0;
        \\        return;
        \\    }
        \\    out_res = 50;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "200")}, .expects = &.{ v("out_keep", "99"), v("out_res", "0") } },
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_keep", "99"), v("out_res", "50") } },
        },
    },
    .{
        .name = "global-roundtrip",
        .source =
        \\var in_a: f32 = 0;
        \\var g: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    g = in_a + 1;
        \\    out = g * 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "10")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "4")} },
        },
    },
    .{
        .name = "global-both-branches",
        .source =
        \\var in_a: f32 = 0;
        \\var g: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 2) {
        \\        g = in_a + 1;
        \\    } else {
        \\        g = in_a + 2;
        \\    }
        \\    out = g * 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "10")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "6")} },
        },
    },
    .{
        .name = "global-interleave",
        .source =
        \\var in_a: f32 = 0;
        \\var a: f32 = 0;
        \\var b: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    a = in_a;
        \\    b = a + 1;
        \\    a = b + 1;
        \\    out = a * 10 + b;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{v("out", "54")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "32")} },
        },
    },
    .{
        .name = "global-unused",
        .source =
        \\var in_a: f32 = 0;
        \\var unused: f32 = 42;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    unused = unused + 0;
        \\    out = in_a + 1;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out", "5"), v("unused", "42") } },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{ v("out", "1"), v("unused", "42") } },
        },
    },
    .{
        .name = "store-patterns",
        .source =
        \\var in_a: f32 = 0;
        \\var out_overwrite: f32 = 0;
        \\var out_use: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_overwrite = 1;
        \\    out_overwrite = 2;
        \\    out_overwrite = in_a;
        \\    const s: f32 = in_a;
        \\    out_use = s + s;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_overwrite", "4"), v("out_use", "8") } },
            .{ .inputs = &.{v("in_a", "-2")}, .expects = &.{ v("out_overwrite", "-2"), v("out_use", "-4") } },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{ v("out_overwrite", "0"), v("out_use", "0") } },
        },
    },
    // ---------------------------------------------------------------- batch 5
    .{
        .name = "float-inf",
        .source =
        \\var in_a: f32 = 0;
        \\var out_dbl: f32 = 0;
        \\var out_big: f32 = 0;
        \\var out_sq: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_dbl = in_a * 2;
        \\    out_big = if (in_a > 1000000) 1 else 2;
        \\    out_sq = in_a * in_a;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "inf")}, .expects = &.{ v("out_dbl", "inf"), v("out_big", "1"), v("out_sq", "inf") } },
            .{ .inputs = &.{v("in_a", "-inf")}, .expects = &.{ v("out_dbl", "-inf"), v("out_big", "2"), v("out_sq", "inf") } },
            .{ .inputs = &.{v("in_a", "1e30")}, .expects = &.{ v("out_dbl", "2e30"), v("out_big", "1"), v("out_sq", "inf") } },
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{ v("out_dbl", "6"), v("out_big", "2"), v("out_sq", "9") } },
        },
    },
    .{
        .name = "float-nan-order",
        .source =
        \\var in_a: f32 = 0;
        \\var out_pos: f32 = 0;
        \\var out_lt: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_pos = if (in_a > 0) 1 else 2;
        \\    out_lt = if (in_a < 0) 1 else 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "nan")}, .expects = &.{ v("out_pos", "2"), v("out_lt", "2") } },
            .{ .inputs = &.{v("in_a", "-0")}, .expects = &.{ v("out_pos", "2"), v("out_lt", "2") } },
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{ v("out_pos", "1"), v("out_lt", "2") } },
            .{ .inputs = &.{v("in_a", "-4")}, .expects = &.{ v("out_pos", "2"), v("out_lt", "1") } },
        },
    },
    // Covers equality boundaries, NaN self-inequality, and -0.0 == 0.0.
    .{
        .name = "cmp-eq-ne",
        .source =
        \\var in_a: f32 = 0;
        \\var out_eq: f32 = 0;
        \\var out_ne: f32 = 0;
        \\var out_selfeq: f32 = 0;
        \\var out_zero: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_eq = if (in_a == 2) 1 else 2;
        \\    out_ne = if (in_a != 2) 1 else 2;
        \\    out_selfeq = if (in_a == in_a) 1 else 2;
        \\    out_zero = if (in_a == 0) 1 else 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "2")}, .expects = &.{ v("out_eq", "1"), v("out_ne", "2"), v("out_selfeq", "1"), v("out_zero", "2") } },
            .{ .inputs = &.{v("in_a", "nan")}, .expects = &.{ v("out_selfeq", "2"), v("out_zero", "2") } },
            .{ .inputs = &.{v("in_a", "-0")}, .expects = &.{v("out_zero", "1")} },
        },
    },
    // ------------------------------------------------- kept-migrated sets
    .{
        .name = "two-ifs",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const s: f32 = if (in_a > 2) 1 else 2;
        \\    if (in_a > 3) {
        \\        out = s + 10;
        \\    } else {
        \\        out = s + 20;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "11")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "22")} },
        },
    },
    .{
        .name = "early-return",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 0) {
        \\        out = 1;
        \\        return;
        \\    }
        \\    out = 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "1")} },
            .{ .inputs = &.{v("in_a", "0")}, .expects = &.{v("out", "2")} },
        },
    },
    .{
        .name = "both-return",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (in_a > 0) {
        \\        out = 1;
        \\        return;
        \\    } else {
        \\        out = 2;
        \\        return;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "1")} },
            .{ .inputs = &.{v("in_a", "-1")}, .expects = &.{v("out", "2")} },
        },
    },
    // ---------------------------------------------------------------- batch 6
    .{
        .name = "while-loop",
        .source =
        \\var sum: f32 = 0;
        \\var i: f32 = 0;
        \\export fn main() callconv(.quakec) void {
        \\    while (i < 5) : (i += 1) {
        \\        sum += i;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{}, .expects = &.{ v("sum", "10"), v("i", "5") } },
        },
    },
    .{
        // Port of test "while with continue expression" from
        // test/behavior/while.zig (i32 -> f32; expect -> out global).
        .name = "while-continue-expr",
        .source =
        \\var out_sum: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var sum: f32 = 0;
        \\    {
        \\        var i: f32 = 0;
        \\        while (i < 10) : (i += 1) {
        \\            if (i == 5) continue;
        \\            sum += i;
        \\        }
        \\    }
        \\    out_sum = sum;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out_sum", "40")} },
        },
    },
    .{
        // Port of test "while with else" from test/behavior/while.zig
        // (i32 -> f32; expect -> out globals).
        .name = "while-else",
        .source =
        \\var out_sum: f32 = 0;
        \\var out_else: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var sum: f32 = 0;
        \\    var i: f32 = 0;
        \\    var got_else: f32 = 0;
        \\    while (i < 10) : (i += 1) {
        \\        sum += 1;
        \\    } else {
        \\        got_else += 1;
        \\    }
        \\    out_sum = sum;
        \\    out_else = got_else;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{ v("out_sum", "10"), v("out_else", "1") } },
        },
    },
    .{
        // Port of test "continue and break" from test/behavior/while.zig
        // (i32 -> f32; expect -> out globals; counter global -> local).
        .name = "while-continue-and-break",
        .source =
        \\var out_i: f32 = 0;
        \\var out_counter: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var counter: f32 = 0;
        \\    var i: f32 = 0;
        \\    while (true) {
        \\        counter += 2;
        \\        i += 1;
        \\        if (i < 4) {
        \\            continue;
        \\        }
        \\        break;
        \\    }
        \\    out_i = i;
        \\    out_counter = counter;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{ v("out_i", "4"), v("out_counter", "8") } },
        },
    },
    .{
        // Port of test "break from outer while loop" from
        // test/behavior/while.zig (a normal return -> out global).
        .name = "while-break-outer",
        .source =
        \\var out: bool = false;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    outer: while (true) {
        \\        while (true) {
        \\            break :outer;
        \\        }
        \\    }
        \\    out = true;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out", "1")} },
        },
    },
    .{
        // Port of test "continue outer while loop" from
        // test/behavior/while.zig (usize -> f32; expect -> out global).
        .name = "while-continue-outer",
        .source =
        \\var out_i: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var i: f32 = 0;
        \\    outer: while (i < 10) : (i += 1) {
        \\        while (true) {
        \\            continue :outer;
        \\        }
        \\    }
        \\    out_i = i;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out_i", "10")} },
        },
    },
    .{
        // Port of test "while bool 2 break statements and an else" from
        // test/behavior/while.zig (S.entry params -> input globals;
        // expect -> out global).
        .name = "while-bool-else-result",
        .source =
        \\var in_t: bool = false;
        \\var in_f: bool = false;
        \\var out_ok: bool = false;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var ok = false;
        \\    ok = while (in_t) {
        \\        if (in_f) break false;
        \\        if (in_t) break true;
        \\    } else false;
        \\    out_ok = ok;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{ v("in_t", "1"), v("in_f", "0") }, .expects = &.{v("out_ok", "1")} },
        },
    },
    // ---------------------------------------------------------------- batch 7
    .{
        // Port of testShortCircuit from test/behavior/bool.zig. The hit flags
        // check which bodies ran, out_err marks operands/bodies that must not
        // execute (catches eager evaluation and wrong or/and values).
        .name = "short-circuit",
        .source =
        \\var in_f: bool = false;
        \\var in_t: bool = true;
        \\var out_h1: bool = false;
        \\var out_h2: bool = false;
        \\var out_h3: bool = false;
        \\var out_h4: bool = false;
        \\var out_err: bool = false;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var hit_1 = in_f;
        \\    var hit_2 = in_f;
        \\    var hit_3 = in_f;
        \\    var hit_4 = in_f;
        \\
        \\    if (in_t or x: {
        \\        out_err = true;
        \\        break :x in_f;
        \\    }) {
        \\        hit_1 = in_t;
        \\    }
        \\    if (in_f or x: {
        \\        hit_2 = in_t;
        \\        break :x in_f;
        \\    }) {
        \\        out_err = true;
        \\    }
        \\
        \\    if (in_t and x: {
        \\        hit_3 = in_t;
        \\        break :x in_f;
        \\    }) {
        \\        out_err = true;
        \\    }
        \\    if (in_f and x: {
        \\        out_err = true;
        \\        break :x in_f;
        \\    }) {
        \\        out_err = true;
        \\    } else {
        \\        hit_4 = in_t;
        \\    }
        \\
        \\    out_h1 = hit_1;
        \\    out_h2 = hit_2;
        \\    out_h3 = hit_3;
        \\    out_h4 = hit_4;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{ v("in_f", "0"), v("in_t", "1") }, .expects = &.{
                v("out_h1", "1"),
                v("out_h2", "1"),
                v("out_h3", "1"),
                v("out_h4", "1"),
                v("out_err", "0"),
            } },
        },
    },
    .{
        .name = "and-const-rhs",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = if (in_a > 2 and true) 1 else 2;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "3")}, .expects = &.{v("out", "1")} },
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "2")} },
        },
    },
    .{
        .name = "bool-not",
        .source =
        \\var in_b: bool = false;
        \\var out_not: bool = false;
        \\var out_dnot: bool = false;
        \\var out_gnot: bool = false;
        \\var out_cond: bool = false;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var b = in_b;
        \\    b = !b;
        \\    out_not = b;
        \\    out_dnot = !!b;
        \\    out_gnot = !out_not;
        \\    if (!b) {
        \\        out_cond = true;
        \\    } else {
        \\        out_cond = false;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_b", "0")}, .expects = &.{
                v("out_not", "1"),
                v("out_dnot", "1"),
                v("out_gnot", "0"),
                v("out_cond", "0"),
            } },
            .{ .inputs = &.{v("in_b", "1")}, .expects = &.{
                v("out_not", "0"),
                v("out_dnot", "0"),
                v("out_gnot", "1"),
                v("out_cond", "1"),
            } },
        },
    },
    // ---------------------------------------------------------------- batch 8
    .{
        .name = "fail-float-from-int",
        .expect_compile_error = true,
        .error_substring = "unsupported quakec backend type: u1",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = @floatFromInt(@intFromBool(in_a > 2));
        \\}
        ,
        .cases = &.{},
    },
    .{
        .name = "fail-oversize-bitcast",
        .expect_compile_error = true,
        .error_substring = "unsupported quakec backend type: f64",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var x: f64 = @bitCast(@as(u64, 2));
        \\    out = 0;
        \\    _ = &x;
        \\}
        ,
        .cases = &.{},
    },
    .{
        .name = "fail-vector-local",
        .expect_compile_error = true,
        .error_substring = "unsupported quakec backend type",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var v: @Vector(2, f32) = .{ in_a, 2 };
        \\    out = 0;
        \\    _ = &v;
        \\}
        ,
        .cases = &.{},
    },
    // ------------------------------------------------- batch 9
    .{
        .disabled = true, // runtime @bitCast lowers to `bit_cast_safe` in safe builds (unimplemented); ints also banned (u24/i25 plan)
        .name = "bitcast-roundtrip",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const bits: u32 = @bitCast(in_a);
        \\    out = @bitCast(bits);
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "4")}, .expects = &.{v("out", "4")} },
            .{ .inputs = &.{v("in_a", "-2")}, .expects = &.{v("out", "-2")} },
        },
    },
    .{
        .name = "calls-and-params",
        .source =
        \\var in_a: f32 = 0;
        \\var in_b: f32 = 0;
        \\var out: f32 = 0;
        \\export fn main() callconv(.quakec) void {
        \\    out = add(in_a, in_b);
        \\}
        \\fn add(a: f32, b: f32) f32 {
        \\    return a + b;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{ v("in_a", "4"), v("in_b", "8") }, .expects = &.{v("out", "12")} },
        },
    },
    .{
        // Port of test "params" from test/behavior/fn.zig (i32 -> f32; literal args).
        .name = "fn-params",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = add(22, 11);
        \\}
        \\
        \\fn add(a: f32, b: f32) f32 {
        \\    return a + b;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out", "33")} },
        },
    },
    .{
        // Port of test "assign inline fn to const variable" from
        // test/behavior/fn.zig (out global proves execution continued past
        // the inlined call; the original asserts no error).
        .name = "fn-inline-alias",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const a = inlineFn;
        \\    a();
        \\    out = 1;
        \\}
        \\
        \\inline fn inlineFn() void {
        \\    out = 2;
        \\}
        ,
        .cases = &.{.{ .expects = &.{v("out", "1")} }},
    },
    .{
        // Port of test "local variables" from test/behavior/fn.zig
        // (i32 -> f32; unreachable -> out flag; void fn call).
        .name = "fn-local-vars",
        .source =
        \\var in_b: f32 = 0;
        \\var out_ok: bool = false;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    locVars(in_b);
        \\}
        \\
        \\fn locVars(b: f32) void {
        \\    const a: f32 = 1;
        \\    out_ok = a + b == 3;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_b", "2")}, .expects = &.{v("out_ok", "1")} },
        },
    },
    .{
        // Port of test "mutable local variables" from test/behavior/fn.zig
        // (i32 -> f32; zero checked via the return value).
        .name = "fn-mutable-locals",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = mutLocs();
        \\}
        \\
        \\fn mutLocs() f32 {
        \\    var zero: f32 = 0;
        \\    _ = &zero;
        \\    var i: f32 = 0;
        \\    while (i != 3) {
        \\        i += 1;
        \\    }
        \\    return i - zero;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out", "3")} },
        },
    },
    .{
        // Port of test "separate block scopes" from test/behavior/fn.zig
        // (i32 -> f32; expect -> globals).
        .name = "fn-block-scopes",
        .source =
        \\var out_inner: f32 = 0;
        \\var out_c: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_c = blockScopes();
        \\}
        \\
        \\fn blockScopes() f32 {
        \\    {
        \\        const no_conflict: f32 = 5;
        \\        out_inner = no_conflict;
        \\    }
        \\
        \\    const c = x: {
        \\        const no_conflict: f32 = 10;
        \\        break :x no_conflict;
        \\    };
        \\    return c;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{ v("out_inner", "5"), v("out_c", "10") } },
        },
    },
    .{
        // Port of test "weird function name" from test/behavior/fn.zig
        // (i32 -> f32; expect -> out global).
        .name = "fn-weird-name",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = @"weird function name"();
        \\}
        \\
        \\fn @"weird function name"() f32 {
        \\    return 1234;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out", "1234")} },
        },
    },
    .{
        // Port of test "function parameter self equality" from
        // test/behavior/fn.zig (u32 -> f32; expect -> out globals;
        // S struct methods -> plain fns). Also proves multi-function
        // linking with 6 callees off one caller.
        .name = "fn-param-self-compare",
        .source =
        \\var in_x: f32 = 0;
        \\var out_eq: bool = false;
        \\var out_ne: bool = false;
        \\var out_lt: bool = false;
        \\var out_le: bool = false;
        \\var out_gt: bool = false;
        \\var out_ge: bool = false;
        \\
        \\const S = struct {
        \\    fn equal(x: f32) bool {
        \\        return x == x;
        \\    }
        \\    fn notEqual(x: f32) bool {
        \\        return x != x;
        \\    }
        \\    fn lessThan(x: f32) bool {
        \\        return x < x;
        \\    }
        \\    fn lessThanOrEqual(x: f32) bool {
        \\        return x <= x;
        \\    }
        \\    fn greaterThan(x: f32) bool {
        \\        return x > x;
        \\    }
        \\    fn greaterThanOrEqual(x: f32) bool {
        \\        return x >= x;
        \\    }
        \\};
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_eq = S.equal(in_x);
        \\    out_ne = S.notEqual(in_x);
        \\    out_lt = S.lessThan(in_x);
        \\    out_le = S.lessThanOrEqual(in_x);
        \\    out_gt = S.greaterThan(in_x);
        \\    out_ge = S.greaterThanOrEqual(in_x);
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_x", "42")}, .expects = &.{
                v("out_eq", "1"),
                v("out_ne", "0"),
                v("out_lt", "0"),
                v("out_le", "1"),
                v("out_gt", "0"),
                v("out_ge", "1"),
            } },
        },
    },
    .{
        .name = "fn-call-live-result",
        .source =
        \\var out_nested: f32 = 0;
        \\var out_seq: f32 = 0;
        \\
        \\fn add(a: f32, b: f32) f32 {
        \\    return a + b;
        \\}
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out_nested = add(add(1, 2), add(3, 4));
        \\    const x = add(1, 2);
        \\    const y = add(3, 4);
        \\    out_seq = x + y;
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{ v("out_nested", "10"), v("out_seq", "10") } },
        },
    },
    .{
        // Port of test "function pointers" from test/behavior/fn.zig, in the
        // shape of a too-many-args call. Fails in the caller before the callee's
        // own params are counted, so the substring is the .call error.
        .name = "fail-too-many-args",
        .expect_compile_error = true,
        .error_substring = "too many arguments",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\fn sum9(a: f32, b: f32, c: f32, d: f32, e: f32, f: f32, g: f32, h: f32, i: f32) f32 {
        \\    return a + b + c + d + e + f + g + h + i;
        \\}
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = sum9(in_a, in_a, in_a, in_a, in_a, in_a, in_a, in_a, in_a);
        \\}
        ,
        .cases = &.{},
    },
    .{
        // Port of test "void parameters" from test/behavior/fn.zig
        // (i32 -> f32; try/expect -> out global).
        .name = "fn-void-params",
        .source =
        \\var in_a: f32 = 0;
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    voidFun(in_a, {}, 2, {});
        \\}
        \\
        \\fn voidFun(a: f32, b: void, c: f32, d: void) void {
        \\    _ = b;
        \\    _ = d;
        \\    out = a + c;
        \\}
        ,
        .cases = &.{
            .{ .inputs = &.{v("in_a", "1")}, .expects = &.{v("out", "3")} },
        },
    },
    .{
        // Port of test "function pointers" from test/behavior/fn.zig, reduced
        // to a single indirect call (the original uses an array of pointers).
        .name = "fail-fn-pointer",
        .expect_compile_error = true,
        .error_substring = "unsupported quakec backend type: *const fn",
        .source =
        \\var out: f32 = 0;
        \\
        \\fn fn1() f32 {
        \\    return 5;
        \\}
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var f: *const fn () f32 = &fn1;
        \\    _ = &f;
        \\    out = f();
        \\}
        ,
        .cases = &.{.{ .expects = &.{v("out", "5")} }},
    },
    .{
        // Port of test "super basic invocations" from test/behavior/call.zig
        // (i32 -> f32; expect -> out global; comptime halves kept).
        .name = "call-super-basic",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const foo = struct {
        \\        fn foo() f32 {
        \\            return 1234;
        \\        }
        \\    }.foo;
        \\
        \\    out = @call(.auto, foo, .{});
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out", "1234")} },
        },
    },
    .{
        // Port of test "basic invocations" from test/behavior/call.zig
        // (i32 -> f32; expect -> out globals; comptime block kept except the
        // .always_tail line; the runtime-known fn pointer lines dropped).
        .name = "call-basic",
        .source =
        \\var out_auto: f32 = 0;
        \\var out_no_suspend: f32 = 0;
        \\var out_never_inline: f32 = 0;
        \\var out_never_tail: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const foo = struct {
        \\        fn foo(_: f32) f32 {
        \\            return 1234;
        \\        }
        \\    }.foo;
        \\
        \\    out_auto = @call(.auto, foo, .{1});
        \\    out_no_suspend = @call(.no_suspend, foo, .{2});
        \\    out_never_inline = @call(.never_inline, foo, .{3});
        \\    out_never_tail = @call(.never_tail, foo, .{4});
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{
                v("out_auto", "1234"),
                v("out_no_suspend", "1234"),
                v("out_never_inline", "1234"),
                v("out_never_tail", "1234"),
            } },
        },
    },
    .{
        // Port of test "recursive inline call with comptime known argument"
        // from test/behavior/call.zig (i32 -> f32; expect -> out global).
        .name = "call-inline-recursion",
        .source =
        \\var out: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const S = struct {
        \\        inline fn foo(x: f32) f32 {
        \\            if (x <= 0) {
        \\                return 0;
        \\            } else {
        \\                return x * 2 + foo(x - 1);
        \\            }
        \\        }
        \\    };
        \\
        \\    out = S.foo(4);
        \\}
        ,
        .cases = &.{
            .{ .expects = &.{v("out", "20")} },
        },
    },
    .{
        // Port of test "forced tail call" from test/behavior/call.zig, as an
        // always_tail error probe (the backend rejects tail calls in Sema).
        .name = "fail-always-tail-call",
        .expect_compile_error = true,
        .error_substring = "does not support tail calls",
        .source =
        \\var out: f32 = 0;
        \\
        \\fn foo() f32 {
        \\    return 42;
        \\}
        \\
        \\fn caller() f32 {
        \\    return @call(.always_tail, foo, .{});
        \\}
        \\
        \\export fn main() callconv(.quakec) void {
        \\    out = caller();
        \\}
        ,
        .cases = &.{},
    },
};

pub fn addQuakeCTests(
    b: *std.Build,
    step: *std.Build.Step,
    opts: struct {
        compiler_exe: *std.Build.Step.Compile,
        dev_env: @import("../src/dev.zig").Env,
        test_filters: []const []const u8,
    },
) void {
    if (opts.dev_env != .quakec) {
        step.dependOn(&b.addFail("test-quakec requires the compiler under testing to have the QuakeC backend enabled (-Ddev=quakec)").step);
        return;
    }
    if (!@import("tests.zig").isNative(&opts.compiler_exe.root_module.resolved_target.?, &b.graph.host.result)) {
        step.dependOn(&b.addFail("test-quakec requires the compiler under testing to be built for the host target").step);
        return;
    }

    const qcvm_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/qcvm/qcvm.zig"),
    });
    const runner_exe = b.addExecutable(.{
        .name = "qctest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/src/qctest.zig"),
            .target = b.graph.host,
            .imports = &.{
                .{ .name = "qcvm", .module = qcvm_mod },
            },
        }),
    });

    const wf = b.addWriteFiles();
    for (case_sets) |set| {
        if (set.disabled) continue;
        for (opts.test_filters) |filter| {
            if (std.mem.find(u8, set.name, filter) != null) break;
        } else if (opts.test_filters.len > 0) continue; // name does not match any filter

        const src = wf.add(b.fmt("cases/{s}.zig", .{set.name}), set.source);
        const compile = b.addRunArtifact(opts.compiler_exe);
        compile.addArgs(&.{ "build-exe", "-fno-llvm", "-fno-lld", "-target", "quakec-freestanding" });
        // compile.addArgs(&.{ "--debug-log", "codegen" });
        compile.addFileArg(src);
        compile.addArgs(&.{ "--name", set.name });
        const dat = compile.addPrefixedOutputFileArg("-femit-bin=", b.fmt("{s}.dat", .{set.name}));
        if (set.expect_compile_error) {
            compile.expectExitCode(1);
            if (set.error_substring) |sub| compile.expectStdErrMatch(sub);
        } else {
            compile.expectExitCode(0);
        }
        step.dependOn(&compile.step);

        if (set.expect_compile_error) continue;
        for (set.cases, 0..) |case, i| {
            const runcase = b.addRunArtifact(runner_exe);
            runcase.addFileArg(dat);
            if (case.inputs.len > 0) {
                runcase.addArg("--input");
                runcase.addArg(joinValues(b, case.inputs));
            }
            if (case.expects.len > 0) {
                runcase.addArg("--expect");
                runcase.addArg(joinValues(b, case.expects));
            }
            runcase.expectExitCode(0);
            if (set.cases.len > 1)
                runcase.setName(b.fmt("test {s}-{d}", .{ set.name, i }))
            else
                runcase.setName(b.fmt("test {s}", .{set.name}));
            step.dependOn(&runcase.step);
        }
    }
}

fn joinValues(b: *std.Build, values: []const Value) []const u8 {
    var alloc_size: usize = 0;
    for (values) |val| alloc_size += 1 + val.name.len + 1 + val.val.len;

    var buf = std.ArrayList(u8).initCapacity(b.allocator, alloc_size) catch @panic("OOM");
    for (values, 0..) |val, i| {
        if (i > 0) buf.appendSliceAssumeCapacity(",");
        buf.appendSliceAssumeCapacity(val.name);
        buf.appendAssumeCapacity('=');
        buf.appendSliceAssumeCapacity(val.val);
    }
    return buf.items;
}
