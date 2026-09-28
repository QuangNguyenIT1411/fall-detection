-- Run only after provisioning device_presence_project_url and
-- device_offline_cron_secret in Vault. No secret values live in this file.
select cron.schedule('check-device-offline', '* * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'device_presence_project_url') ||
           '/functions/v1/check-device-offline',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets
                        where name = 'device_offline_cron_secret')),
    body := '{}'::jsonb
  );
$$);
