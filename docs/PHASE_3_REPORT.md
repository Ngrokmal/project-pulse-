# PULSE — Phase 3 report

**Date:** 2026-11-14 · **Scope:** FCM token registration (top priority), Android
13+ permission flow, token lifecycle, `send-push` Edge Function, in-app push
delivery · **Gate:** every number below was produced by a run you can repeat.

---

## 1. Result at a glance

| check | command | result |
| --- | --- | --- |
| Dart static analysis | `dart analyze lib test` | **No issues found** |
| Dart tests | `flutter test` | **51 / 51 pass** (was 32) |
| Edge Function type-check | `deno check supabase/functions/*/index.ts` | **clean** |
| Edge Function unit tests | `deno test supabase/functions/` | **9 / 9 pass** |
| Live Firebase probe | `deno run -A supabase/functions/send-push/live_check.ts` | **4 / 4 pass** |
| Live database/API suite | `bash supabase/tests/30_live_api_test.sh` | **39 / 39 pass** (was 26) |
| CI (4 jobs) | `Flutter CI` | **all green**, signed APK artifact |

---

## 2. FCM token registration — the whole chain

**Android config**

* `firebase_core 5.1.0` + `firebase_messaging 17.0.1`; `com.google.gms.google-services 4.4.4`
  applied in `android/app/build.gradle.kts`, `google-services.json` at
  `android/app/` (project `pulse-2f3a4`, package `com.pulsemessenger.app`).
* `MainActivity` creates the **`pulse_default`** notification channel
  (`IMPORTANCE_HIGH`) before the first push can arrive; the manifest points FCM
  at that channel id and sets the brand accent colour `#7B5FED`.
* Manifest now declares `INTERNET` for release builds too (Flutter only adds it
  to debug/profile), plus `POST_NOTIFICATIONS` and `VIBRATE`.
  `minSdk` stays at Flutter's 24 — firebase_messaging 17 requires exactly 24.

**Token lifecycle**

```
sign-in  → permission state read → token() → validate → INSERT fcm_tokens
           └ 23505 (unique token) → row is mine?  → reactivate → done
                                  → row is foreign → deleteToken() → fresh token → INSERT
onTokenRefresh → same sync path (hot path, no UI blocking)
sign-out → handleSignOut() BEFORE the session dies → is_active = false
```

* `PushToken.validate` mirrors the live `fcm_tokens_len` CHECK (20–4096, no
  whitespace) so a bad token is refused locally instead of failing silently.
* Every failure is typed and visible. If Firebase never initialises
  (`firebaseReady == false`) the Profile card says notifications are
  unavailable — no fake "on" state.
* `denied` vs `deniedPermanently` comes from the plugin's own
  `AuthorizationStatus.deniedPermanently`, so the UI offers "Turn on" only when
  Android would still show a prompt, and system-settings instructions otherwise.

**In-app delivery**

`PushMessageController` consumes `onMessage` (foreground), `onMessageOpenedApp`
(tap) and `getInitialMessage()` (cold-start tap); `PushBanner` renders it in the
shell with a dismiss control. Payload routing already understands
`kind=force_audio` + `force_audio_alert_id`, which is the hook Force Audio Alert
will use.

---

## 3. `send-push` Edge Function

* **Service-role only**: the caller's JWT `role` claim must be `service_role`,
  so the mobile app can never push arbitrary notifications.
* **FCM HTTP v1**, `messages:send`, with a **dependency-free RS256 OAuth2 grant**
  implemented on WebCrypto (`crypto.subtle`) — no `googleapis`, no npm tree.
* Payload: `notification` + `data` (all values stringified) + `android`
  (`priority: high`, `channel_id: pulse_default`, `collapse_key`/`tag`).
  Titles >120 chars, bodies >500 chars and missing titles are rejected locally.
* **Dead tokens are retired**: FCM `UNREGISTERED`/`INVALID_ARGUMENT` →
  `is_active = false`; 429/5xx stay retryable. Errors are never treated as
  "token dead" by accident (`classifyFcmError`, 6 assertions).
