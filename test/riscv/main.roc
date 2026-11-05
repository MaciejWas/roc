app [main!] { pf: platform "platform/main.roc" }
import pf.Uart
import pf.Host

identity : a -> a
identity = |value| value

main! = || {
    value : U64
    value = identity(Host.number!())
    if value * 67 != 827115 or 123456789 // value != 10000 or 123456789 % value != 6789 {
        crash "native-word arithmetic mismatch"
    }
    high_divisor = value + 9223372036854763463
    if 18446744073709551615 // high_divisor != 1 or 18446744073709551615 % high_divisor != 9223372036854775807 {
        crash "high-bit division mismatch"
    }
    Uart.write!("riscv platform ".concat(value.to_str()).concat(" passed\n"))
}
