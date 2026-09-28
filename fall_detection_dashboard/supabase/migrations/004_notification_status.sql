-- Phase 7: server-owned Telegram delivery state. Dashboard remains read-only.
alter table public.fall_events
  add column if not exists notification_sent_at timestamptz,
  add column if not exists notification_claim_token uuid,
  add column if not exists notification_claimed_at timestamptz;

create or replace function public.claim_fall_notification(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid
)
returns boolean
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.fall_events
  set notification_claim_token = p_claim_token,
      notification_claimed_at = now()
  where id = p_event_id
    and device_id = p_device_id
    and status = 'CONFIRMED'
    and notification_sent_at is null
    and (
      notification_claim_token is null
      or notification_claimed_at < now() - interval '2 minutes'
    );
  return found;
end;
$$;

create or replace function public.mark_fall_notification_sent(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid
)
returns timestamptz
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_sent_at timestamptz;
begin
  update public.fall_events
  set notification_sent_at = now(),
      notification_claim_token = null,
      notification_claimed_at = null
  where id = p_event_id
    and device_id = p_device_id
    and status = 'CONFIRMED'
    and notification_sent_at is null
    and notification_claim_token = p_claim_token
  returning notification_sent_at into v_sent_at;
  return v_sent_at;
end;
$$;

create or replace function public.release_fall_notification_claim(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid
)
returns void
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.fall_events
  set notification_claim_token = null,
      notification_claimed_at = null
  where id = p_event_id
    and device_id = p_device_id
    and notification_sent_at is null
    and notification_claim_token = p_claim_token;
end;
$$;

revoke all on function public.claim_fall_notification(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.mark_fall_notification_sent(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.release_fall_notification_claim(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_fall_notification(uuid, uuid, uuid)
  to service_role;
grant execute on function public.mark_fall_notification_sent(uuid, uuid, uuid)
  to service_role;
grant execute on function public.release_fall_notification_claim(uuid, uuid, uuid)
  to service_role;
