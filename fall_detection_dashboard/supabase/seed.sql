-- Deterministic sample data for Phase 2.
-- Run after schema.sql in Supabase Dashboard > SQL Editor.

insert into public.devices (
  id,
  device_code,
  name,
  is_online,
  last_seen,
  created_at
)
values (
  '00000000-0000-4000-8000-000000000001',
  'device01',
  'Thiết bị người cao tuổi 01',
  true,
  '2026-09-24T02:20:00Z',
  '2026-09-01T01:00:00Z'
)
on conflict (id) do update set
  device_code = excluded.device_code,
  name = excluded.name,
  is_online = excluded.is_online,
  last_seen = excluded.last_seen;

insert into public.fall_events (
  id,
  device_id,
  detected_at,
  peak_acc,
  peak_gyro,
  final_pose,
  low_g_duration_ms,
  low_g_to_impact_ms,
  status,
  cancelled_at,
  created_at
)
values
  (
    '10000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000001',
    '2026-09-24T02:15:00Z',
    7.02, 306.8, 88.9, 330, 340,
    'DETECTED', null,
    '2026-09-24T02:15:02Z'
  ),
  (
    '10000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000001',
    '2026-09-22T08:30:00Z',
    5.80, 245.5, 72.4, 180, 220,
    'CANCELLED', '2026-09-22T08:31:10Z',
    '2026-09-22T08:30:03Z'
  ),
  (
    '10000000-0000-4000-8000-000000000103',
    '00000000-0000-4000-8000-000000000001',
    '2026-09-19T14:05:00Z',
    9.10, 612.3, 104.6, 240, 390,
    'CONFIRMED', null,
    '2026-09-19T14:05:02Z'
  ),
  (
    '10000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000001',
    '2026-09-15T03:45:00Z',
    6.45, 288.0, 65.2, 120, 175,
    'CANCELLED', '2026-09-15T03:46:30Z',
    '2026-09-15T03:45:02Z'
  ),
  (
    '10000000-0000-4000-8000-000000000105',
    '00000000-0000-4000-8000-000000000001',
    '2026-09-10T11:20:00Z',
    8.35, 525.4, 96.7, 295, 365,
    'CONFIRMED', null,
    '2026-09-10T11:20:02Z'
  )
on conflict (id) do update set
  device_id = excluded.device_id,
  detected_at = excluded.detected_at,
  peak_acc = excluded.peak_acc,
  peak_gyro = excluded.peak_gyro,
  final_pose = excluded.final_pose,
  low_g_duration_ms = excluded.low_g_duration_ms,
  low_g_to_impact_ms = excluded.low_g_to_impact_ms,
  status = excluded.status,
  cancelled_at = excluded.cancelled_at;
