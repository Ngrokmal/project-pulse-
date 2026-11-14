# PULSE — RLS & privilege matrix

Migrations: `supabase/migrations/0001_profiles.sql`, `0002_account_status.sql`,
`0003_devices_and_tokens.sql`.
Verified locally by `supabase/tests/run_local.sh` (fresh PostgreSQL + RLS suite).
**Status: APPLIED to the production project and verified live — 26/26 SQL
assertions and 26/26 API assertions pass (see "Live verification" below).**

| Table | anon | authenticated (own) | authenticated (other) | service_role |
|---|---|---|---|---|
| `profiles` | ⛔ no privilege | ✅ SELECT, UPDATE (display_name, username, bio, avatar_url, cover_url) | 👁 SELECT only | ✅ all |
| `account_status` | ⛔ no privilege | 👁 SELECT own row only | ⛔ 0 rows | ✅ all (only writer) |
| `devices` | ⛔ no privilege | 👁 SELECT if linked to caller | ⛔ 0 rows | ✅ all (only writer) |
| `account_device_history` | ⛔ no privilege | 👁 SELECT own links | ⛔ 0 rows | ✅ all (only writer) |
| `device_security_events` | ⛔ no privilege | ⛔ no privilege | ⛔ no privilege | ✅ all |
| `fcm_tokens` | ⛔ no privilege | ✅ SELECT / INSERT / UPDATE / DELETE own rows | ⛔ denied (WITH CHECK) | ✅ all |

**Deliberate design choices**

1. **No INSERT/DELETE policy on `profiles`** → rows are created by the
   `handle_new_user()` trigger (SECURITY DEFINER) and deleted by the
   `auth.users` cascade. A client cannot create or delete profile rows at all.
2. **Column-level UPDATE grant on `profiles`** → a user cannot rewrite
   `joined_at` or `id`; only editable fields are granted.
3. **`account_status` is read-only for every client role**, including the user's
   own row. A restriction can therefore never be lifted from the app (§25).
4. **Devices are never written by clients.** `device-register` (Edge Function,
   service_role) is the only writer; it stores a keyed HMAC-SHA256 of the
   Android ID, never the raw value.
5. **`is_account_active(uuid)`** is SECURITY DEFINER with a fixed `search_path`
   so future policies can gate on account status without exposing the table.
6. **Shared devices are legitimate** — `account_device_history` is an audit
   trail, not an automatic ban signal (§31.7).

**Local test evidence (run 2026-11-14)**

```
→ stub (auth schema + roles)
→ applying supabase/migrations/0001_profiles.sql
→ applying supabase/migrations/0002_account_status.sql
→ applying supabase/migrations/0003_devices_and_tokens.sql
→ RLS tests
ALL RLS TESTS PASSED
```

Assertions covered: profile trigger creation (1 row per auth user), own-row
update allowed, cross-user update blocked, invalid username rejected by check
constraint, client INSERT denied, client DELETE denied, `joined_at` rewrite
denied, `account_status` isolation + no client writes, client device INSERT
denied, own FCM token CRUD allowed, forged token for another user denied,
service_role device insert + link visible to the linked account and invisible
to an unrelated account, anon denied on `profiles` and `account_status`.

---

## Live verification against the production project (2026-11-14)

Migrations `0001`–`0003` were applied to the real project
(`lehrtdrxaioknyuenqeg`, region `ap-south-1`) and verified twice against the
live stack. Nothing is left behind: the SQL suite runs in a single transaction
that ends in `ROLLBACK`, and the API suite deletes the account it creates.

**Resulting schema**

| object | count |
| --- | --- |
| tables in `public` (all with `relrowsecurity = true`) | 6 |
| policies | 9 (`profiles` 2, `account_status` 1, `devices` 1, `account_device_history` 1, `fcm_tokens` 4) |
| triggers | 5 (`on_auth_user_created`, `on_profile_created`, 3 × `touch_updated_at`) |
| functions | 4 (`handle_new_user`, `handle_new_profile_status`, `touch_updated_at`, `is_account_active`) |