* Secrets never leave the server: the service-account JSON, the OAuth assertion
  and the device tokens are never logged or echoed. Responses carry counts plus a
  `correlationId`.

**Live probe output (real Firebase project, nothing delivered):**

```
PASS  OAuth2 access token from our RS256 assertion  (1024 chars)
PASS  FCM accepted our message shape (validate_only, topic target)
      → projects/pulse-2f3a4/messages/36386854462675409…
PASS  unknown token classified as a dead token  (invalid)
PASS  error classifier keeps 5xx retryable
===== LIVE FCM CHECK: all assertions passed =====
```

Note: FCM validates the *token* even under `validate_only`, so payload validation
uses a topic target. That is why the probe proves the message shape and the
credentials separately from the token.

---

## 4. Token-conflict behaviour, proven on the live database

The client has to survive two real situations: reinstalling, and handing the
phone to another account. Both were executed against production (then rolled
back/cleaned up):

```
PASS  account A registers the device token
PASS  re-registering the same token is a unique violation (409), not an RLS denial
PASS  …and PostgREST reports it as 23505
PASS  the owner can still see the row (so the client reactivates it)
PASS  reactivation update succeeds for the owner
PASS  account B sees nothing for that token (RLS)
PASS  account B cannot steal the token row
PASS  sign-out simulation deactivates A's token
PASS  A now has no active tokens
```

That is exactly the branch structure implemented in
`SupabasePushTokenRepository.register`.

---

## 5. CI

`Flutter CI` now has four jobs, all green on commit ``b3994e0` (phase 3 first commit)`:

1. **Migrations & RLS** — fresh PostgreSQL, every migration, RLS suite.
2. **Edge Functions** — `deno check` every function + Deno unit tests.
3. **Analyze & test** — format, `flutter analyze` (fatal), 51 tests.
4. **Build release APK** — keystore decoded from a secret, build, then
   `apksigner` verifies `CN=Pulse Messenger` / SHA-256 `801b67a4…d1123`.

`FCM verification` (manual workflow) runs the live probe; it needs the
`FCM_SERVICE_ACCOUNT` secret, which is intentionally **not** set until the leaked
key is rotated (§6).

---

## 6. Still blocked on you

1. **Deploy the two Edge Functions.** Still no Supabase **Personal Access
   Token**, so neither `device-register` nor `send-push` is live. One command
   each once you paste a PAT:
   ```bash
   supabase login
   supabase functions deploy device-register --project-ref lehrtdrxaioknyuenqeg
   supabase functions deploy send-push      --project-ref lehrtdrxaioknyuenqeg
   supabase secrets set --project-ref lehrtdrxaioknyuenqeg \
     DEVICE_HASH_KEY="$(openssl rand -hex 32)" \
     FCM_SERVICE_ACCOUNT="$(cat fresh-service-account.json)"
   ```
2. **Rotate the Firebase service-account key** and send the replacement. The
   current one passes every live check, but it was shared in plain text earlier;
   after rotation, put the new JSON in the `FCM_SERVICE_ACCOUNT` repo secret and
   the `FCM verification` workflow will keep the probe green.
3. **Custom SMTP** — signup confirmation mails are still rate-limited by the
   built-in mailer (~2/hour).
4. **A real Android device.** Delivery to a device cannot be proven from this
   sandbox (no `/dev/kvm`, no phone). Once the functions are deployed and the APK
   installed, the honest end-to-end check is: sign in → Profile shows
   "This device is registered for push" → send one message with
   `send-push {userId, title, body}` and confirm the banner/notification.

---

## 7. Phase 4 entry point

Chat itself: `conversations`/`messages` tables + RLS, Supabase Realtime
subscriptions, Hive offline cache + outbox queue, the 3-second typing debounce,
and Cloudinary uploads with real progress. Force Audio Alert then builds on top
of `send-push` (which already emits `kind=force_audio` with an alert id).
