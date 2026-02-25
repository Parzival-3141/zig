const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const fs = std.fs;
const Path = std.Build.Cache.Path;

const QuakeC = @This();
const build_options = @import("build_options");
const Zcu = @import("../Zcu.zig");
const Module = @import("../Package/Module.zig");
const InternPool = @import("../InternPool.zig");
const Alignment = InternPool.Alignment;
const Compilation = @import("../Compilation.zig");
const codegen = @import("../codegen.zig");
const link = @import("../link.zig");
const trace = @import("../tracy.zig").trace;
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const AnyMir = @import("../codegen.zig").AnyMir;

base: link.File,

pub fn open(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*QuakeC {
    return createEmpty(arena, comp, emit, options);
}

pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*QuakeC {
    const target = &comp.root_mod.resolved_target.result;
    assert(target.ofmt == .quakec);
    assert(comp.config.output_mode == .Exe);

    const file = try emit.root_dir.handle.createFile(emit.sub_path, .{
        // Truncation is done on `flush`.
        .truncate = false,
    });
    errdefer file.close();

    const qc_file = try arena.create(QuakeC);
    qc_file.* = .{
        .base = .{
            .tag = .quakec,
            .comp = comp,
            .emit = emit,
            .gc_sections = options.gc_sections orelse true,
            .print_gc_sections = options.print_gc_sections,
            .stack_size = options.stack_size orelse 16777216,
            .allow_shlib_undefined = options.allow_shlib_undefined orelse false,
            .file = file,
            .build_id = options.build_id,
        },
        // .navs = .empty,
        // .string_bytes = .empty,
        // .uavs = .empty,
        // .aligned_uavs = .empty,
        // .exported_navs = .empty,
        // .exported_uavs = .empty,
        // .fwd_decl_buf = &.{},
        // .code_header_buf = &.{},
        // .code_buf = &.{},
        // .scratch_buf = &.{},
    };
    errdefer qc_file.base.destroy();

    return qc_file;
}

pub fn deinit(self: *QuakeC) void {
    _ = self; // autofix
    @panic("@Todo");
}

pub fn updateFunc(
    self: *QuakeC,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *AnyMir,
) link.File.UpdateNavError!void {
    _ = self; // autofix
    _ = pt; // autofix
    _ = func_index; // autofix
    _ = mir; // autofix
    @panic("@Todo");
}

pub fn updateNav(
    self: *QuakeC,
    pt: Zcu.PerThread,
    nav_index: InternPool.Nav.Index,
) link.File.UpdateNavError!void {
    _ = self; // autofix
    _ = pt; // autofix
    _ = nav_index; // autofix
    @panic("@Todo");
}

pub fn updateLineNumber(
    self: *QuakeC,
    pt: Zcu.PerThread,
    ti_id: InternPool.TrackedInst.Index,
) !void {
    _ = self; // autofix
    _ = pt; // autofix
    _ = ti_id; // autofix
    @panic("@Todo");
}

pub fn updateExports(
    self: *QuakeC,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) !void {
    _ = self; // autofix
    _ = pt; // autofix
    _ = exported; // autofix
    _ = export_indices; // autofix
    @panic("@Todo");
}

pub fn getNavVAddr(
    self: *QuakeC,
    pt: Zcu.PerThread,
    nav_index: InternPool.Nav.Index,
    reloc_info: link.File.RelocInfo,
) !u64 {
    _ = self; // autofix
    _ = pt; // autofix
    _ = nav_index; // autofix
    _ = reloc_info; // autofix
    @panic("@Todo");
}

pub fn lowerUav(
    self: *QuakeC,
    pt: Zcu.PerThread,
    decl_val: InternPool.Index,
    decl_align: InternPool.Alignment,
    src_loc: Zcu.LazySrcLoc,
) codegen.GenerateSymbolError!codegen.SymbolResult {
    _ = self; // autofix
    _ = pt; // autofix
    _ = decl_val; // autofix
    _ = decl_align; // autofix
    _ = src_loc; // autofix
    @panic("@Todo");
}

pub fn getUavVAddr(self: *QuakeC, decl_val: InternPool.Index, reloc_info: link.File.RelocInfo) !u64 {
    _ = self; // autofix
    _ = decl_val; // autofix
    _ = reloc_info; // autofix
    @panic("@Todo");
}

pub fn deleteExport(
    self: *QuakeC,
    exported: Zcu.Exported,
    _: InternPool.NullTerminatedString,
) void {
    _ = self; // autofix
    _ = exported; // autofix
    @panic("@Todo");
}

/// Commit pending changes and write headers. Takes into account final output mode.
/// `arena` has the lifetime of the call to `Compilation.update`.
pub fn flush(
    self: *QuakeC,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.File.FlushError!void {
    _ = self; // autofix
    _ = arena; // autofix
    _ = tid; // autofix
    _ = prog_node; // autofix
    @panic("@Todo");
}
