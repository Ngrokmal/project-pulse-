# PHASE 0 — Repository, Service & Dependency Audit

**Date:** 2026-11-14 · **Project:** PULSE (Flutter Android) · **Repo:** `Ngrokmal/project-pulse-`

> Ei document master prompt §1 (First Action) ar §17 (Phase 0) er deliverable.
> Sob statement **actual probe/test** theke — kono assumption na.

---

## 1. Repository audit

| Item | Finding | Evidence |
|---|---|---|
| Repo state | **Empty** — kono file, kono commit nei | `GET /repos/Ngrokmal/project-pulse-/contents/` → `"This repository is empty."` |
| Default branch | `main` | GitHub API |
| Visibility | **Public** | GitHub API `"private": false` |
| Existing code to preserve | **Kichu nei** — greenfield | — |
| Existing Force Audio implementation | **Repo te nei** | Full repo scan (empty) |
| Existing migrations / Edge Functions / tests | **Nei** | — |

**Consequence:** §1.2 / §1.3 (preserve existing, port proven Force Audio implementation) **apply kore na** — karon repo te kono code nei. Master prompt §1.4 onujayi **tomar onno repo-r Force Audio implementation** lage (dekhun §5, Blocker B1).

### Swift-er partial files (amar banano, push kora nei)
`pubspec.yaml`, `lib/theme/app_colors.dart`, `lib/theme/app_theme.dart`, `assets/brand/*` — ei gulo tomar "foundation baniyo na" instruction er por theke nei; Phase 1 e notun architecture onujayi **rewrite/expand** hobe.

---

## 2. Service audit — ki ki verified (live probe)

| Service | Status | Evidence |
|---|---|---|
| **GitHub** | ✅ Push/admin OK | token valid, `permissions: admin:true, push:true`, repo size 0 |
| **GitHub token scope** | ⚠️ Over-privileged | `repo, workflow, delete_repo, admin:org, admin:enterprise, admin:repo_hook, write:packages...` |
| **Supabase — project live** | ✅ | `GET /auth/v1/health` → 200, GoTrue `v2.197.0` |
| **Supabase — anon/publishable key** | ✅ | storage buckets 200 (`[]`), auth reachable |
| **Supabase — public schema** | ⚠️ **Empty** | `GET /rest/v1/profiles` → `PGRST205 Could not find the table` |
| **Supabase — management/DB access** | ❌ **NEI** | `GET api.supabase.com/v1/projects` with anon key → 401 `JWT could not be decoded` |
| **Firebase — client config** | ✅ | `google-services.json` valid, package `com.pulsemessenger.app` |
| **Firebase — Auth enabled?** | ❌ **Nei** | Identity Toolkit probe → `CONFIGURATION_NOT_FOUND` |
| **Firebase — FCM v1 send** | ✅ **Verified** | JWT→OAuth2 token minted; `messages:send` with fake token → `400 INVALID_ARGUMENT` (auth+API OK) |
| **Cloudinary — credentials** | ✅ | `/ping` → `{"status":"ok"}` |
| **Cloudinary — presets** | **0 ta** | `/upload_presets` → `{"presets":[]}` |
| **Cloudinary — plan/quota** | Free, 25 credits, usage 0 | `/usage` |

---

## 3. Gap analysis — master prompt vs ekhon kar obostha

| Spec area | Needed | Available now | Gap |
|---|---|---|---|
| Supabase schema + RLS (§7, §8) | migrations apply | project empty, no admin access | **Blocker B2** |
| Edge Functions (§7) | deploy (`fcm-send`, `cloudinary-sign`, `force-audio-create`, `device-register`) | no Supabase access token / CLI auth | **Blocker B2** |
| FCM send (§9) | service account in Supabase secret | verified locally, secret set kora nei | dependency on B2 |
| Cloudinary uploads (§6) | signed upload via Edge Function (preferred) ba restricted unsigned preset | 0 preset | decision + Edge Function |
| Force Audio (§5) | proven foreground-activation implementation | repo empty, reference code nei | **Blocker B1** |
| Device ID / device ban (§31.7) | Android ID native plugin, keyed hashing server-side | kichu nei | design ready (plan §7) |
| Hive offline-first (§31) | hive + hive_flutter, typed adapters | kichu nei | plan ready |
| Calling UI now / Agora later (§23) | provider abstraction, no SDK | kichu nei | plan ready |
| Sounds (§22) | original/licensed ringtones & SFX | kichu nei | **Blocker B4** (license source decision) |
| Real device verification (§5, §10, §16) | এমুলেটর/ফোন | **`/dev/kvm` nei, RAM 1.9 GB** | **Blocker B3** |

---

## 4. Hard constraints — ja ami korte parbo na (honest)

