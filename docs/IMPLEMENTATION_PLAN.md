# PULSE — Implementation Plan (master prompt §17 phases)

**Stack:** Flutter (Android) · Supabase (Auth/Postgres/RLS/Realtime/Edge Functions) · Cloudinary (media) · FCM (push) · Hive (offline-first) · Agora **deferred by design** (§23)

---

## 1. Architecture — feature-first + clean layers

```
lib/
├── main.dart                        # bootstrap, error boundary, DI overrides
├── app/
│   ├── app.dart                     # MaterialApp.router, theme, locale
│   ├── router/                      # go_router config, guards (auth, banned, onboarding)
│   └── di/                          # Riverpod providers, dependency graph
├── core/
│   ├── config/
│   │   ├── app_config.dart          # env (SUPABASE_URL, ANON_KEY, CLOUDINARY_*, limits)
│   │   └── limits.dart              # SINGLE SOURCE OF TRUTH for §6 caps
│   ├── error/                       # AppFailure hierarchy, mapping PostgREST/FCM/Cloudinary
│   ├── logging/                     # structured logger + redaction
│   ├── extensions/  utils/  widgets/# shared UI atoms (buttons, states, skeletons)
│   └── theme/                       # tokens (color/type/space/radius/shadow/motion)
├── features/
│   ├── auth/            {data, domain, application, presentation}
│   ├── onboarding/      splash, welcome, brand intro
│   ├── profile/         my / other / edit / privacy
│   ├── friends/         requests, relationships
│   ├── explore/         search, filters
│   ├── inbox/           conversation list, filters, FABs
│   ├── chat/            personal chat, composer, media, voice, replies, reactions
│   ├── groups/          create, members, roles, group chat
│   ├── force_audio/     ★ record, upload, receive, check, download, play
│   ├── calls/           history + UI + provider abstraction (Agora slot)
│   ├── settings/        notifications, data, privacy, force audio prefs
│   ├── account_status/  banned / suspended / under-review screen
│   └── media/           uploader, downloader, cache, viewers
└── shared/              cross-feature models, services, local db
```

**Dependency rule:** `presentation → application → domain ← data`. UI-te kono SQL/HTTP/FCM/file-I/O nei. Sob provider interface er pichone.

**State:** Riverpod (feature-scoped `Notifier`s + `select` to avoid whole-tree rebuilds).
**Routing:** go_router with guards — `authGuard`, `accountStatusGuard`, `deviceGuard`.
**Local:** Hive boxes per feature + change-log for cursor sync.
**DI:** Riverpod overrides only; no global singleton service locators.

---

## 2. Single source of truth — limits (§6, §19.13)

```dart
// core/config/limits.dart
const kImageMaxBytes  = 10 * 1024 * 1024;   // MiB, defined once
const kVideoMaxBytes  = 49 * 1024 * 1024;   // 49 MiB
const kRawMaxBytes    = 10 * 1024 * 1024;   // 10 MiB (audio, pdf, zip...)
const kForceAudioMaxDurationMs = 70 * 1000; // 1m10s
// resource type mapping — EXACT (§6): image→image, video→video, EVERYTHING ELSE→raw
```
Server (Edge Function) same numbers re-validate kore; client-only check **kokhono** trusted na.

---

## 3. Database schema (v1 draft — final hobe migration likhar somoy)

