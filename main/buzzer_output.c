#include "buzzer_output.h"

#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "esp_log.h"

static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;
static bool s_enabled = true; // Safety default on every fresh boot.
static bool s_alarm_should_sound = false;
static int s_physical_level = -1;

// Both writers hold the same short critical section, including the GPIO write:
// a stale sensor-task write cannot turn sound back on after a remote OFF.
static void apply_output_locked(void)
{
    const int level = s_alarm_should_sound && s_enabled ? 1 : 0;
    if (level != s_physical_level)
    {
        gpio_set_level(GPIO_NUM_4, level);
        s_physical_level = level;
    }
}

void buzzer_output_set_alarm(bool alarm_should_sound)
{
    portENTER_CRITICAL(&s_lock);
    s_alarm_should_sound = alarm_should_sound;
    apply_output_locked();
    portEXIT_CRITICAL(&s_lock);
}

void buzzer_output_apply_heartbeat(const cJSON *response)
{
    const cJSON *success = cJSON_GetObjectItemCaseSensitive(response, "success");
    const cJSON *setting = cJSON_GetObjectItemCaseSensitive(response, "buzzer_enabled");
    if (!cJSON_IsTrue(success) || !cJSON_IsBool(setting))
        return; // Failed/missing/malformed config retains the last value.
    const bool enabled = cJSON_IsTrue(setting);
    portENTER_CRITICAL(&s_lock);
    const bool changed = s_enabled != enabled;
    s_enabled = enabled;
    apply_output_locked(); // Silence an active alarm immediately on this task.
    portEXIT_CRITICAL(&s_lock);
    if (changed)
        ESP_LOGI("BUZZER_CONFIG", "%s", enabled ? "ENABLED" : "DISABLED");
}
