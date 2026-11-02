# Roc + Zig + FreeRTOS on QEMU RISC-V

A minimal working example: a FreeRTOS task invokes Roc, Roc writes
`Hello world` to the emulated UART, and the task cleans up and deletes itself.
The idle hook then exits QEMU successfully.

From the repository root, using the same Zig version as the compiler:

```sh
zig build roc
zig build --build-file examples/qemu-freertos/build.zig run
```

The first build downloads the pinned FreeRTOS Kernel V11.2.0 release source.
`qemu-system-riscv64` must be on PATH. To build firmware without running it,
omit `run`; the firmware artifact is named `hello.elf`.

Expected output:

```text
Hello world
```

The command exits with status zero. QEMU shutdown is part of this example's
test harness; on hardware the task would exit and FreeRTOS would keep running.

The sequence is:

1. Machine-mode startup initializes RAM and the stack on QEMU's `virt` board.
2. The Zig host creates a FreeRTOS recursive mutex and one Roc task.
3. The Roc app calls `Uart.write!("Hello world\n")` through the platform.
4. Zig writes the borrowed string to the emulated 16550 UART.
5. The task cleans up its Roc runtime state and deletes itself.
6. The idle hook tells QEMU's test device to exit successfully.

The scheduler uses the standard RISC-V port and the QEMU machine timer.
`-bios none` starts the firmware directly, without Linux or OpenSBI.
The Zig/FreeRTOS firmware uses RV64IMA plus CSR instructions for privileged
scheduler code. The Roc archive retains its RV64IA baseline; everything uses
the LP64 ABI. The platform deliberately requires hardware multiplication and
division (`M`). The FreeRTOS kernel remains upstream C; the platform is
Zig, with a small C bridge for FreeRTOS macros. Zig supplies compiler runtime
helpers. Standard C declarations come from Zig's LP64 musl headers; no libc
library is linked.

Files:

- `main.roc`: the application.
- `platform/`: Roc's platform declaration and hosted UART effect.
- `host.zig`: UART, allocator, task-local state, recursive mutex callbacks,
  cooperative task shutdown, and QEMU exit handling.
- `freertos_bridge.c`: wrappers for the FreeRTOS macro API.
- `FreeRTOSConfig.h`: scheduler, heap, timer, and task-local storage settings.
- `startup.S` and `linker.ld`: boot code and the `virt` memory layout.

The example deliberately uses one task and one hart. It does not test
concurrent tasks, nested entry, task recreation, or boxy execution yet.
