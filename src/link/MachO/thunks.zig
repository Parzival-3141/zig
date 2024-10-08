pub fn createThunks(sect_id: u8, macho_file: *MachO) !void {
    const tracy = trace(@src());
    defer tracy.end();

    const gpa = macho_file.base.comp.gpa;
    const slice = macho_file.sections.slice();
    const header = &slice.items(.header)[sect_id];
    const thnks = &slice.items(.thunks)[sect_id];
    const atoms = slice.items(.atoms)[sect_id].items;
    assert(atoms.len > 0);

    for (atoms) |ref| {
        ref.getAtom(macho_file).?.value = @bitCast(@as(i64, -1));
    }

    var i: usize = 0;
    while (i < atoms.len) {
        const start = i;
        const start_atom = atoms[start].getAtom(macho_file).?;
        assert(start_atom.isAlive());
        start_atom.value = advance(header, start_atom.size, start_atom.alignment);
        i += 1;

        while (i < atoms.len and
            header.size - start_atom.value < max_allowed_distance) : (i += 1)
        {
            const atom = atoms[i].getAtom(macho_file).?;
            assert(atom.isAlive());
            atom.value = advance(header, atom.size, atom.alignment);
        }

        // Insert a thunk at the group end
        const thunk_index = try macho_file.addThunk();
        const thunk = macho_file.getThunk(thunk_index);
        thunk.out_n_sect = sect_id;
        try thnks.append(gpa, thunk_index);

        // Scan relocs in the group and create trampolines for any unreachable callsite
        try scanRelocs(thunk_index, gpa, atoms[start..i], macho_file);
        thunk.value = advance(header, thunk.size(), .@"4");

        log.debug("thunk({d}) : {}", .{ thunk_index, thunk.fmt(macho_file) });
    }
}

fn advance(sect: *macho.section_64, size: u64, alignment: Atom.Alignment) u64 {
    const offset = alignment.forward(sect.size);
    const padding = offset - sect.size;
    sect.size += padding + size;
    sect.@"align" = @max(sect.@"align", alignment.toLog2Units());
    return offset;
}

fn scanRelocs(thunk_index: Thunk.Index, gpa: Allocator, atoms: []const MachO.Ref, macho_file: *MachO) !void {
    const tracy = trace(@src());
    defer tracy.end();

    const thunk = macho_file.getThunk(thunk_index);

    for (atoms) |ref| {
        const atom = ref.getAtom(macho_file).?;
        log.debug("atom({d}) {s}", .{ atom.atom_index, atom.getName(macho_file) });
        for (atom.getRelocs(macho_file)) |rel| {
            if (rel.type != .branch) continue;
            if (isReachable(atom, rel, macho_file)) continue;
            try thunk.symbols.put(gpa, rel.getTargetSymbolRef(atom.*, macho_file), {});
        }
        atom.addExtra(.{ .thunk = thunk_index }, macho_file);
    }
}

fn isReachable(atom: *const Atom, rel: Relocation, macho_file: *MachO) bool {
    const target = rel.getTargetSymbol(atom.*, macho_file);
    if (target.getSectionFlags().stubs or target.getSectionFlags().objc_stubs) return false;
    if (atom.out_n_sect != target.getOutputSectionIndex(macho_file)) return false;
    const target_atom = target.getAtom(macho_file).?;
    if (target_atom.value == @as(u64, @bitCast(@as(i64, -1)))) return false;
    const saddr = @as(i64, @intCast(atom.getAddress(macho_file))) + @as(i64, @intCast(rel.offset - atom.off));
    const taddr: i64 = @intCast(rel.getTargetAddress(atom.*, macho_file));
    _ = math.cast(i28, taddr + rel.addend - saddr) orelse return false;
    return true;
}

