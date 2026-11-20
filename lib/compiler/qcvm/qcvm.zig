// Copyright (C) 1996-1997 Id Software, Inc.
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

// @Todo create handle types for strings/functions/entities?

// Fully renamed types/fields have their original C names in a comment above them.

// etype_t
pub const ValueType = enum(u15) {
    void,
    string,
    float,
    vector,
    entity,
    field,
    function,
    pointer,
    _,
};

// OFS_*
/// Offsets of special purpose registers in Vm.globals
pub const SpecialRegisterOffset = enum(u16) {
    null = 0,
    /// Padded to 3 words to hold vectors
    @"return" = 1,
    // parm0-7
    /// Function arguments, filled by caller.
    /// Each argument is padded to 3 words to hold vectors.
    arg0 = 4,
    arg1 = 7,
    arg2 = 10,
    arg3 = 13,
    arg4 = 16,
    arg5 = 19,
    arg6 = 22,
    arg7 = 25,
    pub const reserved_len = 28;
};

pub const Opcode = enum(u16) {
    done,
    mul_f,
    mul_v,
    mul_fv,
    mul_vf,
    div_f,
    add_f,
    add_v,
    sub_f,
    sub_v,

    eq_f,
    eq_v,
    eq_s,
    eq_e,
    eq_fnc,

    ne_f,
    ne_v,
    ne_s,
    ne_e,
    ne_fnc,

    le,
    ge,
    lt,
    gt,

    load_f,
    load_v,
    load_s,
    load_ent,
    load_fld,
    load_fnc,

    address,

    store_f,
    store_v,
    store_s,
    store_ent,
    store_fld,
    store_fnc,

    storep_f,
    storep_v,
    storep_s,
    storep_ent,
    storep_fld,
    storep_fnc,

    @"return",
    not_f,
    not_v,
    not_s,
    not_ent,
    not_fnc,
    @"if",
    ifnot,
    call0,
    call1,
    call2,
    call3,
    call4,
    call5,
    call6,
    call7,
    call8,
    state,
    goto,
    @"and",
    @"or",

    bitand,
    bitor,

    _,
};

pub const Statement = extern struct {
    op: Opcode,
    // a, b, c
    args: [3]i16,
};

pub const Def = extern struct {
    type: packed struct(u16) {
        tag: ValueType,
        /// if DEF_SAVEGLOBGAL bit is set the variable needs
        /// to be saved in savegames.
        save_global: bool,
    },
    offset: u16,
    s_name: u32,
};

pub const Function = extern struct {
    /// A negative value is a builtin index and marks this function as a builtin.
    first_statement: i32,
    // parm_start
    /// Offset of the function frame (parameters + local variables) in Vm.globals.
    frame_start: u32,
    // locals
    frame_size: u32,

    /// runtime
    profile: u32,

    s_name: u32,
    /// source file defined in
    s_file: u32,

    num_params: u32,
    param_size: [MAX_PARAMETERS]u8,

    pub const MAX_PARAMETERS = 8;
};

pub const PROG_VERSION = 6;

// dprograms_t
pub const Header = extern struct {
    version: u32,
    /// check of progsdefs header file
    crc: u32,

    ofs_statements: u32,
    /// statement 0 is an error
    num_statements: u32,

    ofs_globaldefs: u32,
    num_globaldefs: u32,

    ofs_fielddefs: u32,
    num_fielddefs: u32,

    ofs_functions: u32,
    /// function 0 is an empty
    num_functions: u32,

    ofs_strings: u32,
    /// includes the null terminator. first string is a null string
    size_strings: u32,

    ofs_globals: u32,
    num_globals: u32,

    entityfields: u32,
};

/// Quake's progdefs.h crc value
pub const PROGDEFS_CRC = 5927;

// ============================================================================

const std = @import("std");
const crc = @import("crc.zig");

const assert = std.debug.assert;
const native_endian = @import("builtin").cpu.arch.endian();

pub const VmError = error{Panic};

pub const BuiltinFn = *const fn (*Vm) VmError!void;

