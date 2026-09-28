import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

export type EmergencyKind = "FALL" | "SOS";
export type VoiceError = "AUTH_ERROR" | "PROVIDER_REJECTED" |
  "PROVIDER_UNAVAILABLE" | "NETWORK_ERROR" | "TIMEOUT" |
  "INVALID_RESPONSE";
export type VoiceResult =
  | { state: "disabled" | "already_accepted" | "in_progress" }
  | { state: "accepted"; sid: string }
  | { state: "failed"; error: VoiceError; retryable: boolean }
  | { state: "database_error" };

export interface VoiceConfig {
  accountSid: string;
  authToken: string;
  from: string;
  to: string;
  voice: string;
}

const SID = /^AC[0-9a-fA-F]{32}$/;
const CALL_SID = /^CA[0-9a-fA-F]{32}$/;
const E164 = /^\+[1-9]\d{1,14}$/;
const VOICE = /^[A-Za-z0-9.-]{1,80}$/;
let disabledLogged = false;

function disabled(reason: string): null {
  if (!disabledLogged) {
    console.info(`Emergency voice disabled: ${reason}`);
    disabledLogged = true;
  }
  return null;
}

export function loadVoiceConfig(
  env: (key: string) => string | undefined = (key) => Deno.env.get(key),
): VoiceConfig | null {
  if (env("EMERGENCY_VOICE_CALL_ENABLED") === "false") return disabled("by configuration");
  const accountSid = env("TWILIO_ACCOUNT_SID");
  const authToken = env("TWILIO_AUTH_TOKEN");
  const from = env("TWILIO_FROM_NUMBER");
  const to = env("CAREGIVER_PHONE_NUMBER");
  const voice = env("TWILIO_TTS_VOICE") ?? "Google.vi-VN-Standard-A";
  if (!accountSid || !authToken || !from || !to) return disabled("configuration unavailable");
  if (!SID.test(accountSid) || !E164.test(from) || !E164.test(to) ||
      !VOICE.test(voice)) {
    return disabled("configuration invalid");
  }
  return { accountSid, authToken, from, to, voice };
}

const fallMessage = "Đây là cảnh báo từ FallGuard. " +
  "Hệ thống phát hiện người cao tuổi có khả năng bị té ngã. " +
  "Vui lòng kiểm tra tình trạng người dùng ngay.";
const sosMessage = "Đây là cảnh báo khẩn cấp từ FallGuard. " +
  "Người dùng đã chủ động nhấn nút SOS yêu cầu trợ giúp. " +
  "Vui lòng kiểm tra tình trạng người dùng ngay.";

function xmlEscape(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll("'", "&apos;");
}

export function buildEmergencyTwiml(kind: EmergencyKind, voice: string): string {
  const message = xmlEscape(kind === "SOS" ? sosMessage : fallMessage);
  const say = `<Say language="vi-VN" voice="${xmlEscape(voice)}">${message}</Say>`;
  return `<?xml version="1.0" encoding="UTF-8"?><Response>${say}<Pause length="1"/>${say}<Hangup/></Response>`;
}

export async function sendTwilioCall(
  kind: EmergencyKind,
  config: VoiceConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<{ ok: true; sid: string } | { ok: false; error: VoiceError; retryable: boolean }> {
  const body = new URLSearchParams({
    To: config.to,
    From: config.from,
    Twiml: buildEmergencyTwiml(kind, config.voice),
  });
  let response: Response;
  try {
    response = await fetchImpl(
      `https://api.twilio.com/2010-04-01/Accounts/${config.accountSid}/Calls.json`,
      {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          authorization: `Basic ${btoa(`${config.accountSid}:${config.authToken}`)}`,
        },
        body,
        signal: AbortSignal.timeout(5000),
      },
    );
  } catch (error) {
    // No response can mean that Twilio accepted the request. Do not retry it.
    return { ok: false, error: error instanceof Error &&
        (error.name === "TimeoutError" || error.name === "AbortError")
        ? "TIMEOUT" : "NETWORK_ERROR", retryable: false };
  }
  if (!response.ok) {
    const error: VoiceError = response.status === 401 || response.status === 403
      ? "AUTH_ERROR"
      : response.status >= 500 ? "PROVIDER_UNAVAILABLE" : "PROVIDER_REJECTED";
    return { ok: false, error, retryable: error === "PROVIDER_UNAVAILABLE" };
  }
  try {
    const result: unknown = await response.json();
    const sid = typeof result === "object" && result !== null
      ? (result as Record<string, unknown>).sid : null;
    if (typeof sid === "string" && CALL_SID.test(sid)) {
      return { ok: true, sid };
    }
  } catch { /* safe category below */ }
  return { ok: false, error: "INVALID_RESPONSE", retryable: false };
}

export async function attemptEmergencyVoice(
  supabase: SupabaseClient,
  eventId: string,
  deviceId: string,
  kind: EmergencyKind,
  options: { config?: VoiceConfig | null; fetchImpl?: typeof fetch } = {},
): Promise<VoiceResult> {
  const config = options.config === undefined ? loadVoiceConfig() : options.config;
  if (!config) return { state: "disabled" };

  const claimToken = crypto.randomUUID();
  const claimArgs = {
    p_event_id: eventId, p_device_id: deviceId, p_claim_token: claimToken,
  };
  const { data: claimed, error: claimError } = await supabase.rpc(
    "claim_emergency_call", claimArgs,
  );
  if (claimError) {
    console.error("Emergency call claim failed");
    return { state: "database_error" };
  }
  if (!claimed) {
    const { data: latest, error } = await supabase.from("fall_events")
      .select("emergency_call_status, emergency_call_error, emergency_call_attempts").eq("id", eventId)
      .eq("device_id", deviceId).maybeSingle();
    if (error) return { state: "database_error" };
    if (latest?.emergency_call_status === "FAILED") {
      return { state: "failed", error: latest.emergency_call_error as VoiceError,
        retryable: latest.emergency_call_error === "PROVIDER_UNAVAILABLE" &&
          latest.emergency_call_attempts < 2 };
    }
    return { state: latest?.emergency_call_status === "ACCEPTED"
      ? "already_accepted" : "in_progress" };
  }

  const outcome = await sendTwilioCall(kind, config, options.fetchImpl);
  if (outcome.ok) {
    const { data, error } = await supabase.rpc("mark_emergency_call_accepted", {
      ...claimArgs, p_call_sid: outcome.sid,
    });
    if (error || !data) {
      console.error("Emergency call acceptance record failed");
      return { state: "database_error" };
    }
    return { state: "accepted", sid: outcome.sid };
  }
  const { data: marked, error: markError } = await supabase.rpc(
    "mark_emergency_call_failed", { ...claimArgs, p_error: outcome.error },
  );
  if (markError || !marked) {
    console.error("Emergency call failure record failed");
    return { state: "database_error" };
  }
  console.warn(`Emergency call failed: ${outcome.error}`);
  if (!outcome.retryable) {
    return { state: "failed", error: outcome.error, retryable: false };
  }
  const { data: latest } = await supabase.from("fall_events")
    .select("emergency_call_attempts").eq("id", eventId)
    .eq("device_id", deviceId).maybeSingle();
  return { state: "failed", error: outcome.error,
    retryable: (latest?.emergency_call_attempts ?? 2) < 2 };
}
