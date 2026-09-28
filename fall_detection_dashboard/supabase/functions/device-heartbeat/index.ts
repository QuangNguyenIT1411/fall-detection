import {
  authenticateDevice,
  type DeviceAuthResult,
  jsonResponse,
} from "../_shared/device_auth.ts";
import {
  deliverPresenceNotification,
  type PresenceNotifier,
} from "../_shared/device_presence.ts";

type Dependencies = {
  authenticate?: (request: Request) => Promise<DeviceAuthResult>;
  notify?: PresenceNotifier;
};

export async function handleDeviceHeartbeat(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }
  const auth = await (dependencies.authenticate ?? authenticateDevice)(request);
  if (!auth.ok) return auth.response;

  const { data: rows, error } = await auth.supabase.rpc(
    "record_device_heartbeat",
    {
      p_device_id: auth.deviceId,
    },
  );
  const presence = Array.isArray(rows) ? rows[0] : null;
  if (error || !presence) {
    console.error(`Heartbeat update failed for device ${auth.deviceId}`);
    return jsonResponse({ success: false, error: "Server error" }, 500);
  }

  if (presence.recovery_pending) {
    // The heartbeat succeeded even if Telegram is temporarily unavailable.
    // The scheduled checker retries pending recovery deliveries.
    await deliverPresenceNotification(
      auth.supabase,
      auth.deviceId,
      "recovery",
      dependencies.notify,
    );
  }
  return jsonResponse({
    success: true,
    device_id: auth.deviceId,
    status: "ONLINE",
    last_seen_at: presence.last_seen_at,
  }, 200);
}

export default { fetch: handleDeviceHeartbeat };
