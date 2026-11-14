/**
 * Live check against the real Firebase project — no delivery, no secrets printed.
 *
 *   FCM_SERVICE_ACCOUNT="$(cat service-account.json)" \
 *     deno run -A supabase/functions/send-push/live_check.ts
 *
 * 1. OAuth2: our hand-rolled RS256 assertion must be accepted by Google.
 * 2. Payload: `validate_only` makes Google validate the exact message we would
 *    send, without delivering anything.
 * 3. Failure mapping: a syntactically valid but unknown token must be classified
 *    as a dead token, which is what triggers is_active = false.
 */
import {
  buildMessage,
  classifyFcmError,
  fetchAccessToken,
  sendToToken,
  type ServiceAccount,
} from "./lib.ts";

const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
if (!raw) {
  console.error("FCM_SERVICE_ACCOUNT is not set");
  Deno.exit(2);
}
const sa = JSON.parse(raw) as ServiceAccount;
let failures = 0;

function report(name: string, ok: boolean, detail = "") {
  if (!ok) failures++;
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
}

const accessToken = await fetchAccessToken(sa);
report(
  "OAuth2 access token from our RS256 assertion",
  accessToken.length > 50,
  `${accessToken.length} chars`,
);

const probeToken = "dGVzdC1saXZlLWNoZWNrLTA" + "abcdef0123456789".repeat(6);
const message = buildMessage(probeToken, {
  title: "Pulse check",
  body: "validate_only",
  data: { kind: "qa" },
});

// Google validates the *token* even in validate_only mode, so payload
// validation has to use a topic target (topics need no device token). This
// proves credentials, endpoint and the exact notification/android block.
const probe = {
  ...buildMessage(probeToken, {
    title: "Pulse check",
    body: "validate_only",
    data: { kind: "qa" },
    collapseKey: "pulse-qa",
  }),
} as Record<string, unknown>;
delete probe.token;
probe.topic = "pulse_qa_probe";

const probeRes = await fetch(
  `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
  {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ validate_only: true, message: probe }),
  },
);
const probeBody = await probeRes.text();
report(
  "FCM accepted our message shape (validate_only, topic target)",
  probeRes.ok,
  probeRes.ok ? probeBody.slice(0, 60) : `${probeRes.status} ${probeBody.slice(0, 200)}`,
);

const real = await sendToToken(sa.project_id, accessToken, message);
report(
  "unknown token classified as a dead token",
  !real.ok && (real.failure === "unregistered" || real.failure === "invalid"),
  real.ok ? "unexpectedly delivered" : real.failure,
);

// Prove the classifier never mistakes a rate limit or server error for a dead token.
report(
  "error classifier keeps 5xx retryable",
  classifyFcmError(503, "backend error") === "retryable",
);

console.log(
  failures === 0
    ? "\n===== LIVE FCM CHECK: all assertions passed ====="
    : `\n===== LIVE FCM CHECK: ${failures} failed =====`,
);
Deno.exit(failures === 0 ? 0 : 1);
