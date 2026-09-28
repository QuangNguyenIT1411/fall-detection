-- Phase 5: device authentication and fall-event diagnostics.
-- Device secrets are stored as bcrypt hashes and are never readable by browser roles.

create extension if not exists pgcrypto;

create table if not exists public.device_credentials (
  device_id uuid primary key
    references public.devices(id)
    on delete cascade,
  secret_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_credentials_secret_hash_not_blank
    check (btrim(secret_hash) <> '')
);

alter table public.device_credentials enable row level security;

-- Deliberately no RLS policies: anon/authenticated cannot read this table.
revoke all on table public.device_credentials from public, anon, authenticated;
grant select, insert, update, delete on table public.device_credentials to service_role;

alter table public.fall_events
  add column if not exists device_uptime_ms bigint;

alter table public.fall_events
  alter column detected_at set default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fall_events_device_uptime_check'
      and conrelid = 'public.fall_events'::regclass
  ) then
    alter table public.fall_events
      add constraint fall_events_device_uptime_check
      check (device_uptime_ms is null or device_uptime_ms >= 0);
  end if;
end
$$;

create or replace function public.set_device_credentials_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists device_credentials_set_updated_at
  on public.device_credentials;
create trigger device_credentials_set_updated_at
before update on public.device_credentials
for each row
execute function public.set_device_credentials_updated_at();

revoke all on function public.set_device_credentials_updated_at() from public;

-- Returns the authenticated device UUID, or NULL for an invalid key.
-- Only the server-side service role may call this function.
create or replace function public.authenticate_device(
  p_device_code text,
  p_device_key text
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
  select d.id
  from public.devices as d
  join public.device_credentials as dc on dc.device_id = d.id
  where d.device_code = p_device_code
    and dc.secret_hash = crypt(p_device_key, dc.secret_hash)
  limit 1;
$$;

revoke all on function public.authenticate_device(text, text) from public, anon, authenticated;
grant execute on function public.authenticate_device(text, text) to service_role;

-- Atomic DETECTED -> CANCELLED transition using database server time.
create or replace function public.cancel_device_fall_event(
  p_event_id uuid,
  p_device_id uuid
)
returns table (
  id uuid,
  status text,
  cancelled_at timestamptz
)
language sql
volatile
security definer
set search_path = pg_catalog, public
as $$
  update public.fall_events
  set status = 'CANCELLED',
      cancelled_at = now()
  where fall_events.id = p_event_id
    and fall_events.device_id = p_device_id
    and fall_events.status = 'DETECTED'
  returning fall_events.id,
            fall_events.status,
            fall_events.cancelled_at;
$$;

revoke all on function public.cancel_device_fall_event(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_device_fall_event(uuid, uuid)
  to service_role;

-- Provisioning example (replace both placeholders locally; never commit the key):
-- insert into public.device_credentials (device_id, secret_hash)
-- select id, crypt('DEVICE_API_KEY', gen_salt('bf', 12))
-- from public.devices where device_code = 'device01'
-- on conflict (device_id) do update
-- set secret_hash = excluded.secret_hash;
