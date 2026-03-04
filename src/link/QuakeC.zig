//! Linker consumes MIR and produces a binary file (link.File)

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const fs = std.fs;
const log = std.log.scoped(.link);

const QuakeC = @This();
const Path = std.Build.Cache.Path;
const Zcu = @import("../Zcu.zig");
const Module = @import("../Package/Module.zig");
const InternPool = @import("../InternPool.zig");
const Alignment = InternPool.Alignment;
const Compilation = @import("../Compilation.zig");
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const CodeGen = @import("../codegen/quakec/CodeGen.zig");

const build_options = @import("build_options");
const codegen = @import("../codegen.zig");
const dev = @import("../dev.zig");
const link = @import("../link.zig");
const trace = @import("../tracy.zig").trace;

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
    mir: *codegen.AnyMir,
) link.File.UpdateNavError!void {
    _ = mir; // autofix
    if (build_options.skip_non_native and builtin.object_format != .quakec) {
        @panic("Attempted to compile for object format that was disabled by build configuration");
    }

    dev.check(.quakec_backend);

    const zcu = pt.zcu;
    const gpa = self.base.comp.gpa;
    _ = gpa; // autofix

    const ip = &zcu.intern_pool;
    const owner_nav = zcu.funcInfo(func_index).owner_nav;
    log.debug("updateFunc {f}", .{ip.getNav(owner_nav).fqn.fmt(ip)});

    // codegen.emitFunction()

    // const function = try CodeGen.function(self, pt, func_index, air, liveness);
    // try self.funcs.put(gpa, func_index, function);
    @panic("@Todo");
}

pub fn updateNav(
    self: *QuakeC,
    pt: Zcu.PerThread,
    nav_index: InternPool.Nav.Index,
) link.File.UpdateNavError!void {
    _ = self; // autofix
    if (build_options.skip_non_native and builtin.object_format != .quakec) {
        @panic("Attempted to compile for object format that was disabled by build configuration");
    }
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(nav_index);

    const nav_init, const chased_nav_index = switch (ip.indexToKey(nav.status.fully_resolved.val)) {
        .func => return, // global const which is a function alias
        .@"extern" => |ext| {
            // const name = ext.name.toSlice(ip);
            if (ip.isFunctionType(nav.typeOf(ip))) {

                // Extern functions are treated as QuakeC builtins
                // how to bind builtin number? Hijack callconv? libname?
                const fn_info = zcu.typeToFunc(.fromInterned(ext.ty)).?;
                _ = fn_info; // autofix
                log.debug("updateNav == extern func {f} ==", .{nav.fqn.fmt(ip)});
                return; // @Incomplete
            }

            @panic("TODO updateNav extern");
        },
        .variable => |variable| .{ variable.init, variable.owner_nav },
        else => .{ nav.status.fully_resolved.val, nav_index },
    };
    log.debug("updateNav {f} {d}", .{ nav.fqn.fmt(ip), chased_nav_index });

    if (nav_init != .none and !Value.fromInterned(nav_init).typeOf(zcu).hasRuntimeBits(zcu)) {
        return;
    }
}

pub fn updateLineNumber(
    self: *QuakeC,
    pt: Zcu.PerThread,
    ti_id: InternPool.TrackedInst.Index,
) !void {
    _ = self; // autofix

    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    const inst_info = ti_id.resolveFull(ip).?;
    assert(inst_info.inst != .main_struct_inst);
    const file = zcu.fileByIndex(inst_info.file);
    const decl = file.zir.?.getDeclaration(inst_info.inst);
    log.debug("updateLineNumber({s}:{d}:{d} %{d} = {s})", .{
        file.sub_file_path,
        decl.src_line + 1,
        decl.src_column + 1,
        @intFromEnum(inst_info.inst),
        file.zir.?.nullTerminatedString(decl.name),
    });
}

pub fn updateExports(
    self: *QuakeC,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) !void {
    _ = self;
    if (build_options.skip_non_native and builtin.object_format != .quakec) {
        @panic("Attempted to compile for object format that was disabled by build configuration");
    }

    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    for (export_indices) |export_idx| {
        const exp = export_idx.ptr(zcu);
        const name_slice = exp.opts.name.toSlice(ip);
        switch (exported) {
            .nav => |nav_index| {
                log.debug("updateExports '{s}' nav={d}", .{ name_slice, @intFromEnum(nav_index) });
            },
            .uav => |uav_index| {
                log.debug("updateExports '{s}' uav={d}", .{ name_slice, @intFromEnum(uav_index) });
            },
        }
    }
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
    name: InternPool.NullTerminatedString,
) void {
    const zcu = self.base.comp.zcu.?;
    const ip = &zcu.intern_pool;
    const name_slice = name.toSlice(ip);
    switch (exported) {
        .nav => |nav_index| {
            log.debug("deleteExport '{s}' nav={d}", .{ name_slice, @intFromEnum(nav_index) });
        },
        .uav => |uav_index| {
            log.debug("deleteExport '{s}' uav={d}", .{ name_slice, @intFromEnum(uav_index) });
        },
    }
}

/// Commit pending changes and write headers. Takes into account final output mode.
/// `arena` has the lifetime of the call to `Compilation.update`.
pub fn flush(
    self: *QuakeC,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.File.FlushError!void {
    // The goal is to never use this because it's only needed if we need to
    // write to InternPool, but flush is too late to be writing to the
    // InternPool.
    _ = tid;
    const comp = self.base.comp;
    const diags = &comp.link_diags;

    const sub_prog_node = prog_node.start("QuakeC Flush", 0);
    defer sub_prog_node.end();

    _ = arena;

    return diags.fail("TODO implement flushModule for quakec", .{});
}
