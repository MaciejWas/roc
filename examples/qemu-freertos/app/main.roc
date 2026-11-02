app [main!] { pf: platform "../platform/main.roc" }

import pf.Uart

goo : I32 -> I32
goo = |cos| {
    cos + 3
}

main! = || {
	Uart.write!("Hello world\n")
	Uart.write!("I co\n")
	Uart.write!(  goo(5).to_str() )
}
