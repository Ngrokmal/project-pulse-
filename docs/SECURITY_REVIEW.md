# PULSE — security review (Phase 10)

Date: 2026-11-14 · Project ref: `lehrtdrxaioknyuenqeg` · Scope: everything shipped
through Phase 9 (auth, profiles, chat, media, Force Audio, push, groups, calls,
settings).

This is a review of the **real, deployed** system: the migrations listed here were
applied to the live database, and every "proven by" line names a file in
`supabase/tests/` that ran against it.

---

## 1. Rules the whole design leans on

1. **The client is never trusted for identity.** Every table has RLS; every
   privileged operation is a `security definer` function that re-reads
   `auth.uid()` and re-checks membership. The app can lie about anything except
   its JWT.
2. **The client is never trusted for state transitions.** Chat messages, Force
   Audio alerts, group membership and calls all move through RPCs that validate
   the transition server-side.
3. **Secrets live in three places only:** Edge Function secrets (service account,
   keys), the build's `--dart-define`s (anon key — public by design), and the
   developer's `.secrets/env` (never committed). The service-role key is not in
   the app.
4. **Nothing is "probably" fine.** If a control was not exercised by a test, it is
   listed in §7 as not verified rather than assumed.

---

## 2. Authentication and accounts

| Threat | Control | Proven by |
| --- | --- | --- |
| Reading another user's profile row | `profiles` RLS: own row + rows of people you share a conversation with | `10_rls_test.sql`, `80_rls_pentest.sql` ("C cannot rename A") |
| Banned account keeps writing | `account_status` checked inside the message insert policy | `40_live_chat_test.sql` ("banned account cannot send messages"), pentest |
| Client bans itself/unbans itself | `account_status` has **select** grant only; writes are service-role | pentest ("a client cannot ban anybody") |
| Signup spam / enumeration | GoTrue confirmation + per-app rate limits (hosted project) | not tested here — external |

Residual: account deletion (`delete_own_account`) exists as an RPC; the app does
not expose it yet. It is exercised by the RLS suite but there is no UI test.

## 3. Chat

| Threat | Control | Proven by |
| --- | --- | --- |
| Reading a conversation you are not in | `is_conversation_member` inside every policy | `10_rls_test.sql`, `40_live_chat_test.sql`, pentest |
| Posting into someone else's chat | insert policy requires membership **and** `sender_id = auth.uid()` **and** not banned | `40_live_chat_test.sql`, pentest |
| Editing/deleting another user's message | RLS narrows UPDATE/DELETE to zero rows (no error, no effect) | pentest ("C cannot edit/delete A's message") |
| Duplicate sends on a flaky network | `client_id` unique per conversation + outbox | `40_live_chat_test.sql` |
| Fake "read" receipts | only `last_read_at` is writable, column-level grant | `40_live_chat_test.sql` |

## 4. Media

Uploads go **unsigned** to Cloudinary from the client, so the bucket preset is a
public write surface. Controls: the app caps size/duration before upload, the
server re-checks duration/size when a Force Audio alert is created, and the
FCM/Edge path only accepts `res.cloudinary.com` URLs.

Residual (accepted for now): anyone with the unsigned preset name can upload
arbitrary files to the account. It cannot read other users' chats, but it can
consume quota. Mitigation path: switch to signed uploads issued by an Edge
Function (needs the Cloudinary API secret as a function secret).

## 5. Force Audio

| Threat | Control | Proven by |
| --- | --- | --- |
| Client fabricates an alert | Edge Function verifies JWT, conversation membership, recipient, 70 s / 10 MiB caps, Cloudinary host | `30_live_api_test.sh` (§8), `50_force_audio_test.sql` |
| Replay / duplicate alerts | `request_id` unique + server `played` flag + on-device `playedAlertIds` | `30_live_api_test.sh` (idempotent replays), `test/force_audio_screen_test.dart` |
| Sender marks their own alert played | update policy restricted to the recipient | `50_force_audio_test.sql` |
| Bogus alert id opens the takeover screen | the screen fetches by id from the server before playing; unknown/expired/played are terminal | `test/force_audio_screen_test.dart` (3 tests) |

## 6. Groups, calls, push tokens

| Threat | Control | Proven by |
| --- | --- | --- |
| Non-member reads a group, its messages or member list | `is_group_member` in every read path | `60_groups_test.sql` (32), `61_live_groups_api.py` (29) |
| Member promotes themselves to owner | `set_group_role` owner-only; `role` column not client-writable | `60_groups_test.sql`, pentest ("C cannot write its own role") |
| Adding yourself to a group | `add_group_member` requires owner/admin | `60_groups_test.sql`, pentest |
| Starting a call in someone else's chat | `start_call` re-checks conversation membership | `70_calls_test.sql`, `71_live_calls_api.py` |
| Forging a "connected" call | `confirm_call_connected` requires participation and a `connecting` row; the UI additionally needs the media layer | `70_calls_test.sql`, `test/call_machine_test.dart` |
| Outing a third party onto a call | calls only exist inside a direct conversation, both parties recorded | `70_calls_test.sql` ("the caller is me and the callee is the other person") |
| Registering a push token for another user | `fcm_tokens` insert policy requires `user_id = auth.uid()` | pentest ("C cannot register a push token for A"), `10_rls_test.sql` |
| Pushing to a retired token | `send-push` retires tokens FCM rejects | `30_live_api_test.sh` |

## 7. What this review did **not** verify (be honest)

- **No device testing.** No physical Android device was available in this
  environment; behaviour on a real handset (background audio, wake lock, FCM
  delivery latency, Doze) is unverified.
- **No third-party penetration test.** The pentest is our own adversarial SQL
  suite: 22 attacks, all refused.
- **Edge Functions were tested for behaviour, not for dependency CVEs.** No
  `deno audit` equivalent was run.
- **Realtime authorisation** relies on Supabase's own per-row filtering; we
  verified the policies on the tables we stream (`messages`, `conversations`,
  `conversation_members`, `calls`) but did not test a hostile WebSocket client.
- **Rate limiting** on the Edge Function is the platform's default; no custom
  limiter.
- **Cloudinary quota abuse** via the unsigned preset is open (see §4).

## 8. Findings

| # | Severity | Finding | Status |
| --- | --- | --- | --- |
| 1 | Medium | Unsigned Cloudinary preset allows unauthenticated uploads to our account (quota abuse; no data exposure) | Open, accepted for this milestone |
| 2 | Low | `delete_own_account` has no UI, so the RPC is only reachable from code | Open |
| 3 | Low | Call signalling has no timeout job: a `ringing` call that nobody answers stays `ringing` until a client ends it | Open (needs a cron, same pattern as `media-cleanup`) |
| 4 | Low | Settings are device-local, so "notifications off" is not enforced server-side | By design |

No critical or high severity finding is open. That is the Phase 10 gate.
