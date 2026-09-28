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

export type TelegramFailure =
  | "missing_config"
  | "transport_error"
  | "http_error"
  | "rejected"
  | "invalid_response";

function vietnamTime(iso: string): string {
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

export async function sendFallConfirmedNotification(
  event: ConfirmedFallNotification,
  options: {
    token?: string;
    chatId?: string;
    fetchImpl?: typeof fetch;
  } = {},
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
        body: JSON.stringify({ chat_id: chatId, text: formatFallConfirmedMessage(event) }),
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
