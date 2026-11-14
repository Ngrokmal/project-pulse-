# PULSE — Phase 2 report

**Date:** 2026-11-14 · **Scope:** database migrations + RLS matrix, profile
read/write, real release keystore, device-register Edge Function, account-status
guard · **Gate:** everything below was executed, not assumed.

---

## 1. What now exists on the real backend

Project `lehrtdrxaioknyuenqeg`, region **ap-south-1**, PostgreSQL 17.11,
GoTrue 2.197.0. Migrations were applied with `psql` over the session pooler
(the direct `db.<ref>` host is IPv6-only).

| migration | contents |
| --- | --- |
| `0001_profiles.sql` | `profiles` (display_name ≤60, username `^[a-z0-9_]{3,24}$` unique, bio ≤200, avatar/cover), `touch_updated_at`, `handle_new_user` on `auth.users` |
| `0002_account_status.sql` | enum `account_status_value` (active, under_review, suspended, banned), `account_status` (own-read only), `handle_new_profile_status`, `is_account_active(uuid)` SECURITY DEFINER |
| `0003_devices_and_tokens.sql` | `devices` (64-hex HMAC, `platform='android'`, unique `(device_hash, hash_version)`), `account_device_history`, `device_security_events`, `fcm_tokens` (length 20–4096, own-row CRUD) |

Verified state on the live database:

```
tables    : profiles, account_status, devices, account_device_history,
            device_security_events, fcm_tokens   (all relrowsecurity = true)
policies  : 9      triggers: 5      functions: 4
grants    : authenticated → profiles SELECT, account_status SELECT,
            devices SELECT, account_device_history SELECT, fcm_tokens CRUD
```

`supabase_migrations.schema_migrations` was created and seeded with
`0001/0002/0003` so a future `supabase db push` will not re-apply them.

---

## 2. Measured test results

| suite | how it runs | result |
| --- | --- | --- |
| `supabase/tests/run_local.sh` | fresh PostgreSQL, stub `auth` schema, real migrations | **ALL RLS TESTS PASSED** (14 assertions) |
| `supabase/tests/20_live_rls_test.sql` | **live** project, one transaction, `ROLLBACK` at the end | **26 / 26 PASS** |
| `supabase/tests/30_live_api_test.sh` | **live** GoTrue sign-in → real JWT → PostgREST → RLS | **26 passed, 0 failed, 1 skipped** |
| `dart analyze lib test` | Flutter 3.50.0 / Dart 3.14.0 | **No issues found** |
| `flutter test` | unit + widget | **32 / 32 pass** |

The one skipped API check is the public signup endpoint: Supabase's built-in
SMTP rate-limits confirmation mail (~2/hour), so signup returned
`429 over_email_send_rate_limit`. The harness provisions the account the way an
admin would and then signs in through the real `/auth/v1/token` endpoint, so the
JWT → PostgREST → RLS path is still exercised end to end.

Nothing was left behind: residue check after both suites reports
`auth.users=0 profiles=0 status=0 devices=0 tokens=0`.

### Two real defects the live run caught

1. **`auth.users` token columns must be `''`, not `NULL`.** A row inserted with
   `confirmation_token`/`email_change` NULL makes GoTrue answer
   `500 Database error querying schema`. The harness now sets them explicitly.
2. **`fcm_tokens_len` CHECK is 20–4096.** A 15-character placeholder token was
   rejected — correct behaviour, wrong fixture. The app must never insert a
   synthetic token.

---

## 3. App-side surface delivered

| piece | path |
| --- | --- |
| Profile model + validation identical to the DB constraints | `lib/features/profile/domain/profile.dart` |
| Supabase profile repository (typed failures, no silent catch) | `lib/features/profile/data/supabase_profile_repository.dart` |
| Profile controller (Riverpod 3 `AsyncNotifier`, optimistic-free save + typed error) | `lib/features/profile/application/profile_controller.dart` |
| Profile screen (real data, loading / error / retry / signed-out states) | `lib/features/profile/presentation/profile_screen.dart` |
| Edit profile form (client validation mirrors DB, server error surfaced) | `lib/features/profile/presentation/edit_profile_screen.dart` |
| Account status model + repository + controller | `lib/features/account_status/**` |
| `AccountGate` — wraps the authenticated shell, renders the banned/suspended screen from server truth | `lib/features/account_status/presentation/account_gate.dart` |
| Device identity MethodChannel (`pulse/device` → `Settings.Secure.ANDROID_ID`) | `lib/core/platform/device_identity.dart`, `android/.../MainActivity.kt` |
| Device registration service + retryable controller (failure never blocks login, surface is visible) | `lib/features/device/**` |
| Device-register Edge Function (JWT verify → HMAC-SHA256 → upsert → audit) | `supabase/functions/device-register/index.ts` |

