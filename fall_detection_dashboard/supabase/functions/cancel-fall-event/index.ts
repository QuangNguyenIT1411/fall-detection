import {
  authenticateDevice,
  jsonResponse,
} from "../_shared/device_auth.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

    const eventId = typeof body === "object" && body !== null && !Array.isArray(body)
      ? (body as Record<string, unknown>).event_id
      : null;
    if (typeof eventId !== "string" || !UUID_PATTERN.test(eventId)) {
      return jsonResponse({ success: false, error: "Invalid event_id" }, 400);
    }

    const { data: event, error: lookupError } = await auth.supabase
      .from("fall_events")
      .select("id, event_type, status")
      .eq("id", eventId)
      .eq("device_id", auth.deviceId)
      .maybeSingle();

    if (lookupError) {
      console.error("Fall event lookup failed", lookupError.message);
      return jsonResponse({ success: false, error: "Server error" }, 500);
    }

    if (!event) {
      return jsonResponse({ success: false, error: "Event not found" }, 404);
    }

    if (event.event_type === "SOS") {
      return jsonResponse({ success: false, error: "Not a fall event" }, 409);
    }

    if (event.status === "CANCELLED") {
      return jsonResponse({
        success: true,
        event_id: event.id,
        status: event.status,
        idempotent: true,
      }, 200);
    }

    if (event.status !== "DETECTED") {
      return jsonResponse({ success: false, error: "Invalid state transition" }, 409);
    }

    const { data: cancelledRows, error: cancelError } = await auth.supabase.rpc(
      "cancel_device_fall_event",
      { p_event_id: eventId, p_device_id: auth.deviceId },
    );

    if (cancelError) {
      console.error("Fall event cancellation failed", cancelError.message);
      return jsonResponse({ success: false, error: "Server error" }, 500);
    }

    const cancelled = Array.isArray(cancelledRows) ? cancelledRows[0] : null;
    if (!cancelled) {
      return jsonResponse({ success: false, error: "Invalid state transition" }, 409);
    }

    return jsonResponse({
      success: true,
      event_id: cancelled.id,
      status: cancelled.status,
      cancelled_at: cancelled.cancelled_at,
      idempotent: false,
    }, 200);
  },
};
