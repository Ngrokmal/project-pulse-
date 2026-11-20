# Suspending an account: one tick, and the account is closed

This is the contract behind `public.account_status`. Read it before touching
anything that reads or writes user data — the pause is only as complete as the
last policy that forgot to ask.

## The switch

Open **Table editor → `account_status`** and tick `suspended`.

That is the whole procedure. On the next statement the row flips, and the
trigger `sync_account_suspension` keeps the two columns honest in both
directions:

| you write | what happens |
|---|---|
| `suspended = true` | `status` becomes `suspended`, `starts_at` becomes `now()` |
| `suspended = false` | `status` becomes `active` |
| `status = 'banned'` | `suspended` becomes `true` |
| `status = 'active'` | `suspended` becomes `false` |

`case_code` (`PULSE-1A2B3C4D5`) is generated once per account and never changes;
it is the reference printed on the hold screen and quoted by support.

## What "closed" means, exactly

When the tick lands, in the same transaction:

1. **Every refresh token of that account is deleted** (`auth.sessions`, which
   cascades to `auth.refresh_tokens`). The phone cannot renew its session; the
   access token it already holds goes dark on its own within the hour, and the
   app does not wait for that — it signs out the moment it hears.
2. **Presence and push tokens are deleted.** The account stops appearing online
   and stops receiving notifications. `send-push` refuses the user id anyway, as
   a third lock on the same door.
3. **Every row-level policy on a user-owned table refuses it.** `messages`,
   `conversations`, `conversation_members`, `profiles`, `user_presence`,
   `friendships`, `friend_requests`, `blocks`, `reports`, `profile_visits`,
   `calls`, `force_audio_alerts`, `fcm_tokens`, `devices`,
   `account_device_history`, and the `avatars` bucket all carry
   `public.is_account_active(auth.uid())`. Reads return nothing; writes are
   refused. This is enforced by Postgres, so a patched APK, a replayed request
   or a hand-written curl all get the same answer.
4. **Writes that go through `SECURITY DEFINER` functions are refused too.** The
   guard trigger `guard_<table>_activity` raises
   `account_suspended` (SQLSTATE `PULSE`) for any row written *by a caller* whose
   account is suspended. Definer functions run as their owner, where RLS does
   not apply; this is the check that covers them, including the ones nobody has
   written yet.
5. **The device forgets.** The app clears its cached messages and its send
   queue, unregisters push, drops the session and shows the notice.

Two doors stay open on purpose, because without them the person could not be
told what happened or ask for it to be looked at again:

* `account_status` — the caller's own row, one row, read-only.
* `account_appeals` — insert one open appeal (a partial unique index allows
  exactly one), read your own history. An active account cannot file one.

## What the app does

```
server row changes (Realtime, ~1 s)
        │      poll every 20 s … resume from background …   "PULSE" on any write
        ▼
AccountStatusController._evaluate  →  AccountLockController.lock(info)
        │
        ├─ snapshot the case + the email into AccountHold (the session is about to go)
        ├─ ChatLocalStore.clear()            cached archive and outbox
        ├─ pushRegistration.handleSignOut()  unregister the device
        └─ authController.signOut()          drop the tokens
        ▼
GoRouter redirect  →  /account-on-hold  →  AccountOnHoldScreen
        (PopScope canPop:false; every other location redirects back here)
```

The notice has exactly two exits: **ask a person to look again** (which signs in
once, only to file the appeal, then signs out again as soon as it is filed) and
**sign in with a different account**.

## Filing an appeal

`INSERT INTO account_appeals (user_id, case_code, note)` as the suspended
account. The policy requires:

* `user_id = auth.uid()`;
* `status = 'open'` (the verdict is not the client's to write);
* the account is **not** active — an active account has nothing to appeal;
* `case_code` equals the caller's own `account_status.case_code`, so an appeal
  cannot be attached to someone else's case.

A second open appeal is refused by `account_appeals_one_open`.

## Verifying it is still true

```bash
# applies every migration to a throwaway database and runs the whole RLS suite
bash supabase/tests/run_local.sh

# the suspension contract against the real project (creates its own throwaway
# users, and ends with ROLLBACK)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/23_live_suspension_test.sql
```

`23_live_suspension_test.sql` includes a schema assertion: **every** policy on a
user-owned table must mention `is_account_active`, and all thirteen
`guard_*_activity` triggers must exist. A future migration that adds a table
without the guard fails that test instead of silently leaving a door open.

## Traps worth remembering

* A `BEFORE` trigger that returns `NULL` does not "allow" the row — it cancels
  it silently. `guard_account_activity` returns `new`/`old`; a version that
  returned `null` made every insert in the app vanish without an error.
* Deleting is not guarded on `user_presence`, `fcm_tokens` and
  `account_device_history`: signing out has to be able to remove the phone's own
  rows even when the account being signed out of is the suspended one.
* A suspension is not a chat outage: the *other* side of a conversation keeps
  reading and writing. The tests assert both halves.