| Table | Key columns | Notes |
|---|---|---|
| `profiles` | id(uuid=uid), username(uniq), display_name, bio, avatar_url, cover_url, joined_at, last_seen_at, privacy jsonb | username lowercase + unique index |
| `account_status` | user_id, status enum(active, suspended, banned, under_review), reason_code, reason_text, starts_at, ends_at, updated_by | server-authoritative (§25) |
| `devices` | id, device_hash, hash_version, platform, first_seen, last_seen, status enum | §31.7 |
| `account_device_history` | user_id, device_id, first_seen, last_seen | distinct account count per device |
| `device_security_events` | id, device_id, user_id, event, meta, created_at | audit |
| `fcm_tokens` | id, user_id, device_id, token(uniq), platform, is_active, updated_at | multi-device (§9) |
| `friendships` | user_a, user_b (a<b), created_at | unique pair, **no follow** |
| `friend_requests` | id, sender_id, receiver_id, status enum(pending, accepted, declined, cancelled), created_at | unique pending per pair |
| `blocks` | blocker_id, blocked_id, created_at | enforced in RLS + Edge Fn |
| `conversations` | id, type enum(direct, group), title, avatar_url, created_by, last_message_at | |
| `conversation_members` | conversation_id, user_id, role enum(owner, admin, member), joined_at, muted_until, last_read_at | role server-enforced |
| `messages` | id, conversation_id, sender_id, client_msg_id(uniq per sender), type enum(text, image, video, audio, file, force_audio_ref, system), body, reply_to, created_at, edited_at, deleted_for_all | idempotent via client_msg_id |
| `message_attachments` | id, message_id, resource_type enum(image, video, raw), public_id, secure_url, format, bytes, duration_ms, width, height | Cloudinary metadata only |
| `message_receipts` | message_id, user_id, delivered_at, read_at | |
| `message_reactions` | message_id, user_id, emoji | unique |
| `force_audio_alerts` ★ | id, request_id(uniq idempotency), sender_id, recipient_id, cloudinary_public_id, secure_url, duration_ms, bytes, status enum(queued, pushed, delivered, downloaded, played, failed, expired), created_at, expires_at | binary **kokhono** DB te na |
| `calls` | id, conversation_id, initiator_id, type enum(voice, video), status enum(states...), started_at, ended_at, duration_s | Agora join hole provider_room_id add |
| `call_participants` | call_id, user_id, state, joined_at, left_at | |
| `notifications` | id, user_id, type, payload jsonb, read_at | in-app inbox |

**Index rationale (examples):** `messages(conversation_id, created_at desc, id desc)` for cursor pagination; `conversations(last_message_at desc)` inbox; `profiles(username)` uniq lookups; `friend_requests(receiver_id, status)`; `force_audio_alerts(recipient_id, created_at desc)`.

**RLS baseline (matrix full hobe migration doc e):**
- `messages`: SELECT only if caller is member of conversation AND not blocked; INSERT only if sender = auth.uid() AND member AND not blocked.
- `force_audio_alerts`: SELECT only recipient/sender; INSERT **only** through Edge Function (service role), client insert denied.
- `account_status`: SELECT own row; write denied to all client roles.
- `devices`: SELECT own; no client UPDATE of status.
- `conversations`: direct conversation create via RPC (atomic, both members).

---

## 4. Supabase Edge Functions (all trusted server work)

| Function | Responsibility | Secrets |
|---|---|---|
| `fcm-send` | auth+authorization, idempotency, FCM HTTP v1 send, invalid-token cleanup | `FIREBASE_SERVICE_ACCOUNT` |
| `force-audio-create` | validate ≤70s/≤10MB, verify recipient relationship, insert alert, trigger `fcm-send` | + Cloudinary (verify only) |
| `cloudinary-sign` | short-lived signed upload params (per resource_type, with cap) | `CLOUDINARY_API_SECRET` |
| `device-register` | verify JWT, keyed-hash Android ID server-side, upsert device + history, enforce device status | `DEVICE_HASH_KEY` |
| `account-status` | return server-authoritative status for guards | — |
| `media-cleanup` (cron) | reconcile orphan uploads, expire stale force audio | service role |

Rules: typed request/response contracts, correlation IDs, structured redacted logs, bounded retry with backoff+jitter for **transient only**, no secret in response/logs.

---

## 5. Force Audio — state machine (§5)

```
SENDER:   idle → recording → (paused) → recorded → validating → uploading(real %)
          → submitted → queued(server ack) → done
          failure branches: permission_denied, too_long(>70s), too_large(>10MB),
          upload_failed(retry), server_rejected(reason)

RECEIVER: push_received → verifying(server) → checking("Checking for new messages")
          → downloading(real % ) → verifying_file → ready → playing → played
          failure branches: expired, unauthorized, network_lost(retry),
          storage_full, corrupt_file, playback_failed
```
- Client **kokhono** arbitrary URL trust korbe na — alert id diye server verify, tarpor download.
- Duplicate guard: `request_id` unique + local `playedAlertIds` Hive box + "played" server state.
- "Checking for new messages" persist korbe puro download jure (fake progress na).
- Foreground activation: **tomar proven implementation** (B1) onujayi, Android version constraint documented.

