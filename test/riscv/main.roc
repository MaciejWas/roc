app [main!] { pf: platform "platform/main.roc" }
import pf.Uart

identity : a -> a
identity = |value| value

main! = || {
    value : U32
    value = identity(8)
    Uart.write!("riscv platform ".concat(value.to_str()).concat(" passed\n"))
}
