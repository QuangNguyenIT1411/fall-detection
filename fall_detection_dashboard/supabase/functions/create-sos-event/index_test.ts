import { handleCreateSosEvent } from "./index.ts";
import { sendSosNotification, sendDevicePresenceNotification } from "../_shared/telegram.ts";
import type { DeviceAuthResult } from "../_shared/device_auth.ts";

const deviceId = "00000000-0000-4000-8000-000000000001";
const keyA = "11111111-1111-4111-8111-111111111111";
const keyB = "22222222-2222-4222-8222-222222222222";
const detectedAt = "2026-09-28T01:19:16Z";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

class Fixture {
  events = new Map<string, Record<string, unknown>>();
  sends = 0;
  nextId = 1;
  claim: string | null = null;
  failSend = false;

  request(key = keyA) {
    return new Request("https://example.test/create-sos-event", {
      method: "POST", body: JSON.stringify({ request_id: key }),
    });
  }

  authenticate = async (_request: Request): Promise<DeviceAuthResult> =>
    ({ ok: true, deviceId, supabase: this } as unknown as DeviceAuthResult);

  notify = async () => {
    this.sends++;
    return this.failSend
      ? { ok: false as const, error: "transport_error" as const }
      : { ok: true as const };
  };

  from(table: string) {
    const self = this;
    const filters: Record<string, string> = {};
    return {
      select(_columns: string) { return this; },
      eq(column: string, value: string) { filters[column] = value; return this; },
      async maybeSingle() {
        if (table === "devices") return {
          data: { name: "Thiết bị người cao tuổi 01", device_code: "device01" }, error: null,
        };
        const event = [...self.events.values()].find((item) => item.id === filters.id);
        return { data: event ? { notification_sent_at: event.notification_sent_at } : null, error: null };
      },
    };
  }

  async rpc(name: string, args: Record<string, string>) {
    if (name === "create_device_sos_event") {
      let event = this.events.get(args.p_request_key);
      if (!event) {
        event = {
          id: `10000000-0000-4000-8000-${String(this.nextId++).padStart(12, "0")}`,
          event_type: "SOS", status: "CONFIRMED",
          detected_at: detectedAt, confirmed_at: detectedAt,
          notification_sent_at: null,
        };
        this.events.set(args.p_request_key, event);
      }
      return { data: { ...event }, error: null };
    }
    if (name === "claim_fall_notification") {
      const event = [...this.events.values()].find((item) => item.id === args.p_event_id);
      if (!event || event.notification_sent_at || this.claim) return { data: false, error: null };
      this.claim = args.p_claim_token;
      return { data: true, error: null };
    }
    if (name === "release_fall_notification_claim") {
      if (this.claim === args.p_claim_token) this.claim = null;
      return { data: null, error: null };
    }
    if (name === "mark_fall_notification_sent") {
      const event = [...this.events.values()].find((item) => item.id === args.p_event_id);
      if (!event || this.claim !== args.p_claim_token) return { data: null, error: null };
      event.notification_sent_at = "2026-09-28T01:19:17Z";
      this.claim = null;
      return { data: event.notification_sent_at, error: null };
    }
    throw new Error(`Unexpected RPC ${name}`);
  }

  handle(key = keyA) {
    return handleCreateSosEvent(this.request(key), {
      authenticate: this.authenticate, notify: this.notify,
    });
  }
}

Deno.test("authenticated SOS is confirmed with server timestamps and idempotent key", async () => {
  const f = new Fixture();
  const first = await f.handle();
  const body = await first.json();
  assert(first.status === 201 && body.event_type === "SOS" && body.status === "CONFIRMED", "Creation failed");
  assert(body.detected_at === detectedAt && body.confirmed_at === detectedAt, "Server time not returned");
  assert(body.notification_sent_at && f.sends === 1 && f.events.size === 1, "Delivery not recorded");
  const duplicate = await f.handle();
  assert(duplicate.status === 200 && (await duplicate.json()).event_id === body.event_id, "Retry changed event");
  assert(f.sends === 1 && f.events.size === 1, "Duplicate Telegram or row");
  const next = await f.handle(keyB);
  assert(next.status === 201 && (await next.json()).event_id !== body.event_id, "New hold did not create event");
  assert(Number(f.events.size) === 2 && Number(f.sends) === 2, "New SOS not delivered");
});

Deno.test("invalid device credential and invalid request key cannot create SOS", async () => {
  const f = new Fixture();
  const denied = await handleCreateSosEvent(f.request(), {
    authenticate: async () => ({ ok: false, response: Response.json({ error: "Unauthorized" }, { status: 401 }) }) as DeviceAuthResult,
    notify: f.notify,
  });
  assert(denied.status === 401, "Bad credential accepted");
  const malformed = await f.handle("bad-key");
  assert(malformed.status === 400 && f.events.size === 0, "Bad key accepted");
});

Deno.test("failed Telegram keeps same SOS row and retries delivery", async () => {
  const f = new Fixture();
  f.failSend = true;
  const original = console.error;
  console.error = () => {};
  try {
    assert((await f.handle()).status === 503, "Failure not retried");
  } finally {
    console.error = original;
  }
  assert(f.events.size === 1 && f.events.get(keyA)?.notification_sent_at === null, "Failed send marked delivered");
  f.failSend = false;
  assert((await f.handle()).status === 201, "Retry did not deliver");
  assert(f.events.size === 1 && f.sends === 2, "Retry created second row");
});

Deno.test("SOS Telegram has dedicated copy and existing ACK callback; presence has neither", async () => {
  let payload: Record<string, unknown> = {};
  const options = {
    token: "fake-token", chatId: "12345",
    fetchImpl: async (_url: string | URL | Request, init?: RequestInit) => {
      payload = JSON.parse(init?.body as string);
      return Response.json({ ok: true, result: { message_id: 1 } });
    },
  };
  const result = await sendSosNotification({
    id: keyA, deviceName: "Thiết bị người cao tuổi 01",
    deviceCode: "device01", detectedAt,
  }, options);
  assert(result.ok, "SOS Telegram failed");
  assert(String(payload.text).includes("🆘 YÊU CẦU TRỢ GIÚP KHẨN CẤP"), "SOS header missing");
  assert(String(payload.text).includes("28/09/2026 08:19:16"), "Wrong Vietnam time");
  assert(JSON.stringify(payload.reply_markup).includes(`ack:${keyA}`), "ACK callback missing");
  for (const kind of ["offline", "recovery"] as const) {
    await sendDevicePresenceNotification(kind, {
      deviceName: "Thiết bị 01", deviceCode: "device01", lastSeenAt: detectedAt,
    }, options);
    assert(!String(payload.text).includes("🆘") && payload.reply_markup === undefined,
      `${kind} incorrectly got SOS formatting`);
  }
});
