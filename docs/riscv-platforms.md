# RISC-V platforms

A platform can declare its instruction set, host ABI, and code model:

```roc
targets: {
    riscv32elf: {
        isa: "rv32imc",
        abi: Ilp32,
        code_model: Medany,
        inputs: ["startup.o", app, "libhost.a"],
        linker_script: "linker.ld",
        entry_point: "_start",
        output: Exe,
    },
}
```

The target name selects pointer width. `isa` accepts an unversioned `i` or `g`
base followed by single-letter extensions, for example `rv32i`, `rv32imc`,
`rv32imac`, `rv32imafc`, and `rv64gc`. Unknown/duplicate extensions and width
mismatches are errors. The reduced-register E base is not supported.

A permits hardware atomic instructions. Its absence does not prevent platform
synchronization on a single hart. Its presence does not enable concurrent Roc
execution or indicate the number of cores.

The calling convention is independent of CPU capabilities:

| Target | ABI | Floating-point argument/result convention |
| --- | --- | --- |
| `riscv32elf` | `Ilp32` | Integer registers |
| `riscv32elf` | `Ilp32f` | Hardware convention for F32 |
| `riscv32elf` | `Ilp32d` | Hardware convention for F32 and F64 |
| `riscv64elf` | `Lp64` | Integer registers |
| `riscv64elf` | `Lp64f` | Hardware convention for F32 |
| `riscv64elf` | `Lp64d` | Hardware convention for F32 and F64 |

An *f ABI requires F; a *d ABI requires F and D. Enabling F/D with an integer
ABI is supported. Platform native objects and generated C/Zig/Rust glue must be
compiled for the same ABI and a compatible ISA.

Omitted fields preserve RV32I/ILP32 or RV64I/LP64 defaults, with Medany. Medany
uses PC-relative addressing; Medlow uses absolute addressing. The linker script
must respect the selected model's addressing range. Roc compiles its builtins,
Boxy runtime, and compiler-support routines for the same selected configuration.
Standalone data objects carry matching ELF ABI flags. Roc supplies and keeps
private its own software arithmetic and memory helpers.

## Runtime boundary

The platform supplies the ordinary `roc_alloc`, `roc_realloc`, `roc_dealloc`,
`roc_dbg`, `roc_expect_failed`, and `roc_crashed` C symbols. Use `roc glue` for
complete declarations and value types. Allocation callbacks return aligned,
non-null memory; failure terminates Roc execution. The platform chooses its own
allocator and memory budgets. Crash/expect-failure handlers do not return to
failed Roc code.

Native freestanding platforms additionally implement:

```c
void roc_acquire_runtime_lock(void);
void roc_release_runtime_lock(void);
```

Generated entry points acquire before execution and release on normal return.
The lock is recursive for same-context nested entry. All host-side Roc value
operations, including reference counts and uniqueness checks, obey the same
lock. The lock callbacks do not enter Roc. Interrupts do not enter Roc or access
its values.

FreeRTOS and Zephyr platforms implement these functions with their own locking
facilities. A bare-metal platform with exclusive access can implement empty
functions. A multicore platform must coordinate across participating harts;
disabling interrupts on one hart is insufficient. Waiting while holding the
lock for a task that must enter Roc can deadlock. A platform that temporarily
releases the lock around a wait must access no shared Roc runtime state while
unlocked and reacquire before resuming such access.

The serialized runtime does not require A for reference counts or descriptor
caches. Pending-call state is frame-owned: platforms do not implement
`roc_get_task_state` or `roc_set_task_state`.

## Final linking

`output: Exe` makes Roc perform the final link with the platform's startup
objects, native libraries, linker script, and entry point. Startup initializes
memory and required CPU state, including enabling FP state before F/D code runs.

An SDK-managed build instead requests an app-only archive:

```roc
targets: {
    riscv32elf: {
        isa: "rv32imac",
        abi: Ilp32,
        code_model: Medany,
        inputs: [app],
        output: Archive,
    },
}
```

The SDK links the archive with its host, startup objects, and libraries. Platform
callbacks need not be defined when the archive is created. `linker_script` and
`entry_point` apply only to executable output; the external build supplies them
when consuming an archive. Compiler-generated support is included privately in
the Roc app object, independently of the platform's compiler runtime.

## Tests

With Zig, Python 3.10+, and both RISC-V QEMU system emulators installed:

```sh
zig build run-test-riscv-platforms
```

The suite exercises both widths, all six ABIs, both lowering strategies,
executable and externally linked archive output, ELF ABI flags, calls in both
Roc/C directions, float aggregates, register exhaustion, and execution without A.
For a subset:

```sh
python3 test/riscv/run.py --filter rv32imaf
```
