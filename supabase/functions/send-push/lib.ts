/**
 * Pure, dependency-free logic for the send-push Edge Function.
 * Kept separate from index.ts so it can be unit-tested without a network or a
 * Supabase client (`deno test supabase/functions/send-push/`).
 */

export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
export const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const CHANNEL_ID = "pulse_default";

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri?: string;
}

export interface PushRequest {
  /** Deliver to every active device of this account. */
  userId?: string;
  /** Deliver to exactly one stored token (used by Force Audio Alert). */
  token?: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  highPriority?: boolean;
  /** Collapse key so N messages replace each other instead of stacking. */
  collapseKey?: string;
  /** Force Audio Alert: sound that must play even in silent mode. */
  forceAudio?: { alertId: string; expiresAt?: string };
}

export interface FcmMessage {
  token: string;
  notification: { title: string; body: string };
  data?: Record<string, string>;
  android: {
    priority: "high" | "normal";
    collapse_key?: string;
    notification: {
      channel_id: string;
      sound?: string;
      default_vibrate_timings?: boolean;
      default_sound?: boolean;
      tag?: string;
    };
  };
}

/** Mirrors the DB CHECK on fcm_tokens_len (20..4096) so we fail fast. */
export function isUsableToken(token: unknown): token is string {
  return (
    typeof token === "string" &&
    !/\s/.test(token) &&
    token.length >= 20 &&
    token.length <= 4096
  );
}

/**
 * Builds the FCM HTTP v1 message. Every value is validated here: a malformed
 * payload is rejected by Google with a 400 and the user simply never gets the
 * notification, which is worse than a loud local error.
 */
export function buildMessage(token: string, req: PushRequest): FcmMessage {
  if (!isUsableToken(token)) throw new Error("invalid_token");
  const title = (req.title ?? "").trim();
  const body = (req.body ?? "").trim();
  if (!title) throw new Error("missing_title");
  if (title.length > 120) throw new Error("title_too_long");
  if (body.length > 500) throw new Error("body_too_long");

  const data: Record<string, string> = { ...(req.data ?? {}) };
  if (req.forceAudio) {
    // The client looks for this to activate the Force Audio screen instead of a
    // plain notification tap.
    data.force_audio_alert_id = req.forceAudio.alertId;
    if (req.forceAudio.expiresAt) {
      data.force_audio_expires_at = req.forceAudio.expiresAt;
    }
    data.kind = "force_audio";
  }
  // FCM requires every data value to be a string.
  for (const [k, v] of Object.entries(data)) data[k] = String(v);

  return {
    token,
    notification: { title, body },
    ...(Object.keys(data).length ? { data } : {}),
    android: {
      priority: req.highPriority === false ? "normal" : "high",
      ...(req.collapseKey ? { collapse_key: req.collapseKey } : {}),
      notification: {
        channel_id: CHANNEL_ID,
        default_sound: true,
        default_vibrate_timings: true,
        ...(req.collapseKey ? { tag: req.collapseKey } : {}),
      },
    },
  };
}

export type FcmFailure = "unregistered" | "invalid" | "quota" | "retryable";

/**
 * Classifies a failed FCM response so the caller knows whether the stored token
 * is dead (and should be deactivated) or whether the send is worth retrying.
 */
export function classifyFcmError(status: number, body: string): FcmFailure {
  const text = body ?? "";
  const status_ = (() => {
    try {
      return (JSON.parse(text) as { error?: { status?: string } }).error?.status ??
        "";
    } catch {
      return "";
    }
  })();

  if (status === 404 || status_ === "NOT_FOUND" || status_ === "UNREGISTERED") {
    return "unregistered";
  }
  if (
    status_ === "INVALID_ARGUMENT" ||
    /registration token|invalid.*token/i.test(text)
  ) {
    return "invalid";
  }
  if (status === 429 || status_ === "RESOURCE_EXHAUSTED" || status_ === "QUOTA_EXCEEDED") {
    return "quota";
  }
  return "retryable";
}

/** Which HTTP status we report to our own caller for a given FCM failure. */
export function httpStatusFor(failure: FcmFailure): number {
  switch (failure) {
    case "unregistered":
    case "invalid":
      return 410; // gone: the stored token is useless
    case "quota":
      return 429;
    default:
      return 502;
  }
}

// ---------------------------------------------------------------------------
// Google OAuth2 (JWT bearer grant) with WebCrypto — no googleapis dependency.
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();

export function base64url(input: ArrayBuffer | Uint8Array | string): string {
  const bytes =
    typeof input === "string" ? encoder.encode(input) : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

export async function signJwt(
  serviceAccount: ServiceAccount,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: serviceAccount.client_email,
    scope: FCM_SCOPE,
    aud: serviceAccount.token_uri || TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(
    JSON.stringify(claims),
  )}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(unsigned),
  );
  return `${unsigned}.${base64url(signature)}`;
}

/** Exchanges a signed assertion for an OAuth2 access token. */
export async function fetchAccessToken(
  serviceAccount: ServiceAccount,
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  const assertion = await signJwt(serviceAccount);
  const res = await fetchImpl(serviceAccount.token_uri || TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json() as { access_token?: string; error?: string };
  if (!res.ok || !json.access_token) {
    // Never echo the assertion or the key.
    throw new Error(`oauth_failed:${res.status}:${json.error ?? "unknown"}`);
  }
  return json.access_token;
}

export async function sendToToken(
  projectId: string,
  accessToken: string,
  message: FcmMessage,
  fetchImpl: typeof fetch = fetch,
  /** Google validates the message without delivering it. Used by the tests. */
  validateOnly = false,
): Promise<{ ok: true } | { ok: false; failure: FcmFailure; detail: string }> {
  const res = await fetchImpl(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(validateOnly ? { validate_only: true, message } : { message }),
    },
  );
  if (res.ok) return { ok: true };
  const detail = await res.text();
  return {
    ok: false,
    failure: classifyFcmError(res.status, detail),
    // Trim: FCM errors can be long; never include the token.
    detail: detail.slice(0, 300),
  };
}
