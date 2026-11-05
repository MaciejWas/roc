OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M }
SECTIONS {
    . = ORIGIN(RAM);
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
    .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) } > RAM
    .data : { __global_pointer$ = . + 0x800; *(.data .data.*) *(.sdata .sdata.*) *(.got .got.*) } > RAM
    .bss (NOLOAD) : { . = ALIGN(16); __bss_start = .; *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) . = ALIGN(16); __bss_end = .; } > RAM
    .stack (NOLOAD) : { . = ALIGN(16); . += 128K; __boot_stack_top = .; } > RAM
}
