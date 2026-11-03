platform ""
	requires {
		main! : () => {}
	}
	exposes [Uart]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted { "roc_uart_write": Uart.write! }
	targets: {
		riscv32elf: {
			inputs: ["startup.o", app, "libhost.a"],
			output: Exe,
			linker_script: "linker.ld",
			entry_point: "_start",
		},
		riscv64elf: {
			inputs: ["startup.o", app, "libhost.a"],
			output: Exe,
			linker_script: "linker.ld",
			entry_point: "_start",
		},
	}

import Uart

main_for_host! : () => {}
main_for_host! = main!
