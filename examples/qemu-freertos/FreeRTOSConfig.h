#ifndef ROC_FREERTOS_CONFIG_H
#define ROC_FREERTOS_CONFIG_H
#include <stdint.h>
void roc_freertos_assert(void);
#define configASSERT(condition) do { if (!(condition)) roc_freertos_assert(); } while (0)
#define configUSE_PREEMPTION 1
#define configUSE_TIME_SLICING 1
#define configCPU_CLOCK_HZ 10000000UL
#define configTICK_RATE_HZ 1000
#define configMAX_PRIORITIES 4
#define configMINIMAL_STACK_SIZE 256
#define configTOTAL_HEAP_SIZE (2 * 1024 * 1024)
#define configMAX_TASK_NAME_LEN 16
#define configTICK_TYPE_WIDTH_IN_BITS TICK_TYPE_WIDTH_64_BITS
#define configIDLE_SHOULD_YIELD 1
#define configUSE_MUTEXES 1
#define configUSE_RECURSIVE_MUTEXES 1
#define configUSE_TIMERS 0
#define configUSE_IDLE_HOOK 1
#define configUSE_TICK_HOOK 0
#define configCHECK_FOR_STACK_OVERFLOW 2
#define configUSE_MALLOC_FAILED_HOOK 1
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configSUPPORT_STATIC_ALLOCATION 0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 1
#define configMTIME_BASE_ADDRESS 0x0200BFF8UL
#define configMTIMECMP_BASE_ADDRESS 0x02004000UL
#define configISR_STACK_SIZE_WORDS 1024
#define INCLUDE_vTaskDelete 1
#define INCLUDE_vTaskDelay 1
#define INCLUDE_vTaskSuspend 1
#endif
