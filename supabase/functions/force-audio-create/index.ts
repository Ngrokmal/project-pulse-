// Edge Function: force-audio-create (§5)
//
// The only way an alert + its push should be created. The client cannot call
// send-push (it is service_role only), so this function is the missing link:
//
//   caller JWT → validate payload → insert the alert AS THE CALLER (RLS decides
//   membership, bans, limits) → push the recipient's devices → return the row.
//
// Nothing is trusted from the request except the alert payload; the audio URL
// must be on our Cloudinary account, and the limits are re-checked here on top of
// the database constraints (defense in depth: a compromised client cannot skip
// the DB checks, and a modified DB cannot skip these).

import { createClient } from "jsr:@supabase/supabase-js@2";

import { validate } from "./lib.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const COLUMNS =
  "id, request_id, conversation_id, message_id, sender_id, recipient_id, media_url, " +
  "duration_ms, size_bytes, mime_type, state, created_at, expires_at, played_at";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: { code: "method_not_allowed" } }, 405);

  const correlationId = crypto.randomUUID();
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ ok: false, error: { code: "unauthenticated" }, correlationId }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Caller-scoped client: every read/write below runs under RLS as this user.
  const asUser = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await asUser.auth.getUser();
  const caller = userData?.user;
  if (userError || !caller) {
    return json({ ok: false, error: { code: "unauthenticated" }, correlationId }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: { code: "invalid_json" }, correlationId }, 400);
  }

  const validated = validate(body, caller.id);
  if (!validated.ok || !validated.value) {
    return json({ ok: false, error: { code: "validation_failed", fields: validated.errors }, correlationId }, 400);
  }
  const alert = validated.value;

  // Insert as the caller: RLS enforces membership, active accounts, and that the
  // recipient is the other member of this conversation.
  const { data: inserted, error: insertError } = await asUser
    .from("force_audio_alerts")
    .insert({
      request_id: alert.requestId,
      conversation_id: alert.conversationId,
      message_id: alert.messageId ?? null,
      sender_id: caller.id,
      recipient_id: alert.recipientId,
      media_url: alert.mediaUrl,
      duration_ms: alert.durationMs,
      size_bytes: alert.sizeBytes,
      mime_type: alert.mimeType ?? "audio/mp4",
    })
    .select(COLUMNS)
    .single();

  let row = inserted as Record<string, unknown> | null;
  if (insertError) {
    // A retry with the same request id is success, not an error.
    if (insertError.code === "23505") {
      const { data: existing } = await asUser
        .from("force_audio_alerts")
        .select(COLUMNS)
        .eq("request_id", alert.requestId)
        .maybeSingle();
      row = existing as Record<string, unknown> | null;
    } else {
      const forbidden = insertError.code === "42501" || insertError.message.includes("row-level security");
      return json(
        {
          ok: false,
          error: { code: forbidden ? "not_allowed" : "insert_failed" },
          correlationId,
        },
        forbidden ? 403 : 400,
      );
    }
  }

  if (!row) {
    return json({ ok: false, error: { code: "insert_failed" }, correlationId }, 400);
  }

  // Sender display name for the notification, read as the caller (profiles are
  // readable by authenticated users).
  const { data: profile } = await asUser
    .from("profiles")
    .select("display_name")
    .eq("id", caller.id)
    .maybeSingle();
  const senderName = (profile?.display_name as string | undefined) ?? "Someone";

  // Push through send-push with the service key. A raw fetch (not
  // functions.invoke) keeps the Authorization header explicit, which is what
  // send-push's service-key check reads.
  let push: Record<string, unknown> = { sent: 0, failed: 0 };
  try {
    const response = await fetch(`${url}/functions/v1/send-push`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
      },
      body: JSON.stringify({
        userId: alert.recipientId,
        title: `Force Audio from ${senderName}`,
        body: "Tap to listen",
        data: {
          conversation_id: alert.conversationId,
          kind: "force_audio",
        },
        collapseKey: `force_audio_${row.id}`,
        forceAudio: {
          alertId: row.id as string,
          expiresAt: row.expires_at as string,
        },
      }),
    });
    const text = await response.text();
    // send-push answers with a real body even on 410 (all devices gone), so read
    // it either way: "0 delivered, 1 dead token retired" is a fact, not a crash.
    const parsed = JSON.parse(text) as Record<string, unknown>;
    push = {
      sent: (parsed.sent as number) ?? 0,
      failed: (parsed.failed as number) ?? 0,
      deactivated: (parsed.deactivated as number) ?? 0,
      status: response.status,
    };
  } catch (e) {
    console.error(`[${correlationId}] push_failed`, (e as Error).message);
    push = { sent: 0, failed: 0, error: "push_failed" };
  }

  return json({ ok: true, alert: row, push, correlationId });
});
