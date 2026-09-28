-- Do not send a new Telegram alert for events confirmed before Phase 7.
-- New fall events remain eligible; failed sends keep eligibility for retry.
alter table public.fall_events
  add column if not exists notification_eligible boolean not null default true;

update public.fall_events
set notification_eligible = false
where status = 'CONFIRMED'
  and notification_sent_at is null;

create or replace function public.claim_fall_notification(
  p_event_id uuid, p_device_id uuid, p_claim_token uuid
)
returns boolean
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  update public.fall_events
  set notification_claim_token = p_claim_token,
      notification_claimed_at = now()
  where id = p_event_id
    and device_id = p_device_id
    and status = 'CONFIRMED'
    and notification_eligible
    and notification_sent_at is null
    and (
      notification_claim_token is null
      or notification_claimed_at < now() - interval '2 minutes'
    );
  return found;
end;
$$;

revoke all on function public.claim_fall_notification(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_fall_notification(uuid, uuid, uuid)
  to service_role;