| Spec demand | Amar obostha |
|---|---|
| "Force Audio foreground activation test on real Android versions/devices" | ❌ Ami real device e test korte parbo na — sandbox e `/dev/kvm` nei, emulator cholbe na. APK build korte parbo, **install kore verify tumi korte hobe**. |
| "Measure stable 120 FPS with profiling evidence" | ❌ Same — profiling real device e dorkar. Ami code-level perf discipline (const, RepaintBoundary, lazy list, no heavy blur) maintain korte parbo, kintu "120 FPS measured" claim **korbo na**. |
| Agora real call test | Deferred by spec §23 — kono claim nei |
| iOS build | ❌ macOS nei (spec Flutter Android, tai issue na) |
| CI te real push notification delivery | ⚠️ Possible: FCM HTTP v1 send CI theke kora jay; kintu device e receive hoyeche kina seta tomar device log dekhe confirm korte hobe |

---

## 5. Missing inputs — exact list (ei gulo chara stated phase e agabo na)

### B2 — Supabase DB & Edge Function access (★ highest priority)
Migration run korte + Edge Function deploy korte authentication lage. **3 ta option, jekono ekta:**

1. **Supabase Personal Access Token** (recommended):
   `https://supabase.com/dashboard/account/tokens` → Generate new token (`sbp_...`)
   → ami `supabase link` + `db push` + `functions deploy` korte parbo.
2. **Database password** (Postgres URI):
   `postgresql://postgres:<DB_PASSWORD>@db.lehrtdrxaioknyuenqeg.supabase.co:5432/postgres`
   → ami `psql` diye migration apply korbo (Edge Function deploy still blocked).
3. **Tumi nijei chalabe**: ami 완전한 SQL file + function code debo, tumi Supabase SQL Editor e run korbe ar Edge Function dashboard theke deploy korbe.

### B1 — Force Audio reference implementation
Tumi bolecho tomar **age ekta app ei kaj koreche** (FCM/Edge Function link → foreground activation → "Checking for new messages" → download → play). Amake exact ei file gulo lagbe:
- `AndroidManifest.xml` (permissions + service/receiver declaration)
- Android `MainActivity` / any `Service` / `BroadcastReceiver` / `FirebaseMessagingService` implementation
- Flutter side: notification handler, lifecycle code, download+play service
- Ekta sample FCM payload + Supabase Edge Function er source

**Ei gulo na pele ami generic notification-tap flow banabo** — mane tomar proven behavior er parity claim korbo na (§1.4, §19.22).

> ⚠️ Note: Android 10+ theke background theke activity auto-launch kora **OS-level restricted** (§5.15 respects this). Tai tomar implementation ta ki technique use koreche (full-screen intent notification / SYSTEM_ALERT_WINDOW / heads-up) — seta code dekhe verify korbo. Legal + reliable path choose korbo, "hidden bypass" na.

### B3 — Device test access
APK pathabo; install + Force Audio + notification behaviour tomar phone e test korte hobe. Kon Android version/device — bolo, ami shei onujayi constraints document korbo.

### B4 — Sound assets license decision
§22 bole "original ba properly licensed". Duita path:
- (a) Ami programmatically **original** chhoto SFX/ringtone generate kori (sine/wave synthesis) → 100% original, license clean
- (b) Licensed library (e.g. CC0) theke niye source+license record rakhi

Ami **option (a)** recommend korchi — original, license problem zero.

---

## 6. Risk register

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Android 10+ background foreground-activation restriction | Force Audio "auto-open app" fail korte pare | Full-screen intent notification + user grant; documented per-version behaviour; test matrix |
| R2 | Android ID unstable (factory reset/signing key) | Device-ban bypass | Versioned hashed ID + server-side keyed hash; documented limits (§31.7) |
| R3 | Cloudinary Free plan 25 credits | Media heavy test e quota shesh | Pilot e compressed thumbnails, upload limit strict, test asset chhoto |
| R4 | Supabase Free tier egress/row limits | Realtime + pagination e limit | Hive cache + cursor sync + throttled typing (§31) |
| R5 | FCM service-account key exposed in chat | Push/db access misuse | **Rotate after setup**; secret শুধু Supabase secret store e |
| R6 | 1.9 GB RAM sandbox | Local build/test slow | CI (GitHub runner 16 GB) e build; local e shudhu analyze/unit test |
| R7 | SQL migration ordering / RLS gap | Data leak ba breakage | Forward-only numbered migrations + RLS matrix + anon-auth penetration test |
| R8 | Realtime duplicate delivery | Duplicate message/alert | Idempotency key + unique constraint + client dedupe |
| R9 | 70s/10MB/49MB limit drift between client & server | Bypass ba false rejection | Single config constant + server re-validation (§6, §19.13) |
| R10 | Force Audio duplicate playback on process restart | User annoyance | Durable "played" state + idempotent play-once guard |

---

## 7. Verification performed in this phase

```
GitHub API        → repo empty, push permission, scopes listed          ✅
Supabase (anon)   → auth health 200, storage 200, profiles table 404     ✅
Supabase (mgmt)   → 401 (no admin access)                               ⚠️
Firebase client   → identitytoolkit CONFIGURATION_NOT_FOUND             ⚠️
Firebase server   → OAuth token minted + FCM send authorized             ✅
Cloudinary        → ping ok, presets [], usage 0                         ✅
SVG asset render  → cairosvg 2.9.1, icon pipeline working                ✅
```

**Kono test pass bola hoy ni jeta run kora hoy ni.** Sob upor er line actual HTTP output theke.
