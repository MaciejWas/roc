//! State selection for targets without native thread-local storage.

const std = @import("std");
const builtin = @import("builtin");
const host_abi = @import("host_abi.zig");

pub const native_freestanding = builtin.os.tag == .freestanding and !builtin.cpu.arch.isWasm();
pub const uses_id_table = builtin.os.tag == .linux and !builtin.link_libc;

pub fn id() usize {
    if (builtin.os.tag == .linux and !builtin.link_libc) return @intCast(std.os.linux.gettid());
    std.debug.assert(uses_id_table);
    unreachable; // only uses_id_table targets call the execution-context ID provider
}

/// Entries live with the runtime; IDs must not be recycled during that time.
/// State contents belong to their context. Only table lookup/creation is locked.
pub fn StateTable(comptime State: type) type {
    return struct {
        const Self = @This();
        const Entry = struct { id: usize, state: State = .{}, next: ?*Entry };
        entries: ?*Entry = null,
        lock: std.atomic.Mutex = .unlocked,

        pub fn getOrCreate(self: *Self, gpa: std.mem.Allocator, context_id: usize) std.mem.Allocator.Error!*State {
            while (!self.lock.tryLock()) std.atomic.spinLoopHint();
            defer self.lock.unlock();
            var current = self.entries;
            while (current) |entry| : (current = entry.next) {
                if (entry.id == context_id) return &entry.state;
            }
            const entry = try gpa.create(Entry);
            entry.* = .{ .id = context_id, .next = self.entries };
            self.entries = entry;
            return &entry.state;
        }
    };
}

test "execution-context state stays separate and repeated IDs retain state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var table: StateTable(struct { pending: ?usize = null }) = .{};
    const first = try table.getOrCreate(arena.allocator(), 0);
    first.pending = 42;
    const second = try table.getOrCreate(arena.allocator(), 1);
    try std.testing.expectEqual(@as(?usize, null), second.pending);
    second.pending = 17;
    try std.testing.expectEqual(first, try table.getOrCreate(arena.allocator(), 0));
    try std.testing.expectEqual(@as(?usize, 42), first.pending);
    try std.testing.expectEqual(@as(?usize, 17), second.pending);
}

/// Separate owners explicitly register their state and cleanup with one task root.
/// The platform stores only the opaque root pointer in its FreeRTOS TLS slot.
pub const TaskSlot = enum { callable, active_runtime, tail };
const Component = struct {
    value: *anyopaque,
    destroy: *const fn (*anyopaque, std.mem.Allocator) void,
};
const TaskState = struct {
    components: std.EnumArray(TaskSlot, ?Component) = .initFill(null),
    allocator: std.mem.Allocator,
};

pub fn taskState(comptime State: type, comptime slot: TaskSlot, comptime deinit: fn (*State, std.mem.Allocator) void) *State {
    const host = host_abi.extern_freestanding_host;
    const root: *TaskState = if (host.roc_get_task_state()) |ptr| @ptrCast(@alignCast(ptr)) else root: {
        const ops = @import("in_process_host.zig").ops();
        const gpa = @import("platform_allocator.zig").allocator(ops);
        const fresh = gpa.create(TaskState) catch ops.crash("out of memory allocating task state");
        fresh.* = .{ .allocator = gpa };
        host.roc_set_task_state(fresh);
        break :root fresh;
    };
    return componentState(State, slot, deinit, root);
}

fn componentState(comptime State: type, comptime slot: TaskSlot, comptime deinit: fn (*State, std.mem.Allocator) void, root: *TaskState) *State {
    const component = root.components.getPtr(slot);
    if (component.*) |existing| return @ptrCast(@alignCast(existing.value));
    const state = root.allocator.create(State) catch @import("in_process_host.zig").ops().crash("out of memory allocating task component");
    state.* = .{};
    component.* = .{ .value = state, .destroy = struct {
        fn destroy(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            const typed: *State = @ptrCast(@alignCast(ptr));
            deinit(typed, gpa);
            gpa.destroy(typed);
        }
    }.destroy };
    return state;
}

/// The current task calls this only after all Roc invocations and owned values
/// have been released. It must not run from an interrupt or another task.
pub fn cleanupTaskState() callconv(.c) void {
    std.debug.assert(native_freestanding);
    if (!native_freestanding) unreachable;
    const host = host_abi.extern_freestanding_host;
    host.roc_acquire_runtime_lock();
    defer host.roc_release_runtime_lock();
    const ptr = host.roc_get_task_state() orelse return;
    const root: *TaskState = @ptrCast(@alignCast(ptr));
    const gpa = root.allocator;
    for (root.components.values) |component| if (component) |owner| owner.destroy(owner.value, gpa);
    host.roc_set_task_state(null);
    gpa.destroy(root);
}

test "task-state components are separate, reused, and cleaned before recreation" {
    const State = struct {
        bytes: std.ArrayList(u8) = .empty,
        fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.bytes.deinit(gpa);
        }
    };
    var first: TaskState = .{ .allocator = std.testing.allocator };
    var second: TaskState = .{ .allocator = std.testing.allocator };
    const a = componentState(State, .tail, State.deinit, &first);
    const b = componentState(State, .tail, State.deinit, &second);
    try a.bytes.append(first.allocator, 42);
    try std.testing.expectEqual(a, componentState(State, .tail, State.deinit, &first));
    try std.testing.expectEqual(@as(usize, 0), b.bytes.items.len);
    for (first.components.values) |component| if (component) |owner| owner.destroy(owner.value, first.allocator);
    first.components = .initFill(null);
    const fresh = componentState(State, .tail, State.deinit, &first);
    try std.testing.expectEqual(@as(usize, 0), fresh.bytes.items.len);
    for (first.components.values) |component| if (component) |owner| owner.destroy(owner.value, first.allocator);
    for (second.components.values) |component| if (component) |owner| owner.destroy(owner.value, second.allocator);
}

/// Both the full and core symbol-ABI roots expose the same lifecycle entry.
pub fn exportTaskCleanup() void {
    if (native_freestanding)
        @export(&cleanupTaskState, .{ .name = @import("shim_symbols.zig").roc_cleanup_task_state });
}
