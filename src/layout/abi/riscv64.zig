//! RISC-V LP64 ABI skeleton for little-endian, freestanding RV64I.
//! https://riscv-non-isa.github.io/riscv-elf-psabi-doc/#_integer_calling_convention

const std = @import("std");
const layout = @import("../layout.zig");
const Store = @import("../store.zig").Store;

pub const xlen_bits: u16 = 64;
pub const gp_argument_registers: u8 = 8;
pub const gp_return_registers: u8 = 2;
pub const stack_alignment: u8 = 16;

pub const Class = enum {
    scalar,
    integer,
    double_integer,
    memory,
};

pub fn classifyType(store: *const Store, idx: layout.Idx) Class {
    _ = store;
    _ = idx;
    
    // TODO: Consume committed layouts, excluding zero-sized values.
    // TODO: Classify integer/pointer/software-float scalars and aggregates.
    // TODO: Cover transparent unions and values wider than two XLEN words.
    @panic("TODO: implement RISC-V LP64 layout classification");
}

pub fn classifyIntegerExtension(bits: u16, signedness: std.builtin.Signedness) IntegerExtension {
    _ = bits;
    _ = signedness;
    // TODO: Extend by signedness to 32 bits, then sign-extend to XLEN.
    // TODO: Cover U32 explicitly; zero extension to XLEN is incorrect.
    @panic("TODO: implement RISC-V LP64 integer widening");
}

pub const IntegerExtension = enum {
    none,
    sign_to_xlen,
    zero_to_32_then_sign_to_xlen,
};
