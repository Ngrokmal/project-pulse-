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

# Supabase grants ALL on public tables to service_role by default (it also has
# BYPASSRLS). Mirror that here so the shipped policies are tested as they will
# actually run in production.
$PSQL -d "$DB" -c "grant all on all tables in schema public to service_role"
$PSQL -d "$DB" -c "grant all on all sequences in schema public to service_role"

echo "→ RLS tests"
$PSQL -d "$DB" -f supabase/tests/10_rls_test.sql
