//! Behavior test harness for the QuakeC backend.

const std = @import("std");

const Case = struct { input: f32, expected: f32 };
const CaseSet = struct {
    name: []const u8,
    source: []const u8,
    cases: []const Case,
    disabled: bool = false,
};

/// Behavior test cases.
/// The `input` global is written by the runner before `main` executes.
pub const case_sets = [_]CaseSet{
    .{
        .name = "two-branch",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const t: f32 = input;
        \\    var s: f32 = 0;
        \\    if (t > 2) {
        \\        s = t + 1;
        \\    } else {
        \\        s = t + 2;
        \\    }
        \\    result = s;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 5 }, // then path
            .{ .input = 1, .expected = 3 }, // else path
        },
    },
    .{
        .name = "two-ifs",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const t: f32 = input;
        \\    const s: f32 = if (t > 2) 1 else 2;
        \\    if (t > 3) {
        \\        result = s + 10;
        \\    } else {
        \\        result = s + 20;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 11 },
            .{ .input = 1, .expected = 22 },
        },
    },
    .{
        .name = "nested-ifs",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const t: f32 = input;
        \\    var s: f32 = 0;
        \\    if (t > 0) {
        \\        if (t > 1) {
        \\            s = 1;
        \\        } else {
        \\            s = 2;
        \\        }
        \\    } else {
        \\        s = 3;
        \\    }
        \\    result = s;
        \\}
        ,
        .cases = &.{
            .{ .input = 0, .expected = 3 },
            .{ .input = 1, .expected = 2 },
            .{ .input = 2, .expected = 1 },
        },
    },
    .{
        .name = "else-only-value",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const t: f32 = input;
        \\    var s: f32 = 0;
        \\    if (t > 2) {
        \\        s = 1;
        \\    } else {
        \\        s = t + 5;
        \\    }
        \\    result = s;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 1 },
            .{ .input = 1, .expected = 6 }, // then_deaths kill + restore
        },
    },
    .{
        .name = "early-return",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (input > 0) {
        \\        result = 1;
        \\        return;
        \\    }
        \\    result = 2;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 1 },
            .{ .input = 0, .expected = 2 },
        },
    },
    .{
        .name = "else-if-chain",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const t: f32 = input;
        \\    var s: f32 = 0;
        \\    if (t > 3) {
        \\        s = 1;
        \\    } else if (t > 1) {
        \\        s = 2;
        \\    } else {
        \\        s = 3;
        \\    }
        \\    result = s;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 1 },
            .{ .input = 2, .expected = 2 },
            .{ .input = 0, .expected = 3 },
        },
    },
    .{
        .name = "const-condition",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var s: f32 = 0;
        \\    if (true) {
        \\        s = input + 1;
        \\    } else {
        \\        s = 100;
        \\    }
        \\    result = s;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 5 },
            .{ .input = 0, .expected = 1 }, // else is comptime-pruned
        },
    },
    .{
        .name = "branch-local-var",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    var s: f32 = 0;
        \\    if (input > 0) {
        \\        const x: f32 = input + 1;
        \\        s = x;
        \\    }
        \\    result = s;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 5 },
            .{ .input = -1, .expected = 0 },
        },
    },
    .{
        .name = "self-operands",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    result = input * input;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 16 },
            .{ .input = 3, .expected = 9 },
        },
    },
    .{
        .name = "chained-arith",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    result = input * input * input;
        \\}
        ,
        .cases = &.{
            .{ .input = 3, .expected = 27 },
            .{ .input = 4, .expected = 64 },
        },
    },
    .{
        .name = "comptime-operands",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    result = input + 1.5 * 2;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 7 },
            .{ .input = 10, .expected = 13 },
        },
    },
    .{
        .name = "multi-store",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    result = 1;
        \\    result = 2;
        \\    result = input;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 4 },
            .{ .input = -7, .expected = -7 },
        },
    },
    .{
        .name = "read-after-write",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    const s: f32 = input;
        \\    result = s + s;
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 8 },
            .{ .input = -2, .expected = -4 },
        },
    },
    .{
        .name = "both-return",
        .source =
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() callconv(.quakec) void {
        \\    if (input > 0) {
        \\        result = 1;
        \\        return;
        \\    } else {
        \\        result = 2;
        \\        return;
        \\    }
        \\}
        ,
        .cases = &.{
            .{ .input = 4, .expected = 1 },
            .{ .input = -1, .expected = 2 },
        },
    },
    .{
        .disabled = true,
        .name = "stuff",
        .source =
        \\const x: f32 = 2;
        \\var input: f32 = 0;
        \\var result: f32 = 0;
        \\
        \\export fn main() void {
        \\    const t: f32 = input;
        \\    var s: f32 = 2.5 * (t * t);
        \\    s *= 0.5;
        \\    s += x * t;
        \\    result = s;
        \\
        \\    const cond: bool = result > 20;
        \\    result = if (cond) 
        \\        @floatFromInt(@intFromBool( cond))
        \\    else 
        \\        input;
        \\}
        ,
        .cases = &.{
            .{ .input = 0, .expected = 0 },
            .{ .input = 2, .expected = 2 },
            .{ .input = 4, .expected = 1 },
        },
    },
};

