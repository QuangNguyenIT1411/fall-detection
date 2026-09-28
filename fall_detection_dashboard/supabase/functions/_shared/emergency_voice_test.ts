import { attemptEmergencyVoice, buildEmergencyTwiml, loadVoiceConfig,
  sendTwilioCall, type VoiceConfig } from "./emergency_voice.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

const eventId = "10000000-0000-4000-8000-000000000103";
const deviceId = "00000000-0000-4000-8000-000000000001";
const config: VoiceConfig = {
  accountSid: `AC${"a".repeat(32)}`,
  authToken: "fake-test-token",
  from: "+15551234567",
  to: "+84912345678",
  voice: "Google.vi-VN-Standard-A",
};
const callSid = `CA${"b".repeat(32)}`;
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

class VoiceDb {
  status: "DETECTED" | "CANCELLED" | "CONFIRMED" = "CONFIRMED";
  type: "FALL" | "SOS" = "FALL";
  callStatus: string | null = null;
  callError: string | null = null;
  sid: string | null = null;
  attempts = 0;
  claim: string | null = null;
  fetches = 0;

  client = this as unknown as SupabaseClient;
  from(table: string) {
    assert(table === "fall_events", "Unexpected table");
    return {
      select(_columns: string) { return this; },
      eq(_column: string, _value: string) { return this; },
      maybeSingle: async () => ({ data: {
        emergency_call_status: this.callStatus,
        emergency_call_error: this.callError,
        emergency_call_attempts: this.attempts,
      }, error: null }),
    };
  }
  async rpc(name: string, args: Record<string, string>) {
    if (name === "claim_emergency_call") {
      const allowed = this.status === "CONFIRMED" && this.attempts < 2 &&
        (this.callStatus === null ||
         (this.callStatus === "FAILED" && this.callError === "PROVIDER_UNAVAILABLE"));
      if (!allowed) return { data: false, error: null };
      this.callStatus = "REQUESTED";
      this.claim = args.p_claim_token;
      this.attempts++;
      return { data: true, error: null };
    }
    if (name === "mark_emergency_call_accepted") {
      assert(this.claim === args.p_claim_token, "Wrong claim token");
      this.sid = args.p_call_sid;
      this.callStatus = "ACCEPTED";
      this.claim = null;
      return { data: "2026-09-28T01:19:17Z", error: null };
    }
    if (name === "mark_emergency_call_failed") {
      assert(this.claim === args.p_claim_token, "Wrong claim token");
      this.callStatus = "FAILED";
      this.callError = args.p_error;
      this.claim = null;
      return { data: true, error: null };
    }
    throw new Error(`Unexpected RPC ${name}`);
  }
  successFetch: typeof fetch = async (_url, init) => {
    this.fetches++;
    assert(init?.method === "POST", "Not a POST");
    assert(String(init?.body).includes("To=%2B84912345678"), "Wrong form data");
    return Response.json({ sid: callSid }, { status: 201 });
  };
}

Deno.test("configuration is disabled safely when credentials are absent", () => {
  assert(loadVoiceConfig(() => undefined) === null, "Missing config enabled calls");
  assert(loadVoiceConfig((name) => name === "EMERGENCY_VOICE_CALL_ENABLED"
    ? "false" : "something") === null, "Explicit disable ignored");
  const values: Record<string, string> = {
    TWILIO_ACCOUNT_SID: config.accountSid, TWILIO_AUTH_TOKEN: config.authToken,
    TWILIO_FROM_NUMBER: config.from, CAREGIVER_PHONE_NUMBER: config.to,
  };
  assert(loadVoiceConfig((key) => values[key])?.voice === config.voice,
    "Vietnamese default voice missing");
});

Deno.test("FALL and SOS use distinct fixed Vietnamese TwiML", () => {
  const fall = buildEmergencyTwiml("FALL", config.voice);
  const sos = buildEmergencyTwiml("SOS", config.voice);
  assert(fall.includes("khả năng bị té ngã") && !fall.includes("nút SOS"), "Wrong FALL text");
  assert(sos.includes("nhấn nút SOS") && !sos.includes("khả năng bị té ngã"), "Wrong SOS text");
  assert(fall.includes('language="vi-VN"') && fall.includes('voice="Google.vi-VN-Standard-A"'),
    "Vietnamese TTS not configured");
  assert(sos.includes("<Hangup/>") && sos.split("<Say ").length === 3,
    "Emergency message not repeated twice");
  assert(!fall.includes(eventId) && !sos.includes(eventId), "UUID read aloud");
  assert(buildEmergencyTwiml("SOS", 'x"<&').includes('voice="x&quot;&lt;&amp;"'),
    "XML attribute escaping failed");
});

