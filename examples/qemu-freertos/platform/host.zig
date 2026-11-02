//! A single-task FreeRTOS platform for QEMU's RISC-V virt board.
const std = @import("std");
const RocStr = @import("roc_str_view").RocStr;

pub const panic = std.debug.FullPanic(panicImpl);
fn panicImpl(message: []const u8, _: ?usize) noreturn {
    uartWrite("Zig panic: ");
    uartWrite(message);
    finish(false);
}

extern fn roc_main() callconv(.c) void;
extern fn roc_cleanup_task_state() callconv(.c) void;
extern fn pvPortMalloc(usize) ?*anyopaque;
extern fn vPortFree(?*anyopaque) void;
extern fn vTaskStartScheduler() void;
extern fn roc_freertos_create_mutex() ?*anyopaque;
extern fn roc_freertos_take_mutex(*anyopaque) c_int;
extern fn roc_freertos_give_mutex(*anyopaque) c_int;
extern fn roc_freertos_get_state() ?*anyopaque;
extern fn roc_freertos_set_state(?*anyopaque) void;
extern fn roc_freertos_create_task(*const fn (?*anyopaque) callconv(.c) void) c_int;
extern fn roc_freertos_delete_task() void;

var runtime_mutex: *anyopaque = undefined;
var task_finished = false;

fn uartWrite(bytes: []const u8) void {
    const tx: *volatile u8 = @ptrFromInt(0x10000000);
    const status: *volatile u8 = @ptrFromInt(0x10000005);
    for (bytes) |byte| {
        while (status.* & 0x20 == 0) {}
        tx.* = byte;
    }
}

fn finish(success: bool) noreturn {
    // QEMU virt's SiFive test device exits the emulator with a process status.
    const test_device: *volatile u32 = @ptrFromInt(0x100000);
    test_device.* = if (success) 0x5555 else 0x13333;
    while (true) asm volatile ("wfi");
}

fn fail(message: []const u8) noreturn {
    uartWrite(message);
    uartWrite("\n");
    finish(false);
}

pub export fn firmware_main() callconv(.c) noreturn {
    runtime_mutex = roc_freertos_create_mutex() orelse fail("cannot create runtime mutex");
    if (roc_freertos_create_task(rocTask) != 1) fail("cannot create Roc task");
    vTaskStartScheduler();
    fail("scheduler returned");
}

fn rocTask(_: ?*anyopaque) callconv(.c) void {
    roc_main();
    roc_cleanup_task_state();
    task_finished = true;
    roc_freertos_delete_task();
    unreachable;
}

pub export fn vApplicationIdleHook() callconv(.c) void {
    // Only the harness exits QEMU. The Roc task itself returns and is deleted.
    if (task_finished) finish(true);
}
pub export fn vApplicationMallocFailedHook() callconv(.c) noreturn {
    fail("FreeRTOS heap exhausted");
}
pub export fn vApplicationStackOverflowHook(_: ?*anyopaque, _: [*:0]u8) callconv(.c) noreturn {
    fail("FreeRTOS task stack overflow");
}
pub export fn roc_freertos_assert() callconv(.c) noreturn {
    fail("FreeRTOS assertion failed");
}

pub export fn roc_get_task_state() callconv(.c) ?*anyopaque {
    return roc_freertos_get_state();
}
pub export fn roc_set_task_state(state: ?*anyopaque) callconv(.c) void {
    roc_freertos_set_state(state);
}
pub export fn roc_acquire_runtime_lock() callconv(.c) void {
    if (roc_freertos_take_mutex(runtime_mutex) != 1) fail("cannot acquire runtime mutex");
}
pub export fn roc_release_runtime_lock() callconv(.c) void {
    if (roc_freertos_give_mutex(runtime_mutex) != 1) fail("cannot release runtime mutex");
}

const Allocation = extern struct { base: *anyopaque, len: usize };
pub export fn roc_alloc(len: usize, alignment: usize) callconv(.c) *anyopaque {
    const actual_alignment = @max(alignment, @alignOf(Allocation));
    const with_header = std.math.add(usize, @max(len, 1), @sizeOf(Allocation)) catch fail("allocation size overflow");
    const total = std.math.add(usize, with_header, actual_alignment - 1) catch fail("allocation alignment overflow");
    const base = pvPortMalloc(total) orelse fail("Roc heap exhausted");
    const address = std.mem.alignForward(usize, @intFromPtr(base) + @sizeOf(Allocation), actual_alignment);
    const header: *Allocation = @ptrFromInt(address - @sizeOf(Allocation));
    header.* = .{ .base = base, .len = len };
    return @ptrFromInt(address);
}
pub export fn roc_dealloc(ptr: *anyopaque, _: usize) callconv(.c) void {
    const header: *const Allocation = @ptrFromInt(@intFromPtr(ptr) - @sizeOf(Allocation));
    vPortFree(header.base);
}
pub export fn roc_realloc(ptr: *anyopaque, new_len: usize, alignment: usize) callconv(.c) *anyopaque {
    const header: *const Allocation = @ptrFromInt(@intFromPtr(ptr) - @sizeOf(Allocation));
    const result = roc_alloc(new_len, alignment);
    const source: [*]const u8 = @ptrCast(ptr);
    const destination: [*]u8 = @ptrCast(result);
    const copy_len = @min(header.len, new_len);
    @memcpy(destination[0..copy_len], source[0..copy_len]);
    roc_dealloc(ptr, alignment);
    return result;
}

pub export fn roc_uart_write(value: RocStr) callconv(.c) void {
    uartWrite(value.asSlice());
}
pub export fn roc_dbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    uartWrite(bytes[0..len]);
}
pub export fn roc_expect_failed(bytes: [*]const u8, len: usize) callconv(.c) noreturn {
    fail(bytes[0..len]);
}
pub export fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) noreturn {
    fail(bytes[0..len]);
}
