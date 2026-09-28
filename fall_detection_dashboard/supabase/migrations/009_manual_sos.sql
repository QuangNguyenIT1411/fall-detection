-- Phase 12: manual SOS shares the protected emergency-event history.
alter table public.fall_events
  add column event_type text not null default 'FALL',
  add column sos_request_key uuid;

alter table public.fall_events
  add constraint fall_events_event_type_check
  check (event_type in ('FALL', 'SOS')),
  add constraint fall_events_sos_shape_check
  check (
    (event_type = 'FALL' and sos_request_key is null)
    or (event_type = 'SOS' and sos_request_key is not null
        and status = 'CONFIRMED' and confirmed_at is not null)
  ),
  add constraint fall_events_sos_request_unique
  unique (device_id, sos_request_key);

-- The service-role-only RPC atomically creates or returns one row per physical
-- activation. No client timestamps or metric values are accepted.
create or replace function public.create_device_sos_event(
  p_device_id uuid, p_request_key uuid
)
returns public.fall_events
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare
  v_event public.fall_events%rowtype;
  v_now timestamptz := now();
begin
  if p_device_id is null or p_request_key is null then
    raise exception 'Missing SOS identity';
  end if;

  insert into public.fall_events (
    device_id, event_type, sos_request_key, status, detected_at,
    confirmed_at, notification_eligible
  ) values (
    p_device_id, 'SOS', p_request_key, 'CONFIRMED', v_now,
    v_now, true
  )
  on conflict (device_id, sos_request_key) do nothing
  returning * into v_event;

  if v_event.id is null then
    select * into v_event from public.fall_events
    where device_id = p_device_id and sos_request_key = p_request_key;
  end if;
  return v_event;
end;
$$;

revoke all on function public.create_device_sos_event(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.create_device_sos_event(uuid, uuid)
  to service_role;
