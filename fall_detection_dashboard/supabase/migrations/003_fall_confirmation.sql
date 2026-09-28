-- Phase 6: authoritative fall confirmation using database server time.

alter table public.fall_events
  add column if not exists confirmed_at timestamptz;

-- Preserve old seeded/legacy CONFIRMED rows before enforcing the invariant.
update public.fall_events
set confirmed_at = detected_at
where status = 'CONFIRMED'
  and confirmed_at is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fall_events_confirmed_at_check'
      and conrelid = 'public.fall_events'::regclass
  ) then
    alter table public.fall_events
      add constraint fall_events_confirmed_at_check
      check (
        (status = 'CONFIRMED' and confirmed_at is not null)
        or (status <> 'CONFIRMED' and confirmed_at is null)
      );
  end if;
end
$$;

-- Atomic and idempotent DETECTED -> CONFIRMED transition. If a concurrent
-- cancel wins first, this function returns no row and never revives the event.
create or replace function public.confirm_device_fall_event(
  p_event_id uuid,
  p_device_id uuid
)
returns table (
  id uuid,
  status text,
  confirmed_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
begin
  return query
    update public.fall_events
    set status = 'CONFIRMED',
        confirmed_at = now()
    where fall_events.id = p_event_id
      and fall_events.device_id = p_device_id
      and fall_events.status = 'DETECTED'
    returning fall_events.id,
              fall_events.status,
              fall_events.confirmed_at;

  if found then
    return;
  end if;

  return query
    select fall_events.id,
           fall_events.status,
           fall_events.confirmed_at
    from public.fall_events
    where fall_events.id = p_event_id
      and fall_events.device_id = p_device_id
      and fall_events.status = 'CONFIRMED';
end;
$$;

revoke all on function public.confirm_device_fall_event(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.confirm_device_fall_event(uuid, uuid)
  to service_role;
