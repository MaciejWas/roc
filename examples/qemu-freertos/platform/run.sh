#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 1 ]; then
    printf 'Usage: %s firmware.elf\n' "$0" >&2
    exit 2
fi
exec qemu-system-riscv64 -cpu rv64,a=false,zawrs=false -machine virt -smp 1 -m 128M -nographic -bios none -kernel "$1"
