# PULSE — phases 6 → 10, what was actually built and measured

Date: 2026-11-14 · Repo: `Ngrokmal/project-pulse-` · Branch: `main`
Live project: `lehrtdrxaioknyuenqeg` · Last release commit: (see §8)

> **How to read this.** Every number below came from a command that ran in this
> session. Where something could not be verified in this environment, it says so
> instead of implying success. Nothing is marked done that did not have a green
> run behind it.

---

## 0. What "phase 6" meant here

The user asked for phases 6 → 10. The plan (`docs/IMPLEMENTATION_PLAN.md` §8)
numbers them: 6 = Force Audio, 7 = groups + roles, 8 = calling, 9 = notifications
/ settings / a11y, 10 = security review + release. Force Audio had already been
delivered as Phase 5b/5c (commit `d2e5013`, CI `43615890546`).

So "6" was read as **the next unbuilt item**, and the work covered:

| Tonight | Plan phase | Delivered |
| --- | --- | --- |
| — | 6 (Force Audio) | already done in 5b/5c; re-verified in the regression below |
| 7 | Groups + roles | migrations + RPCs + UI, 32 SQL + 29 live assertions |
| 8 | Calling | state machine + provider seam + UI, 22 SQL + 22 live + 18 unit tests |
| 9 | Settings / notifications / a11y / lifecycle | 17 tests incl. every permission-denied path |
| 10 | Security review, pentest, perf, release | 22-attack pentest, measured benchmarks, APK, docs |

---

## 1. Phases at a glance

| Phase | Commit | DB | App | Proof |
| --- | --- | --- | --- | --- |
| 7 — groups + roles + group media | `24fcbe3` | `0006_groups.sql` | group sheet, info screen, roles | `60_groups_test.sql` 32/32, `61_live_groups_api.py` 29/29, `group_conversation_test.dart` 9 tests |
| 8 — calls | `49189f4` | `0007_calls.sql` | call screen, state machine, media seam | `70_calls_test.sql` 22/22, `71_live_calls_api.py` 22/22, `call_machine_test.dart` 18 tests |
| 9 — settings / permissions / a11y / lifecycle | `2d710ed` | — | `/settings`, permission states, text scale, reduce motion, resume refresh | `settings_test.dart` 9 + `settings_screen_test.dart` 8 |
| 10 — security, perf, release | `d0ebdba` | `0006`+`0007` live | — | `80_rls_pentest.sql` 22/22, `perf_bench_test.dart`, `SECURITY_REVIEW.md`, this file |

---

## 2. Phase 7 — groups, roles, group media

**Schema** (`supabase/migrations/0006_groups.sql`, applied to the live project):
`conversations.kind` accepts `group`, plus `title` / `avatar_url` with a length
check; `conversation_members.role` ∈ {owner, admin, member}. Membership rows are
no longer client-writable — `insert`/`update`/`delete` were revoked and only
`last_read_at` was granted back, so read receipts keep working but nobody can
write a `role`. All changes go through `create_group`, `add_group_member`,
`remove_group_member`, `set_group_role`, `leave_group`, `rename_group`.

Two behaviours worth naming:
- `leave_group` hands ownership to an admin (else the longest-standing member)
  and deletes the conversation when the last member leaves, so a group can never
  be ownerless or empty-but-visible.
- `rename_group` is column-scoped (`grant update (title, avatar_url)`).

**App**: `Conversation` grew `kind` / `title` / `memberCount` / `myRole` with
`displayName`, `subtitleLabel`, `initials`; a `New group` screen (title + member
picker), a group info sheet (roles, promote/demote, remove, add, rename, leave),
a group-aware inbox tile and chat header.

**The gate — "a non-member is denied, proven":**

```
$ python3 …/run_sql_test.py supabase/tests/60_groups_test.sql
32 / 32 assertions passed        ← includes: non-member sees no conversation row,
                                    no messages, no membership rows, cannot post,
                                    cannot add itself
$ python3 supabase/tests/61_live_groups_api.py
===== LIVE GROUPS API: 29 passed, 0 failed =====
```

