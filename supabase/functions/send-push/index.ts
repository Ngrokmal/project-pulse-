/**
 * send-push — the only place in PULSE that talks to Firebase (§31).
 *
 * Contract
 *   POST /functions/v1/send-push
 *   Authorization: Bearer <service role JWT>   (verify_jwt = true)
 *   { userId?: string, token?: string, title: string, body: string,
 *     data?: Record<string,string>, collapseKey?: string,
 *     forceAudio?: { alertId: string, expiresAt?: string } }
 *
 * Guarantees
 *   • Clients can never call this: the caller's role claim must be service_role.
 *   • Tokens are read from fcm_tokens (RLS-protected); dead tokens are marked
 *     is_active = false instead of being retried forever.
 *   • Secrets never leave the server: the service account JSON and the tokens
 *     are never logged or echoed; responses carry only counts and suffixes.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

import {
  buildMessage,
  fetchAccessToken,
  httpStatusFor,
  isUsableToken,
  type PushRequest,
  type ServiceAccount,
  sendToToken,
} from "./lib.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface JwtClaims {
  role?: string;
  sub?: string;
}

function decodeClaims(jwt: string): JwtClaims {
  try {
    const part = jwt.split(".")[1];
    const padded = part.replace(/-/g, "+").replace(/_/g, "/");
    const json = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
    return JSON.parse(json) as JwtClaims;
  } catch {
    return {};
  }
}


/** Length-independent comparison: no early exit that leaks a prefix. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function serviceAccountFromEnv(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) throw new Error("missing_service_account");
  const parsed = JSON.parse(raw) as ServiceAccount;
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error("malformed_service_account");
  }
  return parsed;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const correlationId = crypto.randomUUID();
  const authHeader = req.headers.get("Authorization") ?? "";
  const callerJwt = authHeader.replace(/^Bearer\s+/i, "");
  const claims = decodeClaims(callerJwt);
  const serviceKeyHeader = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Admin-only primitive: the mobile app must never be able to push arbitrary
  // notifications to arbitrary accounts.
  //
  // Two accepted callers, both server-side:
  //   • a JWT whose role claim is service_role (the legacy anon/service JWT pair)
  //   • the project's current service key, compared literally. Newer projects
  //     issue `sb_secret_…` keys that are not JWTs, so the claim check alone
  //     would lock every server-side caller out of this function.
  const isServiceJwt = claims.role === "service_role";
  const isServiceKey = serviceKeyHeader.length > 0 &&
    timingSafeEqual(callerJwt, serviceKeyHeader);
  if (!isServiceJwt && !isServiceKey) {
    return json({ ok: false, error: "forbidden", correlationId }, 403);
  }

  let payload: PushRequest;
  try {
    payload = await req.json() as PushRequest;
  } catch {
    return json({ ok: false, error: "invalid_json", correlationId }, 400);
  }

  if (!payload.userId && !payload.token) {
    return json({ ok: false, error: "no_target", correlationId }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = serviceAccountFromEnv();
  } catch (e) {
    // Deliberately vague to the caller; the real reason goes to server logs.
    console.error(`[${correlationId}] config_error`, (e as Error).message);
    return json({ ok: false, error: "push_not_configured", correlationId }, 503);
  }
  if (!supabaseUrl || !serviceKey) {
    console.error(`[${correlationId}] missing_supabase_env`);
    return json({ ok: false, error: "push_not_configured", correlationId }, 503);
  }

  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  let tokens: string[] = [];
  if (payload.token) {
    if (!isUsableToken(payload.token)) {
      return json({ ok: false, error: "invalid_token", correlationId }, 400);
    }
    tokens = [payload.token];
  } else {
    const { data, error } = await db
      .from("fcm_tokens")
      .select("token")
      .eq("user_id", payload.userId)
      .eq("is_active", true);
    if (error) {
      console.error(`[${correlationId}] token_lookup_failed`, error.code);
      return json({ ok: false, error: "lookup_failed", correlationId }, 500);
    }
    tokens = (data ?? []).map((r) => r.token as string).filter(isUsableToken);
  }

  if (tokens.length === 0) {
    return json({ ok: true, sent: 0, failed: 0, reason: "no_devices", correlationId });
  }

  let accessToken: string;
  try {
    accessToken = await fetchAccessToken(serviceAccount);
  } catch (e) {
    console.error(`[${correlationId}] oauth_failed`, (e as Error).message);
    return json({ ok: false, error: "oauth_failed", correlationId }, 502);
  }

  const results: Array<{ ok: boolean; failure?: string }> = [];
  const dead: string[] = [];

  for (const token of tokens) {
    let message;
    try {
      message = buildMessage(token, payload);
    } catch (e) {
      // A bad payload is our bug: fail loudly, do not mark the token dead.
      console.error(`[${correlationId}] build_failed`, (e as Error).message);
      results.push({ ok: false, failure: "invalid_payload" });
      continue;
    }
    const outcome = await sendToToken(
      serviceAccount.project_id,
      accessToken,
      message,
    );
    if (outcome.ok) {
      results.push({ ok: true });
    } else {
      results.push({ ok: false, failure: outcome.failure });
      console.warn(
        `[${correlationId}] send_failed`,
        outcome.failure,
        outcome.detail,
      );
      if (outcome.failure === "unregistered" || outcome.failure === "invalid") {
        dead.push(token);
      }
    }
  }

  // Retire tokens Google no longer recognises, so the next send is cheap.
  if (dead.length) {
    const { error } = await db
      .from("fcm_tokens")
      .update({ is_active: false })
      .in("token", dead);
    if (error) console.error(`[${correlationId}] deactivate_failed`, error.code);
  }

  const sent = results.filter((r) => r.ok).length;
  const failed = results.length - sent;
  const status = failed === 0
    ? 200
    : httpStatusFor(
      (results.find((r) => !r.ok)?.failure as "retryable") ?? "retryable",
    );

  return json(
    {
      ok: failed === 0,
      sent,
      failed,
      deactivated: dead.length,
      correlationId,
    },
    status,
  );
});
