# LLVM compiler-rt integer builtins

Unmodified sources from LLVM tag `llvmorg-22.1.8`:
https://github.com/llvm/llvm-project/tree/llvmorg-22.1.8/compiler-rt

Licensed under Apache-2.0 WITH LLVM-exception; see LICENSE.TXT.

RISC-V private runtimes use these integer builtins, including LLVM's native
assembly multiply for each XLEN. The build composes their bitcode and assembly
with the common runtime before embedding it. Roc does not replace arithmetic
implementations or repair runtime aliases during application compilation.

The selected source files implement signed/unsigned 32- and 64-bit division and
remainder, combined quotient/remainder, and 64- and 128-bit multiplication.
RV32 uses the generic 64-bit multiply and the RV32 assembly 32-bit multiply;
RV64 uses the RV64 assembly 64-bit multiply. Sources remain identical to upstream.
