//! RISC-V LP64 layout classification for little-endian, freestanding RV64IA.
//! https://riscv-non-isa.github.io/riscv-elf-psabi-doc/#_integer_calling_convention

const std = @import("std");
const invariant = @import("base").invariant;
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

/// Classify a nonzero committed layout. Call lowering handles register
/// exhaustion separately; named arguments and results share these classes.
pub fn classifyType(store: *const Store, start: layout.Idx) Class {
    if (store.targetUsize() != .u64) invariant("LP64 classification requires a 64-bit layout store", .{});
    var idx = start;
    var remaining = store.layoutCount();
    while (true) {
        if (remaining == 0) invariant("LP64 transparent union chain must be acyclic", .{});
        remaining -= 1;
        const lay = store.getLayout(idx);
        const size = store.layoutSize(lay);
        if (size == 0) invariant("ABI call lowering must omit zero-sized values before LP64 classification", .{});
        switch (lay.tag) {
            .scalar => switch (lay.getScalar().tag) {
                .int => return if (size <= 8) .scalar else classifyBySize(size),
                .opaque_ptr => return .scalar,
                // LP64 transports floating-point bits and fixed-width vectors
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
    if (size <= 8) return .integer;
    if (size <= 16) return .double_integer;
    return .memory;
}

/// Integer scalars use their signedness up to 32 bits, then sign-extension
/// to XLEN. Aggregates, pointers and floating-point bits do not use this rule.
pub fn classifyIntegerExtension(bits: u16, signedness: std.builtin.Signedness) IntegerExtension {
    switch (bits) {
        8, 16, 32 => return if (signedness == .signed) .sign_to_xlen else .zero_to_32_then_sign_to_xlen,
        64, 128 => return .none,
        else => invariant("Roc integer precision must be 8, 16, 32, 64, or 128 bits", .{}),
    }
}

pub const IntegerExtension = enum {
    none,
    sign_to_xlen,
    zero_to_32_then_sign_to_xlen,
};

const testing = std.testing;

fn testStruct(store: *Store, fields: []const layout.Idx) !layout.Idx {
    const entries = try testing.allocator.alloc(layout.StructField, fields.len);
    defer testing.allocator.free(entries);
    for (fields, entries, 0..) |field, *entry, i| {
        entry.* = .{ .index = @intCast(i), .layout = field };
    }
    return store.putStructFields(entries);
}

test "riscv64 LP64: scalars and pointers" {
    var store = try Store.init(testing.allocator, .u64);
    defer store.deinit();
    for ([_]layout.Idx{ .bool, .u8, .i8, .u16, .i16, .u32, .i32, .u64, .i64, .opaque_ptr }) |idx| {
        try testing.expectEqual(Class.scalar, classifyType(&store, idx));
    }
    try testing.expectEqual(Class.double_integer, classifyType(&store, .u128));
    try testing.expectEqual(Class.double_integer, classifyType(&store, .i128));
    const pointers = [_]layout.Idx{
        try store.insertBox(.u64),
        try store.insertBox(.zst),
        try store.insertErasedBox(),
        try store.insertPtr(.u8),
        try store.insertErasedCallable(),
    };
    for (pointers) |idx| try testing.expectEqual(Class.scalar, classifyType(&store, idx));
}

test "riscv64 LP64: software floats decimal and vectors use integer chunks" {
    var store = try Store.init(testing.allocator, .u64);
    defer store.deinit();
    try testing.expectEqual(Class.integer, classifyType(&store, .f32));
    try testing.expectEqual(Class.integer, classifyType(&store, .f64));
    try testing.expectEqual(Class.double_integer, classifyType(&store, .dec));
    for ([_]layout.Idx{ .u8x16, .i8x16, .u16x8, .i16x8, .u32x4, .i32x4, .u64x2, .i64x2 }) |idx| {
        try testing.expectEqual(Class.double_integer, classifyType(&store, idx));
    }
}

test "riscv64 LP64: aggregate size boundaries include padding" {
    var store = try Store.init(testing.allocator, .u64);
    defer store.deinit();
    const cases = [_]struct { fields: []const layout.Idx, size: u32, class: Class }{
        .{ .fields = &.{.u8}, .size = 1, .class = .integer },
        .{ .fields = &.{ .u32, .u32 }, .size = 8, .class = .integer },
        .{ .fields = &.{ .u8, .u64 }, .size = 16, .class = .double_integer },
        .{ .fields = &.{ .u8, .u8, .u8, .u8, .u8, .u8, .u8, .u8, .u8 }, .size = 9, .class = .double_integer },
        .{ .fields = &.{ .u64, .u64, .u8 }, .size = 24, .class = .memory },
        .{ .fields = &.{ .f32, .f32 }, .size = 8, .class = .integer },
        .{ .fields = &.{ .f64, .f64 }, .size = 16, .class = .double_integer },
    };
    for (cases) |case| {
        const idx = try testStruct(&store, case.fields);
        try testing.expectEqual(case.size, store.layoutSize(store.getLayout(idx)));
        try testing.expectEqual(case.class, classifyType(&store, idx));
    }
    const padded = try store.putNominalStructFields(&.{.{ .index = 0, .layout = .u64, .is_padding = true }});
    try testing.expectEqual(Class.integer, classifyType(&store, padded));
    try testing.expectEqual(Class.memory, classifyType(&store, .str));
    try testing.expectEqual(Class.memory, classifyType(&store, try store.insertLayout(layout.Layout.list(.u8))));
    try testing.expectEqual(Class.memory, classifyType(&store, try store.insertLayout(layout.Layout.list(.zst))));
}

test "riscv64 LP64: transparent unions preserve payload classification" {
    var store = try Store.init(testing.allocator, .u64);
    defer store.deinit();
    for ([_]layout.Idx{ .u32, .f32, .i128, .str }) |payload| {
        const wrapped = try store.putTagUnion(&.{payload});
        const nested = try store.putTagUnion(&.{wrapped});
        try testing.expectEqual(classifyType(&store, payload), classifyType(&store, nested));
    }
    const tagged = try store.putTagUnion(&.{ .u64, .u8 });
    try testing.expectEqual(Class.double_integer, classifyType(&store, tagged));
}

test "riscv64 LP64: integer widening includes unsigned 32-bit sign extension" {
    for ([_]u16{ 8, 16, 32 }) |bits| {
        try testing.expectEqual(IntegerExtension.sign_to_xlen, classifyIntegerExtension(bits, .signed));
        try testing.expectEqual(IntegerExtension.zero_to_32_then_sign_to_xlen, classifyIntegerExtension(bits, .unsigned));
    }
    for ([_]u16{ 64, 128 }) |bits| {
        try testing.expectEqual(IntegerExtension.none, classifyIntegerExtension(bits, .signed));
        try testing.expectEqual(IntegerExtension.none, classifyIntegerExtension(bits, .unsigned));
    }
}