Two bugs were found and fixed **because** the tests were run, and both are worth
recording:
1. `leave_group` looked up the successor while still evaluating as the caller —
   it was fine, but the *test* asserted from the ex-owner's session, which is
   exactly the state RLS hides. The suite now switches identity before asserting,
   which doubles as proof that the ex-owner really loses visibility.
2. `0006` initially revoked all of `conversation_members`, which silently broke
   read receipts (CI caught it: `member can move their own last_read_at` failed).
   Fixed by re-granting the single column.

---

## 3. Phase 8 — calls

**Schema** (`0007_calls.sql`): `calls(id, conversation_id, caller_id, callee_id,
kind, state, end_reason, timestamps)`, RLS = the two parties only, no client
writes at all. Transitions live in RPCs and are re-checked server side:

```
ringing ──accept──▶ connecting ──confirm media──▶ active ⇄ reconnecting
   │                    │                          │
   ├─ decline ▶ declined├─ error ▶ failed          └─ hangup ▶ ended
   └─ timeout ▶ missed  └──────────────────────────────────────┘
```

`start_call` refuses a second live call per person, refuses a busy callee, and
refuses groups **by name** (`group_calls_not_supported`) rather than half-working.

**App**: a pure `CallMachine` (every transition is unit-tested), a `CallMedia`
interface with a `MockCallMedia` that reports its own honesty
(`connect: false` never claims a channel), and a `CallScreen` that shows the
machine's label and only runs the timer when the call is `active`.

**The gate — "every state reachable, no fake connected":**

```
$ flutter test test/call_machine_test.dart
18 tests … All tests passed!

  · every state in the machine is reachable        (graph walk from idle)
  · no shortcut from ringing straight to active
  · the row saying active is not enough while media is down
  · a media layer that never comes up fails the call, it does not connect
  · the call screen never says Connected on the row alone   (fake repo + dead media)
```

```
$ python3 supabase/tests/71_live_calls_api.py
===== LIVE CALLS API: 22 passed, 0 failed =====
$ python3 …/run_sql_test.py supabase/tests/70_calls_test.sql
22 / 22 assertions passed
```

---

## 4. Phase 9 — notifications, settings, a11y, lifecycle

- **Settings** (`/settings`, from the Profile tab): notification banner, Force
  Audio auto-open, in-app sounds, reduce motion, text size (0.9 – 1.6, clamped in
  the model *and* at the root `MediaQuery`). Stored with Hive behind a
  `SettingsStore` interface, so tests use an in-memory store.
- **Permission states**, each worded differently and each offering only what can
  still work: granted / never asked (`Turn on`) / denied (`Ask again`) /
  permanently denied (`Open system settings`, **no** in-app retry) /
  unsupported build ("Firebase did not initialise").
- **Lifecycle**: `AppLifecycleNotifier` + `ResumeRefresher`; a resume refreshes
  the conversation list and the incoming-call check once per 5 s window.

**The gate — "permission-denied paths tested":**

```
$ flutter test test/settings_test.dart test/settings_screen_test.dart
18 tests … All tests passed!
  denied: explains and offers Ask again
  declining again keeps it off and says why
  permanently denied: points at the system settings, no in-app retry
  unsupported build says push is unavailable, honestly
  text size is exposed with a semantics value for screen readers
  resuming refreshes the caches once, not on every flicker
```

---

## 5. Phase 10 — security, pentest, performance, release

**Pentest** — `supabase/tests/80_rls_pentest.sql`, 22 attacks as
`authenticated`/`anon`, all refused:

```
C cannot read A/B conversation rows        C cannot read A/B messages
C cannot post into someone else's chat     C cannot edit A's message
C cannot delete A's message                C cannot rename A
C cannot register a push token for A       C cannot read A's push tokens
C cannot forge a Force Audio alert         C cannot start a call in A/B chat
C cannot rename a group it is not in       C cannot add itself to a group
C cannot write a membership row directly   C cannot write its own role
C cannot read account_status of others     a client cannot ban anybody
a banned account still cannot send         anon sees no profiles
anon cannot create a group                 anon cannot start a call
is_conversation_member says no             group_role is null

22 / 22 attacks were correctly refused
```

