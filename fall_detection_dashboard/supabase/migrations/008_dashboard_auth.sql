-- Phase 11: caregiver-only dashboard reads. Edge Functions retain service_role.
alter table public.devices enable row level security;
alter table public.fall_events enable row level security;

drop policy if exists "Dashboard can read devices" on public.devices;
drop policy if exists "Dashboard can read fall events" on public.fall_events;

create policy "Caregivers can read devices"
  on public.devices for select to authenticated using (true);
create policy "Caregivers can read fall events"
  on public.fall_events for select to authenticated using (true);

revoke all privileges on table public.devices, public.fall_events from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.devices, public.fall_events from authenticated;
grant select on table public.devices, public.fall_events to authenticated;

revoke all privileges on table public.device_credentials from anon, authenticated;
