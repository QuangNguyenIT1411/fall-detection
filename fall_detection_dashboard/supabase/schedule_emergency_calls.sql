-- Run after migration 011 and both new Edge Functions are deployed.
-- Reuses Phase 9 Vault entries; never paste credentials into this file.
-- pg_cron >= 1.6 supports second intervals. No HTTP request when idle.
select cron.schedule('check-emergency-calls', '5 seconds', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'device_presence_project_url') || '/functions/v1/check-emergency-calls',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets
                        where name = 'device_offline_cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  ) where exists (
    select 1 from public.fall_events where emergency_call_status = 'ACCEPTED'
      and emergency_call_last_sid is not null and (
        (emergency_call_retry_count = 0 and emergency_call_retry_after <= now())
        or (emergency_call_final_status is null
          and emergency_call_requested_at >= now() - interval '15 minutes')
      )
  );
$$);
