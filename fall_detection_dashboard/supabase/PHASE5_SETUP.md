# Phase 5 setup: ESP32 fall events

## 1. Apply the migration

From `fall_detection_dashboard` after linking the Supabase project:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Alternatively, run `migrations/002_device_credentials.sql` once in the
Supabase SQL Editor.

## 2. Generate and provision the device key

Generate a 32-byte random value in PowerShell:

```powershell
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$deviceKey = [Convert]::ToBase64String($bytes)
$deviceKey
```

Keep the output private. In the SQL Editor, provision only its bcrypt hash:

```sql
insert into public.device_credentials (device_id, secret_hash)
select id, crypt('PASTE_DEVICE_KEY_HERE', gen_salt('bf', 12))
from public.devices
where device_code = 'device01'
on conflict (device_id) do update
set secret_hash = excluded.secret_hash;
```

Verify without displaying the hash or key:

```sql
select d.device_code, dc.created_at, dc.updated_at
from public.device_credentials dc
join public.devices d on d.id = dc.device_id;
```

Do not add a browser RLS policy to `device_credentials`.

## 3. Deploy the functions

`config.toml` disables gateway JWT verification only for these two functions.
They perform their own device-key authentication.

```powershell
supabase functions deploy create-fall-event
supabase functions deploy cancel-fall-event
```

Hosted Edge Functions receive `SUPABASE_URL` and server secret variables from
Supabase automatically. Never copy a service-role or secret key into firmware,
Flutter, Git, or this document.

For local function testing only, create an ignored
`supabase/functions/.env` containing the local Supabase server variables, then:

```powershell
supabase functions serve --env-file supabase/functions/.env
```

## 4. Test CREATE in PowerShell

Keep the device key in a session variable so it is not embedded in scripts:

```powershell
$projectRef = 'YOUR_PROJECT_REF'
$deviceKey = Read-Host 'Device API key'
$headers = @{
  'X-Device-Code' = 'device01'
  'X-Device-Key' = $deviceKey
}
$fallBody = @{
  peak_acc = 7.02
  peak_gyro = 306.8
  final_pose = 88.9
  low_g_duration_ms = 330
  low_g_to_impact_ms = 340
  device_uptime_ms = 615218
} | ConvertTo-Json

$created = Invoke-RestMethod `
  -Method Post `
  -Uri "https://$projectRef.supabase.co/functions/v1/create-fall-event" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $fallBody

$created
```

Expected HTTP status is `201`; save `$created.event_id` for cancellation.

Equivalent curl request:

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/functions/v1/create-fall-event" \
  -H "Content-Type: application/json" \
  -H "X-Device-Code: device01" \
  -H "X-Device-Key: $DEVICE_API_KEY" \
  -d '{"peak_acc":7.02,"peak_gyro":306.8,"final_pose":88.9,"low_g_duration_ms":330,"low_g_to_impact_ms":340,"device_uptime_ms":615218}'
```

## 5. Test CANCEL in PowerShell

```powershell
$cancelBody = @{ event_id = $created.event_id } | ConvertTo-Json

$cancelled = Invoke-RestMethod `
  -Method Post `
  -Uri "https://$projectRef.supabase.co/functions/v1/cancel-fall-event" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $cancelBody

$cancelled
```

Expected HTTP status is `200` and status is `CANCELLED`.

## 6. Configure firmware

In the ignored `main/app_config.h` set:

```c
#define CLOUD_EVENT_ENABLED 1
#define SUPABASE_FUNCTION_BASE_URL "https://YOUR_PROJECT_REF.supabase.co/functions/v1"
#define DEVICE_API_KEY "THE_SAME_RANDOM_DEVICE_KEY"
```

Then rebuild and flash. The key must match the bcrypt hash provisioned above.

## 7. Database verification

```sql
select
  fe.id,
  d.device_code,
  fe.detected_at,
  fe.peak_acc,
  fe.peak_gyro,
  fe.final_pose,
  fe.low_g_duration_ms,
  fe.low_g_to_impact_ms,
  fe.device_uptime_ms,
  fe.status,
  fe.cancelled_at
from public.fall_events fe
join public.devices d on d.id = fe.device_id
where d.device_code = 'device01'
order by fe.detected_at desc
limit 20;
```
