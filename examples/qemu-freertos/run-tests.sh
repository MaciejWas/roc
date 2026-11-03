#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
platform_dir="$script_dir/platform"
app="$script_dir/app/main.roc"

build_platform() {
    local bits="$1"
    (cd "$platform_dir" && zig build --prefix . -Driscv-bits="$bits")
}

run_profile() {
    local profile="$1"
    local bits="$2"
    local cores="$3"
    local atomics="$4"
    local target emulator cpu firmware

    case "$bits" in
        32) target=riscv32elf; emulator=qemu-system-riscv32; cpu=rv32 ;;
        64) target=riscv64elf; emulator=qemu-system-riscv64; cpu=rv64 ;;
        *) printf 'Profile %s has an unsupported register width: %s\n' "$profile" "$bits" >&2; exit 2 ;;
    esac
    case "$cores" in
        1|2) ;;
        *) printf 'Profile %s has an unsupported core count: %s\n' "$profile" "$cores" >&2; exit 2 ;;
    esac
    case "$atomics" in
        no-a) cpu+=",a=false,zawrs=false" ;;
        with-a) cpu+=",a=true,zawrs=false" ;;
        *) printf 'Profile %s has an unsupported atomic-extension setting: %s\n' "$profile" "$atomics" >&2; exit 2 ;;
    esac

    firmware="$script_dir/app/boot-$profile.elf"
    zig-out/bin/roc build "$app" --target="$target" --output="$firmware"
    "$emulator" -cpu "$cpu" -machine virt -smp "$cores" -m 128M -nographic -bios none -kernel "$firmware" </dev/null
}

cd "$repo_root"
zig build roc

platform_32_built=false
platform_64_built=false
while read -r profile bits cores atomics extra <&3; do
    if [ -z "${profile:-}" ] || [[ "$profile" == \#* ]]; then
        continue
    fi
    if [ -n "${extra:-}" ] || [ -z "${bits:-}" ] || [ -z "${cores:-}" ] || [ -z "${atomics:-}" ]; then
        printf 'Expected exactly four fields: profile bits cores atomics\n' >&2
        exit 2
    fi

    case "$bits" in
        32) if ! "$platform_32_built"; then build_platform 32; platform_32_built=true; fi ;;
        64) if ! "$platform_64_built"; then build_platform 64; platform_64_built=true; fi ;;
        *) printf 'Profile %s has an unsupported register width: %s\n' "$profile" "$bits" >&2; exit 2 ;;
    esac
    printf '\n== %s ==\n' "$profile"
    run_profile "$profile" "$bits" "$cores" "$atomics"
done 3<<'PROFILES'
# profile                     bits  cores  atomics
rv32-single-core-no-a          32    1      no-a
rv32-multi-core-with-a         32    2      with-a
rv64-single-core-no-a          64    1      no-a
rv64-multi-core-with-a         64    2      with-a
PROFILES