`suggested review: docs/SECURITY_REVIEW.md` — per-surface controls, the four open
findings (one medium: unsigned Cloudinary preset quota abuse; three low), and an
explicit "not verified" list (no physical device, no third-party pentest, no
Dependency CVE scan, realtime tested through policies only).

**Performance** — `test/perf_bench_test.dart`, measured on the CI/test VM
(JIT, so a real device is slower; the assertions are 10× the observation):

| Work | Measured |
| --- | --- |
| 1,000 conversations × 3 members (row → model) | 31 ms (31.8 µs/row) |
| 5,000 messages (row → model) | 25 ms (5.1 µs/row) |
| 20,000 settings maps | 6 ms (0.32 µs/row) |
| 200,000 call-machine evaluations | 3 ms (0.02 µs each) |
| Inbox projection for 1,000 conversations | 8 ms |

**Release build** — GitHub Actions run `43623535110` on `d0ebdba`:
Migrations & RLS ✅ · Analyze & test ✅ · Edge Functions ✅ · Build release APK ✅
Artifact `pulse-release-apk` `14125047760`, **32.8 MB**. The downloaded APK was
unpacked and its `libapp.so` grepped for this turn's work:

```
/call/          present x6      /group/new      present x3   /settings      present x18
Incoming call   present x3      Reduce motion   present x3   Notification banner present x3
Call ended / Declined / Missed  present          /force-audio/  present x6
```

CI's own gates (in the workflow, not added tonight): network + notification +
microphone permissions present in the manifest, APK signed with the upload key.

---

## 6. Full regression, run tonight

| Suite | Result |
| --- | --- |
| `flutter test` (whole app) | **139 passed, 3 skipped** |
| `dart analyze lib test` | no issues |
| `10_rls_test.sql` | ALL RLS TESTS PASSED |
| `40_live_chat_test.sql` | 19 / 19 |
| `50_force_audio_test.sql` | 26 / 26 |
| `60_groups_test.sql` | 32 / 32 |
| `70_calls_test.sql` | 22 / 22 |
| `80_rls_pentest.sql` | 22 / 22 |
| `30_live_api_test.sh` (live project, 93 assertions) | 93 passed, 0 failed |
| `61_live_groups_api.py` (live) | 29 passed, 0 failed |
| `71_live_calls_api.py` (live) | 22 passed, 0 failed |

Local note: this sandbox has **no PostgreSQL server binaries**, so `run_local.sh`
cannot run here — the SQL suites were executed against the live project in a
single rolled-back transaction (`/home/user/tmp/run_sql_test.py`), and CI runs the
same files on a fresh local Postgres. Both paths agree, which is why the CI number
and the local number match.

---

## 7. Still open (deliberately, and honestly)

1. **No physical-device testing.** Nothing here proves background audio, Doze
   behaviour, real FCM delivery latency or battery. Everything was verified
   in-app, in the DB and through the APK's contents.
2. **Call timeout job missing.** A `ringing` call nobody answers stays `ringing`;
   it needs the same cron pattern as `media-cleanup`. (Finding #3 in the review.)
3. **`media-cleanup` cron still not deployed**, so Cloudinary grows forever.
4. **Floating Alerts are surfaced in the inbox, not the profile/settings tab** —
   the `/notifications` route from the plan is still not built; the banner
   covers it.
5. **Unsigned Cloudinary preset** (medium, accepted): quota abuse possible,
   no data exposure. Fix = signed uploads via an Edge Function.
6. **`delete_own_account` has no UI.**
7. **`send-push` has behaviour tests but no non-JWT unit test.**
8. **Realtime is trusted to Supabase's row filtering**; no hostile WebSocket
   client was simulated.

---

## 8. Commits

```
d2e5013  Phase 5c: notification tap opens the Force Audio takeover screen
24fcbe3  Phase 7: groups, roles and group media
49189f4  Phase 8: calls — state machine, provider abstraction, no fake connected
2d710ed  Phase 9: settings, notification permission states, a11y and lifecycle
d0ebdba  Phase 10: security review, RLS pentest, measurements, release proof
```

CI green on `d0ebdba`: `43623535110` (4/4 jobs), APK `14125047760`.
