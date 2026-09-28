export interface ConfirmedFallNotification {
  id: string;
  deviceName: string;
  deviceCode: string;
  confirmedAt: string;
  peakAcc: number | null;
  peakGyro: number | null;
  finalPose: number | null;
  lowGDurationMs: number | null;
  lowGToImpactMs: number | null;
}

export interface SosNotification {
  id: string;
  deviceName: string;
  deviceCode: string;
  detectedAt: string;
}

export type TelegramFailure =
  | "missing_config"
  | "transport_error"
  | "http_error"
  | "rejected"
  | "invalid_response";

export function vietnamTime(iso: string): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Ho_Chi_Minh",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(iso));
  const value = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${value("day")}/${value("month")}/${value("year")} ` +
    `${value("hour")}:${value("minute")}:${value("second")}`;
}

const oneLine = (value: string) => value.replace(/[\r\n\t]+/g, " ").trim();
const metric = (value: number | null, digits: number, unit: string) =>
  value === null ? "—" : `${value.toFixed(digits)} ${unit}`;

export function formatFallConfirmedMessage(event: ConfirmedFallNotification): string {
  return [
    "⚠️ CẢNH BÁO TÉ NGÃ",
    "",
    `Thiết bị: ${oneLine(event.deviceName)} (${oneLine(event.deviceCode)})`,
    "Trạng thái: ĐÃ XÁC NHẬN TÉ NGÃ",
    `Thời gian: ${vietnamTime(event.confirmedAt)}`,
    "",
    `Peak ACC: ${metric(event.peakAcc, 2, "g")}`,
    `Peak GYRO: ${metric(event.peakGyro, 1, "dps")}`,
    `Final POSE: ${metric(event.finalPose, 1, "°")}`,
    `LOW-G duration: ${event.lowGDurationMs === null ? "—" : `${event.lowGDurationMs} ms`}`,
    `LOW-G → IMPACT: ${event.lowGToImpactMs === null ? "—" : `${event.lowGToImpactMs} ms`}`,
    "",
    `Sự kiện: ${event.id}`,
    "",
    "Vui lòng kiểm tra tình trạng người dùng.",
  ].join("\n");
}

export function formatSosMessage(event: SosNotification): string {
  return [
    "🆘 YÊU CẦU TRỢ GIÚP KHẨN CẤP",
    "",
    `Thiết bị: ${oneLine(event.deviceName)} (${oneLine(event.deviceCode)})`,
    `Thời gian: ${vietnamTime(event.detectedAt)}`,
    "",
    "Người dùng đã chủ động yêu cầu trợ giúp bằng nút SOS.",
    "",
    `Sự kiện: ${event.id}`,
    "",
    "Vui lòng kiểm tra tình trạng người dùng ngay.",
  ].join("\n");
}

export interface DevicePresenceNotification {
  deviceName: string;
  deviceCode: string;
  lastSeenAt: string;
  offlineSince?: string;
  recoveredAt?: string;
}

export function formatDevicePresenceMessage(
  kind: "offline" | "recovery",
  device: DevicePresenceNotification,
): string {
  const label = `Thiết bị: ${oneLine(device.deviceName)} (${oneLine(device.deviceCode)})`;
  return kind === "offline"
    ? [
      "⚠️ THIẾT BỊ MẤT KẾT NỐI", "", label,
      `Mất kết nối từ: ${vietnamTime(device.offlineSince ?? device.lastSeenAt)}`,
      `Lần cuối hoạt động: ${vietnamTime(device.lastSeenAt)}`,
      "", "Vui lòng kiểm tra thiết bị và nguồn điện.",
    ].join("\n")
    : [
      "✅ THIẾT BỊ ĐÃ KẾT NỐI TRỞ LẠI", "", label,
      `Kết nối lại lúc: ${vietnamTime(device.recoveredAt ?? device.lastSeenAt)}`,
    ].join("\n");
}

export async function sendDevicePresenceNotification(
  kind: "offline" | "recovery",
  device: DevicePresenceNotification,
  options: { token?: string; chatId?: string; fetchImpl?: typeof fetch } = {},
): Promise<{ ok: true } | { ok: false; error: TelegramFailure }> {
  return sendTelegramText(formatDevicePresenceMessage(kind, device), options);
}

export async function sendFallConfirmedNotification(
  event: ConfirmedFallNotification,
  options: {
    token?: string;
    chatId?: string;
    fetchImpl?: typeof fetch;
  } = {},
): Promise<{ ok: true } | { ok: false; error: TelegramFailure }> {
  return sendTelegramText(formatFallConfirmedMessage(event), {
    ...options,
    replyMarkup: acknowledgementButton(event.id),
  });
}

export async function sendSosNotification(
  event: SosNotification,
  options: { token?: string; chatId?: string; fetchImpl?: typeof fetch } = {},
): Promise<{ ok: true } | { ok: false; error: TelegramFailure }> {
  return sendTelegramText(formatSosMessage(event), {
    ...options,
    replyMarkup: acknowledgementButton(event.id),
  });
}

function acknowledgementButton(id: string) {
  return {
    inline_keyboard: [[{
      text: "✅ Đã nhận cảnh báo",
      callback_data: `ack:${id}`,
    }]],
  };
}

async function sendTelegramText(
  text: string,
  options: {
    token?: string;
    chatId?: string;
    fetchImpl?: typeof fetch;
    replyMarkup?: { inline_keyboard: { text: string; callback_data: string }[][] };
  },
): Promise<{ ok: true } | { ok: false; error: TelegramFailure }> {
  const token = options.token ?? Deno.env.get("TELEGRAM_BOT_TOKEN");
  const chatId = options.chatId ?? Deno.env.get("TELEGRAM_CHAT_ID");
  if (!token || !chatId) return { ok: false, error: "missing_config" };

  let response: Response;
  try {
    response = await (options.fetchImpl ?? fetch)(
      `https://api.telegram.org/bot${token}/sendMessage`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text,
          ...(options.replyMarkup ? { reply_markup: options.replyMarkup } : {}),
        }),
        signal: AbortSignal.timeout(5000),
      },
    );
  } catch {
    return { ok: false, error: "transport_error" };
  }
  if (!response.ok) return { ok: false, error: "http_error" };
  try {
    const result: unknown = await response.json();
    if (typeof result !== "object" || result === null) {
      return { ok: false, error: "invalid_response" };
    }
    const data = result as Record<string, unknown>;
    if (data.ok !== true) return { ok: false, error: "rejected" };
    if (typeof data.result !== "object" || data.result === null ||
      typeof (data.result as Record<string, unknown>).message_id !== "number") {
      return { ok: false, error: "invalid_response" };
    }
    return { ok: true };
  } catch {
    return { ok: false, error: "invalid_response" };
  }
}
