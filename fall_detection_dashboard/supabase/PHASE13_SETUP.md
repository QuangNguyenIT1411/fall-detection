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