pub const Vm = struct {
    version: u32,
    /// checksum of progsdefs header file
    progdefs_crc: u16,
    program_crc: u16,

    /// Entire QuakeC program dat file loaded in memory.
    program: []const u8,

    // These fields are pointers into program memory.
    statements: []const Statement,
    funcs: []const Function,
    globaldefs: []const Def,
    fielddefs: []const Def,
    strings: [:0]const u8,
    globals: []u32,

    num_entity_fields: u32,

    ///////////////////////////////////////////////////////////////////////////
    // The following fields should be set by the user before execution.

    /// User supplied builtin functions
    builtins: []const BuiltinFn,
    /// User supplied data accessible in builtin functions
    userdata: ?*anyopaque,

    // Entities are stored in a seperate memory region that the user supplies.
    // The size of this memory region must be at least
    // num_entities * num_entity_fields * @sizeOf(u32) bytes.
    // Currently we store all entities contiguously as an array of fields (u32s),
    // but this may change in the future if we allow users to define their own
    // data layout for entities.

    // @Todo at least 1 entity must be allocated so accessing the null entity will always work
    /// User supplied entities
    entity_memory: []u32,
    num_entities: u32,

    /// User supplied string buffer
    temporary_strings_buffer: [:0]u8,

    /// User supplied logger callback. The vm will call this function when
    /// panicking or to log diagnostic information. The default handler prints to
    /// stderr, but you can replace it with your own, or set it to null to disable
    /// logging entirely.
    logger: ?LoggerCallbackFn,

    /// Enable logging of statements as they are executed
    trace: bool,

    ///////////////////////////////////////////////////////////////////////////
    // The following fields are managed by the runtime. You should not modify
    // them unless you know what you are doing.

    /// The number of arguments passed to a builtin function.
    /// Will always be <= 8 when entering a builtin.
    argc: u4,

    stack: CallStack,

    current_function: u32,
    program_counter: u32,

    panicking: bool,

    // @Todo make these configurable
    /// Maximum number of functions in the call stack
    const MAX_STACK_DEPTH = 32;
    /// Word capacity of the stack
    const MAX_STACK_SIZE = 2048;

    const CallStack = struct {
        locals: [MAX_STACK_SIZE]u32,
        locals_used: u32, // std.math.IntFittingRange(0, MAX_STACK_SIZE) ?

        trace: [MAX_STACK_DEPTH]struct {
            stmt: u32, // index into statements
            func: u32, // index into functions
        },
        trace_depth: u32, // std.math.IntFittingRange(0, MAX_STACK_DEPTH) ?
    };

    pub const blank: Vm = .{
        .version = 0,
        .progdefs_crc = 0,
        .program_crc = 0,

        .program = &.{},
        .strings = &.{},
        .funcs = &.{},
        .globaldefs = &.{},
        .fielddefs = &.{},
        .statements = &.{},
        .globals = &.{},

        .argc = 0,
        .builtins = &.{},
        .userdata = null,

        .entity_memory = &.{},
        .num_entities = 0,
        .num_entity_fields = 0,
        .temporary_strings_buffer = @constCast(&.{}),

        .trace = false,
        .logger = defaultLogger,

        .panicking = false,

        .stack = .{
            .locals = @splat(0),
            .locals_used = 0,
            .trace = @splat(.{ .stmt = 0, .func = 0 }),
            .trace_depth = 0,
        },
        .current_function = 0,
        .program_counter = 0,
    };

    ///////////////////////////////////////////////////////////////////////////
    // User builtin function I/O helpers

    // These functions accept a u4 with range checks instead of a u3 because
    // it reduces casting for the user, especially when iterating up to argc.
    pub fn getArgVector(vm: *const Vm, arg: u4) *const [3]f32 {
        assert(arg < 8);
        const offset = @backingInt(SpecialRegisterOffset.arg0) + @as(u5, arg) * 3;
        return @ptrCast(vm.globals[offset..][0..3]);
    }
    pub fn getArgInt(vm: *const Vm, arg: u4) i32 {
        assert(arg < 8);
        const offset = @backingInt(SpecialRegisterOffset.arg0) + @as(u5, arg) * 3;
        return @bitCast(vm.globals[offset]);
    }
    pub fn getArgFloat(vm: *const Vm, arg: u4) f32 {
        assert(arg < 8);
        const offset = @backingInt(SpecialRegisterOffset.arg0) + @as(u5, arg) * 3;
        return @bitCast(vm.globals[offset]);
    }
    pub fn getArgString(vm: *const Vm, arg: u4) [:0]const u8 {
        assert(arg < 8);
        const offset = @backingInt(SpecialRegisterOffset.arg0) + @as(u5, arg) * 3;
        return getString(vm, @bitCast(vm.globals[offset]));
    }

    pub fn setReturnValueVector(vm: *Vm, vec: [3]f32) void {
        for (0..3) |i| vm.globals[@backingInt(SpecialRegisterOffset.@"return") + i] = @bitCast(vec[i]);
    }
    pub fn setReturnValueEntityIndex(vm: *Vm, entity: u32) void {
        vm.globals[@backingInt(SpecialRegisterOffset.@"return")] = entity;
    }
    pub fn setReturnValueFloat(vm: *Vm, float: f32) void {
        vm.globals[@backingInt(SpecialRegisterOffset.@"return")] = @bitCast(float);
    }
    /// Copies the string into temporary_strings_buffer.
    /// If there is not enough space it will return the null string value instead.
    pub fn setReturnValueString(vm: *Vm, string: []const u8) void {
        if (string.len <= vm.temporary_strings_buffer.len) {
            vm.setReturnValueStringAssumeCapacity(string);
        } else {
            vm.globals[@backingInt(SpecialRegisterOffset.@"return")] = 0;
            // @Incomplete return an error?
        }
    }

    /// Copies the string into temporary_strings_buffer.
    pub fn setReturnValueStringAssumeCapacity(vm: *Vm, string: []const u8) void {
        assert(string.len <= vm.temporary_strings_buffer.len);
        // @Todo ensure temp string allocation is compatible with vanilla Quake
        // @Todo we could be more clever about how temp strings are allocated,
        // like using a bump allocator, or a circular buffer of fixed size strings,
        // but for now just overwrite with the latest returned string.
        @memcpy(vm.temporary_strings_buffer[0..string.len], string);
        vm.temporary_strings_buffer[string.len] = 0;
        vm.setReturnValueManuallyFilledTempString(0);
    }

    /// Call this function if you have manually written to the
    /// temporary_strings_buffer, otherwise call setReturnValueString.
    pub fn setReturnValueManuallyFilledTempString(vm: *Vm, start_idx: u31) void {
        vm.temporary_strings_buffer[vm.temporary_strings_buffer.len] = 0; // maintain sentinel, just in case!
        vm.globals[@backingInt(SpecialRegisterOffset.@"return")] =
            @bitCast(@as(i32, -1) - start_idx);
    }

    /// Returns a string from either the global or temporary strings buffer
    /// depending on whether offset is positive or negative respectively.
    /// Returns the null string if offset is out of bounds.
    fn getString(vm: *const Vm, offset: i32) [:0]const u8 {
        if (offset < 0) {
            // temp string
            const idx: u32 = @intCast(-offset - 1);
            if (idx >= vm.temporary_strings_buffer.len) return vm.getString(0);
            return subCString(vm.temporary_strings_buffer, idx);
        } else {
            // global string
            var idx: u32 = @intCast(offset);
            if (idx >= vm.strings.len) idx = 0;
            return subCString(vm.strings, idx);
        }
    }

    pub fn panic(vm: *Vm, msg: []const u8) VmError {
        vm.panicking = true;
        if (vm.logger) |logger| logger(vm, .{ .panic = msg });
        return error.Panic;
    }

    pub fn panicExtra(vm: *Vm, comptime fmt: []const u8, args: anytype) VmError {
        vm.panicking = true;
        if (vm.logger) |logger| {
            var buf: [256]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buf);

            w.print(fmt, args) catch {
                const truncated = "...(msg truncated)";
                @memcpy(buf[buf.len - truncated.len ..], truncated);
            };
            logger(vm, .{ .panic = w.buffered() });
        }
        return error.Panic;
    }
};

