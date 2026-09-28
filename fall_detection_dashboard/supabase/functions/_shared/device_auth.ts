import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

export type DeviceAuthResult =
  | { ok: true; deviceId: string; supabase: SupabaseClient }
  | { ok: false; response: Response };

export function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function serverSecret(): string | null {
  const legacyServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacyServiceRole) return legacyServiceRole;

  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!secretKeys) return null;

  try {
    const parsed = JSON.parse(secretKeys) as Record<string, string>;
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch {
    return null;
  }
}

export async function authenticateDevice(
  request: Request,
): Promise<DeviceAuthResult> {
  const deviceCode = request.headers.get("x-device-code")?.trim() ?? "";
  const deviceKey = request.headers.get("x-device-key") ?? "";

  if (!deviceCode || !deviceKey) {
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Missing device credentials" },
        401,
      ),
    };
  }

  if (deviceCode.length > 64 || deviceKey.length < 32 || deviceKey.length > 256) {
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Invalid device credentials" },
        401,
      ),
    };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const secret = serverSecret();
  if (!supabaseUrl || !secret) {
    console.error("Missing Supabase server environment configuration");
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Server configuration error" },
        500,
      ),
    };
  }

  const supabase = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: device, error: deviceError } = await supabase
    .from("devices")
    .select("id")
    .eq("device_code", deviceCode)
    .maybeSingle();

  if (deviceError) {
    console.error("Device lookup failed", deviceError.message);
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Server error" },
        500,
      ),
    };
  }

  if (!device) {
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Device not found" },
        404,
      ),
    };
  }

  const { data: authenticatedId, error: authError } = await supabase.rpc(
    "authenticate_device",
    { p_device_code: deviceCode, p_device_key: deviceKey },
  );

  if (authError) {
    console.error("Device authentication RPC failed", authError.message);
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Server error" },
        500,
      ),
    };
  }

  if (authenticatedId !== device.id) {
    return {
      ok: false,
      response: jsonResponse(
        { success: false, error: "Invalid device credentials" },
        401,
      ),
    };
  }

  return { ok: true, deviceId: device.id, supabase };
}
