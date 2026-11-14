# PHASE 1 REPORT — design system, brand, onboarding, auth UI, shell, CI

**Repo:** `Ngrokmal/project-pulse-` · **Flutter:** 3.50.0 (Dart 3.14)
**CI:** run #3 — `Analyze & test` ✅ · `Build release APK` ✅ (artifact `pulse-release-apk`)

---

## 1. Delivered

| Area | What exists now |
|---|---|
| Design system | Measured tokens (`app_colors`, `app_typography`, `app_spacing`, `app_theme`) — light + dark Material 3, derived from the reference mockups |
| Brand | Original vector mark (`assets/brand/src/*.svg`) + rendered launcher icons mdpi→xxxhdpi, adaptive foreground/background, splash logo, notification icon |
| Fonts | Poppins bundled (400/500/600/700); body uses the platform font to keep the APK small |
| Splash | Brand intro animation, session restore, 6 s safety timeout, reduced-motion respected |
| Welcome | Full-viewport hero (generated asset, 146 KB), navy overlay, single gradient CTA, responsive to height |
| Auth | Real Supabase email/password **sign in + sign up**, inline validation, password visibility, duplicate-submit guard, typed error mapping (invalid credentials / unconfirmed email / weak password / rate limit / network) |
| Shell | Bottom navigation (Home / Calls / Profile), honest empty states, working sign-out, About dialog |
| Debug tool | Design-system gallery (`/design`, debug builds only) |
| Foundations | `AppFailure` typed hierarchy, structured redacting logger, root error boundary + `runZonedGuarded`, `MediaLimits` single source of truth, `AppConfig` via `--dart-define` |

## 2. Verification actually performed

```
dart analyze lib test   → No issues found (0 errors, 0 warnings, 0 infos)
flutter test            → 16/16 passed
GitHub Actions run #3   → analyze & test: success
                          release APK build: success
                          artifact: pulse-release-apk, 24.6 MB (14-day retention)
```

Covered by tests: resource-type mapping (image/video/raw, incl. audio/pdf/zip → raw),
size caps (49 MiB video, 10 MiB raw), 70 s force-audio cap, logger secret redaction
(JWT, Supabase-style key, GitHub-style token, password pairs), auth validation
(empty submit performs **no** network call, invalid email, typed login failure),
unconfigured-build error screen.

## 3. Deliberate scope decisions (documented, not hidden)

1. **Explore tab not shipped yet** — it needs the search backend (Phase 3). A
   decorative no-op tab would violate §19.18, so the bar ships with 3 real tabs.
2. **Android release lint disabled** in `android/app/build.gradle.kts` — AGP's lint
   crashes inside its own `JavaDocParser` (`NoSuchMethodError`) and fails the release
   build for reasons unrelated to this code. Dart analysis stays the fatal
   static-analysis gate in CI. Follow-up task, not a silent ignore.
3. **Release APK is debug-signed** — a real upload keystore is Phase 2 work and must
   never enter git.
4. **`firebase/google-services.json` is committed** — it holds only public client
   identifiers (identical values are inside every APK). Restrict the Firebase API
   key by package name + SHA-1 in Google Cloud Console.
5. **`package:material_ui` is used instead of `package:flutter/material.dart`** —
   Flutter 3.50 deprecates the old import; the new package is the forward path.

## 4. Not verified — and therefore not claimed

- Real-device behaviour (Force Audio foreground activation, notifications, lifecycle):
  this environment has no emulator (`/dev/kvm` absent). The APK is installable; device
  verification is yours to run.
- 120 FPS: no profiling evidence exists, so no claim is made.
- iOS: not targeted.

## 5. Phase 2 scope (blocked on Supabase access)

Migrations (`profiles`, `account_status`, `devices`, `account_device_history`,
`device_security_events`, `fcm_tokens`), RLS policies + policy matrix, profile
read/write, `device-register` Edge Function, account-status guard, real keystore.

**Needed from you:** Supabase personal access token, or DB password/URI, or you run
the SQL I hand over.