Deno.test("Twilio REST request uses Basic Auth/form and accepts a Call SID", async () => {
  let auth = "";
  const result = await sendTwilioCall("FALL", config, async (url, init) => {
    assert(String(url) === `https://api.twilio.com/2010-04-01/Accounts/${config.accountSid}/Calls.json`,
      "Wrong Twilio endpoint");
    auth = new Headers(init?.headers).get("authorization") ?? "";
    assert(new Headers(init?.headers).get("content-type") ===
      "application/x-www-form-urlencoded", "Wrong content type");
    const body = new URLSearchParams(init?.body as URLSearchParams);
    assert(body.get("To") === config.to && body.get("From") === config.from,
      "Wrong phone numbers");
    assert(body.get("Twiml")?.includes("<Say") === true, "Missing TwiML");
    return Response.json({ sid: callSid }, { status: 201 });
  });
  assert(result.ok && result.sid === callSid, "Twilio acceptance failed");
  assert(auth.startsWith("Basic ") && atob(auth.slice(6)) ===
    `${config.accountSid}:${config.authToken}`, "Wrong Basic Auth");
});

Deno.test("CONFIRMED FALL and SOS each call once; repeat is idempotent", async () => {
  for (const kind of ["FALL", "SOS"] as const) {
    const db = new VoiceDb();
    db.type = kind;
    const first = await attemptEmergencyVoice(db.client, eventId, deviceId,
      kind, { config, fetchImpl: db.successFetch });
    const again = await attemptEmergencyVoice(db.client, eventId, deviceId,
      kind, { config, fetchImpl: db.successFetch });
    assert(first.state === "accepted" && again.state === "already_accepted",
      `${kind} status incorrect`);
    assert(db.fetches === 1 && db.attempts === 1 && db.sid === callSid,
      `${kind} duplicated call`);
  }
});

Deno.test("DETECTED and CANCELLED are not eligible for calls", async () => {
  for (const status of ["DETECTED", "CANCELLED"] as const) {
    const db = new VoiceDb(); db.status = status;
    const result = await attemptEmergencyVoice(db.client, eventId, deviceId,
      "FALL", { config, fetchImpl: db.successFetch });
    assert(result.state === "in_progress" && db.fetches === 0,
      `${status} placed a call`);
  }
});

Deno.test("concurrent workers cannot intentionally place two calls", async () => {
  const db = new VoiceDb();
  let release = () => {};
  const pending = new Promise<void>((resolve) => { release = resolve; });
  let entered = () => {};
  const started = new Promise<void>((resolve) => { entered = resolve; });
  const slowFetch: typeof fetch = async () => {
    db.fetches++;
    entered();
    await pending;
    return Response.json({ sid: callSid }, { status: 201 });
  };
  const first = attemptEmergencyVoice(db.client, eventId, deviceId,
    "SOS", { config, fetchImpl: slowFetch });
  await started;
  const second = await attemptEmergencyVoice(db.client, eventId, deviceId,
    "SOS", { config, fetchImpl: slowFetch });
  assert(second.state === "in_progress" && db.fetches === 1,
    "Second worker made a call");
  release();
  assert((await first).state === "accepted", "First worker did not finish");
});

Deno.test("5xx retries at most twice; auth 4xx never retries", async () => {
  const db = new VoiceDb();
  const unavailable: typeof fetch = async () => {
    db.fetches++; return new Response("unavailable", { status: 503 });
  };
  const original = console.warn;
  console.warn = () => {};
  try {
    const first = await attemptEmergencyVoice(db.client, eventId, deviceId,
      "FALL", { config, fetchImpl: unavailable });
    const second = await attemptEmergencyVoice(db.client, eventId, deviceId,
      "FALL", { config, fetchImpl: unavailable });
    const third = await attemptEmergencyVoice(db.client, eventId, deviceId,
      "FALL", { config, fetchImpl: unavailable });
    assert(first.state === "failed" && first.retryable, "5xx first attempt not retryable");
    assert(second.state === "failed" && !second.retryable, "5xx retry not capped");
    assert(third.state === "failed" && db.fetches === 2, "Extra call after max attempts");
    const authDb = new VoiceDb();
    const unauthorized: typeof fetch = async () => {
      authDb.fetches++; return new Response("denied", { status: 401 });
    };
    const auth = await attemptEmergencyVoice(authDb.client, eventId, deviceId,
      "FALL", { config, fetchImpl: unauthorized });
    await attemptEmergencyVoice(authDb.client, eventId, deviceId,
      "FALL", { config, fetchImpl: unauthorized });
    assert(auth.state === "failed" && auth.error === "AUTH_ERROR" &&
      authDb.fetches === 1, "Auth failure retried");
  } finally { console.warn = original; }
});

Deno.test("timeout is ambiguous and not retried; no credentials enter logs", async () => {
  const db = new VoiceDb();
  const logs: string[] = [];
  const original = console.warn;
  console.warn = (...values: unknown[]) => { logs.push(values.join(" ")); };
  try {
    const timeout: typeof fetch = async () => {
      db.fetches++; throw new DOMException("fake-test-token", "TimeoutError");
    };
    const first = await attemptEmergencyVoice(db.client, eventId, deviceId,
      "SOS", { config, fetchImpl: timeout });
    await attemptEmergencyVoice(db.client, eventId, deviceId,
      "SOS", { config, fetchImpl: timeout });
    assert(first.state === "failed" && first.error === "TIMEOUT" &&
      !first.retryable && db.fetches === 1, "Ambiguous timeout retried");
    assert(!logs.join(" ").includes(config.authToken) &&
      !logs.join(" ").includes(config.to), "Credentials logged");
  } finally { console.warn = original; }
});
