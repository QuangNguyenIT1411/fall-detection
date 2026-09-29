import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { serverSecret } from "../_shared/device_auth.ts";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};
function respond(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" },
  });
}
type Dependencies = {
  publicClient?: () => SupabaseClient | null;
  serviceClient?: () => SupabaseClient | null;
};
const clientOptions = { auth: { persistSession: false, autoRefreshToken: false } };
function publicClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  return url && key ? createClient(url, key, clientOptions) : null;
}
function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = serverSecret();
  return url && key ? createClient(url, key, clientOptions) : null;
}

export async function handleSetBuzzerEnabled(request: Request, dependencies: Dependencies = {}): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method !== "POST") return respond({ success: false, error: "Method not allowed" }, 405);
  const token = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "")?.[1];
  if (!token) return respond({ success: false, error: "Unauthorized" }, 401);
  const authClient = (dependencies.publicClient ?? publicClient)();
  if (!authClient) return respond({ success: false, error: "Server configuration error" }, 503);
  // Online verification with Supabase Auth; never trust a browser-decoded JWT.
  try {
    const { data, error } = await authClient.auth.getUser(token);
    if (error || !data.user?.id || data.user.role !== "authenticated" || data.user.is_anonymous) {
      return respond({ success: false, error: "Unauthorized" }, 401);
    }
  } catch { return respond({ success: false, error: "Session verification unavailable" }, 503); }
  let body: unknown;
  try {
    const raw = await request.text();
    if (raw.length > 1024) return respond({ success: false, error: "Invalid request" }, 400);
    body = JSON.parse(raw);
  } catch { return respond({ success: false, error: "Invalid request" }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      Object.keys(body).length !== 1 || !("enabled" in body) || typeof body.enabled !== "boolean") {
    return respond({ success: false, error: "Expected enabled boolean only" }, 400);
  }
  // Service credentials are accessed only after successful user verification.
  const db = (dependencies.serviceClient ?? serviceClient)();
  if (!db) return respond({ success: false, error: "Server configuration error" }, 503);
  try {
    const { data, error } = await db.rpc("set_device_buzzer_enabled", { p_enabled: body.enabled });
    if (error) return respond({ success: false, error: "Unable to save buzzer setting" }, 500);
    const row = Array.isArray(data) ? data[0] : null;
    if (!row) return respond({ success: false, error: "Device not found" }, 404);
    return respond({ success: true, buzzer_enabled: row.buzzer_enabled, updated_at: row.buzzer_updated_at }, 200);
  } catch { return respond({ success: false, error: "Unable to save buzzer setting" }, 500); }
}

export default { fetch: handleSetBuzzerEnabled };
