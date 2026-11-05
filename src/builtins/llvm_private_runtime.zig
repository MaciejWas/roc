//! The private runtime the LLVM backend links into every object it builds.
//!
//! LLVM's code generator lowers some operations to calls rather than
//! instructions: block copies and fills to `memcpy`, `memmove` and `memset`
//! (`bzero` for a zero fill on Darwin), a float remainder to `fmod`, rounding
//! on a CPU without rounding instructions to `floor` and its siblings, wide
//! arithmetic the target has no instruction for to compiler-rt helpers, and a
//! large stack frame on Windows to a stack probe. build.zig compiles this root
//! to bitcode once per target, for the lowest CPU that target names, and the
//! LLVM backend links it into the object it builds and gives the routines
//! `shim_symbols.llvm_private_runtime_set` names internal linkage. Every such
//! call binds to the object's own definition, so the object leaves only the
//! `roc_*` symbols for its platform to supply.

const std = @import("std");
const builtin = @import("builtin");
const compiler_rt = @import("compiler_rt");

/// The runtime must not pull in Zig's panic formatting machinery.
pub const panic = std.debug.no_panic;

comptime {
    // Referencing compiler-rt compiles every routine it exports.
    _ = @import("compiler_rt");
    // Zig's decomposed i64 arithmetic uses native u32 arithmetic. RV64I
    // legalizes that back to the i64 helpers, recursively calling them.
    // Own the native-word primitives with instruction-only bodies.
    if (builtin.cpu.arch == .riscv64) {
        @export(&muldi3, .{ .name = "roc__riscv_muldi3", .linkage = .strong, .visibility = .hidden });
        @export(&udivdi3, .{ .name = "roc__riscv_udivdi3", .linkage = .strong, .visibility = .hidden });
        @export(&umoddi3, .{ .name = "roc__riscv_umoddi3", .linkage = .strong, .visibility = .hidden });
        @export(&udivmoddi4, .{ .name = "roc__riscv_udivmoddi4", .linkage = .strong, .visibility = .hidden });
    }
    if (builtin.os.tag.isDarwin()) {
        @export(&bzero, .{ .name = "bzero", .linkage = .weak, .visibility = .hidden });
    }
}

/// Darwin targets lower a zero fill of unknown length to `bzero`, which
/// compiler-rt does not define because libSystem does.
fn bzero(dest: ?[*]u8, len: usize) callconv(.c) void {
    @disableIntrinsics();
    _ = compiler_rt.memset(dest, 0, len);
}

/// Low 64 bits of the product, using only operations RV64I implements.
fn muldi3(a: i64, b: i64) callconv(.c) i64 {
    var x: u64 = @bitCast(a);
    var y: u64 = @bitCast(b);
    var result: u64 = 0;
    while (x != 0) {
        if (x & 1 != 0) result +%= y;
        x >>= 1;
        y <<= 1;
    }
    return @bitCast(result);
}

/// Binary long division, including a carry when doubling the remainder.
/// No multiply, divide, or remainder operation may occur in these primitives.
fn udivmoddi4(a: u64, b: u64, remainder: ?*u64) callconv(.c) u64 {
    var quotient: u64 = 0;
    var rem: u64 = 0;
    for (0..64) |i| {
        const shift: u6 = @intCast(63 - i);
        const carry = rem >> 63 != 0;
        rem = (rem << 1) | ((a >> shift) & 1);
        if (carry or rem >= b) {
            rem -%= b;
            quotient |= @as(u64, 1) << shift;
        }
    }
    if (remainder) |ptr| ptr.* = rem;
    return quotient;
}

fn udivdi3(a: u64, b: u64) callconv(.c) u64 {
    return udivmoddi4(a, b, null);
}

fn umoddi3(a: u64, b: u64) callconv(.c) u64 {
    var rem: u64 = undefined;
    _ = udivmoddi4(a, b, &rem);
    return rem;
}
