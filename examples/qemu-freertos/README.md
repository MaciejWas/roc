# Hello World on FreeRTOS

This example builds the Roc application in [app/main.roc](app/main.roc) as a
freestanding RISC-V firmware ELF, using the accompanying FreeRTOS platform.

The platform build downloads its pinned FreeRTOS source and produces host-library artifacts
for the selected register width.

## 32-bit RISC-V on QEMU

```sh
# From the repository root, build the Roc compiler.
zig build roc

# Build and install the RV32 FreeRTOS platform artifacts once.
(cd examples/qemu-freertos/platform && zig build --prefix . -Driscv-bits=32)

# Compile the example firmware for the platform's RV32I target.
zig-out/bin/roc build examples/qemu-freertos/app/main.roc \
  --target=riscv32elf \
  --output=examples/qemu-freertos/app/hello-rv32.elf

# Run the firmware with QEMU's 32-bit RISC-V system emulator.
examples/qemu-freertos/platform/run.sh examples/qemu-freertos/app/hello-rv32.elf 32
```

## 64-bit RISC-V on QEMU

```sh
# From the repository root, build the Roc compiler.
zig build roc

# Build and install the RV64 FreeRTOS platform artifacts once.
(cd examples/qemu-freertos/platform && zig build --prefix . -Driscv-bits=64)

# Compile the example firmware for the platform's RV64I target.
zig-out/bin/roc build examples/qemu-freertos/app/main.roc \
  --target=riscv64elf \
  --output=examples/qemu-freertos/app/hello-rv64.elf

# Run the firmware with QEMU's 64-bit RISC-V system emulator.
examples/qemu-freertos/platform/run.sh examples/qemu-freertos/app/hello-rv64.elf 64
```
