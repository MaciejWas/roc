# QEMU / FreeRTOS platform

This is a platform package for Roc applications. It contains no Hello World
message or other application logic. Apps select `main.roc` in their platform
declaration and implement its required `main! : () => {}` entry point.

The public boundary is:

- `main.roc`: requires the app entry point, exposes `Uart`, and declares how
  `roc build` links firmware for `riscv32elf` and `riscv64elf`.
- `Uart.roc`: declares `write! : Str => {}`.
- `host.zig`: implements the hosted `roc_uart_write` symbol, runtime callbacks,
  and FreeRTOS task lifecycle. It invokes the app's exported `roc_main`.

## Building the platform

From this directory, run `zig build --prefix . -Driscv-bits=32` or
`zig build --prefix . -Driscv-bits=64` to compile the Zig host and the pinned
upstream FreeRTOS kernel.
It installs three artifacts beside this platform declaration:

```text
targets/riscv32elf/ or targets/riscv64elf/
├── startup.o
├── libhost.a
└── linker.ld
```

`main.roc` lists `startup.o`, the compiled app, and `libhost.a` in link order.
Its `linker_script` and `entry_point` settings supply the board's memory layout
and boot symbol to Roc's ELF linker. These settings apply to ELF executable
output; script paths are relative to the target's inputs directory.

The build does not need an application or a Roc compiler executable. Its
source view of Roc strings comes from this repository. To distribute the
prebuilt platform, include `main.roc`, `Uart.roc`, and `targets/`; consumers do
not need the Zig/FreeRTOS sources or build tools.

The example's outer `run-tests.sh` builds the platform and runs every declared
QEMU boot profile. Each profile makes its hart count and atomic-extension
setting explicit.

## Implementation

- `build.zig` and `build.zig.zon`: platform build and pinned FreeRTOS dependency.
- `FreeRTOSConfig.h`: scheduler, heap, machine timer, and task-local storage settings.
- `freertos_bridge.c`: bridges FreeRTOS C macros to Zig functions.
- `startup.S`: machine-mode boot, stack initialization, and trap setup.
- `linker.ld`: memory layout for QEMU's RISC-V `virt` board.

The platform starts one FreeRTOS task, invokes the app, calls
`roc_cleanup_task_state`, and deletes the task. An idle hook exits QEMU
successfully after deletion. UART output uses the emulated 16550 device.

Allocation comes from FreeRTOS's heap. One task-local slot holds Roc's opaque
state, and a shared recursive mutex protects execution. The upstream kernel
is C; platform policy and runtime callbacks are Zig.

Firmware uses RV64IM plus CSR instructions and LP64. The Roc code retains
its RV64I baseline. This platform requires hardware multiplication and
division (`M`), but does not require hardware atomics (`A`). All Roc value
operations, including platform-side retain/release outside generated entry
wrappers, must hold the same recursive runtime mutex. Standard C declarations
come from Zig's LP64 musl headers;
no libc library is linked. `-bios none` boots without Linux or OpenSBI.

The platform starts one FreeRTOS task. In multi-hart boot profiles, only hart
zero enters the scheduler; secondary harts park in startup. The example does
not exercise concurrent tasks, nested entry, task recreation, SMP execution,
or boxy execution.
