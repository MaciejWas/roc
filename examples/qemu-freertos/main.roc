app [main!] { pf: platform "./platform/main.roc" }

import pf.Uart

main! = || {
	Uart.write!("Hello world\n")
}
