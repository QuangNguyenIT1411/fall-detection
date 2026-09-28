# Phase 9: backend device presence

The ESP32 cloud worker sends `POST /device-heartbeat` every 20 seconds using
the existing `X-Device-Code` / `X-Device-Key` credentials. Postgres supplies
`last_seen_at`; device uptime is never used for backend presence. The Flutter
8-second MQTT watchdog stays independent and unchanged.

## Deploy

From `fall_detection_dashboard`, after linking the project:

```powershell
npx -y supabase@latest db push
npx -y supabase@latest functions deploy device-heartbeat --no-verify-jwt
npx -y supabase@latest functions deploy check-device-offline --no-verify-jwt
```

Set a random 32+-character `DEVICE_OFFLINE_CRON_SECRET` as an Edge Function
secret. Store the **same** value in Supabase Vault, along with the project URL.
Never put either secret into a migration, Git, firmware, or Flutter. In the SQL
Editor, with the placeholders replaced locally, run:

```sql
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault;

select vault.create_secret('https://YOUR_PROJECT_REF.supabase.co',
  'device_presence_project_url');
select vault.create_secret('YOUR_RANDOM_CRON_SECRET',
  'device_offline_cron_secret');
```

Then execute the secret-free `supabase/schedule_device_offline.sql` through
the SQL Editor or:

```powershell
npx -y supabase@latest db query --linked --file supabase/schedule_device_offline.sql
```

Cron runs every minute. With a 60-second stale threshold, the usual offline
Telegram delay is approximately 60–120 seconds after the last heartbeat,
plus network/Telegram latency. A failed Telegram request releases its claim;
the next cron run retries. A two-minute claim lease protects against a crashed
worker. External Telegram delivery cannot be mathematically exactly-once if
Telegram accepts a message but the subsequent database update fails; this
small ambiguous window needs operational monitoring.

Legacy devices have `last_seen_at = NULL`, so deploying this migration alone
does not create historical offline alerts. An authenticated first heartbeat
enrolls a device in presence monitoring. If the device is unplugged afterward,
the checker marks it `OFFLINE` and sends one alert. After a recovery heartbeat,
one recovery alert is sent; the cycle fields reset for a future outage.

Check `cron.job_run_details`, Edge Function logs, and the `devices` row if an
alert is delayed. `check-device-offline` requires `x-cron-secret`, while
`device-heartbeat` uses only the existing device credentials.

## Physical test

1. Flash the new firmware and power the ESP32; confirm a heartbeat updates
   `devices.last_seen_at` and `connectivity_status = ONLINE`.
2. Unplug power. Flutter should show OFFLINE in about 8–9 seconds, independent
   of the backend.
3. Wait up to roughly two minutes for one offline Telegram. Observe repeated
   cron runs without a second alert.
4. Power on again. After the first successful heartbeat, expect one recovery
   Telegram; subsequent heartbeats must not repeat it.