pub const LoggerCallbackFn = *const fn (vm: *Vm, mode: LoggerMode) void;
pub const LoggerMode = union(enum) {
    panic: []const u8, // reason
    statement: Statement,
};

/// Log to stderr.
pub fn defaultLogger(vm: *Vm, mode: LoggerMode) void {
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();
    const w = &stderr.file_writer.interface;

    nosuspend switch (mode) {
        .panic => |msg| {
            w.print("panic: {s}\n", .{msg}) catch {};
            printStackTrace(w, vm) catch {};
        },
        .statement => |stmt| {
            printStatement(w, vm, stmt) catch {};
            w.writeByte('\n') catch {};
        },
    };
}

pub const LoadProgramError = error{ WrongVersion, InvalidChecksum };

pub fn loadProgram(vm: *Vm, bytes: []align(@alignOf(Header)) u8, check_progdefs_crc: bool) LoadProgramError!void {
    var progs_crc = crc.init;
    for (bytes) |b| crc.processByte(&progs_crc, b);

    const hdr: *Header = @ptrCast(bytes);
    if (native_endian == .big) std.mem.byteSwapAllFields(Header, hdr);

    if (hdr.version != PROG_VERSION) {
        std.log.err(
            "progs.dat has wrong version number ({d} should be {d})",
            .{ hdr.version, PROG_VERSION },
        );
        return error.WrongVersion;
    }

    if (hdr.crc > std.math.maxInt(u16)) {
        return error.InvalidChecksum;
    }
    if (check_progdefs_crc and hdr.crc != PROGDEFS_CRC) {
        std.log.err(
            "crc doesn't match, progs.dat system vars have been modified (expected {d}, found {d})",
            .{ PROGDEFS_CRC, hdr.crc },
        );
        return error.InvalidChecksum;
    }

    // zig fmt: off
    const strings:    [:0]u8      =                     bytes[hdr.ofs_strings   ..][0..hdr.size_strings  -| 1                 :0];
    const funcs:      []Function  = @ptrCast(@alignCast(bytes[hdr.ofs_functions ..][0..hdr.num_functions  * @sizeOf(Function) ]));
    const globaldefs: []Def       = @ptrCast(@alignCast(bytes[hdr.ofs_globaldefs..][0..hdr.num_globaldefs * @sizeOf(Def)      ]));
    const fielddefs:  []Def       = @ptrCast(@alignCast(bytes[hdr.ofs_fielddefs ..][0..hdr.num_fielddefs  * @sizeOf(Def)      ]));
    const statements: []Statement = @ptrCast(@alignCast(bytes[hdr.ofs_statements..][0..hdr.num_statements * @sizeOf(Statement)]));
    const globals:    []u32       = @ptrCast(@alignCast(bytes[hdr.ofs_globals   ..][0..hdr.num_globals    * @sizeOf(u32)      ]));
    // zig fmt: on

    if (native_endian == .big) {
        std.mem.byteSwapAllElements(Statement, statements);
        std.mem.byteSwapAllElements(Function, funcs);
        std.mem.byteSwapAllElements(Def, globaldefs);
        std.mem.byteSwapAllElements(Def, fielddefs);
        std.mem.byteSwapAllElements(u32, globals);
    }

    vm.version = hdr.version;
    vm.progdefs_crc = @intCast(hdr.crc);
    vm.program_crc = progs_crc;

    vm.program = bytes;
    vm.strings = strings;
    vm.funcs = funcs;
    vm.globaldefs = globaldefs;
    vm.fielddefs = fielddefs;
    vm.statements = statements;
    vm.globals = globals;

    vm.num_entity_fields = hdr.entityfields;
}

pub const ExecError = error{FunctionNotFound} || VmError;

