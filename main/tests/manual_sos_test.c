#include "../manual_sos.h"

#include <assert.h>
#include <stdio.h>

static manual_sos_t sos;
static int triggers;
static int silences;

static void step(bool eligible, bool high, int64_t ms)
{
    manual_sos_result_t result = manual_sos_update(&sos, eligible, high, ms);
    triggers += result.triggered;
    silences += result.silenced;
    assert(result.active == sos.active);
}

static void reset(void)
{
    manual_sos_init(&sos);
    triggers = 0;
    silences = 0;
    step(true, true, 0);
    step(true, true, 40);
}

static void press(int64_t at)
{
    step(true, false, at);
    step(true, false, at + 40);
}

static void release(int64_t at)
{
    step(true, true, at);
    step(true, true, at + 40);
}

int main(void)
{
    reset();
    press(100);
    release(400);
    assert(triggers == 0);
    press(500);
    step(true, false, 2999);
    assert(triggers == 0);
    release(3000);
    assert(triggers == 0);

    reset();
    press(100);
    step(true, false, 3139);
    assert(triggers == 0);
    step(true, false, 3140);
    assert(triggers == 1 && sos.active);
    step(true, false, 8140);
    assert(triggers == 1);
    release(8200);
    assert(silences == 0 && sos.active);

    press(8300);
    step(true, false, 11340);
    assert(triggers == 2);
    release(11400);
    assert(sos.active);
    press(11500);
    step(true, false, 12140);
    release(12150);
    assert(silences == 1 && !sos.active);
    // Silencing is local only: the trigger count (and queued cloud actions)
    // remains unchanged.
    assert(triggers == 2);

    reset();
    step(false, false, 100);
    step(false, false, 4000);
    step(true, false, 5000);
    step(true, false, 9000);
    assert(triggers == 0);
    release(9010);
    press(9100);
    step(true, false, 12140);
    assert(triggers == 1);

    reset();
    // A button already held during startup cannot generate an SOS.
    step(true, false, 0);
    step(true, false, 4000);
    assert(triggers == 0);
    release(4010);
    press(4100);
    step(true, false, 7140);
    assert(triggers == 1);

    puts("manual_sos_test: PASS");
    return 0;
}
