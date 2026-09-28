-- Phase 10: Telegram is the only acknowledgement write path. Public dashboard
-- roles retain read-only access to fall_events.
alter table public.fall_events
  add column if not exists acknowledged_at timestamptz,
  add column if not exists acknowledged_via text;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'fall_events_acknowledgement_check'
      and conrelid = 'public.fall_events'::regclass
  ) then
    alter table public.fall_events
      add constraint fall_events_acknowledgement_check check (
        (acknowledged_at is null and acknowledged_via is null)
        or (status = 'CONFIRMED' and acknowledged_at is not null
            and acknowledged_via = 'TELEGRAM')
      );
  end if;
end $$;

create or replace function public.acknowledge_fall_event(
  p_event_id uuid, p_via text
)
returns table (acknowledged_at timestamptz, acknowledged_via text,
               already_acknowledged boolean)
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
declare v_event public.fall_events%rowtype;
begin
  if p_via <> 'TELEGRAM' then return; end if;
  select * into v_event from public.fall_events
  where id = p_event_id for update;
  if not found or v_event.status <> 'CONFIRMED'
    or v_event.notification_sent_at is null then
    return;
  end if;
  if v_event.acknowledged_at is not null then
    acknowledged_at := v_event.acknowledged_at;
    acknowledged_via := v_event.acknowledged_via;
    already_acknowledged := true;
    return next;
    return;
  end if;
  update public.fall_events as e
  set acknowledged_at = now(), acknowledged_via = 'TELEGRAM'
  where e.id = p_event_id
  returning e.acknowledged_at, e.acknowledged_via
  into acknowledged_at, acknowledged_via;
  already_acknowledged := false;
  return next;
end; $$;

revoke all on function public.acknowledge_fall_event(uuid, text)
  from public, anon, authenticated;
grant execute on function public.acknowledge_fall_event(uuid, text)
  to service_role;