pub fn exec(vm: *Vm, func_name: []const u8) ExecError!void {
    // @Todo add some sort of configure phase to the API where the user can
    // supply values to fulfill this contract.
    assert(vm.entity_memory.len == vm.num_entities * vm.num_entity_fields);
    assert(vm.num_entities >= 1); // at least the null entity needs to exist

    // find function by name
    const func_idx: u32 = for (vm.funcs, 0..) |func, i| {
        const name = subCString(vm.strings, func.s_name);
        if (std.mem.eql(u8, name, func_name)) break @intCast(i);
    } else {
        return error.FunctionNotFound;
    };

    vm.panicking = false;
    errdefer vm.panicking = false;

    const exit_depth = vm.stack.trace_depth;
    var runaway: u32 = 100_000;

    try enterVmFunction(vm, func_idx);
    run_loop: while (true) {
        const stmt = vm.statements[vm.program_counter];

        runaway -= 1;
        if (runaway == 0) return vm.panic(
            "runaway loop; vm exceeded maximum cycle count without yielding",
        );

        if (vm.trace and vm.logger != null)
            vm.logger.?(vm, .{ .statement = stmt });

        const GlobalValue = extern union {
            float: f32,
            uint: u32,
            vector: [3]f32,
            string: i32, // negative values are temporary strings
            function: u32,
            entity_index: u32,
            entity_field_offset: u32,
            entity_field_address: u32,
        };

        // Global registers accessed by statement arguments. The branch operand of
        // goto/if/ifnot holds a statement offset instead of a global index, so
        // substitute the null register; the branch logic reads it from stmt.args.
        // @Todo bounds checking for vectors, indices, etc. We should not trust user input!
        const a: *GlobalValue = @ptrCast(&vm.globals[@intCast(if (stmt.op == .goto) 0 else stmt.args[0])]);
        const b: *GlobalValue = @ptrCast(&vm.globals[@intCast(if (stmt.op == .@"if" or stmt.op == .ifnot) 0 else stmt.args[1])]);
        const c: *GlobalValue = @ptrCast(&vm.globals[@intCast(stmt.args[2])]);

        switch (stmt.op) {
            .add_f => c.float = a.float + b.float,
            .sub_f => c.float = a.float - b.float,
            .mul_f => c.float = a.float * b.float,
            .div_f => c.float = a.float / b.float,

            .add_v => for (0..3) |i| {
                c.vector[i] = a.vector[i] + b.vector[i];
            },
            .sub_v => for (0..3) |i| {
                c.vector[i] = a.vector[i] - b.vector[i];
            },
            .mul_fv => for (0..3) |i| {
                c.vector[i] = a.float * b.vector[i];
            },
            .mul_vf => for (0..3) |i| {
                c.vector[i] = a.vector[i] * b.float;
            },
            .mul_v => c.float =
                a.vector[0] * b.vector[0] +
                a.vector[1] * b.vector[1] +
                a.vector[2] * b.vector[2],

            .bitand, .bitor => |op| {
                // This casting is weird but matches Quake behavior, except for out-of-range floats.
                // Quake doesn't check the range at all and ends up depending on UB. Here we use lossyCast
                // to avoid a runtime panic/UB, which does result in different values, but they're garbage
                // anyway. Sane code would not depend on this behavior!
                const ai = std.math.lossyCast(i32, a.float);
                const bi = std.math.lossyCast(i32, b.float);
                c.float = @floatFromInt(if (op == .bitand) ai & bi else ai | bi);
            },
            // the following "floatFromBool" casts are weird but match Quake behavior
            .@"and" => c.float = floatFromBool(a.float != 0 and b.float != 0),
            .@"or" => c.float = floatFromBool(a.float != 0 or b.float != 0),

            .not_f => c.float = floatFromBool(a.float == 0),
            .not_v => c.float = floatFromBool(a.vector[0] == 0 and a.vector[1] == 0 and a.vector[2] == 0),
            .not_s => c.float = floatFromBool(a.string == 0 or vm.getString(a.string)[0] == 0), // check if string is null or empty
            .not_ent => c.float = floatFromBool(a.entity_index == 0), // the 0th entity (world entity) doubles as the false-y/null entity. This matches vanilla Quake behavior.
            .not_fnc => c.float = floatFromBool(a.function == 0), // the 0th function is the null function

            .eq_f => c.float = floatFromBool(a.float == b.float),
            .eq_v => c.float = floatFromBool(std.mem.eql(f32, &a.vector, &b.vector)),
            .eq_s => c.float = floatFromBool(std.mem.eql(u8, vm.getString(a.string), vm.getString(b.string))),
            .eq_e => c.float = floatFromBool(a.entity_index == b.entity_index),
            .eq_fnc => c.float = floatFromBool(a.function == b.function),

            .ne_f => c.float = floatFromBool(a.float != b.float),
            .ne_v => c.float = floatFromBool(!std.mem.eql(f32, &a.vector, &b.vector)),
            .ne_s => c.float = floatFromBool(!std.mem.eql(u8, vm.getString(a.string), vm.getString(b.string))),
            .ne_e => c.float = floatFromBool(a.entity_index != b.entity_index),
            .ne_fnc => c.float = floatFromBool(a.function != b.function),

            .ge => c.float = floatFromBool(a.float >= b.float),
            .le => c.float = floatFromBool(a.float <= b.float),
            .gt => c.float = floatFromBool(a.float > b.float),
            .lt => c.float = floatFromBool(a.float < b.float),

            // store value in global register
            .store_f,
            .store_ent,
            .store_fld,
            .store_s,
            .store_fnc,
            => b.uint = a.uint,
            .store_v => @memcpy(&b.vector, &a.vector),

            // store value in entity field via its address
            .storep_f,
            .storep_ent,
            .storep_fld,
            .storep_s,
            .storep_fnc,
            => vm.entity_memory[b.entity_field_address] = a.uint,
            .storep_v => {
                const field_ptr: []f32 = @ptrCast(vm.entity_memory[b.entity_field_address..][0..3]);
                @memcpy(field_ptr, &a.vector);
            },

            // load value from entity field
            .load_f,
            .load_fld,
            .load_ent,
            .load_s,
            .load_fnc,
            => {
                const field_address = a.entity_index * vm.num_entity_fields + b.entity_field_offset;
                const field: u32 = vm.entity_memory[field_address];
                c.uint = field;
            },
            .load_v => {
                const field_address = a.entity_index * vm.num_entity_fields + b.entity_field_offset;
                const field: []f32 = @ptrCast(vm.entity_memory[field_address..][0..3]);
                @memcpy(&c.vector, field);
            },

            // store entity field address in global register
            .address => {
                // The address instruction returns a host defined entity field address, which is used in
                // storep_* instructions. The reason it's done this way is so the host's entity data structure
                // doesn't have to mirror the QuakeC representation. In other words, all QC entity fields do not have
                // to be stored contiguously in memory. Quake utilizes this feature to store entities in the edict
                // (Entity Dictionary) data structure, and returns byte offset into the edict pool instead of a
                // field offset in ints.
                //
                // Here our entity storage is flat, so just return the field offset directly. In the future,
                // we could let the user define this mapping via a callback so they can use their own data layout.
                if (a.entity_index == 0) return vm.panic("assignment to world entity"); // @Todo allow user to disable check?
                c.entity_field_address = a.entity_index * vm.num_entity_fields + b.entity_field_offset;
            },

            .@"if", .ifnot, .goto => |op| {
                const jump: bool, const offset: i16 = switch (op) {
                    .@"if" => .{ a.uint != 0, stmt.args[1] },
                    .ifnot => .{ a.uint == 0, stmt.args[1] },
                    .goto => .{ true, stmt.args[0] },
                    else => unreachable,
                };
                if (jump) {
                    // sign extend the offset so that backwards jumps can underflow
                    // and forwards jumps can overflow the program counter
                    vm.program_counter +%= @as(u32, @bitCast(@as(i32, offset)));
                    continue; // don't increment counter
                }
            },

            .call0,
            .call1,
            .call2,
            .call3,
            .call4,
            .call5,
            .call6,
            .call7,
            .call8,
            => |call| {
                const num_args: u4 = @intCast(@backingInt(call) - @backingInt(Opcode.call0));

                if (a.function == 0) return vm.panic("attempted to call null function");
                const next_func = vm.funcs[a.function];

                if (next_func.first_statement < 0) {
                    // @Todo start user builtins at index 1 instead of 0, and make 0 the null builtin,
                    // matching the other values with sentinels
                    const builtin_idx: u32 = @intCast(-next_func.first_statement - 1);
                    if (builtin_idx >= vm.builtins.len) {
                        return vm.panicExtra("unimplemented builtin: {d}", .{builtin_idx + 1});
                    }
                    vm.argc = num_args;
                    // push a call stack frame for the builtin
                    try pushStackTraceFrame(vm, a.function);
                    vm.builtins[builtin_idx](vm) catch |err| {
                        // We want panics from builtins to be logged like normal,
                        // but if the user just returns an error instead of calling panic
                        // we need to call it for them.
                        if (!vm.panicking) vm.panicExtra(
                            "panicked in builtin {s}",
                            .{vm.getString(@bitCast(next_func.s_name))},
                        ) catch {}; // ignore this error so it doesn't show up in the error trace
                        return err; // bubbling up error, ignore me!
                    };
                    // @Todo should this error? The user could modify the call stack
                    // such that this would be reachable. Is that a programmer error
                    // or safety checked behavior?
                    popStackTraceFrame(vm) catch unreachable;
                } else {
                    try enterVmFunction(vm, a.function);
                    continue; // don't increment counter
                }
            },

            inline .done, .@"return" => |op| {
                if (op == .@"return") @memcpy(
                    vm.globals[@backingInt(SpecialRegisterOffset.@"return")..][0..3],
                    vm.globals[@intCast(stmt.args[0])..][0..3],
                );
                try leaveVmFunction(vm);
                if (exit_depth == vm.stack.trace_depth)
                    break :run_loop; // all done
            },

            .state => {
                return vm.panic("unimplemented opcode: state"); // @Incomplete
            },

            _ => |op| return vm.panicExtra("invalid opcode: {d}", .{@backingInt(op)}),
        }

        vm.program_counter +%= 1;
    }
}

