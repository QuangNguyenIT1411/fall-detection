import { handleConfirmFallEvent } from "./index.ts";
import { sendDevicePresenceNotification, sendFallConfirmedNotification } from "../_shared/telegram.ts";
import type { DeviceAuthResult } from "../_shared/device_auth.ts";

const eventId = "10000000-0000-4000-8000-000000000103";
const deviceId = "00000000-0000-4000-8000-000000000001";
const confirmedAt = "2026-09-28T01:19:16Z";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function fixture(initialStatus: "DETECTED" | "CANCELLED" | "CONFIRMED", eligible = true) {
  const event = {
    id: eventId, status: initialStatus as string,
    confirmed_at: initialStatus === "CONFIRMED" ? confirmedAt : null as string | null,
    notification_sent_at: null as string | null,
    notification_eligible: eligible,
    peak_acc: 10.82, peak_gyro: 1000.1, final_pose: 83.9,
    low_g_duration_ms: 1150, low_g_to_impact_ms: 1160,
  };
  let claim: string | null = null;
  const client = {
    from(table: string) {
      return {
        select(_columns: string) {
          return {
            eq(_column: string, _value: string) { return this; },
            async maybeSingle() {
              return { data: table === "devices"
                ? { name: "Thiết bị người cao tuổi 01", device_code: "device01" }
                : { ...event }, error: null };
            },
          };
        },
      };
    },
    async rpc(name: string, args: Record<string, string>) {
      switch (name) {
        case "confirm_device_fall_event":
          if (event.status === "DETECTED") {
            event.status = "CONFIRMED";
            event.confirmed_at = confirmedAt;
          }
          return { data: event.status === "CONFIRMED" ? [{ ...event }] : [], error: null };
        case "claim_fall_notification":
          if (event.status !== "CONFIRMED" || !event.notification_eligible || event.notification_sent_at || claim) {
            return { data: false, error: null };
          }
          claim = args.p_claim_token;
          return { data: true, error: null };
        case "release_fall_notification_claim":
          if (claim === args.p_claim_token) claim = null;
          return { data: null, error: null };
        case "mark_fall_notification_sent":
          if (claim !== args.p_claim_token) return { data: null, error: null };
          event.notification_sent_at = "2026-09-28T01:19:17Z";
          claim = null;
          return { data: event.notification_sent_at, error: null };
      }
      throw new Error(`Unknown RPC: ${name}`);
    },
  };
  const authenticate = async (_request: Request): Promise<DeviceAuthResult> =>
    ({ ok: true, deviceId, supabase: client } as unknown as DeviceAuthResult);
  const request = () => new Request("https://example.test/confirm", {
    method: "POST", body: JSON.stringify({ event_id: eventId }),
  });
  return { event, authenticate, request };
}

Deno.test("DETECTED alone does not notify; CANCELLED cannot notify", async () => {
  for (const status of ["DETECTED", "CANCELLED"] as const) {
    const f = fixture(status);
    let calls = 0;
    const response = await handleConfirmFallEvent(
      status === "DETECTED"
        ? new Request("https://example.test/confirm", { method: "GET" })
        : f.request(),
      { authenticate: f.authenticate, notify: async () => { calls++; return { ok: true }; } },
    );
    assert(response.status === (status === "DETECTED" ? 405 : 409), "Unexpected status");
    assert(calls === 0, "Notification sent before confirmation");
  }
});

Deno.test("transition sends once and repeat confirm does not resend", async () => {
  const f = fixture("DETECTED");
  let calls = 0;
  const notify = async () => {
    assert(f.event.status === "CONFIRMED", "Sent while only DETECTED");
    calls++; return { ok: true as const };
  };
  const first = await handleConfirmFallEvent(f.request(), { authenticate: f.authenticate, notify });
  const again = await handleConfirmFallEvent(f.request(), { authenticate: f.authenticate, notify });
  assert(first.status === 200 && again.status === 200, "Confirmation failed");
  assert(calls === 1, "Duplicate Telegram send");
  assert(f.event.status === "CONFIRMED", "DB status not confirmed");
  assert(f.event.notification_sent_at !== null, "Delivery not marked");
});

Deno.test("pre-Phase-7 CONFIRMED event is not sent retrospectively", async () => {
  const f = fixture("CONFIRMED", false);
  let calls = 0;
  const response = await handleConfirmFallEvent(f.request(), {
    authenticate: f.authenticate,
    notify: async () => { calls++; return { ok: true }; },
  });
  assert(response.status === 200 && calls === 0, "Legacy event was sent");
  assert(f.event.notification_sent_at === null, "Legacy event incorrectly marked sent");
});

Deno.test("concurrent confirm cannot claim a second Telegram send", async () => {
  const f = fixture("CONFIRMED");
  let releaseSend = () => {};
  const waitForSend = new Promise<void>((resolve) => { releaseSend = resolve; });
  let enteredSend = () => {};
  const entered = new Promise<void>((resolve) => { enteredSend = resolve; });
  let calls = 0;
  const notify = async () => {
    calls++;
    enteredSend();
    await waitForSend;
    return { ok: true as const };
  };
  const first = handleConfirmFallEvent(f.request(), { authenticate: f.authenticate, notify });
  await entered;
  const second = await handleConfirmFallEvent(f.request(), { authenticate: f.authenticate, notify });
  assert(second.status === 503 && calls === 1, "Second caller sent concurrently");
  releaseSend();
  assert((await first).status === 200, "First send did not finish");
  assert((await handleConfirmFallEvent(f.request(), { authenticate: f.authenticate, notify })).status === 200,
    "Completed notification is not idempotent");
  assert(calls === 1, "Notification sent again after completion");
});

