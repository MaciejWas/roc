//! RISC-V data-only ELF objects. No instruction-set code generator is involved.
const std = @import("std");
const facade = @import("../ObjectWriter.zig");
const Allocator = std.mem.Allocator;
fn put(a: Allocator, out: *std.ArrayList(u8), comptime T: type, value: anytype) (Allocator.Error || error{UnsupportedTarget})!void {
    const v = std.math.cast(T, value) orelse return error.UnsupportedTarget;
    try out.appendSlice(a, &std.mem.toBytes(std.mem.nativeToLittle(T, v)));
}
fn pad(a: Allocator, out: *std.ArrayList(u8), alignment: usize) (Allocator.Error || error{UnsupportedTarget})!void {
    try out.appendNTimes(a, 0, std.mem.alignForward(usize, out.items.len, alignment) - out.items.len);
}
const Section = struct { name: u32, kind: u32, flags: u64, offset: u64, size: u64, link: u32 = 0, info: u32 = 0, alignment: u64 = 1, entry: u64 = 0 };
pub fn emit(a: Allocator, bits: u16, flags: u32, data: []const u8, bss: u64, alignment: u32, symbols: []const facade.Symbol, relocations: []const facade.IndexedDataRelocation, out: *std.ArrayList(u8)) (Allocator.Error || error{UnsupportedTarget})!void {
    std.debug.assert(bits == 32 or bits == 64);
    const wide = bits == 64;
    const word: usize = bits / 8;
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(a);
    try names.append(a, 0);
    var sym: std.ArrayList(u8) = .empty;
    defer sym.deinit(a);
    try sym.appendNTimes(a, 0, if (wide) 24 else 16);
    const indices = try a.alloc(u32, symbols.len);
    defer a.free(indices);
    var count: u32 = 1;
    var first_global: u32 = 1;
    for ([_]bool{ false, true }) |global| {
        if (global) first_global = count;
        for (symbols, 0..) |s, i| {
            if ((s.is_global or s.is_external) != global) continue;
            indices[i] = count;
            count += 1;
            const name = names.items.len;
            try names.appendSlice(a, s.name);
            try names.append(a, 0);
            std.debug.assert(s.is_external or s.section != .text);
            const section: u16 = if (s.is_external) 0 else switch (s.section) {
                .rodata => 1,
                .zero_fill => 2,
                .undef => 0,
                .text => unreachable,
            };
            const info: u8 = (if (global) @as(u8, 16) else 0) | (if (s.is_function) @as(u8, 2) else 1);
            try put(a, &sym, u32, name);
            if (wide) {
                try put(a, &sym, u8, info);
                try put(a, &sym, u8, if (s.is_hidden) @as(u8, 2) else 0);
                try put(a, &sym, u16, section);
                try put(a, &sym, u64, s.offset);
                try put(a, &sym, u64, s.size);
            } else {
                try put(a, &sym, u32, s.offset);
                try put(a, &sym, u32, s.size);
                try put(a, &sym, u8, info);
                try put(a, &sym, u8, if (s.is_hidden) @as(u8, 2) else 0);
                try put(a, &sym, u16, section);
            }
        }
    }
    var rela: std.ArrayList(u8) = .empty;
    defer rela.deinit(a);
    for (relocations) |r| {
        const index = indices[@backingInt(r.symbol)];
        if (wide) {
            try put(a, &rela, u64, r.offset);
            try put(a, &rela, u64, (@as(u64, index) << 32) | 2); // R_RISCV_64
            try put(a, &rela, i64, r.addend);
        } else {
            try put(a, &rela, u32, r.offset);
            try put(a, &rela, u32, (index << 8) | 1); // R_RISCV_32
            try put(a, &rela, i32, r.addend);
        }
    }
    const header_size: u16 = if (wide) 64 else 52;
    const sh_size: u16 = if (wide) 64 else 40;
    const shnames = "\x00.rodata\x00.bss\x00.symtab\x00.strtab\x00.shstrtab\x00.rela.rodata\x00";
    try out.appendNTimes(a, 0, header_size);
    try pad(a, out, alignment);
    const data_offset = out.items.len;
    try out.appendSlice(a, data);
    const bss_offset = out.items.len;
    try pad(a, out, word);
    const sym_offset = out.items.len;
    try out.appendSlice(a, sym.items);
    const str_offset = out.items.len;
    try out.appendSlice(a, names.items);
    const shstr_offset = out.items.len;
    try out.appendSlice(a, shnames);
    try pad(a, out, word);
    const rel_offset = out.items.len;
    try out.appendSlice(a, rela.items);
    try pad(a, out, word);
    const sh_offset = out.items.len;
    const sections = [_]Section{
        .{ .name = 0, .kind = 0, .flags = 0, .offset = 0, .size = 0, .alignment = 0 },
        .{ .name = 1, .kind = 1, .flags = 2, .offset = data_offset, .size = data.len, .alignment = alignment },
        .{ .name = 9, .kind = 8, .flags = 3, .offset = bss_offset, .size = bss, .alignment = alignment },
        .{ .name = 14, .kind = 2, .flags = 0, .offset = sym_offset, .size = sym.items.len, .link = 4, .info = first_global, .alignment = word, .entry = if (wide) 24 else 16 },
        .{ .name = 22, .kind = 3, .flags = 0, .offset = str_offset, .size = names.items.len },
        .{ .name = 30, .kind = 3, .flags = 0, .offset = shstr_offset, .size = shnames.len },
        .{ .name = 40, .kind = 4, .flags = 0, .offset = rel_offset, .size = rela.items.len, .link = 3, .info = 1, .alignment = word, .entry = if (wide) 24 else 12 },
    };
    for (sections) |s| {
        try put(a, out, u32, s.name);
        try put(a, out, u32, s.kind);
        if (wide) {
            try put(a, out, u64, s.flags);
            try put(a, out, u64, 0);
            try put(a, out, u64, s.offset);
            try put(a, out, u64, s.size);
        } else {
            try put(a, out, u32, s.flags);
            try put(a, out, u32, 0);
            try put(a, out, u32, s.offset);
            try put(a, out, u32, s.size);
        }
        try put(a, out, u32, s.link);
        try put(a, out, u32, s.info);
        if (wide) {
            try put(a, out, u64, s.alignment);
            try put(a, out, u64, s.entry);
        } else {
            try put(a, out, u32, s.alignment);
            try put(a, out, u32, s.entry);
        }
    }
    var header: std.ArrayList(u8) = .empty;
    defer header.deinit(a);
    try header.appendSlice(a, &.{ 0x7f, 'E', 'L', 'F', if (wide) 2 else 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try put(a, &header, u16, 1);
    try put(a, &header, u16, 243);
    try put(a, &header, u32, 1);
    if (wide) {
        try put(a, &header, u64, 0);
        try put(a, &header, u64, 0);
        try put(a, &header, u64, sh_offset);
    } else {
        try put(a, &header, u32, 0);
        try put(a, &header, u32, 0);
        try put(a, &header, u32, sh_offset);
    }
    try put(a, &header, u32, flags);
    try put(a, &header, u16, header_size);
    try put(a, &header, u16, 0);
    try put(a, &header, u16, 0);
    try put(a, &header, u16, sh_size);
    try put(a, &header, u16, sections.len);
    try put(a, &header, u16, 5);
    @memcpy(out.items[0..header_size], header.items);
}