/// Pushes current_function and program_counter onto the trace stack,
/// and updates them to the new function index and entry respectively.
/// If func is a builtin then the program_counter will be set to 0.
fn pushStackTraceFrame(vm: *Vm, func_idx: u32) VmError!void {
    const func = vm.funcs[func_idx];
    const is_builtin = func.first_statement < 0;
    assert(func.first_statement < vm.statements.len);

    if (vm.stack.trace_depth == 0) {
        assert(vm.program_counter == 0);
        assert(vm.current_function == 0);
    }
    vm.stack.trace[vm.stack.trace_depth] = .{
        .stmt = vm.program_counter,
        .func = vm.current_function,
    };

    vm.stack.trace_depth += 1;
    if (vm.stack.trace_depth >= vm.stack.trace.len)
        // Technically we lose the last stack frame here. Running this check first
        // (panicking on the next push) would be more efficient, but then we wouldn't
        // be able to push another frame in printStackTrace. Also, it's a nice property
        // for vm.stack.trace[vm.stack.trace_depth] to never fail.
        // This matches vanilla Quake behavior.
        return vm.panic("call stack overflow");

    vm.current_function = func_idx;
    vm.program_counter = if (!is_builtin)
        @intCast(func.first_statement)
    else blk: {
        assert(vm.statements[0].op == .done);
        break :blk 0;
    };
}

