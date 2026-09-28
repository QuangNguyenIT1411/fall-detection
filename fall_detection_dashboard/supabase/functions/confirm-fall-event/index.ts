import {
  authenticateDevice,
  jsonResponse,
  type DeviceAuthResult,
} from "../_shared/device_auth.ts";
import {
  sendFallConfirmedNotification,
  type ConfirmedFallNotification,
} from "../_shared/telegram.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type Dependencies = {
  authenticate?: (request: Request) => Promise<DeviceAuthResult>;
  notify?: typeof sendFallConfirmedNotification;
};

export async function handleConfirmFallEvent(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }
  const auth = await (dependencies.authenticate ?? authenticateDevice)(request);
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
    .select("id, event_type, status, confirmed_at, notification_sent_at, notification_eligible, peak_acc, peak_gyro, final_pose, low_g_duration_ms, low_g_to_impact_ms")
    .eq("id", eventId).eq("device_id", auth.deviceId).maybeSingle();
  if (lookupError) {
    console.error("Fall event lookup failed");
    return jsonResponse({ success: false, error: "Server error" }, 500);
  }
  if (!event) return jsonResponse({ success: false, error: "Event not found" }, 404);
  if (event.event_type === "SOS") {
    return jsonResponse({ success: false, error: "Not a fall event" }, 409);
  }
  if (event.status === "CANCELLED") {
    return jsonResponse({ success: false, error: "Cancelled event cannot be confirmed", status: event.status }, 409);
  }

  const idempotent = event.status === "CONFIRMED";
  let confirmedAt: string;
  if (idempotent) {
    confirmedAt = event.confirmed_at;
  } else if (event.status === "DETECTED") {
    const { data: rows, error } = await auth.supabase.rpc(
      "confirm_device_fall_event", { p_event_id: eventId, p_device_id: auth.deviceId },
    );
    if (error) {
      console.error("Fall event confirmation failed");
      return jsonResponse({ success: false, error: "Server error" }, 500);
    }
    const confirmed = Array.isArray(rows) ? rows[0] : null;
    if (!confirmed) return jsonResponse({ success: false, error: "Invalid state transition" }, 409);
    confirmedAt = confirmed.confirmed_at;
  } else {
    return jsonResponse({ success: false, error: "Invalid event status" }, 409);
  }

  if (event.notification_sent_at) {
    return jsonResponse({
      success: true, event_id: eventId, status: "CONFIRMED", confirmed_at: confirmedAt,
      notification_sent_at: event.notification_sent_at, idempotent,
    }, 200);
  }

  if (!event.notification_eligible) {
    return jsonResponse({
      success: true, event_id: eventId, status: "CONFIRMED", confirmed_at: confirmedAt,
      notification_sent_at: null, idempotent: true,
      notification_skipped: "pre_phase_7_event",
    }, 200);
  }

  const claimToken = crypto.randomUUID();
  const claimArgs = { p_event_id: eventId, p_device_id: auth.deviceId, p_claim_token: claimToken };
  const { data: claimed, error: claimError } = await auth.supabase.rpc("claim_fall_notification", claimArgs);
  if (claimError) {
    console.error(`Telegram notification claim failed for event ${eventId}`);
    return jsonResponse({ success: false, error: "Notification claim failed", status: "CONFIRMED" }, 503);
  }
  if (!claimed) {
    const { data: latest, error } = await auth.supabase.from("fall_events")
      .select("notification_sent_at").eq("id", eventId).eq("device_id", auth.deviceId).maybeSingle();
    if (!error && latest?.notification_sent_at) {
      return jsonResponse({
        success: true, event_id: eventId, status: "CONFIRMED", confirmed_at: confirmedAt,
        notification_sent_at: latest.notification_sent_at, idempotent: true,
      }, 200);
    }
    return jsonResponse({ success: false, error: "Notification in progress", status: "CONFIRMED" }, 503);
  }

  const { data: device, error: deviceError } = await auth.supabase.from("devices")
    .select("name, device_code").eq("id", auth.deviceId).maybeSingle();
  if (deviceError || !device) {
    await auth.supabase.rpc("release_fall_notification_claim", claimArgs);
    console.error(`Telegram notification device lookup failed for event ${eventId}`);
    return jsonResponse({ success: false, error: "Notification data unavailable", status: "CONFIRMED" }, 503);
  }

  const notification: ConfirmedFallNotification = {
    id: eventId, deviceName: device.name, deviceCode: device.device_code,
    confirmedAt, peakAcc: event.peak_acc, peakGyro: event.peak_gyro,
    finalPose: event.final_pose, lowGDurationMs: event.low_g_duration_ms,
    lowGToImpactMs: event.low_g_to_impact_ms,
  };
  const sent = await (dependencies.notify ?? sendFallConfirmedNotification)(notification);
  if (!sent.ok) {
    await auth.supabase.rpc("release_fall_notification_claim", claimArgs);
    console.error(`Telegram notification failed for event ${eventId}: ${sent.error}`);
    return jsonResponse({ success: false, error: "Telegram notification failed", status: "CONFIRMED" }, 503);
  }

  const { data: notificationSentAt, error: markError } = await auth.supabase.rpc("mark_fall_notification_sent", claimArgs);
  if (markError || !notificationSentAt) {
    console.error(`Telegram notification status update failed for event ${eventId}`);
    return jsonResponse({ success: false, error: "Notification status update failed", status: "CONFIRMED" }, 503);
  }
  console.info(`Telegram notification sent for event ${eventId}`);
  return jsonResponse({
    success: true, event_id: eventId, status: "CONFIRMED", confirmed_at: confirmedAt,
    notification_sent_at: notificationSentAt, idempotent,
  }, 200);
}

export default { fetch: handleConfirmFallEvent };
