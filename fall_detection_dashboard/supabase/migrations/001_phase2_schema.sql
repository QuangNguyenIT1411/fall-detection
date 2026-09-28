-- Phase 2: read-only schema for the Flutter dashboard.

create extension if not exists pgcrypto;

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  device_code text not null unique,
  name text not null,
  is_online boolean not null default false,
  last_seen timestamptz,
  created_at timestamptz not null default now(),
  constraint devices_device_code_not_blank check (btrim(device_code) <> ''),
  constraint devices_name_not_blank check (btrim(name) <> '')
);

create table if not exists public.fall_events (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete cascade,
  detected_at timestamptz not null,
  peak_acc double precision,
  peak_gyro double precision,
  final_pose double precision,
  low_g_duration_ms integer,
  low_g_to_impact_ms integer,
  status text not null,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint fall_events_status_check
    check (status in ('DETECTED', 'CANCELLED', 'CONFIRMED')),
  constraint fall_events_peak_acc_check
    check (peak_acc is null or peak_acc >= 0),
  constraint fall_events_peak_gyro_check
    check (peak_gyro is null or peak_gyro >= 0),
  constraint fall_events_final_pose_check
    check (final_pose is null or final_pose between 0 and 180),
  constraint fall_events_low_g_duration_check
    check (low_g_duration_ms is null or low_g_duration_ms >= 0),
  constraint fall_events_low_g_to_impact_check
    check (low_g_to_impact_ms is null or low_g_to_impact_ms >= 0),
  constraint fall_events_cancelled_at_check
    check (status <> 'CANCELLED' or cancelled_at is not null),
  constraint fall_events_cancelled_after_detection_check
    check (cancelled_at is null or cancelled_at >= detected_at)
);

create index if not exists fall_events_device_detected_idx
  on public.fall_events (device_id, detected_at desc);

create index if not exists fall_events_detected_at_idx
  on public.fall_events (detected_at desc);

create index if not exists fall_events_status_idx
  on public.fall_events (status);

alter table public.devices enable row level security;
alter table public.fall_events enable row level security;

drop policy if exists "Dashboard can read devices" on public.devices;
create policy "Dashboard can read devices"
  on public.devices
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Dashboard can read fall events" on public.fall_events;
create policy "Dashboard can read fall events"
  on public.fall_events
  for select
  to anon, authenticated
  using (true);

revoke insert, update, delete, truncate, references, trigger
  on table public.devices, public.fall_events
  from anon, authenticated;

grant usage on schema public to anon, authenticated;
grant select on table public.devices, public.fall_events
  to anon, authenticated;
