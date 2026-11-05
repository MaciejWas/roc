//! Native freestanding runtime synchronization contract.
const builtin = @import("builtin");

/// Platform entry and host-side value operations hold the platform runtime
/// lock. This property is independent of the CPU's atomic instructions.
pub const native_freestanding = builtin.os.tag == .freestanding and !builtin.cpu.arch.isWasm();
