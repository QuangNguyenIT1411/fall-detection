import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.57.4";
import { jsonResponse, serverSecret } from "../_shared/device_auth.ts";

const ACK_PATTERN =
  /^ack:([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
type TelegramMethod = "answerCallbackQuery" | "editMessageReplyMarkup";
type TelegramApi = (
  method: TelegramMethod,
  body: Record<string, unknown>,
) => Promise<boolean>;

type Dependencies = {
  webhookSecret?: string;
  chatId?: string;
  createSupabase?: typeof createClient;
  telegramApi?: TelegramApi;
};

function equalSecret(actual: string, expected: string): boolean {
  let difference = actual.length ^ expected.length;
  for (let i = 0; i < Math.max(actual.length, expected.length); i++) {
    difference |= (actual.charCodeAt(i) || 0) ^ (expected.charCodeAt(i) || 0);
  }
  return difference === 0;
}

async function telegramApi(
  method: TelegramMethod,
  body: Record<string, unknown>,
): Promise<boolean> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  if (!token) return false;
  try {
    const response = await fetch(
      `https://api.telegram.org/bot${token}/${method}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(5000),
      },
    );
    if (!response.ok) return false;
    const result: unknown = await response.json();
    return typeof result === "object" && result !== null &&
      (result as Record<string, unknown>).ok === true;
  } catch {
    return false;
  }
}

export async function handleTelegramWebhook(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }
  const expected = dependencies.webhookSecret ??
    Deno.env.get("TELEGRAM_WEBHOOK_SECRET");
  if (!expected || expected.length < 32) {
    console.error("Telegram webhook secret is not configured");
    return jsonResponse(
      { success: false, error: "Server configuration error" },
      503,
    );
  }
  const supplied = request.headers.get("x-telegram-bot-api-secret-token") ?? "";
  if (!equalSecret(supplied, expected)) {
    return jsonResponse({ success: false, error: "Unauthorized" }, 401);
  }
  const chatId = dependencies.chatId ?? Deno.env.get("TELEGRAM_CHAT_ID");
  if (!chatId) {
    console.error("Telegram destination is not configured");
    return jsonResponse(
      { success: false, error: "Server configuration error" },
      503,
    );
  }

  let update: unknown;
  try {
    update = await request.json();
  } catch {
    return jsonResponse({ success: false, error: "Invalid JSON" }, 400);
  }
  if (typeof update !== "object" || update === null) {
    return jsonResponse({ success: true, ignored: true }, 200);
  }
  const callback = (update as Record<string, unknown>).callback_query;
  if (typeof callback !== "object" || callback === null) {
    return jsonResponse({ success: true, ignored: true }, 200);
  }
  const query = callback as Record<string, unknown>;
  const message = query.message;
  const chat = typeof message === "object" && message !== null
    ? (message as Record<string, unknown>).chat
    : null;
  const actualChatId = typeof chat === "object" && chat !== null
    ? (chat as Record<string, unknown>).id
    : null;
  if (String(actualChatId) !== chatId) {
    return jsonResponse({ success: false, error: "Wrong Telegram chat" }, 403);
  }
  const match = typeof query.data === "string"
    ? ACK_PATTERN.exec(query.data)
    : null;
  if (!match || typeof query.id !== "string" || !query.id) {
    if (typeof query.id === "string" && query.id) {
      await (dependencies.telegramApi ?? telegramApi)("answerCallbackQuery", {
        callback_query_id: query.id,
        text: "Yêu cầu không hợp lệ.",
      });
    }
    return jsonResponse({ success: true, ignored: true }, 200);
  }
  const messageId = (message as Record<string, unknown>).message_id;
  if (typeof messageId !== "number" || !Number.isSafeInteger(messageId)) {
    return jsonResponse({ success: true, ignored: true }, 200);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const key = serverSecret();
  if (!url || !key) {
    console.error("Telegram webhook missing database configuration");
    return jsonResponse(
      { success: false, error: "Server configuration error" },
      503,
    );
  }
  const supabase: SupabaseClient =
    (dependencies.createSupabase ?? createClient)(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  const { data: rows, error } = await supabase.rpc("acknowledge_fall_event", {
    p_event_id: match[1],
    p_via: "TELEGRAM",
  });
  if (error) {
    console.error("Fall acknowledgement database update failed");
    return jsonResponse({ success: false, error: "Server error" }, 503);
  }
  const acknowledged = Array.isArray(rows) ? rows[0] : null;
  if (!acknowledged) {
    await (dependencies.telegramApi ?? telegramApi)("answerCallbackQuery", {
      callback_query_id: query.id,
      text: "Không thể ghi nhận cảnh báo này.",
    });
    return jsonResponse({
      success: true,
      acknowledged: false,
      reason: "not_confirmed",
    }, 200);
  }

  const call = dependencies.telegramApi ?? telegramApi;
  const answer = await call("answerCallbackQuery", {
    callback_query_id: query.id,
    text: acknowledged.already_acknowledged
      ? "Cảnh báo này đã được ghi nhận trước đó."
      : "Đã ghi nhận cảnh báo.",
  });
  if (!answer) console.error("Telegram answerCallbackQuery failed");
  const edited = await call("editMessageReplyMarkup", {
    chat_id: chatId,
    message_id: messageId,
    reply_markup: { inline_keyboard: [] },
  });
  if (!edited) console.error("Telegram editMessageReplyMarkup failed");

  return jsonResponse({
    success: true,
    acknowledged: true,
    acknowledged_at: acknowledged.acknowledged_at,
    already_acknowledged: acknowledged.already_acknowledged,
  }, 200);
}

export default { fetch: handleTelegramWebhook };