fn popStackTraceFrame(vm: *Vm) VmError!void {
    if (vm.stack.trace_depth == 0)
        return vm.panic("call stack underflow");

    vm.stack.trace_depth -= 1;
    vm.current_function = vm.stack.trace[vm.stack.trace_depth].func;
    vm.program_counter = vm.stack.trace[vm.stack.trace_depth].stmt;
}

/// Sets up the program counter and call stack.
/// Passing the null function is allowed.
fn enterVmFunction(vm: *Vm, func_idx: u32) VmError!void {
    const func = vm.funcs[func_idx];

    try pushStackTraceFrame(vm, func_idx);

    // @Note on weird stack behavior:
    // Confusingly, function locals (their parameters + local variables) are not stored on the stack, but in global memory.
    // Each function gets a global memory region for its locals (i.e. its frame). Critically, this memory region is *reused
    // for every invocation of the function*. Calls to a function that already appears higher up the call stack will clobber
    // any existing locals (including parameters!), corrupting execution. Because we can't know for sure the locals won't be
    // clobbered at runtime, we always save them to the stack.
    // If you're wondering why carmack didn't use a stack pointer + local offsets, so am I.
    // This matches vanilla Quake behavior.

    if (vm.stack.locals_used + func.frame_size > vm.stack.locals.len)
        return vm.panic("local stack overflow");
    @memcpy(
        vm.stack.locals[vm.stack.locals_used..][0..func.frame_size],
        vm.globals[func.frame_start..][0..func.frame_size],
    );
    vm.stack.locals_used += func.frame_size;

    // copy arguments into function parameter registers
    var reg = func.frame_start;
    for (0..func.num_params) |arg_idx| {
        for (0..func.param_size[arg_idx]) |elem_idx| {
            vm.globals[reg] = vm.globals[@backingInt(SpecialRegisterOffset.arg0) + arg_idx * 3 + elem_idx];
            reg += 1;
        }
    }

    assert(reg - func.frame_start <= func.frame_size);
}

fn leaveVmFunction(vm: *Vm) VmError!void {
    // It's important we do this before popping the call stack
    const current_func = vm.funcs[vm.current_function];

    // restore locals from the stack
    if (current_func.frame_size > vm.stack.locals_used) return vm.panic("local stack underflow");
    vm.stack.locals_used -= current_func.frame_size;

    @memcpy(
        vm.globals[current_func.frame_start..][0..current_func.frame_size],
        vm.stack.locals[vm.stack.locals_used..][0..current_func.frame_size],
    );

    try popStackTraceFrame(vm);
}

pub fn printStackTrace(w: *std.Io.Writer, vm: *Vm) std.Io.Writer.Error!void {
    if (vm.stack.trace_depth == 0)
        return w.writeAll("<NO CALL STACK>\n");

    // @Performance the mutability of vm here is viral and affects the public API (logging).
    // For the sake of better codegen, maybe it's worth changing the logic here to let vm be const?
    // I dunno.

    // temporarily push the current function so the loop below can be simpler
    const old_trace = vm.stack.trace[vm.stack.trace_depth]; // this should always be empty but just copy it anyway
    vm.stack.trace[vm.stack.trace_depth] = .{
        .func = vm.current_function,
        .stmt = vm.program_counter,
    };
    defer vm.stack.trace[vm.stack.trace_depth] = old_trace;

    var i: u32 = vm.stack.trace_depth;
    while (true) : (i -= 1) {
        if (vm.stack.trace[i].func == 0) {
            try w.writeAll("???: stmt 0 in ???\n");
        } else {
            // @Todo parse fteqcc line info and print the correct line of source code
            const func = vm.funcs[vm.stack.trace[i].func];
            if (func.first_statement < 0) {
                try w.print("{s}: builtin #{d} {s}\n", .{
                    vm.getString(@bitCast(func.s_file)),
                    @as(u32, @intCast(-func.first_statement)),
                    vm.getString(@bitCast(func.s_name)),
                });
            } else {
                try w.print("{s}: stmt {d} in {s}\n", .{
                    vm.getString(@bitCast(func.s_file)),
                    vm.stack.trace[i].stmt,
                    vm.getString(@bitCast(func.s_name)),
                });
            }
        }

        if (i == 0) break;
    }
}

inline fn floatFromBool(b: bool) f32 {
    return @floatFromInt(@intFromBool(b));
}

