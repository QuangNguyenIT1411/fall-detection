-- Physical sound preference only; existing alarm/event state is untouched.
alter table public.devices
  add column buzzer_enabled boolean not null default true,
  add column buzzer_updated_at timestamptz;

-- The browser still has SELECT only. This fixed-device RPC is service-only
-- and is called by set-buzzer-enabled after validating the caregiver session.
create or replace function public.set_device_buzzer_enabled(p_enabled boolean)
returns table (buzzer_enabled boolean, buzzer_updated_at timestamptz)
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  if p_enabled is null then raise exception 'Enabled must be a boolean'; end if;
  return query update public.devices as d
  set buzzer_enabled = p_enabled, buzzer_updated_at = clock_timestamp()
  where d.device_code = 'device01'
  returning d.buzzer_enabled, d.buzzer_updated_at;
end;
$$;
revoke all on function public.set_device_buzzer_enabled(boolean) from public, anon, authenticated;
grant execute on function public.set_device_buzzer_enabled(boolean) to service_role;
