import twilio from "npm:twilio@6.1.2";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { handleTwilioCallStatus } from "./index.ts";

const token = "fake-signature-test-token";
const accountSid = `AC${"a".repeat(32)}`;
const callSid = `CA${"b".repeat(32)}`;
const publicUrl = "https://example.supabase.co/functions/v1/twilio-call-status";
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
function request(status: string, signatureValid = true, signedUrl = publicUrl) {
  const fields = { AccountSid: accountSid, CallSid: callSid, CallStatus: status,
    SequenceNumber: "2", To: "+15551234567", From: "+15557654321" };
  const signature = signatureValid
    ? twilio.getExpectedTwilioSignature(token, signedUrl, fields) : "invalid";
  return new Request(publicUrl, { method: "POST", headers: {
    "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": signature,
  }, body: new URLSearchParams(fields) });
}

for (const status of ["initiated", "ringing", "in-progress", "completed",
  "no-answer", "busy", "failed", "canceled"]) {
  Deno.test(`valid signed ${status} callback forwards SID/status only`, async () => {
    let calls = 0;
    const supabase = { rpc: (name: string, args: Record<string, unknown>) => {
      calls++;
      assert(name === "record_emergency_call_status", "Wrong RPC");
      assert(args.p_call_sid === callSid && args.p_call_status === status && args.p_sequence === 2,
        "Wrong callback data");
      assert(Object.keys(args).length === 3, "Phone fields persisted");
      return Promise.resolve({ data: true, error: null });
    } } as unknown as SupabaseClient;
    const result = await handleTwilioCallStatus(request(status), { token, accountSid, publicUrl, supabase });
    assert(result.status === 204 && calls === 1, "Valid callback rejected");
  });
}

Deno.test("invalid signature, altered URL/body/account rejected before database access", async () => {
  const supabase = { rpc: () => { throw new Error("Unauthenticated database access"); } } as unknown as SupabaseClient;
  for (const input of [request("completed", false), request("completed", true, `${publicUrl}?forged=1`)]) {
    const result = await handleTwilioCallStatus(input, { token, accountSid, publicUrl, supabase });
    assert(result.status === 403, "Invalid signature accepted");
  }
  const tampered = request("completed");
  const altered = new Request(publicUrl, { method: "POST", headers: tampered.headers,
    body: (await tampered.text()).replace("completed", "no-answer") });
  assert((await handleTwilioCallStatus(altered, { token, accountSid, publicUrl, supabase })).status === 403,
    "Altered signed body accepted");
  assert((await handleTwilioCallStatus(request("completed"), {
    token, accountSid: `AC${"c".repeat(32)}`, publicUrl, supabase,
  })).status === 403, "Different account accepted");
});

Deno.test("database failure exposes no token/phone/provider payload", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...values) => logs.push(values.join(" "));
  try {
    const supabase = { rpc: () => Promise.resolve({ data: null,
      error: { message: `${token} +15551234567 Authorization` } }) } as unknown as SupabaseClient;
    const result = await handleTwilioCallStatus(request("completed"), { token, accountSid, publicUrl, supabase });
    assert(result.status === 503 && await result.text() === "", "Raw error exposed");
    assert(logs.join("") === "Voice delivery update failed", "Sensitive data logged");
  } finally { console.error = original; }
});

Deno.test("unknown/pre-acceptance SID is acknowledged for durable inbox replay", async () => {
  const supabase = { rpc: () => Promise.resolve({ data: false, error: null }) } as unknown as SupabaseClient;
  assert((await handleTwilioCallStatus(request("ringing"), {
    token, accountSid, publicUrl, supabase,
  })).status === 204, "Early callback rejected");
});
