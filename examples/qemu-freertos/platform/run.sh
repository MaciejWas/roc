#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf 'Usage: %s firmware.elf [32|64]\n' "$0" >&2
    exit 2
fi
case "${2:-64}" in
    32) emulator=qemu-system-riscv32; cpu=rv32,a=false,zawrs=false ;;
    64) emulator=qemu-system-riscv64; cpu=rv64,a=false,zawrs=false ;;
    *) printf 'Register width must be 32 or 64\n' >&2; exit 2 ;;
esac
exec "$emulator" -cpu "$cpu" -machine virt -smp 1 -m 128M -nographic -bios none -kernel "$1"
