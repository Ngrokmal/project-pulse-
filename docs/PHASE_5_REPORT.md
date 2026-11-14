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