pub fn add(
    b: *std.Build,
    step: *std.Build.Step,
    opts: struct {
        compiler_exe: *std.Build.Step.Compile,
        dev_env: @import("../src/dev.zig").Env,
        /// Path to the QuakeC-VM test runner.
        /// Must accept these args: <progs.dat path> <input f32> <expected f32>
        /// and return a non-zero exit code if the `result` global != the `expected` value.
        /// Only compiles the test cases if null.
        // @Todo backport qcvm and include in source tree to remove system dependency.
        runner_path: ?[]const u8,
        test_filters: []const []const u8,
    },
) void {
    if (opts.dev_env != .quakec) {
        step.dependOn(&b.addFail("test-quakec requires the compiler under testing to have the QuakeC backend enabled (-Ddev=quakec)").step);
        return;
    }
    if (!opts.compiler_exe.root_module.resolved_target.?.query.isNative()) {
        step.dependOn(&b.addFail("test-quakec requires the compiler under testing to be built for the host target").step);
        return;
    }

    const wf = b.addWriteFiles();
    for (case_sets) |set| {
        if (set.disabled) continue;
        for (opts.test_filters) |filter| {
            if (std.mem.indexOf(u8, set.name, filter) != null) break;
        } else if (opts.test_filters.len > 0) continue; // name does not match any filter

        const src = wf.add(b.fmt("cases/{s}.zig", .{set.name}), set.source);
        const compile = b.addRunArtifact(opts.compiler_exe);
        compile.addArgs(&.{ "build-exe", "-fno-llvm", "-fno-lld", "-target", "quakec-freestanding" });
        // compile.addArgs(&.{ "--debug-log", "codegen" });
        compile.addFileArg(src);
        compile.addArgs(&.{ "--name", set.name });
        const dat = compile.addPrefixedOutputFileArg("-femit-bin=", b.fmt("{s}.dat", .{set.name}));
        step.dependOn(&compile.step); // compile-only without a runner

        const runner = opts.runner_path orelse continue;
        for (set.cases, 0..) |case, i| {
            const runcase = b.addSystemCommand(&.{runner});
            runcase.addFileArg(dat);
            runcase.addArg(b.fmt("{d}", .{case.input}));
            runcase.addArg(b.fmt("{d}", .{case.expected}));
            runcase.expectExitCode(0);
            if (set.cases.len > 1)
                runcase.setName(b.fmt("test {s}-{d}", .{ set.name, i }))
            else
                runcase.setName(b.fmt("test {s}", .{set.name}));
            step.dependOn(&runcase.step);
        }
    }

    if (opts.runner_path == null) {
        step.dependOn(&b.addFail("The -Dqcvm-runner=... option is required for running QuakeC test cases").step);
    }
}
