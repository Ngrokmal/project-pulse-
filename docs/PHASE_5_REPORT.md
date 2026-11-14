# Phase 5 progress report — media messages (5a) shipped

**Commit:** `5b305d2` · **CI run:** `43606865403` (all 4 jobs green) ·
**Artifact:** `pulse-release-apk`, 29.8 MB, id `14118920981`

Phase 5 was authorized as three things: media messages with real Cloudinary
progress, the Force Audio recorder (≤ 70 s), and the Force Audio end-to-end flow.
**This report covers item 1 only (5a). Items 2 and 3 are not built yet** — see
"What is still missing" at the end.

---

## 1. What a tester can now do

1. Install the artifact APK, **log in** (see §5 — sign-up is still blocked by
   Supabase's mailer, not by the app).
2. Open a chat, tap the **paperclip** in the composer.
3. Pick a photo → it uploads to Cloudinary while a bar shows the real percentage
   (bytes actually sent), then the bubble shows the image loaded from Cloudinary.
4. Pick a video / PDF / zip → same upload path, bubble shows a file card with the
   real size; tapping it opens the file in the system viewer.

Nothing in that path is a placeholder: no fake progress timer, no dead button, no
local-only "sent" state.

## 2. Measured results

| Check | Command | Result |
|---|---|---|
| Static analysis (lib + test) | `dart analyze lib test` | **No issues found** |
| Unit/widget tests | `flutter test` | **72 passed, 2 skipped** (the 2 skips are the live-network tests, which need `--dart-define=CLOUDINARY_CLOUD_NAME`) |
| Real image upload | `flutter test test/live/media_upload_test.dart` | HTTP 200, `https://res.cloudinary.com/kojvlesm/image/upload/v1794667578/pulse/messages/teiebawv5ruijmz9lgss.jpg`, 148 568 bytes |
| Real progress stream | same | 4 194 304 bytes → **65 progress events**, monotonic, last = **1.0** |
| Raw resource routing | same | text file → `…/raw/upload/…` 200 |
| Live API suite (PostgREST + RLS) | `supabase/tests/30_live_api_test.sh` | **64 / 64 passed** (8 new media assertions) |
| Chat RLS suite | `supabase/tests/40_live_chat_test.sql` | **19 / 19 passed** |
| Local RLS harness | `supabase/tests/run_local.sh` | **ALL RLS TESTS PASSED** |
| Release APK permissions (from the downloaded artifact, not source) | androguard on `app-release.apk` | `INTERNET, POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK, ACCESS_NETWORK_STATE, com.google.android.c2dm.permission.RECEIVE` |
| `<queries>` present in the release manifest | androguard | `VIEW https`, `VIEW http`, `image/*`, `video/*`, `audio/*` |
| Cloudinary config baked into the release binary | `grep -c` on `libapp.so` | `kojvlesm: 1`, `pulse_unsigned: 1` |

The new media assertions in the live suite prove the server side of the contract
without trusting the client:

- an image message with an **empty body** and a `media_url` is accepted (201);
- the other member can read that `media_url`;
- `media_bytes` round-trips (148 568);
- a non-text message **without** `media_url` is rejected (400) — the check
  constraint, not app code;
- `media_bytes = 0` is rejected;
- an unknown `kind` is rejected;
- a **text** message with an empty body is still rejected.

## 3. How the upload actually reports progress

`CloudinaryUploader` does not use `MultipartFile.fromPath` (which hides the
transfer). It opens `file.openRead()` and pipes it through a counting
`StreamTransformer` into `http.MultipartFile('file', stream, total)`. Every chunk
that leaves the app increments the counter and pushes `sent / total` to the UI, so
the bar is the fraction of bytes handed to the socket. Because the byte length is
passed up front, the multipart request still carries a correct `Content-Length` —
no chunked-encoding rejections from Cloudinary (the 4 MiB test above is the proof).

Routing and limits live in `PickedMedia`:

| Type | Extensions | Resource | Limit |
|---|---|---|---|
| image | jpg, jpeg, png, webp, heic, gif | `image` | 10 MiB |
| video | mp4, mov, m4v, 3gp, webm, mkv | `video` | 49 MiB |
| everything else | — | `raw` | 10 MiB |

The limit is enforced on the client **before** any byte is sent, and the unsigned
preset `pulse_unsigned` carries a server-side `max_file_size` of 52 428 800 bytes
(50 MiB) as a second fence.

## 4. Changes in this phase

- `lib/features/media/domain/media_asset.dart` — `MediaResourceType`,
  `PickedMedia` (routing, limits, `humanSize`), `CloudinaryAsset.fromJson`.
- `lib/features/media/data/cloudinary_uploader.dart` — streaming multipart
  upload with real byte progress, 5-minute ceiling, typed failures.
- `lib/features/media/data/file_picker_source.dart` — file_picker 13 static API,
  real file length from disk.
- `lib/features/media/application/media_controller.dart` — upload state
  (`mediaUploadProvider`) feeding the progress bar.
- `lib/features/media/presentation/media_bubble.dart` — image bubble with a
  byte-accurate loader, file/video/audio card that opens externally.
- `lib/features/chat/…` — `Message.mediaUrl/mediaBytes`, `sendMessage(mediaUrl,
  mediaBytes)`, `sendMedia()` (optimistic bubble → upload → insert → mark failed
  instead of pretending on error), composer paperclip.
- `android/app/src/main/AndroidManifest.xml` — `<queries>` for `VIEW` intents.
  Without this, Android 11+ cannot resolve a browser or viewer and tapping an
  attachment would silently do nothing in a release build.
- Tests: `test/media_test.dart` (22 assertions), `test/live/media_upload_test.dart`
  (real network, self-skipping).

One pre-existing test bug fixed along the way: the live suite read
`profiles?limit=1` and asserted "own profile", which broke once real accounts
existed next to the throwaway user. It now filters `id=eq.<uid>`.

## 5. Sign-up is still blocked — log in instead

`POST /auth/v1/signup` still returns `429 over_email_send_rate_limit`, because
`mailer_autoconfirm = false` and Supabase's built-in mailer allows roughly two
messages per hour. That is a project setting, not app code, and changing it needs
the Supabase owner login.

**Two confirmed accounts exist for testing** (verified: HTTP 200 + session):

| Account | Email | Password |
|---|---|---|
| Arif | `pulse.demo.arif@mailinator.com` | `PulseDemo!2026` |
| Bela | `pulse.demo.bela@mailinator.com` | `PulseDemo!2026` |

Log in as Arif on one device and Bela on another to test media between two
people. If you do tap "create account" and see the "Too many attempts" notice, the
app now offers a **"Log in instead"** button that takes you to the login form.

## 6. What is still missing (honest list)

1. **Force Audio recorder** — not started. Needs `record`, a real mic-permission
   prompt, hold-to-record with a hard 70 s stop, local playback before send.
2. **Force Audio receive → download → play** — not started. Needs
   `force_audio_alerts` (migration 0005), server-side verification of the alert id,
   real download progress and a play-once guard.
3. **Server side of Force Audio** — `force-audio-create` and `fcm-send` are
   written but **cannot be deployed without a Supabase personal access token**, so
   no push is actually delivered yet. Until then Force Audio can only be exercised
   in the foreground.
4. Nothing in this phase was tested on a physical device — I have no `/dev/kvm`
   and no phone. Foreground/Doze/FCM behaviour remains yours to verify.

---

# Phase 5b — Force Audio, end to end (pushed, deployed)

**Commits:** `70f265f` + `879d950` · **CI run:** `43611852237` — all four jobs
green · **Artifact:** `pulse-release-apk`, 32.4 MB, id `14120557621`
**Migration:** `0005_force_audio.sql` (applied to the live project, version
recorded) · **Edge Functions deployed:** `send-push`, `device-register`,
`force-audio-create` (all `ACTIVE`, `verify_jwt = true`)

The Supabase personal access token arrived during this phase, which unblocked the
server half — the parts that were previously impossible.

## 1. What is now real

| Piece | State |
|---|---|
| Recorder (real microphone, amplitude meter, hard stop at 1:10) | built |
| Sender: record → upload with real % → message + alert | built |
| Alert storage with server-enforced limits and lifecycle | built + applied |
| `force-audio-create` Edge Function (validates, inserts under RLS, pushes) | built + **deployed** |
| `send-push` (FCM HTTP v1) | **deployed**, real Google round-trip proven |
| Receiver: verify → download with real % → play once → mark played | built |
| Duplicate-playback guard (Hive) | built + tested |
| Auto-open the Force Audio screen from a push | **not yet** (next) |

The client cannot call `send-push` — it is server-only. `force-audio-create`
inserts the alert **as the caller** (so RLS still decides membership, bans and
limits) and then pushes the recipient with the service key.

## 2. Measured results

| Check | Result |
|---|---|
| `dart analyze lib test` | **No issues found** |
| `flutter test` | **88 passed, 3 skipped** (the 3 skips are live-network suites) |
| `deno test supabase/functions/` | **19 / 19** (9 send-push + 10 force-audio validation) |
| Release APK permission gate (CI) | `network + notification + microphone permissions present` |
| `run_local.sh` (fresh DB, all migrations) | 10_rls **PASS**, chat **19/19**, force audio **26/26** |
| `30_live_api_test.sh` | **93 / 93** |
| Real audio upload | `…/video/upload/v1794670207/…wav`, 96 044 bytes, Cloudinary reports **duration 3000 ms** |
| Real download with progress | 96 044 bytes, **57 progress events**, monotonic, last = 1.0 |
| Cached second play | progress = `[1.0]`, no re-fetch |
| `force-audio-create` live call | HTTP 200, `ok: true`, alert row created, **`push.status 200`** |
| Real FCM round-trip | a deliberately dead token went **`is_active: true` → `false`** because Google answered 410 |

That last row is the important one: it proves the push path is not a stub. The
function's token lookup found the registered device, called FCM with the real
service account, Google said "unregistered", and the token was retired — exactly
the behaviour §31 requires.

## 3. Server-side rules now enforced by the database, not by the app

- `duration_ms between 500 and 70000` — 71 s is refused even from a modified client.
- `size_bytes between 1 and 10485760` — 10 MiB + 1 byte is refused.
- `media_url like 'https://res.cloudinary.com/%'` — the receiver can never be
  pointed at a third-party host.
- `sender_id <> recipient_id`, and the recipient must be the other member of that
  conversation and not banned.
- `state`/`played_at`/`expires_at` are **not granted** to `authenticated`: a client
  cannot pre-mark an alert played or extend its own expiry.
- A trigger makes evidence immutable and `played`/`expired` terminal, so a replayed
  push cannot resurrect a played alert.
- `expire_force_audio_alerts()` (service_role only) sweeps stale alerts; it uses a
  transaction-local flag rather than a role name for its maintenance bypass.

## 4. Two bugs found and fixed while doing this

1. **Cloudinary `duration` is in seconds, not milliseconds.** The old parser
   returned `13` for a 12.6 s video. Now it returns `12600`, and the live upload of
   3 s of audio reports `3000 ms`.
2. **`send-push` rejected every server-side caller.** Its guard required a JWT with
   `role: service_role`, but newer projects issue `sb_secret_…` keys that are not
   JWTs, so `force-audio-create` got a 403 and every push failed. It now also
   accepts the project's service key with a constant-time comparison.

## 5. What a tester can do with the new build

1. Log in as Arif, open the chat with Bela.
2. Tap the **microphone** in the composer → grant the microphone → tap to record.
3. Watch the bars move with your voice, the timer count up, and the meter stop
   hard at 1:10. Stop, preview, send.
4. The bubble shows "Uploading — 42%" with real bytes, then "Force Audio sent".
5. On Bela's phone (logged in as Bela, same chat) tapping the bubble shows
   "Checking for new messages…" → "Downloading 63%" → plays.
6. Tapping again says "Played" and does **not** replay.

## 6. Still open (honest)

1. **Push → auto-open**: `force-audio-create` now sends a real notification with
   `force_audio_alert_id`, and the app already parses it, but tapping the
   notification still lands on the chat rather than jumping straight into a
   full-screen Force Audio playback with "Checking for new messages". That is the
   last piece of §5 and it needs the notification-tap handler wired to the alert id.
2. **No physical-device testing** — I have no phone and no `/dev/kvm`. The
   recorder, the runtime permission prompt, Doze, background playback and the
   notification tap are all yours to verify.
3. **`send-push`'s new service-key acceptance** should get a unit test in
   `lib_test.ts` for the non-JWT case (the constant-time compare is covered only
   by the live call above).

One CI failure happened on the way here and is fixed: `deno test` runs without
`--allow-net`, and importing `force-audio-create/index.ts` executed `Deno.serve`
at import time. The validation moved to `lib.ts` (same layout as `send-push`), so
the tests import only the pure code.
