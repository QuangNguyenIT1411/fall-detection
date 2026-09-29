# Phase 13 — Activate emergency voice calls

The backend may be deployed without Twilio credentials. Missing credentials
leave voice calls disabled; Telegram, fall confirmation, and SOS remain active.
Do not add these values to Git, firmware, Flutter, or Vercel environment.

1. In [Twilio Console](https://console.twilio.com/), complete Voice onboarding.
   Find the **Account SID** and **Auth Token** under account credentials. Obtain
   a Voice-capable Twilio sender number; on a trial, use the sender provided by
   the **Try out Voice** flow. Verify the caregiver recipient number in the
   trial account. Confirm that calling its country is permitted.
2. Convert both phone numbers to E.164 (for Vietnam, `+84` followed by the
   national number without the initial `0`). Do not publish either number.
3. In the Supabase project `nuwcsqdedelgfkjpmrsj`, open **Edge Functions →
   Secrets** and add these four secrets:

   | Secret | Value |
   |---|---|
   | `TWILIO_ACCOUNT_SID` | Twilio Account SID (`AC...`) |
   | `TWILIO_AUTH_TOKEN` | Twilio Auth Token |
   | `TWILIO_FROM_NUMBER` | Voice-capable Twilio sender in E.164 |
   | `CAREGIVER_PHONE_NUMBER` | Verified caregiver recipient in E.164 |

   Optional: `EMERGENCY_VOICE_CALL_ENABLED=true` (set `false` to disable);
   `TWILIO_TTS_VOICE=Google.vi-VN-Standard-A` (default). A different voice
   must support Vietnamese (`vi-VN`). Keep all values only in Supabase secrets.
   For a trial account, add **`TWILIO_TRIAL_MODE=true`** manually. This uses
   Twilio's permitted `voice_text_to_speech` URL template, not inline TwiML.
   The automatic call may play a trial announcement/generic template and
   **must not be described as custom FallGuard Vietnamese speech**.
   For a full account, set `TWILIO_TRIAL_MODE=false` (also the default when
   absent) to retain the custom Vietnamese FALL/SOS messages. Invalid values
   safely disable voice; neither mode changes Telegram or call claims.
4. Create a **new** fall or manual SOS and inspect its `fall_events` row:
   `emergency_call_status` should become `ACCEPTED` with a Call SID if Twilio
   accepted the request. `ACCEPTED` does **not** mean the caregiver answered;
   check Twilio **Voice → Logs** for actual call progress.
5. Verify Telegram independently. For a fall, CANCEL before confirmation
   must produce no call. For SOS, Telegram and the call should start promptly.
   Repeat the same request ID to confirm neither channel intentionally sends
   twice. Test an unavailable Twilio account only with controlled mock tests;
   avoid generating unwanted real emergency calls.
   After switching modes, test with a **NEW** SOS. Leave previously failed
   events unchanged; do not manually reset their call status or attempts.

The backend makes at most two API attempts for a provider 5xx response.
HTTP 4xx, timeout, and lost-response network errors are not automatically
retried because Twilio might already have accepted the call. A crashed worker
can reclaim a two-minute lease once; consequently, true exactly-once delivery
cannot be guaranteed across a lost Twilio response. Do not treat the absence
of `ACCEPTED` as proof that no phone rang.

Twilio trial accounts can require a verified recipient, add a trial announcement,
limit geographic calling, or restrict custom TwiML. See the current
[trial guide](https://www.twilio.com/docs/usage/tutorials/how-to-use-your-free-trial-account)
and [Voice trial guide](https://www.twilio.com/docs/usage/trials/try-out-voice).
An upgraded account removes some trial restrictions, subject to the account's
phone-number capabilities and geographic permissions. Do not bypass trial
restrictions.

## Phase 13.1 — Delivery tracking and one safe retry

`ACCEPTED` means only that Create Call succeeded. It does not prove ringing,
answering, or delivery to a human. The UI displays API acceptance separately
from `emergency_call_final_status` and server-observed progress timestamps.
`COMPLETED` establishes a connection, which can be **voicemail or IVR**, not
necessarily a caregiver. No automatic retry follows an answered/completed call.

Apply `011_voice_delivery_tracking.sql`, deploy `twilio-call-status` and
`check-emergency-calls` with `--no-verify-jwt`, and redeploy `confirm-fall-event`
and `create-sos-event` to include the shared voice update. Call creation sets
the exact Supabase HTTPS callback URL automatically. There is no Twilio Console
webhook setting or new secret to enter. The callback validates every form field
using the official Twilio SDK and `X-Twilio-Signature` with the existing Auth
Token; untrusted Host/forwarded headers are never used for the signed URL.
Invalid signatures return 403 before database access. The audit inbox stores
only SID, status, sequence and server observation time, not phone numbers.

Full mode requests initiated/ringing/answered/completed callbacks and preserves
the fixed Vietnamese FALL/SOS TwiML. Trial sends **only To, From, Url,
StatusCallback**. The current [Trial docs](https://www.twilio.com/docs/usage/trials/try-out-voice)
do not list `StatusCallbackEvent` as allowed, so Trial uses the default terminal
callback plus read-only Call resource GET reconciliation every ~5 seconds while
the call is active. Very short ringing/answering phases can occur between reads:
missing progress is never invented. Completed still records a server-observed
connection/end time, not an exact provider answer timestamp. Reconciliation is
bounded to 15 minutes after the most recent request; signed callbacks remain
valid after that window.

Run `schedule_emergency_calls.sql` after deploying the functions. It reuses the
existing Phase 9 `DEVICE_OFFLINE_CRON_SECRET` and Vault entries
`device_offline_cron_secret` / `device_presence_project_url`. Cron checks every
5 seconds, invoking the checker only for active/new calls or a due retry.
No 15-second sleep runs inside an Edge Function. First NO_ANSWER/BUSY/FAILED
sets `retry_after = server now + 15 seconds`: the normal next checker tick starts
the final retry in approximately 15–20 seconds, plus network/cold-start delay.
The atomic database claim caps both delivery retries (one) and **total Create
Call requests (two)**, including the pre-existing API failure budget. A preceding
API failure can therefore consume the budget before a delivery retry is possible.
Lost responses/worker failures are not retried blindly. A delivery retry claim
is never reclaimed after a crash, prioritizing no extra physical calls over a
guarantee that the final attempt occurs under every failure scenario.

The retry uses the same event UUID; `emergency_call_sid` retains the first
accepted SID, `emergency_call_last_sid` identifies the active attempt, and
private audit rows retain both attempts. Callback-before-acceptance is replayed
when that SID is recorded. Stale first-call callbacks cannot overwrite the second
attempt. Telegram delivery/ACK fields are untouched and do not cancel retry.
Existing historical events are not reset, backfilled or automatically retried.

Manual physical test (caregiver consent required):

1. Use a **NEW** SOS from the physical button. Keep ESP32 firmware unchanged.
   Record the new event UUID and ensure Telegram arrives independently.
2. Watch the dashboard: initially “Đã gửi yêu cầu gọi”; it must not say answered
   until authoritative progress is available. On Trial, consult Voice Logs too
   if a progress phase was shorter than the checker interval.
3. Do not answer the first call. After Twilio reports no-answer, verify final
   NO_ANSWER and retry_after. You may ACK Telegram: the retry must still occur.
4. After approximately 15–20 seconds from the terminal observation, a second
   call should use the same event, a different latest SID and retry_count=1.
5. Answer the second call: verify answered_at and then COMPLETED/completed_at.
   A Trial announcement/template is expected, not custom Vietnamese speech.
6. In a separate controlled NEW SOS, ignore both calls; second NO_ANSWER must
   leave retry_after null. Wait another minute: there must be no third call.
7. In a separate NEW SOS, answer the first call; completion must never schedule
   retry. Do not reset an older failed event to conduct these tests.

Backend tests mock every HTTP request. The SQL regression test is rollback-only
and invokes no HTTP functions. No real test call is made during deployment.
