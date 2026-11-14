// Pure validation tests for force-audio-create (§5 limits, URL trust).
import { assertEquals } from "jsr:@std/assert@1";
import { LIMITS, validate } from "./index.ts";

const CALLER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const CONV = "33333333-3333-4333-8333-333333333333";

function body(over: Record<string, unknown> = {}) {
  return {
    requestId: "fa-request-0001",
    conversationId: CONV,
    recipientId: OTHER,
    mediaUrl: "https://res.cloudinary.com/kojvlesm/video/upload/v1/a.m4a",
    durationMs: 42000,
    sizeBytes: 240000,
    ...over,
  };
}

Deno.test("a well-formed request passes", () => {
  const r = validate(body(), CALLER);
  assertEquals(r.ok, true);
  assertEquals(r.value?.durationMs, 42000);
});

Deno.test("70 s is allowed, 70.001 s is not", () => {
  assertEquals(validate(body({ durationMs: LIMITS.maxDurationMs }), CALLER).ok, true);
  const tooLong = validate(body({ durationMs: LIMITS.maxDurationMs + 1 }), CALLER);
  assertEquals(tooLong.ok, false);
  assertEquals(tooLong.errors[0].code, "out_of_range");
});

Deno.test("10 MiB is allowed, 10 MiB + 1 is not", () => {
  assertEquals(validate(body({ sizeBytes: LIMITS.maxBytes }), CALLER).ok, true);
  assertEquals(validate(body({ sizeBytes: LIMITS.maxBytes + 1 }), CALLER).ok, false);
});

Deno.test("anything shorter than half a second is rejected", () => {
  assertEquals(validate(body({ durationMs: 499 }), CALLER).ok, false);
});

Deno.test("an audio URL that is not ours is rejected", () => {
  const r = validate(body({ mediaUrl: "https://evil.example.com/a.m4a" }), CALLER);
  assertEquals(r.ok, false);
  assertEquals(r.errors[0].code, "untrusted_host");
});

Deno.test("http (not https) is rejected", () => {
  assertEquals(validate(body({ mediaUrl: "http://res.cloudinary.com/a.m4a" }), CALLER).ok, false);
});

Deno.test("you cannot force-audio yourself", () => {
  const r = validate(body({ recipientId: CALLER }), CALLER);
  assertEquals(r.ok, false);
  assertEquals(r.errors[0].code, "self");
});

Deno.test("non-uuid ids are rejected", () => {
  assertEquals(validate(body({ conversationId: "nope" }), CALLER).ok, false);
  assertEquals(validate(body({ recipientId: "nope" }), CALLER).ok, false);
});

Deno.test("a short request id is rejected", () => {
  assertEquals(validate(body({ requestId: "abc" }), CALLER).ok, false);
});

Deno.test("junk bodies never throw", () => {
  assertEquals(validate(null, CALLER).ok, false);
  assertEquals(validate("nope", CALLER).ok, false);
  assertEquals(validate({ durationMs: "42000" }, CALLER).ok, false);
});
