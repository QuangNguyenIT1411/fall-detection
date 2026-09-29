-- Synthetic RPC assertions only. No Edge invocation or HTTP calls; all fixtures
-- and delivery audit records are rolled back. Never touch a real event.
begin;
do $$
declare
  v_device uuid; v_event uuid; v_claim uuid; v_second uuid;
  v_sid text; v_next text; v_kind text; v_status text;
  v_row public.fall_events%rowtype; v_due timestamptz;
begin
  if has_function_privilege('anon', 'public.record_emergency_call_status(text,text,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.claim_emergency_call_retry(uuid,uuid,uuid)', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.emergency_call_delivery_updates', 'SELECT') then
    raise exception 'Private voice delivery permissions are unsafe';
  end if;
  insert into public.devices(device_code, name)
  values ('voice-delivery-test-' || gen_random_uuid()::text, 'Rollback-only delivery test')
  returning id into v_device;

  foreach v_kind in array array['FALL', 'SOS'] loop
    foreach v_status in array array['no-answer', 'busy', 'failed'] loop
      v_claim := gen_random_uuid(); v_second := gen_random_uuid();
      v_sid := 'CA' || replace(gen_random_uuid()::text, '-', '');
      v_next := 'CA' || replace(gen_random_uuid()::text, '-', '');
      insert into public.fall_events(device_id, event_type, sos_request_key, detected_at, status, confirmed_at,
        notification_sent_at, acknowledged_at, acknowledged_via)
      values (v_device, v_kind, case when v_kind = 'SOS' then gen_random_uuid() else null end,
        now(), 'CONFIRMED', now(), now(), now(), 'TELEGRAM')
      returning id into v_event;
      if not public.claim_emergency_call(v_event, v_device, v_claim)
         or public.mark_emergency_call_accepted(v_event, v_device, v_claim, v_sid) is null then
        raise exception 'Initial call not accepted';
      end if;
      perform public.record_emergency_call_status(v_sid, 'initiated', 0);
      perform public.record_emergency_call_status(v_sid, 'ringing', 1);
      perform public.record_emergency_call_status(v_sid, v_status, 2);
      select * into v_row from public.fall_events where id = v_event;
      v_due := v_row.emergency_call_retry_after;
      if v_row.emergency_call_final_status <> upper(replace(v_status, '-', '_'))
         or v_row.emergency_call_initiated_at is null or v_row.emergency_call_ringing_at is null
         or v_row.emergency_call_completed_at is null or v_due is null
         or v_due <> now() + interval '15 seconds'
         or v_row.emergency_call_retry_count <> 0 then
        raise exception 'First terminal failure did not schedule exactly one retry';
      end if;
      perform public.record_emergency_call_status(v_sid, v_status, 2);
      if (select emergency_call_retry_after from public.fall_events where id = v_event) <> v_due
         or public.claim_emergency_call_retry(v_event, v_device, v_second) then
        raise exception 'Duplicate callback or premature retry';
      end if;
      update public.fall_events set emergency_call_retry_after = now() - interval '1 second'
      where id = v_event;
      if not public.claim_emergency_call_retry(v_event, v_device, v_second)
         or public.claim_emergency_call_retry(v_event, v_device, gen_random_uuid())
         or public.claim_emergency_call(v_event, v_device, gen_random_uuid()) then
        raise exception 'Retry not exclusive or incorrectly depends on Telegram ACK';
      end if;
      -- First-call callbacks during or after retry cannot mutate the new attempt.
      if public.record_emergency_call_status(v_sid, 'in-progress', 3) then
        raise exception 'Stale callback applied during retry claim';
      end if;
      if public.mark_emergency_call_accepted(v_event, v_device, v_second, v_next) is null
         or public.record_emergency_call_status(v_sid, 'completed', 4) then
        raise exception 'New SID not accepted or stale SID updated second attempt';
      end if;
      select * into v_row from public.fall_events where id = v_event;
      if v_row.emergency_call_sid <> v_sid or v_row.emergency_call_last_sid <> v_next
         or v_row.emergency_call_final_status is not null or v_row.emergency_call_answered_at is not null
         or v_row.emergency_call_retry_count <> 1 or v_row.emergency_call_attempts <> 2 then
        raise exception 'Retry SID/state/attempt cap incorrect';
      end if;
      perform public.record_emergency_call_status(v_next, v_status, 2);
      select * into v_row from public.fall_events where id = v_event;
      if v_row.emergency_call_final_status <> upper(replace(v_status, '-', '_'))
         or v_row.emergency_call_retry_after is not null
         or v_row.notification_sent_at is null or v_row.acknowledged_at is null
         or public.claim_emergency_call_retry(v_event, v_device, gen_random_uuid()) then
        raise exception 'Second failure schedules a third call or changes Telegram';
      end if;
    end loop;
  end loop;

  foreach v_status in array array['completed', 'canceled', 'in-progress'] loop
    v_claim := gen_random_uuid(); v_sid := 'CA' || replace(gen_random_uuid()::text, '-', '');
    insert into public.fall_events(device_id, detected_at, status, confirmed_at)
    values (v_device, now(), 'CONFIRMED', now()) returning id into v_event;
    perform public.claim_emergency_call(v_event, v_device, v_claim);
    -- Callback-before-acceptance race is durably replayed on acceptance.
    if public.record_emergency_call_status(v_sid, v_status, 1) then
      raise exception 'Unknown SID updated an event';
    end if;
    perform public.mark_emergency_call_accepted(v_event, v_device, v_claim, v_sid);
    select * into v_row from public.fall_events where id = v_event;
    if v_row.emergency_call_retry_after is not null then raise exception 'Success/canceled retry'; end if;
    if v_status = 'in-progress' then
      if v_row.emergency_call_answered_at is null then raise exception 'Answer time missing'; end if;
      perform public.record_emergency_call_status(v_sid, 'failed', 2);
      if (select emergency_call_retry_after from public.fall_events where id = v_event) is not null then
        raise exception 'Answered call scheduled retry';
      end if;
    elsif v_row.emergency_call_final_status <> upper(v_status)
       or v_row.emergency_call_completed_at is null then
      raise exception 'Terminal callback not replayed';
    end if;
    if v_status = 'completed' and v_row.emergency_call_answered_at is null then
      raise exception 'Completed connection time missing';
    end if;
  end loop;

  -- A late authoritative answer cancels an unclaimed failure retry.
  v_claim := gen_random_uuid(); v_sid := 'CA' || replace(gen_random_uuid()::text, '-', '');
  insert into public.fall_events(device_id, detected_at, status, confirmed_at)
  values (v_device, now(), 'CONFIRMED', now()) returning id into v_event;
  perform public.claim_emergency_call(v_event, v_device, v_claim);
  perform public.mark_emergency_call_accepted(v_event, v_device, v_claim, v_sid);
  perform public.record_emergency_call_status(v_sid, 'no-answer', 2);
  perform public.record_emergency_call_status(v_sid, 'in-progress', 1);
  select * into v_row from public.fall_events where id = v_event;
  if v_row.emergency_call_answered_at is null or v_row.emergency_call_retry_after is not null then
    raise exception 'Late answer did not prevent retry';
  end if;

  v_claim := gen_random_uuid(); v_sid := 'CA' || replace(gen_random_uuid()::text, '-', '');
  insert into public.fall_events(device_id, detected_at, status, confirmed_at)
  values (v_device, now(), 'CONFIRMED', now()) returning id into v_event;
  perform public.claim_emergency_call(v_event, v_device, v_claim);
  perform public.mark_emergency_call_accepted(v_event, v_device, v_claim, v_sid);
  perform public.record_emergency_call_status(v_sid, 'no-answer', 2);
  perform public.record_emergency_call_status(v_sid, 'canceled', 3);
  select * into v_row from public.fall_events where id = v_event;
  if v_row.emergency_call_final_status <> 'CANCELED' or v_row.emergency_call_retry_after is not null then
    raise exception 'Late cancellation did not prevent retry';
  end if;

  -- Pre-13.1 historical ACCEPTED rows are not reactivated by this migration.
  v_sid := 'CA' || replace(gen_random_uuid()::text, '-', '');
  insert into public.fall_events(device_id, detected_at, status, confirmed_at,
    emergency_call_status, emergency_call_sid, emergency_call_attempts)
  values (v_device, now(), 'CONFIRMED', now(), 'ACCEPTED', v_sid, 1) returning id into v_event;
  if public.record_emergency_call_status(v_sid, 'no-answer', 2) then
    raise exception 'Historical call reactivated';
  end if;
  if (select emergency_call_retry_after from public.fall_events where id = v_event) is not null then
    raise exception 'Historical event scheduled retry';
  end if;
end $$;
rollback;
