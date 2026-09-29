import twilio from "npm:twilio@6.1.2";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { serverSecret } from "../_shared/device_auth.ts";

type Dependencies = {
  token?: string;
  accountSid?: string;
  publicUrl?: string;
  supabase?: SupabaseClient;
};
const SID = /^CA[0-9a-fA-F]{32}$/;
const STATUSES = new Set(["queued", "initiated", "ringing", "in-progress",
  "completed", "busy", "failed", "no-answer", "canceled"]);

export async function handleTwilioCallStatus(
  request: Request, dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  const token = dependencies.token ?? Deno.env.get("TWILIO_AUTH_TOKEN");
  const accountSid = dependencies.accountSid ?? Deno.env.get("TWILIO_ACCOUNT_SID");
  const projectUrl = Deno.env.get("SUPABASE_URL");
  const publicUrl = dependencies.publicUrl ?? (projectUrl
    ? `${projectUrl.replace(/\/$/, "")}/functions/v1/twilio-call-status` : null);
  if (!token || !accountSid || !publicUrl) return new Response(null, { status: 503 });
  if (!request.headers.get("content-type")?.startsWith("application/x-www-form-urlencoded")) {
    return new Response(null, { status: 403 });
  }
  const raw = await request.text();
  if (raw.length > 16384) return new Response(null, { status: 413 });
  const params = new URLSearchParams(raw);
  const fields: Record<string, string> = Object.create(null);
  for (const [key, value] of params) {
    if (key in fields) return new Response(null, { status: 403 });
    fields[key] = value;
  }
  // Validate all submitted fields against the exact configured public URL.
  // Never trust Host/forwarded headers to reconstruct the signed URL.
  const signature = request.headers.get("x-twilio-signature") ?? "";
  let valid = false;
  try { valid = twilio.validateRequest(token, signature, publicUrl, fields); }
  catch { /* malformed signatures are rejected without logging input */ }
  if (!valid ||
      fields.AccountSid !== accountSid) return new Response(null, { status: 403 });
  if (!SID.test(fields.CallSid ?? "") || !STATUSES.has(fields.CallStatus)) {
    return new Response(null, { status: 400 });
  }
  const sequence = fields.SequenceNumber === undefined ? -1 : Number(fields.SequenceNumber);
  if (!Number.isInteger(sequence) || sequence < -1 || sequence > 2147483647) {
    return new Response(null, { status: 400 });
  }
  const key = serverSecret();
  const supabase = dependencies.supabase ?? (projectUrl && key
    ? createClient(projectUrl, key, { auth: { persistSession: false, autoRefreshToken: false } }) : null);
  if (!supabase) return new Response(null, { status: 503 });
  const { error } = await supabase.rpc("record_emergency_call_status", {
    p_call_sid: fields.CallSid, p_call_status: fields.CallStatus, p_sequence: sequence,
  });
  if (error) {
    console.error("Voice delivery update failed");
    return new Response(null, { status: 503 });
  }
  return new Response(null, { status: 204 });
}

export default { fetch: handleTwilioCallStatus };