pub const Thunk = struct {
    value: u64 = 0,
    out_n_sect: u8 = 0,
    symbols: std.AutoArrayHashMapUnmanaged(MachO.Ref, void) = .{},
    output_symtab_ctx: MachO.SymtabCtx = .{},

    pub fn deinit(thunk: *Thunk, allocator: Allocator) void {
        thunk.symbols.deinit(allocator);
    }

    pub fn size(thunk: Thunk) usize {
        return thunk.symbols.keys().len * trampoline_size;
    }

    pub fn getAddress(thunk: Thunk, macho_file: *MachO) u64 {
        const header = macho_file.sections.items(.header)[thunk.out_n_sect];
        return header.addr + thunk.value;
    }

    pub fn getTargetAddress(thunk: Thunk, ref: MachO.Ref, macho_file: *MachO) u64 {
        return thunk.getAddress(macho_file) + thunk.symbols.getIndex(ref).? * trampoline_size;
    }

    pub fn write(thunk: Thunk, macho_file: *MachO, writer: anytype) !void {
        for (thunk.symbols.keys(), 0..) |ref, i| {
            const sym = ref.getSymbol(macho_file).?;
            const saddr = thunk.getAddress(macho_file) + i * trampoline_size;
            const taddr = sym.getAddress(.{}, macho_file);
            const pages = try aarch64.calcNumberOfPages(@intCast(saddr), @intCast(taddr));
            try writer.writeInt(u32, aarch64.Instruction.adrp(.x16, pages).toU32(), .little);
            const off: u12 = @truncate(taddr);
            try writer.writeInt(u32, aarch64.Instruction.add(.x16, .x16, off, false).toU32(), .little);
            try writer.writeInt(u32, aarch64.Instruction.br(.x16).toU32(), .little);
        }
    }

    pub fn calcSymtabSize(thunk: *Thunk, macho_file: *MachO) void {
        thunk.output_symtab_ctx.nlocals = @as(u32, @intCast(thunk.symbols.keys().len));
        for (thunk.symbols.keys()) |ref| {
            const sym = ref.getSymbol(macho_file).?;
            thunk.output_symtab_ctx.strsize += @as(u32, @intCast(sym.getName(macho_file).len + "__thunk".len + 1));
        }
    }

    pub fn writeSymtab(thunk: Thunk, macho_file: *MachO, ctx: anytype) void {
        var n_strx = thunk.output_symtab_ctx.stroff;
        for (thunk.symbols.keys(), thunk.output_symtab_ctx.ilocal..) |ref, ilocal| {
            const sym = ref.getSymbol(macho_file).?;
            const name = sym.getName(macho_file);
            const out_sym = &ctx.symtab.items[ilocal];
            out_sym.n_strx = n_strx;
            @memcpy(ctx.strtab.items[n_strx..][0..name.len], name);
            n_strx += @intCast(name.len);
            @memcpy(ctx.strtab.items[n_strx..][0.."__thunk".len], "__thunk");
            n_strx += @intCast("__thunk".len);
            ctx.strtab.items[n_strx] = 0;
            n_strx += 1;
            out_sym.n_type = macho.N_SECT;
            out_sym.n_sect = @intCast(thunk.out_n_sect + 1);
            out_sym.n_value = @intCast(thunk.getTargetAddress(ref, macho_file));
            out_sym.n_desc = 0;
        }
    }

    pub fn format(
        thunk: Thunk,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = thunk;
        _ = unused_fmt_string;
        _ = options;
        _ = writer;
        @compileError("do not format Thunk directly");
    }

    pub fn fmt(thunk: Thunk, macho_file: *MachO) std.fmt.Formatter(format2) {
        return .{ .data = .{
            .thunk = thunk,
            .macho_file = macho_file,
        } };
    }

    const FormatContext = struct {
        thunk: Thunk,
        macho_file: *MachO,
    };

    fn format2(
        ctx: FormatContext,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = unused_fmt_string;
        const thunk = ctx.thunk;
        const macho_file = ctx.macho_file;
        try writer.print("@{x} : size({x})\n", .{ thunk.value, thunk.size() });
        for (thunk.symbols.keys()) |ref| {
            const sym = ref.getSymbol(macho_file).?;
            try writer.print("  {} : {s} : @{x}\n", .{ ref, sym.getName(macho_file), sym.value });
        }
    }

    const trampoline_size = 3 * @sizeOf(u32);

    pub const Index = u32;
};

/// Branch instruction has 26 bits immediate but is 4 byte aligned.
const jump_bits = @bitSizeOf(i28);
const max_distance = (1 << (jump_bits - 1));

/// A branch will need an extender if its target is larger than
/// `2^(jump_bits - 1) - margin` where margin is some arbitrary number.
/// mold uses 5MiB margin, while ld64 uses 4MiB margin. We will follow mold
/// and assume margin to be 5MiB.
const max_allowed_distance = max_distance - 0x500_000;

const aarch64 = @import("../aarch64.zig");
const assert = std.debug.assert;
const log = std.log.scoped(.link);
const macho = std.macho;
const math = std.math;
const mem = std.mem;
const std = @import("std");
const trace = @import("../../tracy.zig").trace;

const Allocator = mem.Allocator;
const Atom = @import("Atom.zig");
const MachO = @import("../MachO.zig");
const Relocation = @import("Relocation.zig");
const Symbol = @import("Symbol.zig");
