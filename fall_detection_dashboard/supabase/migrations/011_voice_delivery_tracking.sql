-- API acceptance and physical delivery are different states.
alter table public.fall_events
  add column emergency_call_final_status text,
  add column emergency_call_initiated_at timestamptz,
  add column emergency_call_ringing_at timestamptz,
  add column emergency_call_answered_at timestamptz,
  add column emergency_call_completed_at timestamptz,
  add column emergency_call_retry_count smallint not null default 0,
  add column emergency_call_last_sid text,
  add column emergency_call_retry_after timestamptz,
  add constraint fall_events_call_final_check check (
    emergency_call_final_status is null or emergency_call_final_status in
      ('COMPLETED', 'NO_ANSWER', 'BUSY', 'FAILED', 'CANCELED')),
  add constraint fall_events_call_retry_check check (emergency_call_retry_count between 0 and 1),
  add constraint fall_events_call_last_sid_check check (
    emergency_call_last_sid is null or emergency_call_last_sid ~ '^CA[0-9a-fA-F]{32}$');

-- The first accepted SID stays immutable, including while a retry is REQUESTED.
alter table public.fall_events drop constraint fall_events_emergency_call_sid_check;
alter table public.fall_events add constraint fall_events_emergency_call_sid_check
  check ((emergency_call_status <> 'ACCEPTED' or emergency_call_sid is not null)
    and (emergency_call_sid is null or emergency_call_sid ~ '^CA[0-9a-fA-F]{32}$'));

-- Durable, private delivery audit/inbox. Handles callbacks arriving before the
-- Create Call response is persisted. Stores no phone numbers or credentials.
create table public.emergency_call_delivery_updates (
  call_sid text not null check (call_sid ~ '^CA[0-9a-fA-F]{32}$'),
  call_status text not null check (call_status in
    ('queued', 'initiated', 'ringing', 'in-progress', 'completed', 'busy',
     'failed', 'no-answer', 'canceled')),
  sequence_number integer not null default -1,
  observed_at timestamptz not null default now(),
  primary key (call_sid, call_status, sequence_number)
);
alter table public.emergency_call_delivery_updates enable row level security;
revoke all on public.emergency_call_delivery_updates from anon, authenticated;
grant all on public.emergency_call_delivery_updates to service_role;
create index fall_events_voice_retry_idx on public.fall_events(emergency_call_retry_after)
  where emergency_call_retry_after is not null;
create unique index fall_events_voice_latest_sid_idx on public.fall_events(emergency_call_last_sid)
  where emergency_call_last_sid is not null;

create or replace function public.record_emergency_call_status(
  p_call_sid text, p_call_status text, p_sequence integer default -1
)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_event public.fall_events%rowtype; v_final text; v_time timestamptz;
begin
  insert into public.emergency_call_delivery_updates(call_sid, call_status, sequence_number)
  values (p_call_sid, p_call_status, coalesce(p_sequence, -1))
  on conflict do nothing;
  select observed_at into v_time from public.emergency_call_delivery_updates
  where call_sid = p_call_sid and call_status = p_call_status
    and sequence_number = coalesce(p_sequence, -1);
  select * into v_event from public.fall_events
  where emergency_call_last_sid = p_call_sid
    and emergency_call_status = 'ACCEPTED'
    and emergency_call_claim_token is null for update;
  if not found then return false; end if;

  if p_call_status = 'initiated' or p_call_status = 'queued' then
    update public.fall_events set emergency_call_initiated_at =
      coalesce(emergency_call_initiated_at, v_time) where id = v_event.id;
  elsif p_call_status = 'ringing' then
    update public.fall_events set emergency_call_ringing_at =
      coalesce(emergency_call_ringing_at, v_time) where id = v_event.id;
  elsif p_call_status = 'in-progress' then
    update public.fall_events set emergency_call_answered_at =
      coalesce(emergency_call_answered_at, v_time), emergency_call_retry_after = null
    where id = v_event.id;
  else
    v_final := upper(replace(p_call_status, '-', '_'));
    -- A terminal duplicate cannot regress a connection or re-arm a retry.
    -- A late cancellation also disarms an unclaimed failure retry.
    if v_event.emergency_call_final_status is not null
      and (v_event.emergency_call_final_status = 'COMPLETED'
        or v_final not in ('COMPLETED', 'CANCELED')
        or v_event.emergency_call_final_status = v_final)
      then return true; end if;
    update public.fall_events
    set emergency_call_final_status = v_final,
        emergency_call_completed_at = v_time,
        emergency_call_answered_at = case when v_final = 'COMPLETED'
          then coalesce(emergency_call_answered_at, v_time) else emergency_call_answered_at end,
        emergency_call_retry_after = case
          when v_final in ('NO_ANSWER', 'BUSY', 'FAILED')
            and emergency_call_retry_count = 0 and emergency_call_attempts < 2
            and emergency_call_answered_at is null
          then now() + interval '15 seconds' else null end
    where id = v_event.id;
  end if;
  return true;
end;
$$;

create or replace function public.mark_emergency_call_accepted(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid, p_call_sid text
)
returns timestamptz language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_time timestamptz; v_update record;
begin
  if p_call_sid is null or p_call_sid !~ '^CA[0-9a-fA-F]{32}$' then return null; end if;
  update public.fall_events
  set emergency_call_status = 'ACCEPTED',
      emergency_call_sid = coalesce(emergency_call_sid, p_call_sid),
      emergency_call_last_sid = p_call_sid,
      emergency_call_final_status = null,
      emergency_call_initiated_at = null, emergency_call_ringing_at = null,
      emergency_call_answered_at = null, emergency_call_completed_at = null,
      emergency_call_retry_after = null,
      emergency_call_claim_token = null, emergency_call_claimed_at = null,
      emergency_call_error = null
  where id = p_event_id and device_id = p_device_id
    and status = 'CONFIRMED' and emergency_call_status = 'REQUESTED'
    and emergency_call_claim_token = p_claim_token
  returning emergency_call_requested_at into v_time;
  if v_time is null then return null; end if;
  for v_update in select * from public.emergency_call_delivery_updates
      where call_sid = p_call_sid order by observed_at, sequence_number loop
    perform public.record_emergency_call_status(p_call_sid,
      v_update.call_status, v_update.sequence_number);
  end loop;
  return v_time;
end;
$$;

create or replace function public.claim_emergency_call_retry(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid
)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  if p_claim_token is null then return false; end if;
  update public.fall_events
  set emergency_call_status = 'REQUESTED',
      emergency_call_requested_at = now(), emergency_call_retry_count = 1,
      emergency_call_retry_after = null, emergency_call_claim_token = p_claim_token,
      emergency_call_claimed_at = now(), emergency_call_error = null,
      emergency_call_attempts = emergency_call_attempts + 1
  where id = p_event_id and device_id = p_device_id and status = 'CONFIRMED'
    and emergency_call_status = 'ACCEPTED' and emergency_call_retry_count = 0
    and emergency_call_attempts < 2
    and emergency_call_final_status in ('NO_ANSWER', 'BUSY', 'FAILED')
    and emergency_call_answered_at is null and emergency_call_retry_after <= now();
  return found;
end;
$$;

revoke all on function public.record_emergency_call_status(text, text, integer)
  from public, anon, authenticated;
revoke all on function public.claim_emergency_call_retry(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.record_emergency_call_status(text, text, integer) to service_role;
grant execute on function public.claim_emergency_call_retry(uuid, uuid, uuid) to service_role;
