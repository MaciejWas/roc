.section .text.start
.global _start
_start:
    /* The example runs exactly one hart and starts directly in machine mode. */
    csrw mie, zero
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __boot_stack_top
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
#if __riscv_xlen == 32
    sw zero, 0(t0)
    addi t0, t0, 4
#else
    sd zero, 0(t0)
    addi t0, t0, 8
#endif
    j 1b
2:
    la t0, freertos_risc_v_trap_handler
    csrw mtvec, t0
    call firmware_main
3:
    wfi
    j 3b
