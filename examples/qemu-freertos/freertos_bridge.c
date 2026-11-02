/* Only bridges FreeRTOS macros to Zig; platform policy lives in host.zig. */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

void *roc_freertos_create_mutex(void) { return xSemaphoreCreateRecursiveMutex(); }
int roc_freertos_take_mutex(void *mutex) { return xSemaphoreTakeRecursive(mutex, portMAX_DELAY); }
int roc_freertos_give_mutex(void *mutex) { return xSemaphoreGiveRecursive(mutex); }
void *roc_freertos_get_state(void) { return pvTaskGetThreadLocalStoragePointer(NULL, 0); }
void roc_freertos_set_state(void *state) { vTaskSetThreadLocalStoragePointer(NULL, 0, state); }
int roc_freertos_create_task(TaskFunction_t entry) {
    return xTaskCreate(entry, "roc-hello", 8192, NULL, 2, NULL);
}
void roc_freertos_delete_task(void) { vTaskDelete(NULL); }