fn subCString(strings: [:0]const u8, start_idx: usize) [:0]const u8 {
    const end = std.mem.indexOfScalarPos(u8, strings, start_idx, 0) orelse strings.len;
    return strings[start_idx..end :0];
}

fn getDefAtOffset(defs: []const Def, offset: u32) ?*const Def {
    return for (defs) |*d| {
        if (d.offset == offset) break d;
    } else null;
}

pub fn printStatement(w: *std.Io.Writer, vm: *const Vm, stmt: Statement) std.Io.Writer.Error!void {
    // @Todo better printing format, this is butt ugly
    switch (stmt.op) {
        else => |op| try w.print("{t: <10} ", .{op}),
        _ => |op| {
            return w.print("invalid opcode: {d}", .{@backingInt(op)});
        },
    }

    switch (stmt.op) {
        .@"if", .ifnot => {
            try printGlobal(w, vm, @intCast(stmt.args[0]), true);
            try w.print("branch {d}", .{stmt.args[1]});
        },
        .goto => {
            try w.print("branch {d}", .{stmt.args[0]});
        },
        .store_f,
        .store_v,
        .store_s,
        .store_ent,
        .store_fld,
        .store_fnc,
        => {
            try printGlobal(w, vm, @intCast(stmt.args[0]), true);
            try printGlobal(w, vm, @intCast(stmt.args[1]), false);
        },
        else => {
            if (stmt.args[0] != 0)
                try printGlobal(w, vm, @intCast(stmt.args[0]), true);
            if (stmt.args[1] != 0)
                try printGlobal(w, vm, @intCast(stmt.args[1]), true);
            if (stmt.args[2] != 0)
                try printGlobal(w, vm, @intCast(stmt.args[2]), false);
        },
        _ => unreachable,
    }
}

fn printGlobal(writer: *std.Io.Writer, vm: *const Vm, offset: u32, print_contents: bool) !void {
    assert(@as(i32, @bitCast(offset)) > 0);
    var alignment_buf: [128]u8 = undefined;
    var sw: std.Io.Writer = .fixed(&alignment_buf); // sub writer

    if (getDefAtOffset(vm.globaldefs, offset)) |global_def| print_def: {
        try sw.print("{d}({s})", .{ offset, vm.strings[global_def.s_name.. :0].ptr });
        if (!print_contents) break :print_def;

        // PR_ValueString
        const value = vm.globals[offset];
        switch (global_def.type.tag) {
            .void => try sw.writeAll("void"),
            .string => {
                const str = vm.getString(@bitCast(value));
                var str_buf: [9]u8 = undefined;
                var str_writer: std.Io.Writer = .fixed(&str_buf);
                str_writer.print("{f}", .{std.ascii.hexEscape(str, .lower)}) catch {
                    str_buf[str_buf.len - 3 ..].* = @splat('.'); // truncate string
                };
                try sw.print("\"{s}\"", .{str_writer.buffered()});
            },
            .float => try sw.printFloat(@as(f32, @bitCast(value)), .{}),
            .vector => try sw.print("{d}, {d}, {d}", .{
                @as(f32, @bitCast(vm.globals[offset + 0])),
                @as(f32, @bitCast(vm.globals[offset + 1])),
                @as(f32, @bitCast(vm.globals[offset + 2])),
            }),
            .entity => try sw.print("entity {d}", .{value}),
            .field => {
                const field_def = getDefAtOffset(vm.fielddefs, value);
                const field_str_offset = if (field_def) |d| d.s_name else 0;
                try sw.print(".{s}", .{vm.getString(@bitCast(field_str_offset))});
            },
            .function => {
                const func = vm.funcs[value];
                try sw.print("{s}()", .{vm.getString(@bitCast(func.s_name))});
            },
            .pointer => try sw.writeAll("pointer"),
            _ => |t| try sw.print("bad type {d}", .{@backingInt(t)}),
        }
    } else {
        try sw.print("{d}(???)", .{offset});
    }

    try writer.alignBuffer(sw.buffered(), 25, .left, ' ');
}

