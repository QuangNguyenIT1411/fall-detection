-- Phase 9: server-owned device presence. Legacy rows have no heartbeat and
-- therefore cannot generate retrospective offline alerts on deployment.
alter table public.devices
  add column if not exists last_seen_at timestamptz,
  add column if not exists connectivity_status text not null default 'OFFLINE',
  add column if not exists offline_since timestamptz,
  add column if not exists offline_notified_at timestamptz,
  add column if not exists recovery_pending_at timestamptz,
  add column if not exists recovery_notified_at timestamptz,
  add column if not exists offline_claim_token uuid,
  add column if not exists offline_claimed_at timestamptz,
  add column if not exists recovery_claim_token uuid,
  add column if not exists recovery_claimed_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'devices_connectivity_status_check') then
    alter table public.devices add constraint devices_connectivity_status_check
      check (connectivity_status in ('ONLINE', 'OFFLINE'));
  end if;
end $$;

create index if not exists devices_presence_check_idx
  on public.devices (last_seen_at) where last_seen_at is not null;

create or replace function public.record_device_heartbeat(p_device_id uuid)
returns table (last_seen_at timestamptz, connectivity_status text, recovery_pending boolean)
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare d public.devices%rowtype;
begin
  select * into d from public.devices where id = p_device_id for update;
  if not found then return; end if;
  update public.devices as x set
    last_seen_at = now(), last_seen = now(), is_online = true,
    connectivity_status = 'ONLINE',
    recovery_pending_at = case
      when d.connectivity_status = 'OFFLINE' and d.offline_notified_at is not null
        then coalesce(d.recovery_pending_at, now())
      else d.recovery_pending_at end,
    offline_since = case
      when d.connectivity_status = 'OFFLINE' and d.offline_notified_at is null
        and d.offline_claim_token is null then null else d.offline_since end
  where x.id = p_device_id
  returning x.last_seen_at, x.connectivity_status,
    x.recovery_pending_at is not null
  into last_seen_at, connectivity_status, recovery_pending;
  return next;
end; $$;

create or replace function public.claim_device_offline_notification(
  p_device_id uuid, p_claim_token uuid)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.devices set
    connectivity_status = 'OFFLINE', is_online = false,
    offline_since = case when connectivity_status = 'ONLINE'
      then last_seen_at + interval '60 seconds'
      else coalesce(offline_since, last_seen_at + interval '60 seconds') end,
    recovery_notified_at = null, recovery_pending_at = null,
    offline_claim_token = p_claim_token, offline_claimed_at = now()
  where id = p_device_id and last_seen_at < now() - interval '60 seconds'
    and offline_notified_at is null
    and (offline_claim_token is null or offline_claimed_at < now() - interval '2 minutes');
  return found;
end; $$;

create or replace function public.mark_device_offline_notification(
  p_device_id uuid, p_claim_token uuid)
returns timestamptz language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_sent timestamptz;
begin
  update public.devices set
    offline_notified_at = now(), offline_claim_token = null,
    offline_claimed_at = null,
    recovery_pending_at = case when connectivity_status = 'ONLINE'
      then coalesce(recovery_pending_at, last_seen_at) else recovery_pending_at end
  where id = p_device_id and offline_claim_token = p_claim_token
    and offline_notified_at is null
  returning offline_notified_at into v_sent;
  return v_sent;
end; $$;

create or replace function public.release_device_offline_claim(
  p_device_id uuid, p_claim_token uuid)
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.devices set offline_claim_token = null, offline_claimed_at = null
  where id = p_device_id and offline_claim_token = p_claim_token
    and offline_notified_at is null;
end; $$;

create or replace function public.claim_device_recovery_notification(
  p_device_id uuid, p_claim_token uuid)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.devices set recovery_claim_token = p_claim_token,
    recovery_claimed_at = now()
  where id = p_device_id and connectivity_status = 'ONLINE'
    and offline_notified_at is not null and recovery_pending_at is not null
    and recovery_notified_at is null
    and (recovery_claim_token is null or recovery_claimed_at < now() - interval '2 minutes');
  return found;
end; $$;

create or replace function public.mark_device_recovery_notification(
  p_device_id uuid, p_claim_token uuid)
returns timestamptz language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_sent timestamptz;
begin
  update public.devices set recovery_notified_at = now(),
    recovery_pending_at = null, recovery_claim_token = null,
    recovery_claimed_at = null, offline_since = null,
    offline_notified_at = null, offline_claim_token = null,
    offline_claimed_at = null
  where id = p_device_id and recovery_claim_token = p_claim_token
    and connectivity_status = 'ONLINE' and recovery_notified_at is null
  returning recovery_notified_at into v_sent;
  return v_sent;
end; $$;

create or replace function public.release_device_recovery_claim(
  p_device_id uuid, p_claim_token uuid)
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.devices set recovery_claim_token = null, recovery_claimed_at = null
  where id = p_device_id and recovery_claim_token = p_claim_token
    and recovery_notified_at is null;
end; $$;

revoke all on function public.record_device_heartbeat(uuid),
  public.claim_device_offline_notification(uuid, uuid),
  public.mark_device_offline_notification(uuid, uuid),
  public.release_device_offline_claim(uuid, uuid),
  public.claim_device_recovery_notification(uuid, uuid),
  public.mark_device_recovery_notification(uuid, uuid),
  public.release_device_recovery_claim(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.record_device_heartbeat(uuid),
  public.claim_device_offline_notification(uuid, uuid),
  public.mark_device_offline_notification(uuid, uuid),
  public.release_device_offline_claim(uuid, uuid),
  public.claim_device_recovery_notification(uuid, uuid),
  public.mark_device_recovery_notification(uuid, uuid),
  public.release_device_recovery_claim(uuid, uuid)
to service_role;
