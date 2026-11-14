// Edge Function: device-register (§31.7)
// Verifies the caller's JWT, hashes the Android ID server-side with a keyed
// HMAC (raw Android ID is never stored), records account↔device history and
// returns the authoritative device status. Clients never write device rows.
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const HASH_VERSION = 1;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function fail(code: string, message: string, status = 400) {
  return json({ ok: false, error: { code, message } }, status);
}

async function keyedHash(raw: string, key: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(`${HASH_VERSION}:${raw}`));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST required", 405);

  const correlationId = crypto.randomUUID();
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return fail("unauthorized", "Missing bearer token", 401);

  const hashKey = Deno.env.get("DEVICE_HASH_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  // Never echo which secret is missing.
  if (!hashKey || !supabaseUrl || !serviceKey) {
    return fail("server_misconfigured", "Service is not configured", 500);
  }

  let body: { androidId?: unknown; platform?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail("invalid_json", "Body must be JSON", 400);
  }

  const androidId = typeof body.androidId === "string" ? body.androidId.trim() : "";
  const platform = body.platform === "android" ? "android" : "android";
  if (androidId.length < 1 || androidId.length > 64) {
    return fail("invalid_android_id", "androidId must be 1-64 characters", 422);
  }

  // Client bound to the caller's JWT — used only to identify the user.
  const asUser = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return fail("unauthorized", "Invalid session", 401);

  // Service client (bypasses RLS) for the privileged writes.
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  const deviceHash = await keyedHash(androidId, hashKey);

  const { data: device, error: deviceError } = await admin
    .from("devices")
    .upsert(
      {
        device_hash: deviceHash,
        hash_version: HASH_VERSION,
        platform,
        last_seen: new Date().toISOString(),
      },
      { onConflict: "device_hash,hash_version" },
    )
    .select("id, status")
    .single();

  if (deviceError || !device) {
    console.error("device_upsert_failed", correlationId, deviceError?.code);
    return fail("device_register_failed", "Could not register this device", 500);
  }

  if (device.status === "banned") {
    return json({
      ok: false,
      error: { code: "device_banned", message: "This device is blocked from using Pulse." },
      correlationId,
    }, 403);
  }

  const { data: existingLink } = await admin
    .from("account_device_history")
    .select("user_id")
    .eq("device_id", device.id)
    .eq("user_id", user.id)
    .maybeSingle();

  const { error: linkError } = await admin
    .from("account_device_history")
    .upsert(
      { user_id: user.id, device_id: device.id, last_seen: new Date().toISOString() },
      { onConflict: "user_id,device_id" },
    );

  if (linkError) {
    console.error("device_link_failed", correlationId, linkError.code);
    return fail("device_register_failed", "Could not register this device", 500);
  }

  if (!existingLink) {
    // First time this account is seen on this device — audit only, no auto-ban.
    await admin.from("device_security_events").insert({
      device_id: device.id,
      user_id: user.id,
      event: "account_linked",
      meta: { correlationId },
    });
  }

  const { count } = await admin
    .from("account_device_history")
    .select("user_id", { count: "exact", head: true })
    .eq("device_id", device.id);

  return json({
    ok: true,
    deviceId: device.id,
    status: device.status,
    // Informational only: multiple accounts on one phone is legitimate.
    accountCount: count ?? 1,
    correlationId,
  });
});
