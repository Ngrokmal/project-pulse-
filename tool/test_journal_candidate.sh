#!/usr/bin/env bash
# Disposable database only, separate from every managed project.
set -euo pipefail
PGBIN=$(pg_config --bindir)
DIR=$(mktemp -d /tmp/pulse-journal-XXXXXX)
PORT=55439
cleanup() { "$PGBIN/pg_ctl" -D "$DIR/data" stop -m fast >/dev/null 2>&1 || true; rm -rf "$DIR"; }
trap cleanup EXIT
"$PGBIN/initdb" -D "$DIR/data" -U postgres --auth=trust >/dev/null
"$PGBIN/pg_ctl" -D "$DIR/data" -o "-p $PORT -k $DIR -c listen_addresses=''" -l "$DIR/server.log" start >/dev/null
PSQL=("$PGBIN/psql" -h "$DIR" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -f supabase/tests/00_local_stub.sql
for migration in supabase/migrations/*.sql; do "${PSQL[@]}" -f "$migration"; done
"${PSQL[@]}" -f supabase/tests/journal_fixture.sql
"${PSQL[@]}" -f supabase/candidates/message_change_journal.sql
"${PSQL[@]}" -f supabase/tests/journal_candidate_test.sql
# Two separate database sessions; the first holds the per-conversation head
# until commit. The second must not overtake it.
"${PSQL[@]}" -c "insert into public.conversations(id,kind,title,created_by) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','group','Concurrency','11111111-1111-4111-8111-111111111111')"
"${PSQL[@]}" -c "begin; insert into public.messages(id,conversation_id,sender_id,body,client_id) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','first','journal-concurrent-1'); select pg_sleep(2); commit" > "$DIR/first.log" 2>&1 &
first=$!
sleep 0.3
"${PSQL[@]}" -c "insert into public.messages(id,conversation_id,sender_id,body,client_id) values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','second','journal-concurrent-2')"
wait "$first"
"${PSQL[@]}" -c "do \$\$ begin if (select array_agg(message_id order by revision) from public.pulse_message_changes where conversation_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') <> array['bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc']::uuid[] then raise exception 'concurrent commits out of order'; end if; end \$\$;"
echo 'journal concurrent commit test passed'
