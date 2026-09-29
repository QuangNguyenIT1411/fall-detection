import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { handleSetBuzzerEnabled } from "./index.ts";

function assert(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
class Fixture {
  verified = false;
  valid = true;
  anonymous = false;
  role = "authenticated";
  enabled = true;
  writes = 0;
  privilegedClients = 0;
  fail = false;
  missingDevice = false;
  publicClient = () => ({ auth: { getUser: (token: string) => {
    assert(token === "test-session", "Token was not forwarded to Auth verification");
    this.verified = this.valid;
    return Promise.resolve({ data: { user: this.valid ? { id: "caregiver", role: this.role,
      is_anonymous: this.anonymous } : null }, error: this.valid ? null : { message: "Invalid JWT" } });
  } } } as unknown as SupabaseClient);
  serviceClient = () => {
    assert(this.verified && !this.anonymous && this.role === "authenticated", "Service access before user auth");
    this.privilegedClients++;
    return { rpc: (name: string, args: Record<string, unknown>) => {
      assert(name === "set_device_buzzer_enabled" && Object.keys(args).join() === "p_enabled", "Arbitrary update");
      if (this.fail) return Promise.resolve({ data: null, error: { message: "private-provider-message" } });
      if (this.missingDevice) return Promise.resolve({ data: [], error: null });
      this.enabled = args.p_enabled as boolean;
      this.writes++;
      return Promise.resolve({ data: [{ buzzer_enabled: this.enabled, buzzer_updated_at: "2026-09-30T00:00:00Z" }], error: null });
    } } as unknown as SupabaseClient;
  };
  call(body: string, authorization: string | null = "Bearer test-session") {
    return handleSetBuzzerEnabled(new Request("https://example/set-buzzer-enabled", {
      method: "POST", headers: authorization ? { authorization, "content-type": "application/json" } : {}, body,
    }), this);
  }
}

Deno.test("missing/invalid/anonymous/service JWT never acquires privileged client", async () => {
  const f = new Fixture();
  assert((await f.call('{"enabled":false}', null)).status === 401, "Missing token allowed");
  f.valid = false;
  assert((await f.call('{"enabled":false}')).status === 401, "Invalid session allowed");
  f.valid = true; f.anonymous = true;
  assert((await f.call('{"enabled":false}')).status === 401, "Anonymous session allowed");
  f.anonymous = false; f.role = "service_role";
  assert((await f.call('{"enabled":false}')).status === 401, "Non-caregiver role allowed");
  assert(f.privilegedClients === 0 && f.writes === 0, "Unauthenticated mutation");
});

Deno.test("verified caregiver can save OFF/ON with sanitized server timestamps", async () => {
  const f = new Fixture();
  for (const enabled of [false, true]) {
    const response = await f.call(JSON.stringify({ enabled }));
    const body = await response.json();
    assert(response.status === 200 && f.enabled === enabled && body.buzzer_enabled === enabled, "Write failed");
    assert(Object.keys(body).sort().join() === "buzzer_enabled,success,updated_at", "Unsanitized output");
    assert(body.updated_at === "2026-09-30T00:00:00Z", "Timestamp not from database");
    assert(response.headers.get("access-control-allow-origin") === "*", "Missing browser CORS");
  }
});

Deno.test("malformed and arbitrary-device payloads are rejected without service access", async () => {
  const f = new Fixture();
  for (const body of ["{", "null", "[]", "{}", '{"enabled":"false"}', '{"enabled":0}',
    '{"enabled":false,"device_id":"other"}', '{"enabled":false,"status":"CANCELLED"}']) {
    assert((await f.call(body)).status === 400, "Malformed payload accepted");
  }
  assert(f.privilegedClients === 0, "Invalid body acquired service client");
});

Deno.test("CORS preflight has no side effects and failures expose no private errors", async () => {
  const f = new Fixture();
  const preflight = await handleSetBuzzerEnabled(new Request("https://example/test", { method: "OPTIONS" }), f);
  assert(preflight.status === 204 && !f.verified && f.privilegedClients === 0, "Preflight side effect");
  f.fail = true;
  const result = await f.call('{"enabled":false}');
  assert(result.status === 500 && !(await result.text()).includes("private-provider-message"), "Raw error leaked");
  f.fail = false; f.missingDevice = true;
  assert((await f.call('{"enabled":false}')).status === 404 && f.writes === 0, "Missing device created");
});
