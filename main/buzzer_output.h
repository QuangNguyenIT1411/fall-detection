#pragma once

#include <stdbool.h>
#include "cJSON.h"

// Call after GPIO4 has been configured as an output. Alarm decisions remain
// owned by the sensor task; this module gates only the physical sound output.
void buzzer_output_set_alarm(bool alarm_should_sound);
void buzzer_output_apply_heartbeat(const cJSON *response);
