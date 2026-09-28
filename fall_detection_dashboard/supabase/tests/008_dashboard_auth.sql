-- Run against the linked project after migration 008. Fails on privilege or RLS drift.
do $$
begin
  if has_table_privilege('anon', 'public.devices', 'SELECT')
     or has_table_privilege('anon', 'public.fall_events', 'SELECT') then
    raise exception 'anon can read dashboard tables';
  end if;
  if not has_table_privilege('authenticated', 'public.devices', 'SELECT')
     or not has_table_privilege('authenticated', 'public.fall_events', 'SELECT') then
    raise exception 'authenticated cannot read dashboard tables';
  end if;
  if has_table_privilege('authenticated', 'public.fall_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fall_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.fall_events', 'DELETE')
     or has_table_privilege('authenticated', 'public.fall_events', 'TRUNCATE') then
    raise exception 'authenticated can write fall_events';
  end if;
  if has_table_privilege('authenticated', 'public.device_credentials', 'SELECT')
     or has_table_privilege('anon', 'public.device_credentials', 'SELECT') then
    raise exception 'device_credentials is exposed';
  end if;
  if (select count(*) from pg_policies
      where schemaname = 'public' and tablename in ('devices', 'fall_events')
      and cmd = 'SELECT' and 'anon' = any(roles)) > 0 then
    raise exception 'anonymous SELECT RLS policy remains';
  end if;
  if (select count(*) from pg_policies
      where schemaname = 'public' and tablename in ('devices', 'fall_events')
      and cmd = 'SELECT' and 'authenticated' = any(roles)) <> 2 then
    raise exception 'authenticated SELECT RLS policies missing';
  end if;
end $$;
