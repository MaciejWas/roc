platform ""
    requires { main! : () => {} }
    exposes [Uart]
    packages {}
    provides { "roc_main": main_for_host!, "roc_f32": id_f32, "roc_f64": id_f64, "roc_pair": id_pair, "roc_mixed": id_mixed, "roc_overflow": overflow }
    hosted { "roc_uart_write": Uart.write!, "roc_host_pair": Host.pair!, "roc_host_mixed": Host.mixed! }
    targets: {
        riscv32elf: { inputs: ["startup.o", app, "libhost.a"], output: Exe, linker_script: "linker.ld", entry_point: "_start" },
        riscv64elf: { inputs: ["startup.o", app, "libhost.a"], output: Exe, linker_script: "linker.ld", entry_point: "_start" },
    }

import Uart
import Host

main_for_host! : () => {}
main_for_host! = || {
    pair = Host.pair!({ x: 1.25, y: 2.5 })
    mixed = Host.mixed!({ f: 1.25, i: 7 })
    if pair.x != 1.25 or pair.y != 2.5 or mixed.f != 1.25 or mixed.i != 7 {
        crash "host ABI mismatch"
    }
    main!()
}

id_f32 : F32 -> F32
id_f32 = |value| value

id_f64 : F64 -> F64
id_f64 = |value| value

id_pair : { x : F64, y : F64 } -> { x : F64, y : F64 }
id_pair = |value| value

id_mixed : { f : F32, i : I32 } -> { f : F32, i : I32 }
id_mixed = |value| value

overflow : F32, F32, F32, F32, F32, F32, F32, F32, F32, { f : F32, i : I32 } -> { f : F32, i : I32 }
overflow = |_a, _b, _c, _d, _e, _f, _g, _h, _i, value| value
