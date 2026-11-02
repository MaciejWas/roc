const std = @import("std");

pub fn build(b: *std.Build) void {
    const kernel = b.dependency("freertos", .{});
    const kernel_root = "FreeRTOS-Kernel-0adc196d4bd52a2d91102b525b0aafc1e14a2386/";
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv64 },
        // The QEMU platform uses hardware multiply/divide and privileged CSR
        // instructions. Roc-generated code keeps its RV64IA baseline.
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .a, .m, .zicsr }),
    });
    const app = std.Build.Step.Run.create(b, "compile Roc app");
    app.addFileArg(b.path("../../zig-out/bin/roc"));
    app.addArgs(&.{ "build", "--target=riscv64elf", "--no-cache" });
    app.addFileArg(b.path("main.roc"));
    const archive = app.addPrefixedOutputFileArg("--output=", "roc_app.a");

    const firmware = b.addExecutable(.{
        .name = "hello.elf",
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
    });
    firmware.entry = .{ .symbol_name = "_start" };
    firmware.setLinkerScript(b.path("linker.ld"));
    firmware.root_module.addImport("roc_str_view", b.createModule(.{
        .root_source_file = b.path("../../src/default_platform/roc_str_view.zig"),
        .target = target,
    }));
    firmware.root_module.addObjectFile(archive);
    firmware.root_module.addIncludePath(b.path("."));
    firmware.root_module.addIncludePath(kernel.path(kernel_root ++ "include"));
    firmware.root_module.addIncludePath(kernel.path(kernel_root ++ "portable/GCC/RISC-V"));
    firmware.root_module.addIncludePath(kernel.path(kernel_root ++ "portable/GCC/RISC-V/chip_specific_extensions/RV32I_CLINT_no_extensions"));
    // FreeRTOS includes standard C declarations. Use Zig's LP64 musl headers
    // only; no libc library is linked, and all memory operations come from Zig.
    firmware.root_module.addSystemIncludePath(std.Build.LazyPath.zig_lib.path(b, "libc/include/riscv64-linux-musl"));
    firmware.root_module.addSystemIncludePath(std.Build.LazyPath.zig_lib.path(b, "libc/include/generic-musl"));
    const c_flags: []const []const u8 = &.{ "-ffreestanding", "-fno-stack-protector", "-mcmodel=medany" };
    for ([_][]const u8{ "tasks.c", "queue.c", "list.c", "portable/MemMang/heap_4.c", "portable/GCC/RISC-V/port.c", "portable/GCC/RISC-V/portASM.S" }) |file| {
        firmware.root_module.addCSourceFile(.{ .file = kernel.path(b.fmt("{s}{s}", .{ kernel_root, file })), .flags = c_flags });
    }
    firmware.root_module.addCSourceFile(.{ .file = b.path("freertos_bridge.c"), .flags = c_flags });
    firmware.root_module.addAssemblyFile(b.path("startup.S"));
    b.installArtifact(firmware);

    const run = b.addSystemCommand(&.{ "qemu-system-riscv64", "-machine", "virt", "-smp", "1", "-m", "128M", "-nographic", "-bios", "none", "-kernel" });
    run.addArtifactArg(firmware);
    b.step("run", "Run the Hello World task on QEMU").dependOn(&run.step);
}
