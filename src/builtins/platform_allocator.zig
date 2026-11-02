//! Zig allocator interface over the platform's existing memory callbacks.
//! No refcount header or platform-independent allocation policy is added.

const std = @import("std");
const RocOps = @import("host_abi.zig").RocOps;

/// The ops table must outlive every allocator copy and outstanding allocation.
/// In platform builds RocOps forwards directly to the roc_* linker symbols.
pub fn allocator(ops: *RocOps) std.mem.Allocator {
    return .{ .ptr = ops, .vtable = &vtable };
}

fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    const ops: *RocOps = @ptrCast(@alignCast(ctx));
    // Host allocation never returns null; failure ends Roc execution.
    return @ptrCast(ops.alloc(alignment.toByteUnits(), len));
}

fn resize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    // The host API cannot promise an in-place grow. Shrinking the usable
    // slice needs no host call: deallocation takes no length argument.
    return new_len <= memory.len;
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    const ops: *RocOps = @ptrCast(@alignCast(ctx));
    return @ptrCast(ops.realloc(memory.ptr, new_len, alignment.toByteUnits()));
}

fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, _: usize) void {
    const ops: *RocOps = @ptrCast(@alignCast(ctx));
    ops.dealloc(memory.ptr, alignment.toByteUnits());
}

const vtable = std.mem.Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

test "platform allocator preserves alignment and frees through the host" {
    var env = @import("utils.zig").TestEnv.init(std.testing.allocator);
    defer env.deinit();
    const gpa = allocator(env.getOps());
    const bytes = try gpa.alignedAlloc(u8, .@"16", 73);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(bytes.ptr) % 16);
    try std.testing.expectEqual(@as(usize, 1), env.getAllocationCount());
    try std.testing.expect(!gpa.resize(bytes, 100));
    try std.testing.expect(gpa.resize(bytes, 12));
    gpa.free(bytes[0..12]);
    try std.testing.expectEqual(@as(usize, 0), env.getAllocationCount());
}

test "platform allocator reallocates through the host and preserves contents" {
    var env = @import("utils.zig").TestEnv.init(std.testing.allocator);
    defer env.deinit();
    const gpa = allocator(env.getOps());
    var bytes = try gpa.alignedAlloc(u8, .@"16", 32);
    @memset(bytes, 0x5a);
    bytes = try gpa.realloc(bytes, 1024);
    for (bytes[0..32]) |byte| try std.testing.expectEqual(@as(u8, 0x5a), byte);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(bytes.ptr) % 16);
    try std.testing.expectEqual(@as(usize, 1), env.getAllocationCount());
    gpa.free(bytes);
    try std.testing.expectEqual(@as(usize, 0), env.getAllocationCount());
}
