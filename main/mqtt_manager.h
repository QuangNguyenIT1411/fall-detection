#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

esp_err_t mqtt_manager_init(void);
bool mqtt_manager_is_connected(void);

int mqtt_publish_telemetry(float acc,
                           float gyro,
                           float pose,
                           const char *state,
                           int64_t timestamp_ms);
int mqtt_publish_state(const char *state, int64_t timestamp_ms);
int mqtt_publish_status(bool online, int64_t timestamp_ms);
