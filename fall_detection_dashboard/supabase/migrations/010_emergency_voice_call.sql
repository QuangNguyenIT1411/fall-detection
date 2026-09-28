-- Phase 13: independent, server-owned outbound voice-call state.
alter table public.fall_events
  add column emergency_call_requested_at timestamptz,
  add column emergency_call_sid text,
  add column emergency_call_status text,
  add column emergency_call_claim_token uuid,
  add column emergency_call_claimed_at timestamptz,
  add column emergency_call_error text,
  add column emergency_call_attempts smallint not null default 0;

alter table public.fall_events
  add constraint fall_events_emergency_call_status_check
    check (emergency_call_status is null or
           emergency_call_status in ('REQUESTED', 'ACCEPTED', 'FAILED')),
  add constraint fall_events_emergency_call_attempts_check
    check (emergency_call_attempts between 0 and 2),
  add constraint fall_events_emergency_call_eligible_check
    check (emergency_call_status is null or
           (status = 'CONFIRMED' and event_type in ('FALL', 'SOS'))),
  add constraint fall_events_emergency_call_sid_check
    check ((emergency_call_status = 'ACCEPTED' and
            emergency_call_sid is not null and
            emergency_call_sid ~ '^CA[0-9a-fA-F]{32}$') or
           (emergency_call_status is distinct from 'ACCEPTED' and
            emergency_call_sid is null)),
  add constraint fall_events_emergency_call_error_check
    check (emergency_call_error is null or
           (emergency_call_status = 'FAILED' and
            emergency_call_error in ('CONFIG_ERROR', 'AUTH_ERROR',
             'PROVIDER_REJECTED', 'PROVIDER_UNAVAILABLE', 'NETWORK_ERROR',
             'TIMEOUT', 'INVALID_RESPONSE', 'DATABASE_ERROR')));

-- A single atomic UPDATE claims the event. A stale lease can be reclaimed
-- once, but an external API's accepted-yet-lost response cannot be deduped.
create or replace function public.claim_emergency_call(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid
)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  if p_claim_token is null then return false; end if;
  update public.fall_events
  set emergency_call_status = 'REQUESTED',
      emergency_call_requested_at = now(),
      emergency_call_claim_token = p_claim_token,
      emergency_call_claimed_at = now(),
      emergency_call_error = null,
      emergency_call_attempts = emergency_call_attempts + 1
  where id = p_event_id and device_id = p_device_id
    and status = 'CONFIRMED' and event_type in ('FALL', 'SOS')
    and emergency_call_sid is null
    and emergency_call_attempts < 2
    and (
      emergency_call_status is null
      or (emergency_call_status = 'FAILED'
          and emergency_call_error = 'PROVIDER_UNAVAILABLE')
      or (emergency_call_status = 'REQUESTED'
          and emergency_call_claimed_at < now() - interval '2 minutes')
    );
  return found;
end;
$$;

create or replace function public.mark_emergency_call_accepted(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid, p_call_sid text
)
returns timestamptz language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_requested_at timestamptz;
begin
  if p_call_sid is null or p_call_sid !~ '^CA[0-9a-fA-F]{32}$' then
    return null;
  end if;
  update public.fall_events
  set emergency_call_status = 'ACCEPTED',
      emergency_call_sid = p_call_sid,
      emergency_call_claim_token = null,
      emergency_call_claimed_at = null,
      emergency_call_error = null
  where id = p_event_id and device_id = p_device_id
    and status = 'CONFIRMED' and emergency_call_status = 'REQUESTED'
    and emergency_call_claim_token = p_claim_token
  returning emergency_call_requested_at into v_requested_at;
  return v_requested_at;
end;
$$;

create or replace function public.mark_emergency_call_failed(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid, p_error text
)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  if p_error is null or p_error not in ('CONFIG_ERROR', 'AUTH_ERROR', 'PROVIDER_REJECTED',
      'PROVIDER_UNAVAILABLE', 'NETWORK_ERROR', 'TIMEOUT',
      'INVALID_RESPONSE', 'DATABASE_ERROR') then return false; end if;
  update public.fall_events
  set emergency_call_status = 'FAILED',
      emergency_call_error = p_error,
      emergency_call_claim_token = null,
      emergency_call_claimed_at = null
  where id = p_event_id and device_id = p_device_id
    and emergency_call_status = 'REQUESTED'
    and emergency_call_claim_token = p_claim_token;
  return found;
end;
$$;

revoke all on function public.claim_emergency_call(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.mark_emergency_call_accepted(uuid, uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.mark_emergency_call_failed(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_emergency_call(uuid, uuid, uuid)
  to service_role;
grant execute on function public.mark_emergency_call_accepted(uuid, uuid, uuid, text)
  to service_role;
grant execute on function public.mark_emergency_call_failed(uuid, uuid, uuid, text)
  to service_role;
