// Pure validation for force-audio-create. Kept separate from index.ts so the
// tests can import it without starting an HTTP server (Deno.serve at import time
// would need --allow-net, which the CI test job deliberately does not grant).

export const LIMITS = {
  maxDurationMs: 70000,
  minDurationMs: 500,
  maxBytes: 10 * 1024 * 1024,
  cloudinaryPrefix: "https://res.cloudinary.com/",
};

export interface AlertRequest {
  requestId: string;
  conversationId: string;
  recipientId: string;
  mediaUrl: string;
  durationMs: number;
  sizeBytes: number;
  messageId?: string;
  mimeType?: string;
}

export type ValidationError = { field: string; code: string; message: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Pure so it can be unit-tested without a database. */
export function validate(body: unknown, callerId: string): {
  ok: boolean;
  errors: ValidationError[];
  value?: AlertRequest;
} {
  const errors: ValidationError[] = [];
  const raw = (body ?? {}) as Record<string, unknown>;

  const str = (k: string): string => (typeof raw[k] === "string" ? (raw[k] as string) : "");
  const num = (k: string): number => (typeof raw[k] === "number" ? (raw[k] as number) : NaN);

  const requestId = str("requestId");
  const conversationId = str("conversationId");
  const recipientId = str("recipientId");
  const mediaUrl = str("mediaUrl");
  const durationMs = num("durationMs");
  const sizeBytes = num("sizeBytes");

  if (requestId.length < 8 || requestId.length > 64) {
    errors.push({ field: "requestId", code: "invalid", message: "requestId must be 8-64 chars" });
  }
  if (!UUID.test(conversationId)) {
    errors.push({ field: "conversationId", code: "invalid", message: "conversationId must be a uuid" });
  }
  if (!UUID.test(recipientId)) {
    errors.push({ field: "recipientId", code: "invalid", message: "recipientId must be a uuid" });
  }
  if (recipientId && recipientId === callerId) {
    errors.push({ field: "recipientId", code: "self", message: "you cannot force-audio yourself" });
  }
  if (!mediaUrl.startsWith(LIMITS.cloudinaryPrefix)) {
    errors.push({ field: "mediaUrl", code: "untrusted_host", message: "audio must be hosted on Cloudinary" });
  }
  if (!Number.isFinite(durationMs) || durationMs < LIMITS.minDurationMs || durationMs > LIMITS.maxDurationMs) {
    errors.push({ field: "durationMs", code: "out_of_range", message: "recording must be 0.5-70 s" });
  }
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0 || sizeBytes > LIMITS.maxBytes) {
    errors.push({ field: "sizeBytes", code: "out_of_range", message: "recording must be at most 10 MB" });
  }
  const messageId = str("messageId");

  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    errors: [],
    value: {
      requestId,
      conversationId,
      recipientId,
      mediaUrl,
      durationMs,
      sizeBytes,
      messageId: UUID.test(messageId) ? messageId : undefined,
      mimeType: str("mimeType") || "audio/mp4",
    },
  };
}
