import { handleDeviceHeartbeat } from "./index.ts";
import { handleCheckDeviceOffline } from "../check-device-offline/index.ts";
import type { DeviceAuthResult } from "../_shared/device_auth.ts";
import {
  deliverPresenceNotification,
  type PresenceNotifier,
} from "../_shared/device_presence.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

class Fixture {
  now = new Date("2026-09-28T00:00:00Z");
  lastSeen: string | null = null;
  status = "ONLINE";
  offlineSince: string | null = null;
  offlineSent: string | null = null;
  recoveryPending: string | null = null;
  recoverySent: string | null = null;
  offlineClaim: string | null = null;
  recoveryClaim: string | null = null;
  sent: string[] = [];
  failOffline = false;
  buzzerEnabled = true;
  configError = false;

  get client(): SupabaseClient {
    return this as unknown as SupabaseClient;
  }
  get authenticate(): (_request: Request) => Promise<DeviceAuthResult> {
    return async () => ({
      ok: true,
      deviceId: "device01-id",
      supabase: this.client,
    });
  }
  get notify(): PresenceNotifier {
    return async (kind) => {
      if (kind === "offline" && this.failOffline) {
        return { ok: false, error: "transport_error" };
      }
      this.sent.push(kind);
      return { ok: true };
    };
  }

  from(_table: string) {
    const filters: Record<string, unknown> = {};
    const query = {
      select(_columns: string) {
        return this;
      },
      eq(column: string, value: unknown) {
        filters[column] = value;
        return this;
      },
      lt(column: string, value: unknown) {
        filters[`lt:${column}`] = value;
        return this;
      },
      is(column: string, value: unknown) {
        filters[`is:${column}`] = value;
        return this;
      },
      not(column: string, _operator: string, value: unknown) {
        filters[`not:${column}`] = value;
        return this;
      },
      limit(_count: number) {
        return this;
      },
      maybeSingle: async () => ({
        data: {
          name: "Thiết bị người cao tuổi 01",
          device_code: "device01",
          last_seen_at: this.lastSeen,
          offline_since: this.offlineSince,
          recovery_pending_at: this.recoveryPending,
          buzzer_enabled: this.buzzerEnabled,
        },
        error: this.configError ? { message: "test read failure" } : null,
      }),
      then: (resolve: (value: unknown) => void) => {
        const stale = filters["lt:last_seen_at"] !== undefined;
        const eligible = stale
          ? this.lastSeen !== null &&
            this.lastSeen < String(filters["lt:last_seen_at"]) &&
            !this.offlineSent
          : this.status === "ONLINE" && !!this.recoveryPending &&
            !this.recoverySent;
        resolve({ data: eligible ? [{ id: "device01-id" }] : [], error: null });
      },
    };
    return query;
  }

  async rpc(name: string, args: Record<string, string>) {
    const token = args.p_claim_token;
    switch (name) {
      case "record_device_heartbeat": {
        if (this.status === "OFFLINE" && this.offlineSent) {
          this.recoveryPending ??= this.now.toISOString();
        }
        this.lastSeen = this.now.toISOString();
        this.status = "ONLINE";
        return {
          data: [{
            last_seen_at: this.lastSeen,
            recovery_pending: !!this.recoveryPending,
          }],
          error: null,
        };
      }
      case "claim_device_offline_notification": {
        const stale = this.lastSeen !== null &&
          this.now.getTime() - Date.parse(this.lastSeen) > 60000;
        if (!stale || this.offlineSent || this.offlineClaim) {
          return { data: false, error: null };
        }
        this.status = "OFFLINE";
        this.offlineSince = new Date(Date.parse(this.lastSeen!) + 60000)
          .toISOString();
        this.recoverySent = null;
        this.offlineClaim = token;
        return { data: true, error: null };
      }
      case "mark_device_offline_notification":
        if (this.offlineClaim !== token) return { data: null, error: null };
        this.offlineSent = this.now.toISOString();
        this.offlineClaim = null;
        return { data: this.offlineSent, error: null };
      case "release_device_offline_claim":
        if (this.offlineClaim === token) this.offlineClaim = null;
        return { data: null, error: null };
      case "claim_device_recovery_notification":
        if (
          !this.recoveryPending || !this.offlineSent || this.recoveryClaim ||
          this.recoverySent
        ) {
          return { data: false, error: null };
        }
        this.recoveryClaim = token;
        return { data: true, error: null };
      case "mark_device_recovery_notification":
        if (this.recoveryClaim !== token) return { data: null, error: null };
        this.recoverySent = this.now.toISOString();
        this.recoveryPending = null;
        this.offlineSince = null;
        this.offlineSent = null;
        this.recoveryClaim = null;
        return { data: this.recoverySent, error: null };
      case "release_device_recovery_claim":
        if (this.recoveryClaim === token) this.recoveryClaim = null;
        return { data: null, error: null };
    }
    throw new Error(`Unknown RPC ${name}`);
  }
}

