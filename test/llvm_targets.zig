const std = @import("std");
const Cases = @import("src/Cases.zig");

const targets = [_]std.zig.CrossTarget{
    .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .aarch64, .os_tag = .ios, .abi = .none },
    .{ .cpu_arch = .aarch64, .os_tag = .ios, .abi = .simulator },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .aarch64, .os_tag = .uefi, .abi = .none },
    .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .msvc },
    .{ .cpu_arch = .aarch64_be, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .aarch64_be, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .aarch64_32, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .aarch64_32, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .amdgcn, .os_tag = .amdhsa, .abi = .none },
    .{ .cpu_arch = .amdgcn, .os_tag = .amdpal, .abi = .none },
    .{ .cpu_arch = .amdgcn, .os_tag = .linux, .abi = .none },
    //.{ .cpu_arch = .amdgcn, .os_tag = .mesa3d, .abi = .none },
    .{ .cpu_arch = .arc, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .arc, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .arm, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .arm, .os_tag = .uefi, .abi = .none },
    .{ .cpu_arch = .armeb, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .armeb, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .avr, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .avr, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .avr, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .bpfel, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .bpfel, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .bpfeb, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .bpfeb, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .csky, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .csky, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .hexagon, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .m68k, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .m68k, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .mips, .os_tag = .linux, .abi = .gnueabihf },
    .{ .cpu_arch = .mips, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .mips, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .mipsel, .os_tag = .linux, .abi = .gnueabihf },
    .{ .cpu_arch = .mipsel, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .mipsel, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .mips64, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .mips64el, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .msp430, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .msp430, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .msp430, .os_tag = .linux, .abi = .none },
    //.{ .cpu_arch = .nvptx, .os_tag = .cuda, .abi = .none },
    //.{ .cpu_arch = .nvptx64, .os_tag = .cuda, .abi = .none },
    .{ .cpu_arch = .powerpc, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .powerpc, .os_tag = .linux, .abi = .gnueabihf },
    .{ .cpu_arch = .powerpc, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .powerpc, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .powerpcle, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .powerpcle, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .powerpcle, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .powerpcle, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .powerpcle, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .powerpc64, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .powerpc64, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .powerpc64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .powerpc64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .powerpc64, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .powerpc64le, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .powerpc64le, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .powerpc64le, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .powerpc64le, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .powerpc64le, .os_tag = .linux, .abi = .none },
    //.{ .cpu_arch = .r600, .os_tag = .mesa3d, .abi = .none },
    .{ .cpu_arch = .riscv32, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .riscv32, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .riscv64, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .s390x, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .s390x, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .sparc, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .sparc, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .sparc, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .sparcel, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .sparcel, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .sparc64, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .sparc64, .os_tag = .linux, .abi = .gnu },
    //.{ .cpu_arch = .spirv32, .os_tag = .opencl, .abi = .none },
    //.{ .cpu_arch = .spirv32, .os_tag = .glsl450, .abi = .none },
    //.{ .cpu_arch = .spirv32, .os_tag = .vulkan, .abi = .none },
    //.{ .cpu_arch = .spirv64, .os_tag = .opencl, .abi = .none },
    //.{ .cpu_arch = .spirv64, .os_tag = .glsl450, .abi = .none },
    //.{ .cpu_arch = .spirv64, .os_tag = .vulkan, .abi = .none },
    .{ .cpu_arch = .thumb, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .thumbeb, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .ve, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .wasm32, .os_tag = .emscripten, .abi = .none },
    .{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .wasm32, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi, .abi = .none },
    .{ .cpu_arch = .wasm64, .os_tag = .emscripten, .abi = .none },
    .{ .cpu_arch = .wasm64, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .wasm64, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .wasm64, .os_tag = .wasi, .abi = .none },
    .{ .cpu_arch = .x86, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .x86, .os_tag = .uefi, .abi = .none },
    .{ .cpu_arch = .x86, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .x86, .os_tag = .windows, .abi = .msvc },
    .{ .cpu_arch = .x86_64, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.x86.featureSet(&.{.soft_float}),
        .cpu_features_sub = std.Target.x86.featureSet(&.{ .mmx, .sse, .sse2, .avx, .avx2 }),
    },
    .{ .cpu_arch = .x86_64, .os_tag = .ios, .abi = .simulator },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .uefi, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc },
    .{ .cpu_arch = .xtensa, .os_tag = .freestanding, .abi = .none },
    .{ .cpu_arch = .xtensa, .os_tag = .linux, .abi = .none },
};

pub fn addCases(ctx: *Cases, build_options: @import("cases.zig").BuildOptions) !void {
    if (!build_options.enable_llvm) return;
    for (targets) |target| {
        if (target.cpu_arch) |arch| switch (arch) {
            .m68k => if (!build_options.llvm_has_m68k) continue,
            .csky => if (!build_options.llvm_has_csky) continue,
            .arc => if (!build_options.llvm_has_arc) continue,
            .xtensa => if (!build_options.llvm_has_xtensa) continue,
            else => {},
        };
        var case = ctx.noEmitUsingLlvmBackend("llvm_targets", target);
        case.addCompile("");
    }
}
