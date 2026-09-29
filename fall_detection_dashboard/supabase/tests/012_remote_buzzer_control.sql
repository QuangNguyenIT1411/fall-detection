-- Rollback-only: no HTTP, MQTT or physical commands; uncommitted settings
-- cannot be observed by a concurrent device heartbeat.
begin isolation level repeatable read;
do $$
declare v_device uuid; v_row record; v_events_before jsonb; v_events_after jsonb;
begin
  if has_table_privilege('authenticated', 'public.devices', 'UPDATE')
     or has_function_privilege('authenticated', 'public.set_device_buzzer_enabled(boolean)', 'EXECUTE')
     or has_function_privilege('anon', 'public.set_device_buzzer_enabled(boolean)', 'EXECUTE')
     or not has_table_privilege('authenticated', 'public.devices', 'SELECT') then
    raise exception 'Caregiver read-only permissions changed';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public'
      and table_name='devices' and column_name='buzzer_enabled'
      and column_default='true' and is_nullable='NO') then
    raise exception 'Safe default / NOT NULL missing';
  end if;
  insert into public.devices(device_code, name)
  values ('buzzer-test-' || gen_random_uuid()::text, 'Rollback buzzer test') returning id into v_device;
  if not (select buzzer_enabled from public.devices where id=v_device) then
    raise exception 'New device default is not enabled';
  end if;
  if not exists (select 1 from public.devices where device_code='device01') then
    raise exception 'Existing device01 is required';
  end if;
  select jsonb_agg(to_jsonb(e) order by e.id) into v_events_before from public.fall_events e;
  select * into v_row from public.set_device_buzzer_enabled(false);
  if v_row.buzzer_enabled is distinct from false or v_row.buzzer_updated_at is null
     or (select buzzer_enabled from public.devices where device_code='device01') then
    raise exception 'OFF write failed';
  end if;
  if not (select buzzer_enabled from public.devices where id=v_device) then
    raise exception 'RPC updated another device';
  end if;
  select * into v_row from public.set_device_buzzer_enabled(true);
  if v_row.buzzer_enabled is distinct from true then raise exception 'ON write failed'; end if;
  select jsonb_agg(to_jsonb(e) order by e.id) into v_events_after from public.fall_events e;
  if v_events_before is distinct from v_events_after then raise exception 'Buzzer control modified events'; end if;
end $$;
rollback;
