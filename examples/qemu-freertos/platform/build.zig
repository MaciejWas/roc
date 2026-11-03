//! Build the reusable QEMU/FreeRTOS platform artifacts without an application.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const bits = b.option(u16, "riscv-bits", "RISC-V register width (32 or 64)") orelse 64;
    if (bits != 32 and bits != 64) @panic("riscv-bits must be 32 or 64");
    const kernel = b.dependency("freertos", .{});
    const target = b.resolveTargetQuery(.{
        .cpu_arch = if (bits == 32) .riscv32 else .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = if (bits == 32) &std.Target.riscv.cpu.generic_rv32 else &std.Target.riscv.cpu.generic_rv64 },
        // The QEMU platform uses hardware multiply/divide and privileged CSR
        // instructions. Roc-generated code keeps its RV32I or RV64I baseline.
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .m, .zicsr }),
    });

    const host = b.addLibrary(.{
        .name = "host",
        .root_module = b.createModule(.{
            .root_source_file = b.path("host.zig"),
            .target = target,
            .optimize = .small,
            .strip = false,
            .code_model = .medium,
            .single_threaded = true,
            .stack_check = false,
            .stack_protector = false,
        }),
        .linkage = .static,
    });
    host.bundle_compiler_rt = true;
    host.root_module.addImport("roc_str_view", b.createModule(.{
        .root_source_file = b.path("../../../src/default_platform/roc_str_view.zig"),
        .target = target,
    }));
    host.root_module.addIncludePath(b.path("."));
    host.root_module.addIncludePath(kernel.path("include"));
    host.root_module.addIncludePath(kernel.path("portable/GCC/RISC-V"));
    host.root_module.addIncludePath(kernel.path("portable/GCC/RISC-V/chip_specific_extensions/RV32I_CLINT_no_extensions"));
    // FreeRTOS includes standard C declarations. Use Zig's matching musl headers
    // only; no libc library is linked, and all memory operations come from Zig.
    host.root_module.addSystemIncludePath(std.Build.LazyPath.zig_lib.path(b, if (bits == 32) "libc/include/riscv32-linux-musl" else "libc/include/riscv64-linux-musl"));
    host.root_module.addSystemIncludePath(std.Build.LazyPath.zig_lib.path(b, "libc/include/generic-musl"));
    const c_flags: []const []const u8 = &.{ "-ffreestanding", "-fno-stack-protector", "-mcmodel=medany" };
    for ([_][]const u8{ "tasks.c", "queue.c", "list.c", "portable/MemMang/heap_4.c", "portable/GCC/RISC-V/port.c", "portable/GCC/RISC-V/portASM.S" }) |file| {
        host.root_module.addCSourceFile(.{ .file = kernel.path(file), .flags = c_flags });
    }
    host.root_module.addCSourceFile(.{ .file = b.path("freertos_bridge.c"), .flags = c_flags });
    const startup = b.addObject(.{
        .name = "startup",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .small,
            .code_model = .medium,
        }),
    });
    startup.bundle_compiler_rt = false;
    startup.root_module.addAssemblyFile(b.path("startup.S"));
    const artifacts = if (bits == 32) "targets/riscv32elf/" else "targets/riscv64elf/";
    b.getInstallStep().dependOn(&b.addInstallFile(host.getEmittedBin(), b.fmt("{s}libhost.a", .{artifacts})).step);
    b.getInstallStep().dependOn(&b.addInstallFile(startup.getEmittedBin(), b.fmt("{s}startup.o", .{artifacts})).step);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("linker.ld"), b.fmt("{s}linker.ld", .{artifacts})).step);
}