pub fn dumpVm(vm: Vm, w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (vm.funcs, 0..) |func, i| {
        if (func.first_statement == 0) {
            try w.print("function[{d}]: null\n", .{i});
            continue;
        }

        try w.print("function[{d}]: {s}:{s}:", .{
            i,
            vm.getString(@bitCast(func.s_file)),
            vm.getString(@bitCast(func.s_name)),
        });

        if (func.first_statement < 0) {
            try w.print(" builtin={d}", .{-func.first_statement});
        } else {
            try w.print(" entry=0x{X}", .{func.first_statement});
        }

        try w.print(", frame_start=0x{X}, frame_size={d}, #params={d}", .{
            func.frame_start,
            func.frame_size,
            func.num_params,
        });

        try w.writeByte('\n');
    }

    for (vm.globaldefs, 0..) |def, i| {
        if (def.offset == 0)
            try w.print("globaldef[{d}]: null\n", .{i})
        else
            try w.print("globaldef[{d}]: {s}: type={t}, offset=0x{X}, save={}\n", .{
                i,
                vm.getString(@bitCast(def.s_name)),
                def.type.tag,
                def.offset,
                def.type.save_global,
            });
    }

    for (vm.fielddefs, 0..) |def, i| {
        if (def.offset == 0)
            try w.print("fielddef[{d}]: null\n", .{i})
        else
            try w.print("fielddef[{d}]: {s}: type={t}, offset=0x{X}, save={}\n", .{
                i,
                vm.getString(@bitCast(def.s_name)),
                def.type.tag,
                def.offset,
                def.type.save_global,
            });
    }

    const GlobalValueFmt = struct {
        vm: *const Vm,
        def: *const Def,

        pub fn format(t: @This(), w_: *std.Io.Writer) std.Io.Writer.Error!void {
            switch (t.def.type.tag) {
                .vector => {
                    const vec: *[3]f32 = @ptrCast(t.vm.globals[t.def.offset..][0..3]);
                    try w_.print("{{{d:.1},{d:.1},{d:.1}}}", .{ vec[0], vec[1], vec[2] });
                },
                .float => try w_.print("{d:.2}", .{@as(f32, @bitCast(t.vm.globals[t.def.offset]))}),
                else => try w_.print("{d: <4}", .{t.vm.globals[t.def.offset]}),
            }
        }
    };

    const StmtPrinter = struct {
        fn printArg(w_: *std.Io.Writer, vm_: *const Vm, arg: u16) !void {
            if (arg == @backingInt(SpecialRegisterOffset.null)) {
                try w_.writeByte('_');
            } else if (getDefAtOffset(vm_.globaldefs, arg)) |def| {
                const name = vm_.getString(@bitCast(def.s_name));
                if (std.mem.eql(u8, name, "IMMEDIATE")) {
                    try w_.print("${f}", .{GlobalValueFmt{ .vm = vm_, .def = def }});
                } else {
                    try w_.print("%{s}", .{name});
                }
            } else {
                try w_.print("[0x{X:0>2}]", .{arg});
            }
        }

        fn printOperand(w_: *std.Io.Writer, vm_: *const Vm, stmt_idx: usize, arg_idx: usize) !void {
            const stmt = vm_.statements[stmt_idx];
            const branch: ?usize = switch (stmt.op) {
                .goto => 0,
                .@"if", .ifnot => 1,
                else => null,
            };
            if (branch == arg_idx) {
                // if/ifnot/goto keep their branch offset in one of the operands;
                // print it as an absolute statement index instead.
                try w_.print("->{d}", .{@as(i32, @intCast(stmt_idx)) + stmt.args[arg_idx]});
            } else {
                try printArg(w_, vm_, @bitCast(stmt.args[arg_idx]));
            }
        }

        fn opcodeName(buf: []u8, op: Opcode) []const u8 {
            const value = @backingInt(op);
            inline for (@typeInfo(Opcode).@"enum".field_names) |name| {
                if (@backingInt(@field(Opcode, name)) == value) return name;
            }
            return std.fmt.bufPrint(buf, "invalid(0x{X})", .{value}) catch "invalid";
        }
    };

    const mnemonic_width = comptime blk: {
        var len = 0;
        for (@typeInfo(Opcode).@"enum".field_names) |name| {
            len = @max(len, name.len);
        }
        break :blk len;
    };

    var buf: [128]u8 = undefined; // shared

    const operand_width: usize = blk: {
        var width: usize = 0;
        for (vm.statements, 0..) |stmt, i| {
            for (0..stmt.args.len) |j| {
                var sw: std.Io.Writer = .fixed(&buf);
                StmtPrinter.printOperand(&sw, &vm, i, j) catch {}; // truncated on overflow
                width = @max(width, sw.buffered().len);
            }
        }
        break :blk width;
    };

    for (vm.statements, 0..) |stmt, i| {
        try w.print("statement[{d: >2}]: ", .{i});

        const op_name = StmtPrinter.opcodeName(&buf, stmt.op);
        try w.writeAll(op_name);
        try w.splatByteAll(' ', mnemonic_width -| op_name.len + 1);

        for (0..stmt.args.len) |j| {
            var sw: std.Io.Writer = .fixed(&buf);
            StmtPrinter.printOperand(&sw, &vm, i, j) catch {}; // truncated on overflow
            try w.writeAll(sw.buffered());
            try w.splatByteAll(' ', operand_width -| sw.buffered().len);
            if (j + 1 < stmt.args.len) try w.splatByteAll(' ', 2);
        }

        try w.print(" a=0x{X:0>2} b=0x{X:0>2} c=0x{X:0>2}\n", .{
            @as(u16, @bitCast(stmt.args[0])),
            @as(u16, @bitCast(stmt.args[1])),
            @as(u16, @bitCast(stmt.args[2])),
        });
    }

    const info = @typeInfo(SpecialRegisterOffset).@"enum";
    inline for (info.field_names, info.field_values) |name, value| {
        try w.print("global[{s: >6}]: {any}\n", .{ name, switch (@field(SpecialRegisterOffset, name)) {
            .null => vm.globals[value],
            else => vm.globals[value..][0..3],
        } });
    }

    var i: u32 = SpecialRegisterOffset.reserved_len;
    while (i < vm.globals.len) : (i += 1) {
        try w.print("global[0x{X: <2}]:", .{i});
        const global = vm.globals[i];

        if (getDefAtOffset(vm.globaldefs, @intCast(i))) |def| {
            try w.print(" {f} ({s}: {t})\n", .{
                GlobalValueFmt{ .vm = &vm, .def = def },
                vm.getString(@bitCast(def.s_name)),
                def.type.tag,
            });
        } else {
            try w.print(" {d}\n", .{global});
        }
    }
}