**Suite 1 — `supabase/tests/20_live_rls_test.sql` (SQL, transactional): 26 / 26 PASS**

Highlights, verbatim from the run:

```
PASS  auth.users insert → profile + account_status created
PASS  cross-user profile update affects 0 rows                (rows=0)
PASS  username check constraint rejects bad value             (profiles_username_format)
PASS  client cannot INSERT profiles                           (permission denied)
PASS  joined_at is not client-writable                        (permission denied)
PASS  account_status shows only own row                       (visible=1)
PASS  client cannot write account_status                      (permission denied)
PASS  device_security_events hidden from clients              (permission denied)
PASS  device visible only through own link                    (visible devices=1)
PASS  forged FCM token for another user denied                (new row violates row-level security policy)
PASS  B sees no rows in a device table linked to A            (visible=0)
PASS  anon cannot select profiles / account_status / fcm_tokens
```

**Suite 2 — `supabase/tests/30_live_api_test.sh` (GoTrue → PostgREST → RLS): 26 passed, 0 failed, 1 skipped**

```
PASS  password sign-in returns a session (http 200)
PASS  JWT role claim is authenticated
PASS  GET own profile (RLS select)            200
PASS  devices not linked to me (empty, error-free)   0
PASS  PATCH display_name + bio allowed        200
PASS  PATCH joined_at denied                  403
PASS  PATCH invalid username rejected         400
PASS  DELETE own profile denied               403
PASS  PATCH account_status denied             403
PASS  INSERT device denied                    403
PASS  INSERT own FCM token allowed            201
PASS  INSERT token for someone else denied    403
PASS  short token rejected by check constraint 400
PASS  DELETE own token allowed                204
PASS  anon GET profiles / account_status denied 401
SKIP  public signup endpoint — GoTrue email rate limit (configure custom SMTP)
```

The skipped assertion is a platform limit, not a code defect: the project still
uses Supabase's built-in SMTP, which allows only a couple of confirmation mails
per hour. Before public launch the project needs custom SMTP (Resend / Brevo /
Postmark) — see `docs/PHASE_2_REPORT.md` → "Open items".

### Two defects the live run caught (both fixed)

1. **`auth.users` provisioning.** Inserting a user with the `*_token` /
   `email_change` columns left `NULL` makes GoTrue fail sign-in with
   `500 Database error querying schema` — it scans those columns into
   non-nullable strings. They must be `''`. The migration test harness sets them
   explicitly.
2. **`fcm_tokens_len` CHECK** (`char_length(token)` between 20 and 4096) — the
   first fixture token was 15 characters and was rejected. Real FCM tokens are
   ~150+ characters, so the constraint is correct; the harness fixtures were
   wrong. Client code must never insert a placeholder token.

---

## Chat tables (migration `0004_chat.sql`)

| Table | anon | authenticated (member) | authenticated (outsider) | service_role |
|---|---|---|---|---|
| `conversations` | ⛔ no privilege | 👁 SELECT | ⛔ 0 rows | ✅ all |
| `conversation_members` | ⛔ no privilege | 👁 SELECT, UPDATE (`last_read_at` only) | ⛔ 0 rows | ✅ all |
| `messages` | ⛔ no privilege | ✅ SELECT / INSERT (own sender) / UPDATE (own) / DELETE (own) | ⛔ 0 rows | ✅ all |

`start_direct_conversation(uuid)` is SECURITY DEFINER, idempotent for a pair of
users and executable by `authenticated` only. Messages are never hard-deleted by
clients; `deleted_at` is the only delete path and RLS filters rows instead of
raising, which the tests assert explicitly. Sending additionally requires
`is_account_active(auth.uid())`, so a banned account cannot post even with a valid
token. Verified live: **19 / 19** SQL assertions and the chat section of the
**54 / 54** API suite.