Deno.test("Telegram failure keeps CONFIRMED and NULL; retry sends", async () => {
  const f = fixture("DETECTED");
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => { logs.push(args.join(" ")); };
  try {
    const first = await handleConfirmFallEvent(f.request(), {
      authenticate: f.authenticate,
      notify: async () => ({ ok: false, error: "transport_error" }),
    });
    assert(first.status === 503, "Failure must request retry");
    assert(f.event.status === "CONFIRMED", "Confirmation rolled back");
    assert(f.event.notification_sent_at === null, "Failed delivery was marked sent");
    const second = await handleConfirmFallEvent(f.request(), {
      authenticate: f.authenticate,
      notify: async () => ({ ok: true }),
    });
    assert(second.status === 200 && f.event.notification_sent_at !== null, "Retry failed");
    assert(!logs.join(" ").includes("secret-test-token"), "Secret logged");
  } finally {
    console.error = original;
  }
});

Deno.test("Telegram HTTP is mocked, message uses Vietnam timezone, no secret logs", async () => {
  const f = fixture("CONFIRMED");
  const payload = {
    id: eventId, deviceName: "Thiết bị 01", deviceCode: "device01",
    confirmedAt, peakAcc: 10.82, peakGyro: 1000.1, finalPose: 83.9,
    lowGDurationMs: 1150, lowGToImpactMs: 1160,
  };
  let text = "";
  let markup: unknown;
  const result = await sendFallConfirmedNotification(payload, {
    token: "secret-test-token", chatId: "12345",
    fetchImpl: async (_url, init) => {
      const sent = JSON.parse(init?.body as string);
      text = sent.text;
      markup = sent.reply_markup;
      return Response.json({ ok: true, result: { message_id: 123 } });
    },
  });
  assert(result.ok, "Mock send failed");
  assert(text.includes("28/09/2026 08:19:16"), "Wrong Vietnam time");
  assert(text.includes("Peak ACC: 10.82 g"), "Missing metric");
  assert(text.includes(eventId), "Missing event UUID");
  assert(JSON.stringify(markup).includes(`ack:${eventId}`), "ACK button missing");
  const rejected = await sendFallConfirmedNotification(payload, {
    token: "secret-test-token", chatId: "12345",
    fetchImpl: async () => Response.json({ ok: false, description: "denied" }),
  });
  assert(!rejected.ok, "Rejected Telegram response accepted");
  assert(f.event.notification_sent_at === null, "Mock changed database");

  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => { logs.push(args.join(" ")); };
  try {
    const transport = await sendFallConfirmedNotification(payload, {
      token: "secret-test-token", chatId: "12345",
      fetchImpl: async () => { throw new Error("request URL contains secret-test-token"); },
    });
    assert(!transport.ok && transport.error === "transport_error", "Transport error not sanitized");
    assert(!logs.join(" ").includes("secret-test-token"), "Secret logged");
  } finally {
    console.error = original;
  }
});

Deno.test("device offline/recovery Telegram never has fall ACK button", async () => {
  for (const kind of ["offline", "recovery"] as const) {
    let sentBody: Record<string, unknown> = {};
    const result = await sendDevicePresenceNotification(kind, {
      deviceName: "Thiết bị 01", deviceCode: "device01",
      lastSeenAt: confirmedAt,
    }, {
      token: "fake-token", chatId: "12345",
      fetchImpl: async (_url, init) => {
        sentBody = JSON.parse(init?.body as string);
        return Response.json({ ok: true, result: { message_id: 123 } });
      },
    });
    assert(result.ok && sentBody.reply_markup === undefined, `${kind} has ACK button`);
  }
});

Deno.test("Telegram failure does not prevent a confirmed FALL voice call", async () => {
  const f = fixture("DETECTED");
  let calls = 0;
  const original = console.error;
  console.error = () => {};
  try {
    const response = await handleConfirmFallEvent(f.request(), {
      authenticate: f.authenticate,
      notify: async () => ({ ok: false, error: "transport_error" }),
      voice: async () => { calls++; return { state: "accepted", sid: `CA${"b".repeat(32)}` }; },
    });
    assert(response.status === 503 && f.event.status === "CONFIRMED" && calls === 1,
      "Telegram failure blocked voice");
  } finally { console.error = original; }
});

Deno.test("voice failure does not prevent FALL Telegram or resend it on retry", async () => {
  const f = fixture("DETECTED");
  let calls = 0;
  const voice = async () => {
    calls++;
    return calls === 1
      ? { state: "failed" as const, error: "AUTH_ERROR" as const, retryable: false }
      : { state: "failed" as const, error: "AUTH_ERROR" as const, retryable: false };
  };
  const first = await handleConfirmFallEvent(f.request(), {
    authenticate: f.authenticate, notify: async () => ({ ok: true }), voice,
  });
  const second = await handleConfirmFallEvent(f.request(), {
    authenticate: f.authenticate, notify: async () => { throw new Error("Duplicate Telegram"); }, voice,
  });
  assert(first.status === 200 && second.status === 200 &&
    f.event.notification_sent_at !== null && calls === 2,
    "Voice failure blocked Telegram or retry failed");
});
