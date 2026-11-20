//! Test runner for the Zig QuakeC backend behavior tests.
const usage = "usage: qctest <dat-path> [--input name=val,...] [--expect name=val,...]";

const std = @import("std");
const quakec = @import("qcvm");
const fatal = std.process.fatal;

const Pair = struct { name: []const u8, val: f32 };

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(arena);
    std.debug.assert(args.skip()); // argv[0]

    var dat_path: ?[]const u8 = null;
    var inputs: std.ArrayList(Pair) = .empty;
    var expects: std.ArrayList(Pair) = .empty;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "--expect")) {
            const flag_name = arg[2..];
            const list = args.next() orelse fatal("missing value for {s}", .{arg});

            var pairs: std.ArrayList(Pair) = try .initCapacity(arena, 1 + std.mem.countScalar(u8, list, ','));
            var it = std.mem.splitScalar(u8, list, ',');
            while (it.next()) |value| {
                const name, const val_str = std.mem.cutScalar(u8, value, '=') orelse fatal(
                    "malformed {s} entry `{s}` (want name=value)",
                    .{ flag_name, value },
                );
                const val = std.fmt.parseFloat(f32, val_str) catch fatal(
                    "invalid {s} value `{s}` for `{s}`",
                    .{ flag_name, val_str, name },
                );
                try pairs.append(arena, .{ .name = name, .val = val });
            }

            if (arg[2] == 'i')
                try inputs.appendSlice(arena, pairs.items)
            else
                try expects.appendSlice(arena, pairs.items);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            fatal("unknown flag `{s}`", .{arg});
        } else {
            if (dat_path != null) fatal("unexpected extra argument `{s}`", .{arg});
            dat_path = arg;
        }
    }

    const file_path = dat_path orelse fatal("missing dat-path argument\n" ++ usage, .{});

    const prog_data = try std.Io.Dir.cwd().readFileAllocOptions(
        io,
        file_path,
        arena,
        .limited(64 * 1024 * 1024),
        .of(quakec.Header),
        null,
    );

    var vm: quakec.Vm = .blank;
    try quakec.loadProgram(&vm, prog_data, false);

    // exec contract: at least the null entity must exist
    vm.num_entities = 1;
    const entity_mem = try arena.alloc(u32, vm.num_entity_fields);
    @memset(entity_mem, 0);
    vm.entity_memory = entity_mem;

    for (inputs.items) |input| {
        const def = findGlobal(&vm, input.name) orelse {
            fatal("no global `{s}`", .{input.name});
        };
        if (def.type.tag != .float) {
            fatal("global `{s}` is not a float", .{input.name});
        }
        vm.globals[def.offset] = @bitCast(input.val);
    }

    try quakec.exec(&vm, "main");

    var failed = false;
    for (expects.items) |expect| {
        const def = findGlobal(&vm, expect.name) orelse {
            std.log.err("no global `{s}`", .{expect.name});
            failed = true;
            continue;
        };
        if (def.type.tag != .float) {
            std.log.err("global `{s}` is not a float", .{expect.name});
            failed = true;
            continue;
        }
        const want = expect.val;
        const got: f32 = @bitCast(vm.globals[def.offset]);
        if (got != want and !(std.math.isNan(got) and std.math.isNan(want))) {
            std.log.err("expected {s} = {d}, found {d}", .{ expect.name, want, got });
            failed = true;
        }
    }
    return @intFromBool(failed);
}

fn findGlobal(vm: *const quakec.Vm, name: []const u8) ?quakec.Def {
    for (vm.globaldefs) |def| {
        if (def.offset == 0) continue; // null def
        if (def.offset < quakec.SpecialRegisterOffset.reserved_len) continue; // reserved registers
        const def_name = std.mem.sliceTo(vm.strings[def.s_name..], 0);
        const last = if (std.mem.findScalarLast(u8, def_name, '.')) |dot| def_name[dot + 1 ..] else def_name;
        if (std.mem.eql(u8, last, name)) return def;
    }
    return null;
}
