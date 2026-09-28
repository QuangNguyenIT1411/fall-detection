import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  type DevicePresenceNotification,
  sendDevicePresenceNotification,
} from "./telegram.ts";

export type PresenceKind = "offline" | "recovery";
export type PresenceNotifier = typeof sendDevicePresenceNotification;

export async function deliverPresenceNotification(
  supabase: SupabaseClient,
  deviceId: string,
  kind: PresenceKind,
  notify: PresenceNotifier = sendDevicePresenceNotification,
): Promise<"sent" | "skipped" | "retry"> {
  const token = crypto.randomUUID();
  const args = { p_device_id: deviceId, p_claim_token: token };
  const claim = kind === "offline"
    ? "claim_device_offline_notification"
    : "claim_device_recovery_notification";
  const mark = kind === "offline"
    ? "mark_device_offline_notification"
    : "mark_device_recovery_notification";
  const release = kind === "offline"
    ? "release_device_offline_claim"
    : "release_device_recovery_claim";

  const claimed = await supabase.rpc(claim, args);
  if (claimed.error) {
    console.error(`Presence ${kind} claim failed for device ${deviceId}`);
    return "retry";
  }
  if (!claimed.data) return "skipped";

  const { data: device, error } = await supabase.from("devices")
    .select(
      "name, device_code, last_seen_at, offline_since, recovery_pending_at",
    )
    .eq("id", deviceId).maybeSingle();
  if (error || !device?.last_seen_at) {
    await supabase.rpc(release, args);
    console.error(`Presence ${kind} device lookup failed for ${deviceId}`);
    return "retry";
  }

  const payload: DevicePresenceNotification = {
    deviceName: device.name,
    deviceCode: device.device_code,
    lastSeenAt: device.last_seen_at,
    offlineSince: device.offline_since ?? undefined,
    recoveredAt: device.recovery_pending_at ?? undefined,
  };
  const sent = await notify(kind, payload);
  if (!sent.ok) {
    await supabase.rpc(release, args);
    console.error(
      `Presence ${kind} Telegram failed for ${deviceId}: ${sent.error}`,
    );
    return "retry";
  }
  const marked = await supabase.rpc(mark, args);
  if (marked.error || !marked.data) {
    console.error(`Presence ${kind} status update failed for ${deviceId}`);
    return "retry";
  }
  return "sent";
}
