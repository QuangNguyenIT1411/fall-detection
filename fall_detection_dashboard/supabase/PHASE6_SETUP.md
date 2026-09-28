# Phase 6 deployment and verification

The device owns the 30-second confirmation deadline. Supabase owns the
authoritative event status and timestamps. Flutter only renders a countdown
derived from `detected_at` and refreshes an official `DETECTED` event until it
becomes terminal.

## Deploy

Run from `fall_detection_dashboard` after linking the Supabase project:

```powershell
npx -y supabase@latest db push --include-all
npx -y supabase@latest functions deploy confirm-fall-event --no-verify-jwt
npx -y supabase@latest functions deploy cancel-fall-event --no-verify-jwt
```

`confirm-fall-event` still performs custom per-device authentication. Disabling
the platform JWT check is required because the ESP32 sends `X-Device-Code` and
`X-Device-Key`, not a user JWT.

## Expected lifecycle

1. ESP32 enters `FALL_DETECTED`, queues `create-fall-event`, and starts its
   monotonic 30-second deadline.
2. A valid physical cancel completed before the deadline queues cancel and
   resets the local alarm.
3. At the deadline, if still latched, ESP32 queues confirm once. The cloud
   worker waits for the create UUID if creation is still retrying.
4. Database transitions are atomic. A concurrent cancel or confirm can only
   change a `DETECTED` row; neither transition can overwrite a terminal row.
5. After confirmation, a physical button press only resets the local
   buzzer/state and does not enqueue a database cancel.

## Manual hardware test matrix

For a no-cancel confirmation test, rebuild and flash the current firmware, then
watch serial for these lines in order (the COM port may differ):

```powershell
cd D:\iot-projects\fall_detection
& 'D:\esp\v5.5.5\esp-idf\export.ps1'
idf.py -p COM5 flash monitor
```

Expected trace:

```text
Cloud confirmation firmware: Phase 6.1, 30s device deadline
FALL confirm timer started: ...
Fall event uploaded: <event UUID>
FALL confirm deadline reached: elapsed=... ms
Cloud confirm queued
Cloud confirm accepted: event_id=<same UUID>
Cloud confirm sending event_id=<same UUID>
Cloud confirm HTTP status=200 transport=ESP_OK
Cloud confirm success: event_id=<same UUID>
```

If `Cloud confirm waiting for create event id` appears, create has not finished;
the worker will send confirm after create returns its UUID. A non-200 response
or transport error should be followed by `Cloud confirm retry scheduled`.
Supabase `fall_events.status` and `confirmed_at` are the final result; a Flutter
countdown reaching zero alone is not confirmation.

- A: trigger a fall, do not press cancel, and verify `CONFIRMED` plus server
  `confirmed_at` after about 30 seconds.
- B: trigger a fall, complete cancel before 30 seconds, and verify `CANCELLED`.
- C: after A completes, press the physical button and verify the buzzer/local
  state resets while the database row remains `CONFIRMED`.
- D: call confirm twice for the same event and verify both calls succeed with
  the same `confirmed_at`.
- E: disconnect Wi-Fi before the deadline, reconnect later, and verify exactly
  one official row eventually becomes `CONFIRMED`.
- F: cancel before the deadline while cloud creation is retrying, reconnect,
  and verify the row becomes `CANCELLED`, never `CONFIRMED`.
- G: open/reload Flutter mid-countdown and verify the remaining time is based
  on server `detected_at`, not reset to 30 seconds.
- H: verify the official state automatically changes to `CONFIRMED` without
  reloading the page.
- I: verify countdown/status polling stops after `CANCELLED`.
- J: verify countdown/status polling stops after `CONFIRMED`.

The pending lifecycle queue is RAM-only. A power loss before an HTTP operation
finishes can still lose the pending create/cancel/confirm action; durable NVS
queueing remains a separate reliability enhancement.
