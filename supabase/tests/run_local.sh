#!/usr/bin/env bash
# Applies every migration to a throw-away local PostgreSQL and runs the RLS
# test suite. This is how migrations are validated before they touch a real
# Supabase project (§8 "test migrations against a fresh database").
set -euo pipefail

# Locate the PostgreSQL server binaries without pinning a single version, so the
# same script runs on a dev box, in this sandbox and on a CI runner.
if [ -z "${PGBIN:-}" ]; then
  for cand in "$(pg_config --bindir 2>/dev/null)" /usr/lib/postgresql/*/bin /usr/pgsql-*/bin; do
    if [ -n "$cand" ] && [ -x "$cand/initdb" ]; then PGBIN=$cand; break; fi
  done
fi
PGBIN=${PGBIN:?could not find PostgreSQL server binaries}
PORT=${PORT:-5433}
DATADIR=${DATADIR:-/tmp/pulse-pg}
DB=pulse_migration_test

if [ ! -d "$DATADIR" ]; then
  "$PGBIN/initdb" -D "$DATADIR" -U postgres --auth=trust >/dev/null
fi

"$PGBIN/pg_ctl" -D "$DATADIR" -o "-p $PORT -k /tmp" -l "$DATADIR/server.log" start >/dev/null || true
sleep 1
trap '"$PGBIN/pg_ctl" -D "$DATADIR" stop -m fast >/dev/null 2>&1 || true' EXIT

PSQL="$PGBIN/psql -h /tmp -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$PSQL -c "drop database if exists $DB" postgres
$PSQL -c "create database $DB" postgres

echo "→ stub (auth schema + roles)"
$PSQL -d "$DB" -f supabase/tests/00_local_stub.sql

for m in supabase/migrations/*.sql; do
  echo "→ applying $m"
  $PSQL -d "$DB" -f "$m"
done

# Verify policy capability preflight fails closed under an unauthorized role.
preflight_log=$(mktemp /tmp/pulse-storage-preflight-XXXXXX)
if printf "set role authenticated;\n\\i supabase/migrations/0020_avatar_storage_control.sql\n" | $PSQL -d "$DB" >"$preflight_log" 2>&1; then
  echo 'FAIL: storage policy preflight accepted unauthorized role'; rm -f "$preflight_log"; exit 1
fi
if ! grep -q 'storage.objects policy management permission required' "$preflight_log"; then
  echo 'FAIL: preflight failed for an unexpected reason'; cat "$preflight_log"; rm -f "$preflight_log"; exit 1
fi
rm -f "$preflight_log"
echo 'storage policy preflight rejected unauthorized role'

# Supabase grants ALL on public tables to service_role by default (it also has
# BYPASSRLS). Mirror that here so the shipped policies are tested as they will
# actually run in production.
$PSQL -d "$DB" -c "grant all on all tables in schema public to service_role"
$PSQL -d "$DB" -c "grant all on all sequences in schema public to service_role"

echo "→ RLS tests"
for f in supabase/tests/10_rls_test.sql supabase/tests/23_live_suspension_test.sql supabase/tests/24_admin_foundation_test.sql supabase/tests/25_expiry_transition_test.sql supabase/tests/26_group_and_expiry_contract.sql supabase/tests/27_admin_api_test.sql supabase/tests/28_avatar_storage_controls_test.sql supabase/tests/40_live_chat_test.sql supabase/tests/50_force_audio_test.sql supabase/tests/60_groups_test.sql supabase/tests/70_calls_test.sql supabase/tests/80_rls_pentest.sql supabase/tests/90_presence_test.sql supabase/tests/91_friends_from_chats_test.sql; do
  [ -f "$f" ] || continue
  echo "  · $f"
  # ON_ERROR_STOP makes psql exit non-zero as soon as an assertion block raises.
  out=$($PSQL -d "$DB" -f "$f" 2>&1) || { printf '%s\n' "$out" | tail -20; exit 1; }
  printf '%s\n' "$out" | grep -E 'FAIL|assertions passed|attacks were correctly refused|ALL RLS TESTS PASSED' || true
done
echo "ALL RLS TESTS PASSED"
