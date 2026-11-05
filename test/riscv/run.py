#!/usr/bin/env python3
"""Execute bare-metal RISC-V platform/ABI tests with Zig and QEMU."""
import argparse
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

PROFILES = [
    (32, "rv32i", "Ilp32"),
    (32, "rv32imc", "Ilp32"),
    (32, "rv32imac", "Ilp32"),
    (32, "rv32imafc", "Ilp32f"),
    (32, "rv32imafdc", "Ilp32d"),
    (32, "rv32imafdc", "Ilp32"),
    (64, "rv64i", "Lp64"),
    (64, "rv64imac", "Lp64"),
    (64, "rv64imafc", "Lp64f"),
    (64, "rv64gc", "Lp64d"),
    (64, "rv64gc", "Lp64"),
]


def run(command, cwd, timeout=120):
    result = subprocess.run([str(arg) for arg in command], cwd=cwd,
                            capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise AssertionError(f"{' '.join(map(str, command))}\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", type=Path, default=Path(__file__).resolve().parents[2] / "zig-out/bin/roc")
    parser.add_argument("--filter", default="", help="Run ISA names containing this string")
    args = parser.parse_args()
    roc = args.roc.resolve()
    fixture = Path(__file__).resolve().parent
    count = 0
    with tempfile.TemporaryDirectory(prefix="roc-riscv-platforms-") as directory:
        root = Path(directory)
        shutil.copytree(fixture / "platform", root / "platform")
        shutil.copyfile(fixture / "main.roc", root / "main.roc")
        template = (root / "platform/main.roc").read_text()
        before, rest = template.split("    targets: {", 1)
        _, after = rest.split("\n    }\n", 1)
        for bits, isa, abi in PROFILES:
            if args.filter not in isa:
                continue
            target = f"riscv{bits}elf"
            inputs = root / "platform/targets" / target
            inputs.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(fixture / "platform/linker.ld", inputs / "linker.ld")
            extensions = list(isa[4:])
            if "g" in extensions:
                extensions.remove("g")
                extensions.extend(["i", "m", "a", "f", "d", "zicsr", "zifencei"])
            cpu = f"generic_rv{bits}" + "".join(f"+{ext}" for ext in extensions)
            cc = ["zig", "cc", "-target", f"riscv{bits}-freestanding-none", f"-mcpu={cpu}",
                  f"-mabi={abi.lower()}", "-mcmodel=medany", "-ffreestanding",
                  "-fno-stack-protector", "-fno-builtin", "-O2"]
            for source in ["host.c", "startup.S"]:
                run([*cc, "-c", root / "platform" / source, "-o", inputs / (Path(source).stem + ".o")], root)
            run(["zig", "ar", "rcs", inputs / "libhost.a", inputs / "host.o"], root)
            for specialized in ["yes", "no"]:
                for output in ["Exe", "Archive"]:
                    declared_inputs = '[app]' if output == 'Archive' else '["startup.o", app, "libhost.a"]'
                    fields = (f'isa: "{isa}", abi: {abi}, code_model: Medany, '
                              f'inputs: {declared_inputs}, output: {output}')
                    if output == "Exe":
                        fields += ', linker_script: "linker.ld", entry_point: "_start"'
                    (root / "platform/main.roc").write_text(before + "    targets: {\n"
                        + f"        {target}: {{ {fields} }},\n    }}\n" + after)
                    artifact = root / ("app.a" if output == "Archive" else "firmware.elf")
                    command = [roc, "build", root / "main.roc", f"--target={target}",
                               f"--specialize={specialized}", f"--output={artifact}"]
                    # Use the cache while changing only the platform settings:
                    # this also exercises checked-module cache invalidation.
                    run(command, root)
                    firmware = root / "firmware.elf"
                    if output == "Archive":
                        run(["zig", "ld.lld", "-o", firmware, "-static", "--gc-sections", "-T", inputs / "linker.ld",
                             inputs / "startup.o", inputs / "host.o", artifact], root)
                    data = firmware.read_bytes()
                    flags = struct.unpack_from("<I", data, 36 if bits == 32 else 48)[0]
                    expected_float = 4 if abi.endswith("d") else 2 if abi.endswith("f") else 0
                    assert flags & 6 == expected_float, (isa, abi, flags)
                    assert bool(flags & 1) == ("c" in isa[4:]), (isa, flags)
                    cpu = f"rv{bits}" if "a" in extensions else f"rv{bits},a=false,zawrs=false"
                    text = run([f"qemu-system-riscv{bits}", "-machine", "virt", "-cpu", cpu,
                                "-nographic", "-bios", "none", "-kernel", firmware], root, 15)
                    assert text == "riscv platform 8 passed\n", repr(text)
                    count += 1
                    print(f"PASS {isa}/{abi} specialize={specialized} output={output}", flush=True)
    assert count, "no matching ISA profiles"
    print(f"{count} firmware executions passed")


if __name__ == "__main__":
    main()
