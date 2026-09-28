-- Execute against the linked project after migration 010; no rows persist.
begin;
do $$
declare
  v_device uuid;
  v_detected uuid;
  v_cancelled uuid;
  v_confirmed uuid;
  v_sos uuid;
  v_claim uuid := gen_random_uuid();
  v_other_claim uuid := gen_random_uuid();
  v_sid text := 'CA' || repeat('a', 32);
begin
  if has_function_privilege('anon',
      'public.claim_emergency_call(uuid,uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated',
      'public.claim_emergency_call(uuid,uuid,uuid)', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.fall_events', 'UPDATE') then
    raise exception 'Public voice write access detected';
  end if;
  insert into public.devices(device_code, name)
  values ('voice-test-' || gen_random_uuid()::text, 'Voice migration test')
  returning id into v_device;
  insert into public.fall_events(device_id, detected_at, status)
  values (v_device, now(), 'DETECTED') returning id into v_detected;
  insert into public.fall_events(device_id, detected_at, status, cancelled_at)
  values (v_device, now(), 'CANCELLED', now()) returning id into v_cancelled;
  insert into public.fall_events(device_id, detected_at, status, confirmed_at)
  values (v_device, now(), 'CONFIRMED', now()) returning id into v_confirmed;
  select id into v_sos from public.create_device_sos_event(v_device, gen_random_uuid());

  if public.claim_emergency_call(v_detected, v_device, v_claim)
     or public.claim_emergency_call(v_cancelled, v_device, v_claim) then
    raise exception 'Non-confirmed event claimed a call';
  end if;
  if not public.claim_emergency_call(v_confirmed, v_device, v_claim)
     or public.claim_emergency_call(v_confirmed, v_device, v_other_claim) then
    raise exception 'Concurrent claim not exclusive';
  end if;
  if public.mark_emergency_call_accepted(v_confirmed, v_device,
      v_other_claim, v_sid) is not null then
    raise exception 'Wrong token marked call accepted';
  end if;
  if public.mark_emergency_call_accepted(v_confirmed, v_device,
      v_claim, v_sid) is null
     or public.claim_emergency_call(v_confirmed, v_device, v_other_claim) then
    raise exception 'Accepted call was duplicated';
  end if;
  if not public.claim_emergency_call(v_sos, v_device, v_claim)
     or not public.mark_emergency_call_failed(v_sos, v_device, v_claim,
        'PROVIDER_UNAVAILABLE')
     or not public.claim_emergency_call(v_sos, v_device, v_other_claim)
     or not public.mark_emergency_call_failed(v_sos, v_device,
        v_other_claim, 'PROVIDER_UNAVAILABLE')
     or public.claim_emergency_call(v_sos, v_device, gen_random_uuid()) then
    raise exception 'SOS retry did not stop after two attempts';
  end if;
end $$;
rollback;