function heartbeat(f: Fixture) {
  return handleDeviceHeartbeat(
    new Request("https://example.test/heartbeat", { method: "POST" }),
    {
      authenticate: f.authenticate,
      notify: f.notify,
    },
  );
}

Deno.test("authenticated heartbeat returns current buzzer setting without changing recovery semantics", async () => {
  const f = new Fixture();
  for (const enabled of [true, false, true]) {
    f.buzzerEnabled = enabled;
    const response = await heartbeat(f);
    const body = await response.json();
    assert(response.status === 200 && body.buzzer_enabled === enabled && body.success === true,
      "Heartbeat omitted authoritative boolean");
    assert(f.status === "ONLINE" && f.sent.length === 0, "Buzzer changed presence notification behavior");
  }
  f.configError = true;
  assert((await heartbeat(f)).status === 500, "Configuration read failure must not invent a value");
});

function checker(f: Fixture) {
  Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-not-real");
  return handleCheckDeviceOffline(
    new Request("https://example.test/check", {
      method: "POST",
      headers: { "x-cron-secret": "x".repeat(32) },
    }),
    {
      cronSecret: "x".repeat(32),
      now: () => f.now,
      createSupabase:
        (() =>
          f.client) as unknown as typeof import("npm:@supabase/supabase-js@2.57.4").createClient,
      notify: f.notify,
    },
  );
}

Deno.test("fresh heartbeats stay ONLINE without Telegram; legacy row is ignored", async () => {
  const f = new Fixture();
  await checker(f);
  assert(f.sent.length === 0, "Legacy device alerted");
  assert(
    (await heartbeat(f)).status === 200 && f.status === "ONLINE",
    "Heartbeat failed",
  );
  f.now = new Date(f.now.getTime() + 20000);
  await heartbeat(f);
  await checker(f);
  assert(f.sent.length === 0, "Active device alerted");
});

Deno.test("stale device alerts once; repeated checks do not duplicate", async () => {
  const f = new Fixture();
  await heartbeat(f);
  f.now = new Date(f.now.getTime() + 61000);
  await checker(f);
  await checker(f);
  assert(f.status === "OFFLINE", "Device not marked offline");
  assert(f.sent.join() === "offline", "Offline alert was not exactly once");
});

Deno.test("concurrent checkers share one offline delivery claim", async () => {
  const f = new Fixture();
  await heartbeat(f);
  f.now = new Date(f.now.getTime() + 61000);
  let unblock = () => {};
  const pending = new Promise<void>((resolve) => {
    unblock = resolve;
  });
  let entered = () => {};
  const started = new Promise<void>((resolve) => {
    entered = resolve;
  });
  let calls = 0;
  const slowNotify: PresenceNotifier = async () => {
    calls++;
    entered();
    await pending;
    return { ok: true };
  };
  const first = deliverPresenceNotification(
    f.client,
    "device01-id",
    "offline",
    slowNotify,
  );
  await started;
  const second = await deliverPresenceNotification(
    f.client,
    "device01-id",
    "offline",
    slowNotify,
  );
  assert(
    second === "skipped" && calls === 1,
    "Concurrent worker duplicated send",
  );
  unblock();
  assert((await first) === "sent", "First worker did not complete");
});

Deno.test("Telegram failure releases claim; retry and second cycle work", async () => {
  const f = new Fixture();
  await heartbeat(f);
  f.now = new Date(f.now.getTime() + 61000);
  f.failOffline = true;
  await checker(f);
  assert(
    f.status === "OFFLINE" && !f.offlineSent && f.sent.length === 0,
    "Failed send marked delivered",
  );
  f.failOffline = false;
  await checker(f);
  await heartbeat(f);
  await heartbeat(f);
  assert(
    f.sent.join() === "offline,recovery",
    "Recovery duplicated or missing",
  );
  f.now = new Date(f.now.getTime() + 61000);
  await checker(f);
  await heartbeat(f);
  assert(
    f.sent.join() === "offline,recovery,offline,recovery",
    "Second cycle failed",
  );
});
