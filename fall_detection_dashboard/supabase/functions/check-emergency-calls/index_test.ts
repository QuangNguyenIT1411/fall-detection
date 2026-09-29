import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { handleCheckEmergencyCalls } from "./index.ts";
import type { VoiceConfig } from "../_shared/emergency_voice.ts";

const config: VoiceConfig = { accountSid: `AC${"a".repeat(32)}`, authToken: "fake-token",
  from: "+15551234567", to: "+15557654321", voice: "Google.vi-VN-Standard-A", trialMode: true,
  callbackUrl: "https://example.supabase.co/functions/v1/twilio-call-status" };
const sid = `CA${"b".repeat(32)}`;
const nextSid = `CA${"c".repeat(32)}`;
const cronSecret = "fake-checker-secret-not-a-real-secret";
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
function request(valid = true) {
  return new Request("https://example/check-emergency-calls", { method: "POST",
    headers: { "x-cron-secret": valid ? cronSecret : "invalid" } });
}

class Db {
  retryCount = 0;
  attempts = 1;
  status = "ACCEPTED";
  firstSid = sid;
  lastSid = sid;
  final: string | null = "NO_ANSWER";
  calls = 0;
  client = this as unknown as SupabaseClient;
  from(table: string) {
    assert(table === "fall_events", "Telegram table touched");
    const db = this;
    const result = { columns: "", select(columns: string) { this.columns = columns; return this; },
      eq(_key: string, _value: unknown) { return this; },
      is(_key: string, _value: unknown) { return this; },
      not(_key: string, _operator: string, _value: unknown) { return this; },
      gte(_key: string, _value: unknown) { return this; },
      lte(_key: string, _value: unknown) { return this; },
      order(_key: string) { return this; },
      limit(_count: number) { return Promise.resolve({ data: this.columns.includes("device_id")
        ? [{ id: "event", device_id: "device", event_type: "SOS" }]
        : db.final === null ? [{ emergency_call_last_sid: db.lastSid }] : [], error: null }); },
      maybeSingle() { return Promise.resolve({ data: { emergency_call_status: db.status,
        emergency_call_attempts: db.attempts }, error: null }); },
    };
    return result;
  }
  rpc(name: string, args: Record<string, unknown>) {
    if (name === "claim_emergency_call_retry") {
      const allowed = this.retryCount === 0 && this.status === "ACCEPTED" && this.final === "NO_ANSWER";
      if (allowed) { this.retryCount++; this.attempts++; this.status = "REQUESTED"; }
      return Promise.resolve({ data: allowed, error: null });
    }
    if (name === "mark_emergency_call_accepted") {
      this.lastSid = args.p_call_sid as string; this.status = "ACCEPTED"; this.final = null;
      return Promise.resolve({ data: "2026-09-29T00:00:00Z", error: null });
    }
    if (name === "record_emergency_call_status") {
      assert(args.p_call_sid === this.lastSid, "Wrong SID reconciled");
      return Promise.resolve({ data: true, error: null });
    }
    throw new Error("Unexpected mutation");
  }
  fetchImpl: typeof fetch = async (_url, init) => {
    if (init?.method === "GET") return Response.json({ sid: this.lastSid,
      account_sid: config.accountSid, status: "ringing" });
    this.calls++;
    assert(init?.method === "POST", "Unexpected request");
    const body = new URLSearchParams(init.body as URLSearchParams);
    assert(body.has("Url") && body.has("StatusCallback") && !body.has("Twiml"), "Trial retry regressed");
    return Response.json({ sid: nextSid }, { status: 201 });
  };
}

Deno.test("unauthorized checker never accesses database/Twilio", async () => {
  const result = await handleCheckEmergencyCalls(request(false), { cronSecret,
    config, fetchImpl: () => { throw new Error("Unexpected call"); } });
  assert(result.status === 401, "Unauthenticated checker accepted");
});

Deno.test("overlapping scheduled checkers retry once on same event, never Telegram or third call", async () => {
  const db = new Db();
  const deps = { cronSecret, config, supabase: db.client, fetchImpl: db.fetchImpl };
  await Promise.all([handleCheckEmergencyCalls(request(), deps), handleCheckEmergencyCalls(request(), deps)]);
  assert(db.calls === 1 && db.retryCount === 1 && db.attempts === 2, "Extra retry created");
  assert(db.firstSid === sid && db.lastSid === nextSid, "First/new SID not preserved");
  db.final = "NO_ANSWER";
  await handleCheckEmergencyCalls(request(), deps);
  assert(db.calls === 1, "Third physical call created");
});

Deno.test("Trial reconciliation polls current call via GET; completed call never retries", async () => {
  const db = new Db(); db.final = null;
  await handleCheckEmergencyCalls(request(), { cronSecret, config,
    supabase: db.client, fetchImpl: db.fetchImpl });
  assert(db.calls === 0, "Active call retried");
  db.final = "COMPLETED";
  await handleCheckEmergencyCalls(request(), { cronSecret, config,
    supabase: db.client, fetchImpl: db.fetchImpl });
  assert(db.calls === 0, "Completed call retried");
});
