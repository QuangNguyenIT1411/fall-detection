#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct
{
    bool stable_high;
    bool raw_high;
    bool requires_release;
    bool active;
    bool triggered_on_press;
    int64_t raw_changed_at_ms;
    int64_t press_started_at_ms;
} manual_sos_t;

typedef struct
{
    bool triggered;
    bool silenced;
    bool active;
} manual_sos_result_t;

void manual_sos_init(manual_sos_t *sos);
manual_sos_result_t manual_sos_update(manual_sos_t *sos, bool eligible,
                                      bool button_high, int64_t now_ms);
