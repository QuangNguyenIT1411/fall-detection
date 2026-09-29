import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { jsonResponse, serverSecret } from "../_shared/device_auth.ts";
import { attemptEmergencyVoice, loadVoiceConfig, readTwilioCallStatus,
  type VoiceConfig } from "../_shared/emergency_voice.ts";

type Dependencies = {
  cronSecret?: string;
  supabase?: SupabaseClient;
  config?: VoiceConfig | null;
  fetchImpl?: typeof fetch;
  now?: () => Date;
};

export async function handleCheckEmergencyCalls(
  request: Request, dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  // Reuse the existing server-only scheduler secret; no new secret to provision.
  const expected = dependencies.cronSecret ?? Deno.env.get("DEVICE_OFFLINE_CRON_SECRET");
  if (!expected || expected.length < 32 || request.headers.get("x-cron-secret") !== expected) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  const config = dependencies.config === undefined ? loadVoiceConfig() : dependencies.config;
  if (!config) return jsonResponse({ success: true, disabled: true }, 200);
  const url = Deno.env.get("SUPABASE_URL");
  const key = serverSecret();
  const supabase = dependencies.supabase ?? (url && key
    ? createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } }) : null);
  if (!supabase) return jsonResponse({ error: "Server configuration error" }, 503);
  const now = (dependencies.now ?? (() => new Date()))();
  // Bound polling to recent Phase 13.1 calls only. Existing historical calls
  // have no last_sid and are never reactivated/backfilled into retries.
  const active = await supabase.from("fall_events").select("emergency_call_last_sid")
    .eq("emergency_call_status", "ACCEPTED").is("emergency_call_final_status", null)
    .not("emergency_call_last_sid", "is", null)
    .gte("emergency_call_requested_at", new Date(now.getTime() - 15 * 60000).toISOString())
    .order("emergency_call_requested_at").limit(10);
  if (active.error) return jsonResponse({ error: "Database query failed" }, 503);
  let reconciled = 0;
  // Read-only GETs supplement callbacks, including short Trial calls whose
  // progress may occur between checks. Missing observations are not fabricated.
  await Promise.all((active.data ?? []).map(async (row) => {
    const status = await readTwilioCallStatus(config, row.emergency_call_last_sid, dependencies.fetchImpl);
    if (!status) return;
    const result = await supabase.rpc("record_emergency_call_status", {
      p_call_sid: row.emergency_call_last_sid, p_call_status: status, p_sequence: -1,
    });
    if (!result.error && result.data) reconciled++;
  }));
  const due = await supabase.from("fall_events").select("id, device_id, event_type")
    .eq("emergency_call_status", "ACCEPTED").eq("emergency_call_retry_count", 0)
    .lte("emergency_call_retry_after", now.toISOString())
    .order("emergency_call_retry_after").limit(10);
  if (due.error) return jsonResponse({ error: "Database query failed" }, 503);
  let accepted = 0;
  let errors = 0;
  await Promise.all((due.data ?? []).map(async (row) => {
    // Atomic claim checks due time, answered state and the total attempt cap.
    // Overlapping checker invocations cannot intentionally create extra calls.
    const result = await attemptEmergencyVoice(supabase, row.id, row.device_id,
      row.event_type === "SOS" ? "SOS" : "FALL",
      { config, fetchImpl: dependencies.fetchImpl, retry: true });
    if (result.state === "accepted") accepted++;
    if (result.state === "database_error" || result.state === "failed") errors++;
  }));
  return jsonResponse({ success: true, reconciled, accepted, errors }, 200);
}

export default { fetch: handleCheckEmergencyCalls };
