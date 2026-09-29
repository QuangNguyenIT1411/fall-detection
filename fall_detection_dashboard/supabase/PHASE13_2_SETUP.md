# Phase 13.2 — Remote physical buzzer control

## Scope and safety

The control changes **only physical sound on GPIO4**, not alarm/event state.
`buzzer_enabled=false` is called test mode, but FALL/SOS, LED GPIO5, Telegram,
Twilio calls and physical GPIO3 CANCEL/SOS behaviour remain real and unchanged.
Do not trigger a FALL/SOS automatically during deployment or verification.

Control path:

```text
Authenticated Flutter -> set-buzzer-enabled -> devices
                                               |
ESP32 authenticated device-heartbeat <----------+
                 -> alarm_should_sound AND buzzer_enabled -> GPIO4
```

Browser MQTT remains subscribe-only. There are no MQTT command topics or ACL
changes. Firmware configuration arrives through the existing immediate startup
heartbeat and approximately 20-second heartbeat cycle. About 20 seconds is the
normal connected-device propagation delay, not a delivery guarantee: network
failures and a busy cloud worker can delay synchronization. A successful UI save
confirms database configuration, **not ESP32 receipt**.

## Database and authentication

- Migration `012_remote_buzzer_control.sql` adds `devices.buzzer_enabled`
  (NOT NULL, default true, including existing devices) and `buzzer_updated_at`.
- `fall_events` and existing authenticated SELECT policies are unchanged.
- The service-only `set_device_buzzer_enabled(boolean)` RPC updates the existing
  fixed `device01` row. It cannot select another device or create one. Timestamp
  comes from PostgreSQL. `anon`/`authenticated` have no RPC execute permission
  and gain no direct UPDATE permission.
- `set-buzzer-enabled` accepts POST with exactly `{ "enabled": true/false }`.
  It verifies the bearer token online with Supabase Auth `getUser(token)`, requires
  a non-anonymous authenticated user, then obtains the internal service client.
  This follows the existing closed-signup caregiver model; it is not multi-tenant
  device management. OPTIONS permits CORS preflight only, with no mutation.
- `verify_jwt=false` deliberately delegates verification to this handler, allowing
  preflight and supported Supabase signing keys. It does **not** grant public
  control. Missing, invalid, anonymous and service-role user tokens are rejected.
- No new credentials or Supabase secret configuration are required.
- Heartbeat records presence with the existing authentication/offline/recovery
  flow, then reads the current boolean from the database. Failed reads return
  failure rather than inventing a default configuration.

## Firmware

`main/buzzer_output.c` owns the final GPIO4 gate. The cloud task and alarm task use
one short FreeRTOS critical section for shared state and the GPIO write. JSON
parsing and change-only logs occur outside it; there is no network, queue wait,
allocation or logging in the 100 Hz alarm critical section.

- Fresh boot defaults enabled, including after a power cycle while the stored
  cloud preference is OFF. The first valid heartbeat then reapplies that preference.
- Missing/invalid boolean, unsuccessful heartbeat or unavailable network retains
  the last valid local value. Cloud failure alone never disables sound.
- OFF immediately silences a currently active buzzer when configuration is
  received. The event remains active; LED, SOS/CANCEL and cloud work are unchanged.
- ON resumes sound if the upstream alarm is still latched; it does not resurrect
  a cleared alarm. Logs appear only on changes: `BUZZER_CONFIG: DISABLED/ENABLED`.

## Flutter

Only the authenticated dashboard creates `BuzzerControlProvider`. Device reads
include both fields; old fixtures lacking the boolean default to true. The
Overview card shows BẬT/TẮT, the persistent OFF warning and propagation-delay text.
The switch is disabled pending a request, without optimistic changes. A failed
write retains the previous display. After success, the Edge result and subsequent
device refresh are authoritative; an older in-flight read cannot undo the save.
A periodic 8-second read also picks up changes from another signed-in dashboard.
Logout disposes the provider and timer. No client MQTT publishing is added.

## Validation and deployment

From Flutter project:

```sh
deno check supabase/functions/set-buzzer-enabled/index.ts supabase/functions/device-heartbeat/index.ts
deno test --allow-env supabase/functions
flutter analyze
flutter test
flutter build web --release
```

