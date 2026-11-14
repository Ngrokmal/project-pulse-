# PULSE — Phase 4 report

**Date:** 2026-11-14 · **Two jobs this phase:** (a) find and kill the "You appear
to be offline" bug that blocked your device testing, (b) build real chat.

---

## 1. The offline bug — root cause, proven

Your downloaded APK had **no `INTERNET` permission**. Flutter only puts that
permission in `android/app/src/debug/AndroidManifest.xml`, so `flutter run`
worked in development while every **release** build silently failed every HTTP
request — which the app then reported as "You appear to be offline".

Proof from the manifest history:

```
e686dac (Phase 1 APK) : INTERNET in main manifest = 0
f3b9323 (Phase 2 APK) : INTERNET in main manifest = 0   ← what you installed
b3994e0 (Phase 3 APK) : INTERNET in main manifest = 1
```

And from the shipped Phase-3 binary itself (androguard, on the artifact):

```
package      : com.pulsemessenger.app
permissions  : ACCESS_NETWORK_STATE, INTERNET, POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK,
               com.google.android.c2dm.permission.RECEIVE, …
endpoint     : https://lehrtdrxaioknyuenqeg.supabase.co   (embedded)
key          : sb_publishable_… (embedded, 46 chars)
```

So: **install the newest artifact from the `Build release APK` job** and the
network works. Everything below makes sure this class of bug cannot come back
quietly.

### Three permanent fixes

1. **CI gate.** After building, the workflow runs `aapt2 dump permissions` and
   fails the job if `INTERNET` or `POST_NOTIFICATIONS` is missing. A release APK
   without network permission can no longer be published.
2. **In-app connection check** (`/connection`, linked from the welcome screen, the
   profile and every network error state). It measures, step by step: build
   config → DNS lookup → HTTPS to `/auth/v1/settings` → PostgREST read, each with
   latency and a specific hint, plus a **copyable report**.
3. **Visible build stamp.** The APK now embeds `BUILD_LABEL` (`<sha>-run<n>`),
   shown in Profile → About and in the connection report. You can always tell
   which artifact is installed.
4. Network failures now carry the underlying cause (`SocketException: Failed host
   lookup …`) in small print instead of a single vague sentence.

---

## 2. Chat backend (migration `0004_chat.sql`, applied live)

| object | contents |
| --- | --- |
| `conversations` | `kind='direct'`, `pair_key` unique, last-message preview/sender/time |
| `conversation_members` | membership + `last_read_at`; PK `(conversation_id, user_id)` |
| `messages` | `message_kind` enum, body ≤4000, media fields, `client_id`, soft delete |
| `start_direct_conversation(uuid)` | SECURITY DEFINER, **idempotent** for a pair of users |
| `handle_new_message()` | keeps the conversation preview in sync |
| realtime | `messages`, `conversations`, `conversation_members` added to the publication |

Privileges had to be taken back explicitly: **Supabase's default privileges grant
`ALL` on every new public table to `authenticated`**, which made `joined_at`
writable. The migration now revokes insert/update/delete and grants only
`select` (+ `update (last_read_at)` on members) — the same column-level
discipline the `profiles` table uses. This was caught by the live suite, not by
reading code.

### Live verification

`supabase/tests/40_live_chat_test.sql` — **19 / 19 assertions pass** on the
production project (single transaction, rolled back):

```
PASS  starting the same chat twice returns the same conversation
PASS  cannot start a chat with yourself
PASS  member can send a message
PASS  conversation preview updated by trigger
PASS  replaying the same client_id is rejected (idempotent send)
PASS  cannot send as another user
PASS  cannot send into a foreign conversation
PASS  clients cannot create conversations directly
PASS  read receipts: only last_read_at is writable
PASS  outsider sees no conversations / messages / membership rows
PASS  banned account cannot send messages
```

`supabase/tests/30_live_api_test.sh` grew to **54 / 54** assertions, adding the
whole chat path over PostgREST (RPC idempotency, message insert, `client_id`
collision → 409, preview trigger, sender spoofing → 403, cross-tenant insert →
403, read receipts, forged `joined_at` → 403, anon lockout). The cleanup also
revealed a leak — memberless conversations survived the test users — which is
now swept automatically; residue is `users=0 convs=0 msgs=0 members=0`.

---

## 3. Chat in the app

* **Conversation list** is now the Home tab (`ChatsScreen`), showing the peer, the
  real preview (`You: …` when the last word is yours), time and unread emphasis.
  A **New chat** sheet starts (or reuses) a direct conversation through the RPC.
* **Chat screen**: gradient own bubbles / lavender counterpart bubbles per the
  mockups, day dividers, long-press to soft-delete, Realtime inserts appended
  live, auto-scroll, `typing…` in the app bar.
* **Sending is optimistic**: the bubble appears instantly as `pending`, becomes
  `sent` on success or `failed` with a **Tap to retry** action.
* **Offline-first with Hive** (`hive_ce`): the last 120 messages per conversation
  are cached; opening a chat offline shows the cached history with an
  `offline — showing saved messages` badge instead of an error screen. Failed
  sends go to a persisted outbox and are retried with their original `client_id`,
  so a retry can never duplicate a message.
* **Typing indicator**: one Realtime broadcast per **3 seconds** maximum per
  sender (throttled in `ChatThreadController.typingThrottle`), displayed for 4s.
* Read receipts update `last_read_at` on open and on every incoming message.

---

## 4. Measured results

| check | result |
| --- | --- |
| `dart analyze lib test` | **No issues found** |
| `flutter test` | **60 / 60 pass** (+1 live probe skipped without dart-defines) |
| `deno test supabase/functions/` | 9 / 9 pass |
| local migration + RLS harness (`run_local.sh`, bare PostgreSQL) | **ALL RLS TESTS PASSED** |
| live chat RLS suite | **19 / 19 pass** |
| live API suite (profiles, tokens, chat) | **54 / 54 pass** |
| live FCM probe | 4 / 4 pass |

---

## 5. What you can test right now with a fresh APK

1. Download the artifact from the latest green `Build release APK` run.
2. **Profile → About** shows the build label — confirm it matches that run.
3. If anything says offline, open **Profile → Connection check** (or the link on
   the welcome screen) and copy the report; it names the failing step.
4. Create two accounts (signup needs the confirmation mail — the built-in mailer
   allows ~2/hour, so use the SMTP fix below or reuse accounts you already have),
   open **New chat**, pick the other account and send a message from both phones.
5. Sign in on the second account and watch the message arrive live; kill the
   network mid-send to see the `failed` bubble and **Tap to retry**; reopen the
   chat offline to see the cached history.

---

## 6. Still blocked on you (unchanged)

1. **Supabase PAT** → deploy `device-register` and `send-push`.
2. **Rotate** the leaked Firebase service-account key, then set the
   `FCM_SERVICE_ACCOUNT` repo secret.
3. **Custom SMTP** so signups/confirmations are not rate limited.
4. **Firebase console**: add release SHA-1 `75:8B:BA:84:4B:21:BB:7D:55:6E:1B:40:CD:DE:DF:88:E3:52:D3:2E`.

## 7. Phase 5 entry point

Media messages: Cloudinary uploads with real progress (image → `image`,
video → `video` ≤49 MiB, everything else → `raw` ≤10 MiB), the audio recorder for
Force Audio (≤70 s), and then the Force Audio end-to-end flow on top of
`send-push` (which already emits `kind=force_audio` + `force_audio_alert_id`).
