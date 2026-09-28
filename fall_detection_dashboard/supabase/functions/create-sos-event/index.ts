import {
  authenticateDevice,
  jsonResponse,
  type DeviceAuthResult,
} from "../_shared/device_auth.ts";
import {
  sendSosNotification,
  type SosNotification,
} from "../_shared/telegram.ts";
import { attemptEmergencyVoice, type VoiceResult } from "../_shared/emergency_voice.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type Dependencies = {
  authenticate?: (request: Request) => Promise<DeviceAuthResult>;
  notify?: typeof sendSosNotification;
  voice?: typeof attemptEmergencyVoice;
};

export async function handleCreateSosEvent(
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
  const requestKey = typeof body === "object" && body !== null && !Array.isArray(body)
    ? (body as Record<string, unknown>).request_id
    : null;
  if (typeof requestKey !== "string" || !UUID.test(requestKey)) {
    return jsonResponse({ success: false, error: "Invalid request_id" }, 400);
  }

  const { data: result, error: createError } = await auth.supabase.rpc(
    "create_device_sos_event",
    { p_device_id: auth.deviceId, p_request_key: requestKey },
  );
  const event = Array.isArray(result) ? result[0] : result;
  if (createError || !event || event.event_type !== "SOS" ||
    event.status !== "CONFIRMED") {
    console.error("SOS event creation failed");
    return jsonResponse({ success: false, error: "Server error" }, 500);
  }

  const response = (sentAt: string | null) => ({
    success: true,
    event_id: event.id,
    event_type: "SOS",
    status: "CONFIRMED",
    detected_at: event.detected_at,
    confirmed_at: event.confirmed_at,
    notification_sent_at: sentAt,
  });
  const voicePromise: Promise<VoiceResult> = (dependencies.voice ??
    attemptEmergencyVoice)(auth.supabase, event.id, auth.deviceId, "SOS")
    .catch(() => {
      console.error("Emergency voice execution failed");
      return { state: "database_error" as const };
    });
  const finish = async (body: Record<string, unknown>, status: number) => {
    const voice = await voicePromise;
    const needsRetry = voice.state === "database_error" ||
      voice.state === "in_progress" ||
      (voice.state === "failed" && voice.retryable);
    return jsonResponse({ ...body,
      emergency_call_status: voice.state === "accepted" || voice.state === "already_accepted"
        ? "ACCEPTED" : voice.state === "failed" ? "FAILED" : null,
    }, (status === 200 || status === 201) && needsRetry ? 503 : status);
  };
  if (event.notification_sent_at) {
    return finish(response(event.notification_sent_at), 200);
  }

  const claimToken = crypto.randomUUID();
  const claimArgs = {
    p_event_id: event.id,
    p_device_id: auth.deviceId,
    p_claim_token: claimToken,
  };
  const { data: claimed, error: claimError } = await auth.supabase.rpc(
    "claim_fall_notification", claimArgs,
  );
  if (claimError) {
    console.error("SOS notification claim failed");
    return finish({ success: false, error: "Notification claim failed" }, 503);
  }
  if (!claimed) {
    const { data: latest } = await auth.supabase.from("fall_events")
      .select("notification_sent_at").eq("id", event.id)
      .eq("device_id", auth.deviceId).maybeSingle();
    if (latest?.notification_sent_at) {
      return finish(response(latest.notification_sent_at), 200);
    }
    return finish({ success: false, error: "Notification in progress" }, 503);
  }

  const { data: device, error: deviceError } = await auth.supabase.from("devices")
    .select("name, device_code").eq("id", auth.deviceId).maybeSingle();
  if (deviceError || !device) {
    await auth.supabase.rpc("release_fall_notification_claim", claimArgs);
    console.error("SOS device lookup failed");
    return finish({ success: false, error: "Notification data unavailable" }, 503);
  }

  const notification: SosNotification = {
    id: event.id,
    deviceName: device.name,
    deviceCode: device.device_code,
    detectedAt: event.detected_at,
  };
  const sent = await (dependencies.notify ?? sendSosNotification)(notification);
  if (!sent.ok) {
    await auth.supabase.rpc("release_fall_notification_claim", claimArgs);
    console.error(`SOS Telegram delivery failed for event ${event.id}: ${sent.error}`);
    return finish({ success: false, error: "Telegram notification failed" }, 503);
  }

  const { data: sentAt, error: markError } = await auth.supabase.rpc(
    "mark_fall_notification_sent", claimArgs,
  );
  if (markError || !sentAt) {
    console.error("SOS notification status update failed");
    return finish({ success: false, error: "Notification status update failed" }, 503);
  }
  return finish(response(sentAt), 201);
}

export default { fetch: handleCreateSosEvent };
