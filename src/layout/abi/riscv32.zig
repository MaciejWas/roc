//! RISC-V ILP32 layout classification for little-endian, freestanding RV32I.
//! https://riscv-non-isa.github.io/riscv-elf-psabi-doc/#_integer_calling_convention

const std = @import("std");
const invariant = @import("base").invariant;
const layout = @import("../layout.zig");
const Store = @import("../store.zig").Store;

pub const xlen_bits: u16 = 32;
pub const gp_argument_registers: u8 = 8;
pub const gp_return_registers: u8 = 2;
pub const stack_alignment: u8 = 16;

pub const Class = enum {
    scalar,
    integer,
    double_integer,
    memory,
};

/// Classify a nonzero committed layout. Call lowering handles register
/// exhaustion separately; named arguments and results share these classes.
pub fn classifyType(store: *const Store, start: layout.Idx) Class {
    if (store.targetUsize() != .u32) invariant("ILP32 classification requires a 32-bit layout store", .{});
    var idx = start;
    var remaining = store.layoutCount();
    while (true) {
        if (remaining == 0) invariant("ILP32 transparent union chain must be acyclic", .{});
        remaining -= 1;
        const lay = store.getLayout(idx);
        const size = store.layoutSize(lay);
        if (size == 0) invariant("ABI call lowering must omit zero-sized values before ILP32 classification", .{});
        switch (lay.tag) {
            .scalar => switch (lay.getScalar().tag) {
                .int => return if (size <= 4) .scalar else classifyBySize(size),
                .opaque_ptr => return .scalar,
                // ILP32 transports floating-point bits and fixed-width vectors
                // using integer chunks, just like aggregates. Dec also uses
                // integer chunks regardless of its scalar layout tag.
                .frac, .vector, .str => return classifyBySize(size),
            },
            .box, .box_of_zst, .ptr, .dynamic, .erased_callable => return .scalar,
            .tag_union => {
                const info = store.getTagUnionInfo(lay);
                if (info.variants.len == 1 and info.data.discriminant_size == 0) {
                    idx = info.variants.get(0).payload_layout;
                    continue;
                }
                // Glue exposes payload-free unions as integer enums. Check
                // the committed variant layouts, not the union's byte shape.
                var has_payload = false;
                for (0..info.variants.len) |i| {
                    const payload = store.getLayout(info.variants.get(i).payload_layout);
                    if (store.layoutSize(payload) != 0) {
                        has_payload = true;
                        break;
                    }
                }
                if (!has_payload) return .scalar;
                return classifyBySize(size);
            },
            .list, .list_of_zst, .struct_, .closure => return classifyBySize(size),
            .zst, .hole => unreachable, // the nonzero-size invariant above excludes these layouts
        }
    }
}

fn classifyBySize(size: u32) Class {
    if (size <= 4) return .integer;
    if (size <= 8) return .double_integer;
    return .memory;
}

/// Integers narrower than XLEN extend according to signedness.
pub fn classifyIntegerExtension(bits: u16, signedness: std.builtin.Signedness) IntegerExtension {
    switch (bits) {
        8, 16 => return if (signedness == .signed) .sign_to_xlen else .zero_to_xlen,
        32, 64, 128 => return .none,
        else => invariant("Roc integer precision must be 8, 16, 32, 64, or 128 bits", .{}),
    }
}

pub const IntegerExtension = enum {
    none,
    sign_to_xlen,
    zero_to_xlen,
};

test "riscv32 ILP32 width boundaries and indirect values" {
    const testing = std.testing;
    var store = try Store.init(testing.allocator, .u32);
    defer store.deinit();
    for ([_]layout.Idx{ .bool, .u8, .i16, .u32, .i32, .opaque_ptr }) |idx| {
        try testing.expectEqual(Class.scalar, classifyType(&store, idx));
    }
    try testing.expectEqual(Class.integer, classifyType(&store, .f32));
    for ([_]layout.Idx{ .i64, .u64, .f64 }) |idx| {
        try testing.expectEqual(Class.double_integer, classifyType(&store, idx));
    }
    for ([_]layout.Idx{ .i128, .u128, .dec, .str, .u8x16 }) |idx| {
        try testing.expectEqual(Class.memory, classifyType(&store, idx));
    }
    const wrapped = try store.putTagUnion(&.{.u64});
    try testing.expectEqual(Class.double_integer, classifyType(&store, wrapped));
    try testing.expectEqual(IntegerExtension.none, classifyIntegerExtension(32, .unsigned));
    try testing.expectEqual(IntegerExtension.sign_to_xlen, classifyIntegerExtension(16, .signed));
    try testing.expectEqual(IntegerExtension.zero_to_xlen, classifyIntegerExtension(16, .unsigned));
}
