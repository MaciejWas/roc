//! Resolved platform-owned RISC-V instruction and host ABI contract.
const std = @import("std");

pub const Abi = enum {
    ilp32,
    ilp32f,
    ilp32d,
    lp64,
    lp64f,
    lp64d,

    pub fn fromTag(name: []const u8) ?Abi {
        inline for (std.meta.tags(Abi)) |abi| {
            if (std.ascii.eqlIgnoreCase(name, @tagName(abi))) return abi;
        }
        return null;
    }

    pub fn bits(self: Abi) u16 {
        return switch (self) {
            .ilp32, .ilp32f, .ilp32d => 32,
            .lp64, .lp64f, .lp64d => 64,
        };
    }

    pub fn floatBits(self: Abi) u16 {
        return switch (self) {
            .ilp32, .lp64 => 0,
            .ilp32f, .lp64f => 32,
            .ilp32d, .lp64d => 64,
        };
    }
};

pub const CodeModel = enum {
    medlow,
    medany,

    pub fn fromTag(name: []const u8) ?CodeModel {
        if (std.mem.eql(u8, name, "Medlow")) return .medlow;
        if (std.mem.eql(u8, name, "Medany")) return .medany;
        return null;
    }
};

pub const Config = struct {
    features: std.Target.Cpu.Feature.Set,
    abi: Abi,
    code_model: CodeModel = .medany,

    pub fn baseline(bits: u16) Config {
        return .{
            .features = std.Target.riscv.featureSet(&.{ if (bits == 32) .@"32bit" else .@"64bit", .i }),
            .abi = if (bits == 32) .ilp32 else .lp64,
        };
    }

    pub const ValidationError = error{ InvalidIsa, WidthMismatch, InvalidAbiFeatures };

    /// Compact unversioned ISA spelling with a base and single-letter extensions.
    pub fn parseIsa(bits: u16, text: []const u8) ValidationError!std.Target.Cpu.Feature.Set {
        if (text.len < 5 or !std.mem.startsWith(u8, text, "rv")) return error.InvalidIsa;
        const width: u16 = if (std.mem.startsWith(u8, text, "rv32")) 32 else if (std.mem.startsWith(u8, text, "rv64")) 64 else return error.InvalidIsa;
        if (width != bits) return error.WidthMismatch;
        if (text[4] != 'i' and text[4] != 'g') return error.InvalidIsa;
        var result = baseline(bits).features;
        for (text[4..], 0..) |letter, index| {
            if (letter == 'g') {
                if (index != 0) return error.InvalidIsa;
                result.addFeatureSet(std.Target.riscv.featureSet(&.{ .m, .a, .f, .d, .zicsr, .zifencei }));
                continue;
            }
            const feature: std.Target.riscv.Feature = switch (letter) {
                'i' => if (index == 0) .i else return error.InvalidIsa,
                'm' => .m,
                'a' => .a,
                'f' => .f,
                'd' => .d,
                'c' => .c,
                'b' => .b,
                'v' => .v,
                'h' => .h,
                'q' => .q,
                else => return error.InvalidIsa,
            };
            if (feature != .i and result.isEnabled(@backingInt(feature))) return error.InvalidIsa;
            result.addFeature(@backingInt(feature));
        }

        if (std.Target.riscv.featureSetHas(result, .d) and !std.Target.riscv.featureSetHas(result, .f)) return error.InvalidIsa;
        const arch: std.Target.Cpu.Arch = if (bits == 32) .riscv32 else .riscv64;
        result.populateDependencies(arch.allFeaturesList());
        return result;
    }

    pub fn validate(self: Config, bits: u16) ValidationError!void {
        if (self.abi.bits() != bits) return error.WidthMismatch;
        if (self.abi.floatBits() >= 32 and !std.Target.riscv.featureSetHas(self.features, .f)) return error.InvalidAbiFeatures;
        if (self.abi.floatBits() == 64 and !std.Target.riscv.featureSetHas(self.features, .d)) return error.InvalidAbiFeatures;
    }

    pub fn targetQuery(self: Config) std.Target.Query {
        const arch: std.Target.Cpu.Arch = if (self.abi.bits() == 32) .riscv32 else .riscv64;
        var removed = std.Target.Cpu.Feature.Set.empty;
        for (arch.allFeaturesList(), 0..) |_, index| {
            if (!self.features.isEnabled(@intCast(index))) removed.addFeature(@intCast(index));
        }
        return .{
            .cpu_arch = arch,
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_model = .{ .explicit = if (arch == .riscv32) &std.Target.riscv.cpu.generic_rv32 else &std.Target.riscv.cpu.generic_rv64 },
            .cpu_features_add = self.features,
            .cpu_features_sub = removed,
        };
    }

    /// RISC-V ELF ABI flags shared by code and standalone data objects.
    pub fn elfFlags(self: Config) u32 {
        return @as(u32, if (std.Target.riscv.featureSetHas(self.features, .c) or std.Target.riscv.featureSetHas(self.features, .zca)) 1 else 0) |
            @as(u32, switch (self.abi.floatBits()) {
                32 => 2,
                64 => 4,
                else => 0,
            });
    }

    /// Stable bytes for emission/cache identities, independent of struct padding.
    pub fn updateHash(self: Config, hasher: anytype) void {
        hasher.update("riscv-platform-v1");
        hasher.update(@tagName(self.abi));
        hasher.update(@tagName(self.code_model));
        for (std.Target.Cpu.Arch.riscv64.allFeaturesList(), 0..) |feature, index| {
            if (self.features.isEnabled(@intCast(index))) {
                hasher.update(feature.name);
                hasher.update(&.{0});
            }
        }
    }
};

test "RISC-V platform ISA and ABI are independent validated contracts" {
    const t = std.testing;
    var config = Config.baseline(32);
    config.features = try Config.parseIsa(32, "rv32imc");
    try config.validate(32);
    try t.expect(!std.Target.riscv.featureSetHas(config.features, .a));
    config.features = try Config.parseIsa(32, "rv32imac");
    try t.expect(std.Target.riscv.featureSetHas(config.features, .a));
    config.abi = .ilp32d;
    try t.expectError(error.InvalidAbiFeatures, config.validate(32));
    config.features = try Config.parseIsa(32, "rv32gc");
    try config.validate(32);
    try t.expectError(error.WidthMismatch, config.validate(64));
    try t.expectError(error.WidthMismatch, Config.parseIsa(32, "rv64imac"));
    for ([_][]const u8{ "rv32e", "rv32imacgarbage", "rv32iaa", "rv32i_zicsr", "rv32id" }) |text| {
        try t.expectError(error.InvalidIsa, Config.parseIsa(32, text));
    }
}