---

## 6. Typing indicator (§24) — event policy

```
keystroke → reset local 3s timer (NO network)
first keystroke of a session → 1 broadcast typing=true
3s continuous inactivity     → 1 broadcast typing=false
send / leave / dispose       → cancel timer + typing=false (guarded by session token)
receiver                      → local expiry 5s if stop event missed
```
**Test:** type 100 chars ⇒ assert exactly 1 `typing=true` broadcast, 1 `typing=false` after 3s; no per-char writes.

---

## 7. Device identity (§31.7) — privacy design

1. Client reads `Settings.Secure.ANDROID_ID` via small platform channel (`device_id` plugin, Android-only, null-safe).
2. Client sends raw value **only** to `device-register` over TLS, once per session (not per rebuild).
3. Server computes `HMAC-SHA256(ANDROID_ID, DEVICE_HASH_KEY)` with `hash_version=1` → stores hash.
4. Never expose raw Android ID; never use IMEI/MAC/serial; document instability (factory reset/signing/user profile).
5. Risk thresholds configurable; **multiple accounts alone kabhi auto-ban na**; review + appeal path.

---

## 8. Phase plan with gates (§17)

| Phase | Deliverable | Gate (pass na hole porer phase e jabо na) |
|---|---|---|
| **0** | Audit + plan + risk register | ✅ ei document |
| **1** | Design system, brand assets, app icon/splash, navigation shell, splash + welcome UI | `flutter analyze` clean, widget test for theme, icon set rendered, CI APK builds |
| **2** | Migrations (profiles, status, devices, fcm_tokens), RLS, Auth flows, device register | migration fresh-run + RLS allow/deny tests pass |
| **3** | Friends, explore/search, requests, profile states | relationship state machine tests |
| **4** | Inbox, direct chat, pagination, realtime, Hive offline queue | offline send survives kill/restart; no duplicate on retry |
| **5** | Cloudinary pipeline (image/video/raw), limits, progress, cache | boundary tests 10MB/49MB pass; wrong resource_type rejected |
| **6** | **Force Audio** (bell, recorder, upload, FCM, receive, download, play) | end-to-end on **your device**, duplicate-delivery test, 70s/10MB enforcement |
| **7** | Groups + roles + group media | non-member read denied by RLS (proven) |
| **8** | Calling UI + state machine + provider abstraction (no Agora) | every state reachable, no fake "connected" |
| **9** | Notifications/settings/sounds/a11y/lifecycle hardening | permission-denied paths tested |
| **10** | Security review, RLS pentest, regression, perf profiling, release build, docs | no known critical/high defects; documented measurements |

---

## 9. Test plan (mapped to §16)

- **Static:** `flutter analyze`, `dart format --set-exit-if-changed`, custom lints (dependency direction).
- **Unit:** limit validation, resource-type mapping, typing FSM, error mapping, cursor pagination, retry policy.
- **Widget:** every screen's loading/empty/error/offline states.
- **Integration:** auth → profile → friend → chat → media → force audio (emulator `/dev/kvm` nei, tai CI te `flutter test integration_test` **run hobe na** — documented limitation).
- **SQL:** migration from empty DB; RLS allow/deny matrix (anon vs member vs non-member vs blocked).
- **Edge Function:** contract tests with mocked FCM/Cloudinary.
- **Failure drill:** no-internet send, upload interrupted, 4xx/5xx, invalid FCM token, oversized files, >70s audio, duplicate FCM, process death mid-download, permission denied, expired session.
- **Manual (your device):** Force Audio foreground behaviour, notification channels, Doze/battery-saver, real push delivery.

---

## 10. Deliverables checklist (§18)

- [x] Phase 0 audit (this folder)
- [x] Design tokens + brand SVG sources + rendered icon set (started)
- [ ] Flutter source (feature-first, clean arch)
- [ ] Ordered SQL migrations + RLS matrix doc
- [ ] Edge Function sources + deploy instructions
- [ ] FCM + Cloudinary configuration docs
- [ ] Force Audio flow doc + test evidence
- [ ] `.env.example` (placeholders only, no secrets)
- [ ] Build/run + deployment checklist
- [ ] Known limitations + verified test report
