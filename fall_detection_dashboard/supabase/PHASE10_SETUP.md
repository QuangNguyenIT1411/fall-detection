# Phase 10: Telegram caregiver acknowledgement

`007_fall_acknowledgement.sql` adds nullable `acknowledged_at` and
`acknowledged_via` to `fall_events`. The service-role-only RPC locks the event
row, accepts only an already-notified `CONFIRMED` event, and never changes an
existing acknowledgement timestamp. The public Flutter site remains read-only.

Deploy from `fall_detection_dashboard`:

```powershell
npx -y supabase@latest db push
npx -y supabase@latest functions deploy telegram-webhook --no-verify-jwt
```

Telegram must be configured with a webhook secret. The plaintext bot token is
not retrievable from Supabase secrets. Run the following **locally** in
PowerShell; input is masked. Do not paste token/secret into Git or chat:
Deploy `confirm-fall-event` only after `setWebhook` succeeds, so new fall
messages never contain an unusable button.

```powershell
$env:TELEGRAM_BOT_TOKEN = Read-Host 'Telegram bot token' -MaskInput
$env:TELEGRAM_WEBHOOK_SECRET = [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
npx -y supabase@latest secrets set "TELEGRAM_WEBHOOK_SECRET=$env:TELEGRAM_WEBHOOK_SECRET"
$webhookBody = @{
  url = 'https://nuwcsqdedelgfkjpmrsj.supabase.co/functions/v1/telegram-webhook'
  secret_token = $env:TELEGRAM_WEBHOOK_SECRET
  allowed_updates = @('callback_query')
} | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$env:TELEGRAM_BOT_TOKEN/setWebhook" -ContentType 'application/json' -Body $webhookBody
Invoke-RestMethod -Uri "https://api.telegram.org/bot$env:TELEGRAM_BOT_TOKEN/getWebhookInfo"
npx -y supabase@latest functions deploy confirm-fall-event --no-verify-jwt
Remove-Item Env:TELEGRAM_BOT_TOKEN,Env:TELEGRAM_WEBHOOK_SECRET
```

`getWebhookInfo` should show the exact URL above and no recent delivery error.
Existing fall alerts have no new button; trigger a **new** confirmed fall after
deploy. Its Telegram message should contain `✅ Đã nhận cảnh báo`. Press it
once, verify `fall_events.acknowledged_at` uses server time and
`acknowledged_via = TELEGRAM`, then refresh Flutter History or reopen Event
Detail. The inline button should disappear. A duplicate callback keeps the
original database timestamp.

If Telegram `answerCallbackQuery` or `editMessageReplyMarkup` fails after the
database write, the database acknowledgement remains authoritative. Check
Edge Function logs; do not manually reset `acknowledged_at`.
