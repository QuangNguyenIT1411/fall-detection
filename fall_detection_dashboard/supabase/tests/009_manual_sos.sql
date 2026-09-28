-- Run against the linked project after migration 009. All test rows roll back.
begin;
do $$
declare
  v_device uuid;
  v_key uuid := gen_random_uuid();
  v_first public.fall_events%rowtype;
  v_again public.fall_events%rowtype;
  v_other public.fall_events%rowtype;
  v_ack timestamptz;
  v_duplicate_ack timestamptz;
begin
  if has_function_privilege('anon',
      'public.create_device_sos_event(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated',
      'public.create_device_sos_event(uuid,uuid)', 'EXECUTE') then
    raise exception 'SOS creation RPC exposed to public clients';
  end if;
  if not has_function_privilege('service_role',
      'public.create_device_sos_event(uuid,uuid)', 'EXECUTE') then
    raise exception 'SOS creation RPC unavailable to service role';
  end if;

  insert into public.devices(device_code, name)
  values ('sos-test-' || gen_random_uuid()::text, 'SOS migration test')
  returning id into v_device;

  select * into v_first from public.create_device_sos_event(v_device, v_key);
  select * into v_again from public.create_device_sos_event(v_device, v_key);
  select * into v_other from public.create_device_sos_event(v_device, gen_random_uuid());
  if v_first.id is null or v_first.id <> v_again.id
     or v_first.id = v_other.id then
    raise exception 'SOS idempotency failed';
  end if;
  if (select count(*) from public.fall_events where device_id = v_device) <> 2 then
    raise exception 'Unexpected duplicate SOS row';
  end if;
  if v_first.event_type <> 'SOS' or v_first.status <> 'CONFIRMED'
     or v_first.detected_at <> v_first.confirmed_at
     or abs(extract(epoch from (now() - v_first.detected_at))) > 5
     or v_first.peak_acc is not null or v_first.peak_gyro is not null
     or v_first.final_pose is not null or v_first.low_g_duration_ms is not null
     or v_first.low_g_to_impact_ms is not null then
    raise exception 'SOS shape or server timestamp invalid';
  end if;

  update public.fall_events set notification_sent_at = now()
  where id = v_first.id;
  select acknowledged_at into v_ack
    from public.acknowledge_fall_event(v_first.id, 'TELEGRAM');
  select acknowledged_at into v_duplicate_ack
    from public.acknowledge_fall_event(v_first.id, 'TELEGRAM');
  if v_ack is null or v_duplicate_ack <> v_ack then
    raise exception 'SOS ACK failed or duplicate changed timestamp';
  end if;
end $$;
rollback;