SQL regression `supabase/tests/012_remote_buzzer_control.sql` uses a rollback-only
transaction. No settings become visible to device heartbeats; no event or phone
call is created. Before first deployment, run migration plus regression in the
same transaction and verify existing rows default ON, then roll it all back.

Firmware host regression on Windows, from repository root (provide a C compiler
and the installed ESP-IDF path; binaries go to ignored `build/host-tests`):

```powershell
./main/tests/run_host_tests.ps1 -Compiler <path-to-gcc-or-tcc> -IdfPath <esp-idf-path>
idf.py build
```

The host tests compile the real buzzer gate, existing SOS state machine and IDF
cJSON, mocking only GPIO/critical sections/logging. They are not a physical board,
LED or end-to-end cloud delivery test. Review the limited integration diff and
complete the physical procedure below after manual flashing.

After validations pass, apply migration 012, then deploy sequentially:

```sh
supabase db push --linked
supabase functions deploy set-buzzer-enabled --no-verify-jwt
supabase functions deploy device-heartbeat --no-verify-jwt
```

Verify the migration/columns, ACTIVE function metadata, public OPTIONS=204 and
unauthenticated POST=401. Deploy Flutter through the existing main/Vercel flow.
Do not invoke real device/FALL/SOS handlers to test deployment. Do not flash
automatically. Firmware output: repository `build/fall_detection.bin` (plus the
normal bootloader/partition binaries).

## Exact manual physical test

1. Review changes. In the configured ESP-IDF terminal at repository root, manually
   run `idf.py -p <actual-COM-port> flash monitor`. Select the actual connected port;
   do not assume the previous port is unchanged.
2. Sign into production and open Overview. Verify initial BẬT and device online.
   Before any intentional alarm, warn the caregiver: **Telegram/Twilio remain real
   even when the physical buzzer is OFF**. Arrange the test with the recipient.
3. Set TẮT. Check switch pending state, persistent warning and saved confirmation.
   Wait for the connected board's next heartbeat (~20 seconds normally) and
   `BUZZER_CONFIG: DISABLED`. Do not treat the database save as hardware receipt.
4. Only when ready for real notifications, while NORMAL hold GPIO3 for at least
   3 seconds. Verify SOS event and LED ON with GPIO4 silent; verify the normal
   Supabase/Telegram/call paths. Setting OFF must not cancel the event.
5. While that alarm is still active, set BẬT, wait for `BUZZER_CONFIG: ENABLED`,
   and verify sound resumes. Set TẮT again; after the next valid heartbeat sound
   must stop while LED/event status remains unchanged.
6. Exercise the existing SOS local-silence press/release range; it must still
   silence/clear the local latch. Re-enabling afterwards must not revive it.
7. If performing an intentional physical FALL test, use a controlled device
   movement, never ask a person to fall. With OFF synchronized, GPIO4 stays silent
   while LED and FALL/cloud flows remain active. Verify the existing 2-second
   guard plus >=600 ms hold/release CANCEL behaviour; remote OFF is not CANCEL.
8. Test power cycle/network loss: fresh boot permits sound by default until a
   valid cloud config; later network failures retain the last local setting.
9. Restore BẬT and verify `BUZZER_CONFIG: ENABLED` before normal monitoring use.

No physical acceptance claim should be made until these user-run tests complete.

## Implementation verification (2026-09-30)

- All 10 Edge Function entrypoints passed Deno check; backend suite: 53 passed.
- Migration preflight/default-existing-row checks and rollback SQL regression
  passed; deployed migration 012 and reran SQL regression successfully.
- Live metadata: `set-buzzer-enabled` ACTIVE v1; `device-heartbeat` ACTIVE v12.
  Both use handler authentication. Unauthenticated control/heartbeat POST=401;
  control OPTIONS=204. Browser UPDATE/RPC execution denied; service RPC allowed.
  `device01` remained enabled after rollback tests.
- Firmware host buzzer/SOS suites passed; ESP32-C3 `idf.py build` succeeded.
- Flutter analyze: no issues; final full suite: 73 passed; release web build passed.
  The first suite run hit an existing MQTT polling test's 20 ms wall-clock race;
  that test passed in isolation and the full rerun passed. MQTT code/tests were
  not changed for this phase.
- No real FALL/SOS, call, authenticated live toggle or automatic flash was run.
  Authenticated writes were tested with mocked HTTP dependencies and rollback SQL;
  browser-to-hardware acceptance remains the manual procedure above.
