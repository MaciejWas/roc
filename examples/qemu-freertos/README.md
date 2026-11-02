# Hello World on FreeRTOS

The application is [app/main.roc](app/main.roc). It selects the platform in one
line and uses its UART effect:

```roc
app [main!] { pf: platform "../platform/main.roc" }

import pf.Uart

main! = || {
    Uart.write!("Hello world\n")
}
```

The [platform](platform/README.md) owns FreeRTOS, the Zig host, UART registers,
allocation, locking, startup, and the memory layout. The app needs no Zig build
file. Build the repository's compiler first with `zig build roc`.

## 1. Build the platform once

```sh
(cd examples/qemu-freertos/platform && zig build --prefix .)
```

This downloads the pinned FreeRTOS source and installs the reusable archive,
startup object, and linker script under `platform/targets/riscv64elf/`.
Repeat only when changing the platform. It does not build an app.

## 2. Build the app with Roc

```sh
zig-out/bin/roc build examples/qemu-freertos/app/main.roc --output=examples/qemu-freertos/app/hello.elf
```

Roc selects the platform's freestanding target and links the app with the
prebuilt artifacts to produce the final firmware ELF. This command does not
invoke Zig or rebuild FreeRTOS. Repeat it whenever the app changes.

## 3. Run the firmware

```sh
examples/qemu-freertos/platform/run.sh examples/qemu-freertos/app/hello.elf
```

With `qemu-system-riscv64` on PATH, the minimal app shown above prints:

```text
Hello world
```

The task returns from Roc, cleans up, and deletes itself. The example harness
then exits QEMU with status zero. QEMU loads the ELF directly: there is no
separate FreeRTOS image to construct. A physical board could supply its own
packaging/flashing script at this step.

All commands above run from the repository root using its Zig version. See
the [platform README](platform/README.md) for CPU and implementation details.