New tests: `profile_model_test.dart`, `account_status_test.dart`,
`device_identity_test.dart` (16 new assertions, 32 total).

Router additions: `/profile/edit` (fade transition), `AccountGate` around the
three-tab shell. Debug-only design gallery stays behind `kDebugMode`.

---

## 4. Release signing

* Keystore `pulse-upload.jks`: RSA 4096, SHA384withRSA, 10 000 days, alias
  `pulse-upload`. Stored **outside** the repo; `*.jks`, `*.keystore` and
  `android/key.properties` are git-ignored.
* `android/app/build.gradle.kts` reads `android/key.properties` and only enables
  a `release` signing config when it exists — otherwise it falls back to debug
  signing so a plain local `flutter run --release` never breaks.
* Certificate fingerprints (public values, safe to publish):
  * SHA-1 `75:8B:BA:84:4B:21:BB:7D:55:6E:1B:40:CD:DE:DF:88:E3:52:D3:2E`
  * SHA-256 `80:1B:67:A4:5A:40:BA:B8:D2:F8:43:8C:2C:55:45:2B:BE:BD:09:04:71:21:85:29:BC:7B:73:E0:C9:2D:11:23`
* CI decodes the keystore from `ANDROID_KEYSTORE_BASE64`, writes
  `key.properties`, builds, then **asserts** with `apksigner verify --print-certs`
  that the APK carries that exact SHA-256. A debug-signed APK now fails the job.
* Repo secrets now set: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `CLOUDINARY_CLOUD_NAME`, `SUPABASE_DB_URL`, `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

---

## 5. CI

* `migrations` job → installs PostgreSQL, runs `supabase/tests/run_local.sh`
  (applies every migration to an empty database, then the RLS suite).
* `analyze-and-test` → format check, `flutter analyze` (fatal), `flutter test`.
* `build-apk` → decodes keystore, builds, verifies the signing certificate,
  uploads `pulse-release-apk`.
* `db-verify.yml` (manual `workflow_dispatch`) → runs both **live** suites
  against the real project. It creates and deletes one throwaway account.

---

## 6. Open items (blocked on things only you can do)

1. **Deploy `device-register`.** Still no Supabase **Personal Access Token**, so
   the function is written, reviewed and type-checked but not deployed. Two ways:
   ```bash
   supabase login                       # paste a PAT when prompted
   supabase functions deploy device-register --project-ref lehrtdrxaioknyuenqeg
   supabase secrets set DEVICE_HASH_KEY="$(openssl rand -hex 32)" --project-ref lehrtdrxaioknyuenqeg
   ```
   or paste a PAT here and I run it. Until then the app shows a visible
   "This device could not be registered. Retry" notice — it never blocks login.
2. **Custom SMTP.** The built-in mailer throttles confirmation mail to a couple
   per hour; signup in the app will hit `429` for real users. Configure
   Resend/Brevo/Postmark in Authentication → Emails before Phase 4 testing with
   more than one account.
3. **Firebase console.** Add the release SHA-1
   `75:8B:BA:84:4B:21:BB:7D:55:6E:1B:40:CD:DE:DF:88:E3:52:D3:2E` to the Android
   app `com.pulsemessenger.app`, otherwise phone-auth/App Check and some FCM
   behaviours won't work.
4. **Rotate the leaked FCM service account key** (`/home/user/.secrets/firebase/service-account.json`)
   in the Firebase console and send me a fresh one; the current one was shared in
   plain text earlier.
5. **Revoke the over-scoped GitHub token** once the repo work is done and send a
   fine-grained replacement (`contents: write`, `actions: write`).

---

## 7. Phase 3 entry point

Phase 3 opens with **FCM token registration**, in this order, because push is the
backbone of Force Audio Alert:

1. `firebase_core` + `firebase_messaging`, `google-services.json` → `android/app/`.
2. `POST_NOTIFICATIONS` permission flow (Android 13+) with a real rationale.
3. Token sync into the already-live, already-RLS-verified `fcm_tokens` table
   (insert on `getToken()`, refresh on `onTokenRefresh`, `is_active=false` on
   sign-out). This table is already proven: own-row CRUD allowed, forged
   `user_id` rejected, `<20` char tokens rejected.
4. Deploy `send-push` Edge Function (Firebase HTTP v1, service account) and
   verify a real notification arrives on a real device.
