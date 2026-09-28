import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { jsonResponse, serverSecret } from "../_shared/device_auth.ts";
import {
  deliverPresenceNotification,
  type PresenceNotifier,
} from "../_shared/device_presence.ts";

type Dependencies = {
  createSupabase?: typeof createClient;
  notify?: PresenceNotifier;
  now?: () => Date;
  cronSecret?: string;
};

export async function handleCheckDeviceOffline(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }
  const expected = dependencies.cronSecret ??
    Deno.env.get("DEVICE_OFFLINE_CRON_SECRET");
  if (
    !expected || expected.length < 32 ||
    request.headers.get("x-cron-secret") !== expected
  ) {
    return jsonResponse({ success: false, error: "Unauthorized" }, 401);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const key = serverSecret();
  if (!url || !key) {
    console.error("Offline checker missing server configuration");
    return jsonResponse(
      { success: false, error: "Server configuration error" },
      500,
    );
  }
  const supabase = (dependencies.createSupabase ?? createClient)(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const cutoff = new Date(
    (dependencies.now ?? (() => new Date()))().getTime() - 60000,
  ).toISOString();
  const [stale, recovering] = await Promise.all([
    supabase.from("devices").select("id").lt("last_seen_at", cutoff)
      .is("offline_notified_at", null).limit(100),
    supabase.from("devices").select("id")
      .eq("connectivity_status", "ONLINE")
      .not("recovery_pending_at", "is", null)
      .is("recovery_notified_at", null).limit(100),
  ]);
  if (stale.error || recovering.error) {
    console.error("Offline checker device query failed");
    return jsonResponse({ success: false, error: "Server error" }, 500);
  }
  let sent = 0;
  let retries = 0;
  for (const row of stale.data ?? []) {
    const result = await deliverPresenceNotification(
      supabase,
      row.id,
      "offline",
      dependencies.notify,
    );
    if (result === "sent") sent++;
    if (result === "retry") retries++;
  }
  for (const row of recovering.data ?? []) {
    const result = await deliverPresenceNotification(
      supabase,
      row.id,
      "recovery",
      dependencies.notify,
    );
    if (result === "sent") sent++;
    if (result === "retry") retries++;
  }
  return jsonResponse({ success: true, sent, retries }, 200);
}

export default { fetch: handleCheckDeviceOffline };
