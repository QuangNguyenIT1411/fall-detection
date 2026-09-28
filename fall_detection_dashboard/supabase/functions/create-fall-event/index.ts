import {
  authenticateDevice,
  jsonResponse,
} from "../_shared/device_auth.ts";

const LIMITS = {
  peak_acc: 50,
  peak_gyro: 5000,
  final_pose: 180,
  low_g_duration_ms: 60_000,
  low_g_to_impact_ms: 60_000,
  device_uptime_ms: Number.MAX_SAFE_INTEGER,
} as const;

type FallPayload = {
  peak_acc: number;
  peak_gyro: number;
  final_pose: number;
  low_g_duration_ms: number;
  low_g_to_impact_ms: number;
  device_uptime_ms: number;
};

function isFiniteRange(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;
}

function validatePayload(value: unknown): value is FallPayload {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return isFiniteRange(body.peak_acc, 0, LIMITS.peak_acc) &&
    isFiniteRange(body.peak_gyro, 0, LIMITS.peak_gyro) &&
    isFiniteRange(body.final_pose, 0, LIMITS.final_pose) &&
    Number.isInteger(body.low_g_duration_ms) &&
    isFiniteRange(body.low_g_duration_ms, 0, LIMITS.low_g_duration_ms) &&
    Number.isInteger(body.low_g_to_impact_ms) &&
    isFiniteRange(body.low_g_to_impact_ms, 0, LIMITS.low_g_to_impact_ms) &&
    Number.isSafeInteger(body.device_uptime_ms) &&
    isFiniteRange(body.device_uptime_ms, 0, LIMITS.device_uptime_ms);
}

export default {
  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return jsonResponse({ success: false, error: "Method not allowed" }, 405);
    }

    const auth = await authenticateDevice(request);
    if (!auth.ok) return auth.response;

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ success: false, error: "Invalid JSON" }, 400);
    }

    if (!validatePayload(body)) {
      return jsonResponse({ success: false, error: "Invalid fall event payload" }, 400);
    }

    const { data, error } = await auth.supabase
      .from("fall_events")
      .insert({
        device_id: auth.deviceId,
        peak_acc: body.peak_acc,
        peak_gyro: body.peak_gyro,
        final_pose: body.final_pose,
        low_g_duration_ms: body.low_g_duration_ms,
        low_g_to_impact_ms: body.low_g_to_impact_ms,
        device_uptime_ms: body.device_uptime_ms,
        status: "DETECTED",
      })
      .select("id, status, detected_at")
      .single();

    if (error) {
      console.error("Fall event insert failed", error.message);
      return jsonResponse({ success: false, error: "Server error" }, 500);
    }

    return jsonResponse({
      success: true,
      event_id: data.id,
      status: data.status,
      detected_at: data.detected_at,
    }, 201);
  },
};
