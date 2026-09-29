#include "../buzzer_output.h"
#include "../manual_sos.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int physical = -1;
static int logs = 0;
static int critical = 0;
static int *shared_lock = NULL;

void test_enter_critical(int *lock)
{
    assert(critical == 0);
    if (shared_lock) assert(shared_lock == lock);
    shared_lock = lock;
    critical++;
}
void test_exit_critical(int *lock) { assert(critical == 1 && shared_lock == lock); critical--; }
int gpio_set_level(int pin, unsigned int value)
{
    assert(pin == 4 && critical == 1); // Must not touch LED/button or write outside lock.
    physical = value;
    return 0;
}
void test_log(const char *tag, const char *format, const char *value)
{
    assert(critical == 0); // No formatting / IO in sensor critical section.
    assert(strcmp(tag, "BUZZER_CONFIG") == 0 && strcmp(format, "%s") == 0);
    assert(strcmp(value, "ENABLED") == 0 || strcmp(value, "DISABLED") == 0);
    logs++;
}
static void heartbeat(const char *json)
{
    cJSON *response = cJSON_Parse(json);
    buzzer_output_apply_heartbeat(response);
    cJSON_Delete(response);
}

int main(void)
{
    buzzer_output_set_alarm(false);
    assert(physical == 0);
    buzzer_output_set_alarm(true);
    assert(physical == 1); // Fresh boot ON before any valid cloud setting.
    heartbeat("{\"success\":true,\"buzzer_enabled\":false}");
    assert(physical == 0 && logs == 1); // Active buzzer stops on config receipt.
    buzzer_output_set_alarm(true);
    assert(physical == 0); // A later sensor write cannot re-enable sound.
    heartbeat("{\"success\":true,\"buzzer_enabled\":false}");
    assert(logs == 1); // Repeated heartbeats do not spam logs.
    heartbeat("{}");
    heartbeat("{\"success\":true}");
    heartbeat("{\"success\":false,\"buzzer_enabled\":true}");
    heartbeat("{\"success\":true,\"buzzer_enabled\":\"true\"}");
    heartbeat("{\"success\":true,\"buzzer_enabled\":1}");
    heartbeat("null");
    heartbeat("invalid json");
    assert(physical == 0 && logs == 1);
    heartbeat("{\"success\":true,\"buzzer_enabled\":true}");
    assert(physical == 1 && logs == 2); // Latched alarm resumes without changing alarm state.
    buzzer_output_set_alarm(false);
    assert(physical == 0);
    heartbeat("{\"success\":true,\"buzzer_enabled\":false}");

    // Exercise the existing SOS state machine while physical sound is gated.
    manual_sos_t sos;
    manual_sos_init(&sos);
    manual_sos_update(&sos, true, true, 0);
    manual_sos_update(&sos, true, true, 40);
    manual_sos_update(&sos, true, false, 100);
    manual_sos_update(&sos, true, false, 140);
    manual_sos_result_t result = manual_sos_update(&sos, true, false, 3140);
    assert(result.triggered && result.active); // Existing cloud enqueue trigger is retained.
    bool alarm_on = result.active; // Same decision used by LED + alarm logic.
    buzzer_output_set_alarm(alarm_on);
    assert(alarm_on && physical == 0);
    manual_sos_update(&sos, true, true, 3200);
    manual_sos_update(&sos, true, true, 3240);
    manual_sos_update(&sos, true, false, 3300);
    manual_sos_update(&sos, true, false, 3340);
    manual_sos_update(&sos, true, true, 3980);
    result = manual_sos_update(&sos, true, true, 4020);
    assert(result.silenced && !result.active); // Existing physical silence timing unchanged.
    buzzer_output_set_alarm(result.active);
    heartbeat("{\"success\":true,\"buzzer_enabled\":true}");
    assert(physical == 0); // Re-enabling does not resurrect a cleared alarm.
    heartbeat("{\"success\":true,\"buzzer_enabled\":false}");
    buzzer_output_set_alarm(true); // FALL uses the same alarm output gate.
    assert(physical == 0);
    buzzer_output_set_alarm(false); // CANCEL clears the upstream alarm normally.
    heartbeat("{\"success\":true,\"buzzer_enabled\":true}");
    assert(physical == 0 && critical == 0);
    puts("buzzer_output_test: PASS");
    return 0;
}
