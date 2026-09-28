#include "manual_sos.h"

#include <string.h>

#define SOS_DEBOUNCE_MS 40
#define SOS_TRIGGER_HOLD_MS 3000
#define SOS_SILENCE_HOLD_MS 600

void manual_sos_init(manual_sos_t *sos)
{
    memset(sos, 0, sizeof(*sos));
    sos->stable_high = true;
    sos->raw_high = true;
    // A held button at startup or after a fall cannot start an SOS.
    sos->requires_release = true;
}

manual_sos_result_t manual_sos_update(manual_sos_t *sos, bool eligible,
                                      bool button_high, int64_t now_ms)
{
    manual_sos_result_t result = {.active = sos->active};
    if (!eligible)
    {
        sos->requires_release = true;
        sos->press_started_at_ms = 0;
        sos->triggered_on_press = false;
        sos->stable_high = button_high;
        sos->raw_high = button_high;
        sos->raw_changed_at_ms = now_ms;
        return result;
    }

    if (button_high != sos->raw_high)
    {
        sos->raw_high = button_high;
        sos->raw_changed_at_ms = now_ms;
    }
    if (button_high != sos->stable_high &&
        now_ms - sos->raw_changed_at_ms >= SOS_DEBOUNCE_MS)
    {
        sos->stable_high = button_high;
        if (button_high)
        {
            if (!sos->requires_release && sos->active &&
                !sos->triggered_on_press && sos->press_started_at_ms > 0)
            {
                const int64_t held_ms = now_ms - sos->press_started_at_ms;
                if (held_ms >= SOS_SILENCE_HOLD_MS &&
                    held_ms < SOS_TRIGGER_HOLD_MS)
                {
                    sos->active = false;
                    result.silenced = true;
                }
            }
            sos->requires_release = false;
            sos->press_started_at_ms = 0;
            sos->triggered_on_press = false;
        }
        else if (!sos->requires_release)
        {
            sos->press_started_at_ms = now_ms;
            sos->triggered_on_press = false;
        }
    }

    if (sos->requires_release && sos->stable_high && button_high &&
        now_ms - sos->raw_changed_at_ms >= SOS_DEBOUNCE_MS)
        sos->requires_release = false;

    if (!sos->requires_release && !sos->stable_high &&
        !sos->triggered_on_press && sos->press_started_at_ms > 0 &&
        now_ms - sos->press_started_at_ms >= SOS_TRIGGER_HOLD_MS)
    {
        sos->active = true;
        sos->triggered_on_press = true;
        result.triggered = true;
    }
    result.active = sos->active;
    return result;
}
