import {
  assert,
  assertEquals,
  assertThrows,
} from "jsr:@std/assert@1";

import {
  base64url,
  buildMessage,
  classifyFcmError,
  FCM_SCOPE,
  httpStatusFor,
  isUsableToken,
  sendToToken,
  signJwt,
  type ServiceAccount,
} from "./lib.ts";

const GOOD_TOKEN = "dGVzdC1saXZlLWFwaS0" + "0123456789abcdef".repeat(8);

Deno.test("isUsableToken mirrors the DB constraint (20..4096, no spaces)", () => {
  assert(isUsableToken(GOOD_TOKEN));
  assert(!isUsableToken("short"));
  assert(!isUsableToken("x".repeat(4097)));
  assert(!isUsableToken("has space " + "x".repeat(30)));
  assert(!isUsableToken(undefined));
  assert(!isUsableToken(42));
});

Deno.test("buildMessage targets the pulse_default channel with high priority", () => {
  const m = buildMessage(GOOD_TOKEN, { title: "New message", body: "Hey there" });
  assertEquals(m.token, GOOD_TOKEN);
  assertEquals(m.notification.title, "New message");
  assertEquals(m.android.notification.channel_id, "pulse_default");
  assertEquals(m.android.priority, "high");
  assertEquals(m.data, undefined);
});

Deno.test("buildMessage marks Force Audio alerts so the client can branch", () => {
  const m = buildMessage(GOOD_TOKEN, {
    title: "Force audio",
    body: "Open Pulse",
    forceAudio: { alertId: "alert-1", expiresAt: "2026-11-14T13:00:00Z" },
    collapseKey: "alert-1",
  });
  assertEquals(m.data?.kind, "force_audio");
  assertEquals(m.data?.force_audio_alert_id, "alert-1");
  assertEquals(m.data?.force_audio_expires_at, "2026-11-14T13:00:00Z");
  assertEquals(m.android.collapse_key, "alert-1");
  assertEquals(m.android.notification.tag, "alert-1");
});

Deno.test("buildMessage rejects payloads FCM would reject", () => {
  assertThrows(() => buildMessage("short", { title: "a", body: "b" }), Error, "invalid_token");
  assertThrows(() => buildMessage(GOOD_TOKEN, { title: "  ", body: "b" }), Error, "missing_title");
  assertThrows(() => buildMessage(GOOD_TOKEN, { title: "x".repeat(121), body: "b" }), Error, "title_too_long");
  assertThrows(() => buildMessage(GOOD_TOKEN, { title: "a", body: "x".repeat(501) }), Error, "body_too_long");
});

Deno.test("data values are always strings (FCM requirement)", () => {
  const m = buildMessage(GOOD_TOKEN, {
    title: "t",
    body: "b",
    data: { count: 3 as unknown as string, chat: "c1" },
  });
  assertEquals(m.data?.count, "3");
  assertEquals(m.data?.chat, "c1");
});

Deno.test("classifyFcmError separates dead tokens from transient failures", () => {
  assertEquals(classifyFcmError(404, '{"error":{"status":"NOT_FOUND"}}'), "unregistered");
  assertEquals(classifyFcmError(400, '{"error":{"status":"INVALID_ARGUMENT"}}'), "invalid");
  assertEquals(classifyFcmError(429, '{"error":{"status":"RESOURCE_EXHAUSTED"}}'), "quota");
  assertEquals(classifyFcmError(503, "{}"), "retryable");
  assertEquals(classifyFcmError(500, "not json at all"), "retryable");
  assertEquals(httpStatusFor("unregistered"), 410);
  assertEquals(httpStatusFor("invalid"), 410);
  assertEquals(httpStatusFor("quota"), 429);
  assertEquals(httpStatusFor("retryable"), 502);
});

Deno.test("base64url produces url-safe, unpadded output", () => {
  assertEquals(base64url("hello"), "aGVsbG8");
  assert(!/[+/=]/.test(base64url(new Uint8Array([251, 255, 254]))));
});

Deno.test("signJwt signs a verifiable RS256 assertion with the FCM scope", async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  ) as CryptoKeyPair;

  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8))
  }\n-----END PRIVATE KEY-----\n`;

  const sa: ServiceAccount = {
    client_email: "pulse-test@pulse-2f3a4.iam.gserviceaccount.com",
    private_key: pem,
    project_id: "pulse-2f3a4",
  };

  const jwt = await signJwt(sa, 1_700_000_000);
  const [h, c, s] = jwt.split(".");
  const header = JSON.parse(atob(h.replace(/-/g, "+").replace(/_/g, "/")));
  const claims = JSON.parse(atob(c.replace(/-/g, "+").replace(/_/g, "/")));

  assertEquals(header.alg, "RS256");
  assertEquals(claims.iss, sa.client_email);
  assertEquals(claims.scope, FCM_SCOPE);
  assertEquals(claims.iat, 1_700_000_000);
  assertEquals(claims.exp, 1_700_003_600);

  const sig = Uint8Array.from(
    atob(s.replace(/-/g, "+").replace(/_/g, "/")),
    (ch) => ch.charCodeAt(0),
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    pair.publicKey,
    sig,
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert(valid, "signature must verify against the public key");
});

Deno.test("sendToToken maps FCM rejections without leaking the token", async () => {
  const fakeFetch = (() =>
    Promise.resolve(
      new Response('{"error":{"status":"INVALID_ARGUMENT","message":"bad token"}}', {
        status: 400,
      }),
    )) as unknown as typeof fetch;

  const res = await sendToToken(
    "pulse-2f3a4",
    "oauth-token",
    buildMessage(GOOD_TOKEN, { title: "t", body: "b" }),
    fakeFetch,
  );
  assertEquals(res.ok, false);
  if (!res.ok) {
    assertEquals(res.failure, "invalid");
    assert(!res.detail.includes(GOOD_TOKEN), "detail must never echo the token");
  }
});
