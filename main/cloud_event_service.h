#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

typedef struct
{
    float peak_acc;
    float peak_gyro;
    float final_pose;
    int64_t low_g_duration_ms;
    int64_t low_g_to_impact_ms;
    int64_t device_uptime_ms;
} cloud_fall_event_t;

esp_err_t cloud_event_service_init(void);
bool cloud_event_enqueue_fall(const cloud_fall_event_t *event);
bool cloud_event_enqueue_cancel(void);
bool cloud_event_enqueue_confirm(void);
bool cloud_event_enqueue_sos(const char request_key[37]);
