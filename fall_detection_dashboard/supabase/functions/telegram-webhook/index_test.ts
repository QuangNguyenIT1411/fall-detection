import { handleTelegramWebhook } from "./index.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

const eventId = "bd41daa7-f814-45f0-867c-0b0e37d0e826";
const secret = "test-webhook-secret-0123456789-abcdef";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

class Fixture {
  status: "CONFIRMED" | "DETECTED" | "CANCELLED" = "CONFIRMED";
  acknowledgedAt: string | null = null;
  rpcCalls = 0;
  apiCalls: { method: string; body: Record<string, unknown> }[] = [];
  editSucceeds = true;

  async rpc(name: string, args: Record<string, string>) {
    assert(name === "acknowledge_fall_event", "Unexpected RPC");
    assert(
      args.p_event_id === eventId && args.p_via === "TELEGRAM",
      "Unsafe RPC parameters",
    );
    this.rpcCalls++;
    if (this.status !== "CONFIRMED") return { data: [], error: null };
    const already = this.acknowledgedAt !== null;
    this.acknowledgedAt ??= "2026-09-28T01:19:19Z";
    return {
      data: [{
        acknowledged_at: this.acknowledgedAt,
        acknowledged_via: "TELEGRAM",
        already_acknowledged: already,
      }],
      error: null,
    };
  }

  request(
    options: { data?: string; chatId?: number; suppliedSecret?: string } = {},
  ) {
    return new Request("https://example.test/telegram-webhook", {
      method: "POST",
      headers: {
        "x-telegram-bot-api-secret-token": options.suppliedSecret ?? secret,
      },
      body: JSON.stringify({
        callback_query: {
          id: "query-123",
          data: options.data ?? `ack:${eventId}`,
          message: { message_id: 456, chat: { id: options.chatId ?? 12345 } },
        },
      }),
    });
  }

  handle(request = this.request()) {
    Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-not-a-secret");
    return handleTelegramWebhook(request, {
      webhookSecret: secret,
      chatId: "12345",
      createSupabase: (() =>
        this as unknown as SupabaseClient) as unknown as typeof import("npm:@supabase/supabase-js@2.57.4").createClient,
      telegramApi: async (method, body) => {
        this.apiCalls.push({ method, body });
        return method !== "editMessageReplyMarkup" || this.editSucceeds;
      },
    });
  }
}

Deno.test("CONFIRMED ACK is stored and Telegram callback answered/edited", async () => {
  const f = new Fixture();
  const response = await f.handle();
  assert(response.status === 200 && f.acknowledgedAt !== null, "ACK failed");
  assert(
    f.apiCalls[0].method === "answerCallbackQuery",
    "Callback was not answered",
  );
  assert(f.apiCalls[0].body.text === "Đã ghi nhận cảnh báo.", "Wrong ACK text");
  assert(
    f.apiCalls[1].method === "editMessageReplyMarkup",
    "Button was not removed",
  );
  assert(
    JSON.stringify(f.apiCalls[1].body.reply_markup) ===
      '{"inline_keyboard":[]}',
    "Markup not cleared",
  );
});

Deno.test("DETECTED and CANCELLED callbacks cannot acknowledge", async () => {
  for (const status of ["DETECTED", "CANCELLED"] as const) {
    const f = new Fixture();
    f.status = status;
    const response = await f.handle();
    assert(
      response.status === 200 && f.acknowledgedAt === null,
      `${status} was acknowledged`,
    );
    assert(
      f.apiCalls.length === 1 && f.apiCalls[0].method === "answerCallbackQuery",
      "Invalid state callback was not answered safely",
    );
  }
});

Deno.test("duplicate and concurrent ACK retain one timestamp", async () => {
  const f = new Fixture();
  const [first, second] = await Promise.all([f.handle(), f.handle()]);
  assert(
    first.status === 200 && second.status === 200,
    "Concurrent callbacks failed",
  );
  const original = f.acknowledgedAt;
  const duplicate = await f.handle();
  assert(
    duplicate.status === 200 && f.acknowledgedAt === original,
    "Timestamp changed",
  );
  assert(
    f.apiCalls.some((call) =>
      call.body.text === "Cảnh báo này đã được ghi nhận trước đó."
    ),
    "Duplicate callback not acknowledged idempotently",
  );
});

Deno.test("bad secret, wrong chat, and invalid data never write", async () => {
  const f = new Fixture();
  assert(
    (await f.handle(f.request({ suppliedSecret: "wrong" }))).status === 401,
    "Invalid secret accepted",
  );
  assert(
    (await f.handle(f.request({ chatId: 999 }))).status === 403,
    "Wrong chat accepted",
  );
  const invalid = await f.handle(f.request({ data: "ack:not-a-uuid" }));
  assert(
    invalid.status === 200 && f.rpcCalls === 0,
    "Invalid callback reached DB",
  );
});

Deno.test("Telegram edit failure never rolls back authoritative ACK", async () => {
  const f = new Fixture();
  f.editSucceeds = false;
  const response = await f.handle();
  assert(
    response.status === 200 && f.acknowledgedAt !== null,
    "ACK was rolled back",
  );
});
