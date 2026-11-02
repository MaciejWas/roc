platform ""
	requires {
		main! : () => {}
	}
	exposes [Uart]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted { "roc_uart_write": Uart.write! }
	targets: {
		riscv64elf: {
			inputs: [app],
			output: Archive,
		},
	}

import Uart

main_for_host! : () => {}
main_for_host! = main!
