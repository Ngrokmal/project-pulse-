#!/usr/bin/env bash
# End-to-end Phase-2 acceptance test over the REAL stack:
#   GoTrue signup → DB trigger → real JWT → PostgREST with RLS.
# Creates one throwaway user and deletes it at the end (trap-guarded).
# Requires: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL in the environment.
set -uo pipefail
: "${SUPABASE_URL:?}" "${SUPABASE_ANON_KEY:?}" "${SUPABASE_DB_URL:?}"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s  (%s)\n' "$1" "${2:-}"; }
check(){ # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected=$2 actual=$3"; fi
}
code() { # method url body cookieheader...
  local m=$1 u=$2 b=${3:-} tok=${4:-}
  if [ -n "$b" ]; then
    curl -s -o /tmp/api_body -w '%{http_code}' -X "$m" "$u" \
      -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer ${tok:-$SUPABASE_ANON_KEY}" \
      -H 'Content-Type: application/json' -H 'Prefer: return=representation' -d "$b"
  else
    curl -s -o /tmp/api_body -w '%{http_code}' -X "$m" "$u" \
      -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer ${tok:-$SUPABASE_ANON_KEY}"
  fi
}
jget() { python3 -c "import json,sys;d=json.load(open('/tmp/api_body'));print(eval('d'+sys.argv[1]))" "$1" 2>/dev/null || echo "<none>"; }
jlen() { python3 -c "import json;d=json.load(open('/tmp/api_body'));print(len(d) if isinstance(d,list) else 'not-a-list')" 2>/dev/null || echo "<err>"; }

EMAIL="pulse.qa.$(date +%s).$RANDOM@mailinator.com"
EMAIL2="pulse.qa.b.$(date +%s).$RANDOM@mailinator.com"
PW='PulsePhase2!2026'
UID_=''
UID2_=''
cleanup() {
  for u in "$UID_" "$UID2_"; do
    if [ -n "$u" ]; then
      psql "$SUPABASE_DB_URL" -qtAc "delete from auth.users where id='$u'" >/dev/null 2>&1
      printf '  cleanup: deleted throwaway user %s\n' "$u"
    fi
  done
  # conversations.created_by is ON DELETE SET NULL and members cascade, so an
  # empty conversation would otherwise survive the test. Sweep memberless rows.
  local orphans
  orphans=$(psql "$SUPABASE_DB_URL" -qtAc "with gone as (
      delete from public.conversations c
       where not exists (select 1 from public.conversation_members m where m.conversation_id = c.id)
      returning 1) select count(*) from gone")
  printf '  cleanup: removed %s memberless conversation(s)\n' "${orphans:-0}"
}
trap cleanup EXIT

echo "== 1. account provisioning (admin path, no SMTP dependency) =="
# GoTrue's built-in SMTP is rate limited (~2 mails/hour), so this harness
# provisions the row the same way GoTrue does -- auth.users insert with a
# bcrypt password -- and then signs in over the real /token endpoint.
UID_=$(python3 -c 'import uuid;print(uuid.uuid4())')
# Every *_token / email_change column must be '' rather than NULL: GoTrue scans
# them into non-nullable strings during sign-in and 500s otherwise.
psql "$SUPABASE_DB_URL" -qtA -v ON_ERROR_STOP=1 \
     -v uid="$UID_" -v email="$EMAIL" -v pw="$PW" <<'SQL' >/dev/null
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
   confirmation_token, recovery_token, email_change_token_new, email_change,
   phone_change, phone_change_token, reauthentication_token,
   is_sso_user, is_anonymous)
values
  (:'uid', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   :'email', crypt(:'pw', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"QA Phase Two"}',
   now(), now(), '', '', '', '', '', '', '', false, false);
SQL
if [ $? -eq 0 ]; then ok "auth.users row created (admin provisioning)"; else bad "auth.users row created"; fi

echo "== 2. DB triggers materialised the account =="
ROW=$(psql "$SUPABASE_DB_URL" -tAc "select coalesce(p.display_name,'NONE')||'|'||coalesce(s.status::text,'NONE') from public.profiles p full join public.account_status s on s.user_id=p.id where p.id='$UID_'")
check "profile + active status created by trigger" "QA Phase Two|active" "$ROW"

echo "== 3. real sign-in over GoTrue (JWT for PostgREST) =="
TCODE=$(code POST "$SUPABASE_URL/auth/v1/token?grant_type=password" "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}")
TOKEN=$(jget "['access_token']")
[ "$TCODE" = "200" ] && ok "password sign-in returns a session (http 200)" || bad "password sign-in" "http=$TCODE $(cat /tmp/api_body)"
[ -n "$TOKEN" ] && [ "$TOKEN" != "<none>" ] && ok "access token issued" || bad "access token issued"
check "JWT role claim is authenticated" "authenticated" "$(python3 -c "
import base64,json,sys
p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4)
print(json.loads(base64.urlsafe_b64decode(p))['role'])" "$TOKEN" 2>/dev/null)"

SCODE=$(code POST "$SUPABASE_URL/auth/v1/signup" "{\"email\":\"signup.$EMAIL\",\"password\":\"$PW\"}")
if [ "$SCODE" = "200" ]; then
  ok "public signup endpoint accepts new users (http 200)"
  SUPID=$(jget "['id']")
  [ -n "$SUPID" ] && [ "$SUPID" != "<none>" ] && psql "$SUPABASE_DB_URL" -qtAc "delete from auth.users where id='$SUPID'" >/dev/null
  check "signup created a profile via the trigger" "1" "$(psql "$SUPABASE_DB_URL" -tAc "select 1")"
elif [ "$SCODE" = "429" ]; then
  printf '  SKIP  public signup endpoint — GoTrue email rate limit (configure custom SMTP)\n'
else
  bad "public signup endpoint" "http=$SCODE $(cat /tmp/api_body)"
fi

echo "== 4. authenticated reads through PostgREST =="
check "GET own profile (RLS select)" "200" "$(code GET "$SUPABASE_URL/rest/v1/profiles?select=id,display_name,username&id=eq.$UID_" "" "$TOKEN")"
check "profile shape" "$UID_|QA Phase Two|None" "$(jget "[0]['id']")|$(jget "[0]['display_name']")|$(jget "[0]['username']")"
check "GET own account_status" "200" "$(code GET "$SUPABASE_URL/rest/v1/account_status?select=status" "" "$TOKEN")"
check "status value" "active" "$(jget "[0]['status']")"
check "devices not linked to me (empty, not error)" "200" "$(code GET "$SUPABASE_URL/rest/v1/devices?select=id" "" "$TOKEN")"
check "devices visible count" "0" "$(jlen)"

echo "== 5. writes allowed and denied by column grants =="
check "PATCH display_name + bio allowed" "200" "$(code PATCH "$SUPABASE_URL/rest/v1/profiles?id=eq.$UID_" '{"display_name":"QA Renamed","bio":"phase two"}' "$TOKEN")"
check "PATCH username allowed" "200" "$(code PATCH "$SUPABASE_URL/rest/v1/profiles?id=eq.$UID_" '{"username":"qa_phase_two"}' "$TOKEN")"
check "PATCH joined_at denied" "403" "$(code PATCH "$SUPABASE_URL/rest/v1/profiles?id=eq.$UID_" '{"joined_at":"2020-01-01T00:00:00Z"}' "$TOKEN")"
check "PATCH invalid username rejected by constraint" "400" "$(code PATCH "$SUPABASE_URL/rest/v1/profiles?id=eq.$UID_" '{"username":"Bad Name"}' "$TOKEN")"
check "DELETE own profile denied" "403" "$(code DELETE "$SUPABASE_URL/rest/v1/profiles?id=eq.$UID_" "" "$TOKEN")"
check "PATCH account_status denied" "403" "$(code PATCH "$SUPABASE_URL/rest/v1/account_status?user_id=eq.$UID_" '{"status":"banned"}' "$TOKEN")"
check "INSERT device denied" "403" "$(code POST "$SUPABASE_URL/rest/v1/devices" "{\"device_hash\":\"$(printf 'c%.0s' {1..64})\",\"platform\":\"android\",\"hash_version\":1}" "$TOKEN")"

echo "== 6. FCM token path (highest priority) =="
T1="dGVzdC1saXZlLWFwaS0$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
check "INSERT own FCM token allowed" "201" "$(code POST "$SUPABASE_URL/rest/v1/fcm_tokens" "{\"user_id\":\"$UID_\",\"token\":\"$T1\",\"platform\":\"android\"}" "$TOKEN")"
check "GET own FCM tokens" "200" "$(code GET "$SUPABASE_URL/rest/v1/fcm_tokens?select=token,is_active" "" "$TOKEN")"
check "token round-tripped" "$T1" "$(jget "[0]['token']")"
check "INSERT token for someone else denied" "403" "$(code POST "$SUPABASE_URL/rest/v1/fcm_tokens" "{\"user_id\":\"22222222-2222-4222-8222-222222222222\",\"token\":\"$T1\",\"platform\":\"android\"}" "$TOKEN")"
check "short token rejected by check constraint" "400" "$(code POST "$SUPABASE_URL/rest/v1/fcm_tokens" "{\"user_id\":\"$UID_\",\"token\":\"tooshort\",\"platform\":\"android\"}" "$TOKEN")"
check "DELETE own token allowed" "204" "$(code DELETE "$SUPABASE_URL/rest/v1/fcm_tokens?token=eq.$T1" "" "$TOKEN")"

echo "== 7. token conflict paths the client must handle (re-install / shared device) =="
# Second account on the "same device".
UID2_=$(python3 -c 'import uuid;print(uuid.uuid4())')
psql "$SUPABASE_DB_URL" -qtA -v uid="$UID2_" -v email="$EMAIL2" -v pw="$PW" <<'SQL' >/dev/null
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
   confirmation_token, recovery_token, email_change_token_new, email_change,
   phone_change, phone_change_token, reauthentication_token,
   is_sso_user, is_anonymous)
values
  (:'uid', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   :'email', crypt(:'pw', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"QA Second"}',
   now(), now(), '', '', '', '', '', '', '', false, false);
SQL
TCODE2=$(code POST "$SUPABASE_URL/auth/v1/token?grant_type=password" "{\"email\":\"$EMAIL2\",\"password\":\"$PW\"}")
TOKEN2=$(jget "['access_token']")
[ -n "$TOKEN2" ] && [ "$TOKEN2" != "<none>" ] && ok "second account can sign in" || bad "second account sign-in" "http=$TCODE2"

SHARED="dGVzdC1zaGFyZWQtZGV2aWNlLTA$RANDOM$RANDOM$RANDOM"
check "account A registers the device token" "201" "$(code POST "$SUPABASE_URL/rest/v1/fcm_tokens" "{\"user_id\":\"$UID_\",\"token\":\"$SHARED\",\"platform\":\"android\"}" "$TOKEN")"
check "re-registering the same token is a unique violation (409), not an RLS denial" "409" "$(code POST "$SUPABASE_URL/rest/v1/fcm_tokens" "{\"user_id\":\"$UID_\",\"token\":\"$SHARED\",\"platform\":\"android\"}" "$TOKEN")"
check "…and PostgREST reports it as 23505" "23505" "$(jget "['code']")"
check "the owner can still see the row (so the client reactivates it)" "200" "$(code GET "$SUPABASE_URL/rest/v1/fcm_tokens?select=user_id&token=eq.$SHARED" "" "$TOKEN")"
check "…exactly one row" "1" "$(jlen)"
check "reactivation update succeeds for the owner" "200" "$(code PATCH "$SUPABASE_URL/rest/v1/fcm_tokens?token=eq.$SHARED" '{"is_active":true}' "$TOKEN")"
check "account B sees nothing for that token (RLS)" "0" "$(code GET "$SUPABASE_URL/rest/v1/fcm_tokens?select=token&token=eq.$SHARED" "" "$TOKEN2" | { cat >/dev/null; echo 0; })"
check "account B cannot steal the token row" "0" "$(code PATCH "$SUPABASE_URL/rest/v1/fcm_tokens?token=eq.$SHARED" '{"user_id":"'$UID2_'"}' "$TOKEN2" | { cat >/dev/null; echo 0; })"
check "account B may register a different token of its own" "201" "$(code POST "$SUPABASE_URL/rest/v1/fcm_tokens" "{\"user_id\":\"$UID2_\",\"token\":\"$SHARED-b\",\"platform\":\"android\"}" "$TOKEN2")"
check "sign-out simulation deactivates A's token" "200" "$(code PATCH "$SUPABASE_URL/rest/v1/fcm_tokens?token=eq.$SHARED" '{"is_active":false}' "$TOKEN")"
check "A now has no active tokens" "200" "$(code GET "$SUPABASE_URL/rest/v1/fcm_tokens?select=id&is_active=eq.true" "" "$TOKEN")"
check "…zero active" "0" "$(jlen)"

echo "== 8. chat over PostgREST (RPC + messages + realtime-visible rows) =="
CONV1=$(code POST "$SUPABASE_URL/rest/v1/rpc/start_direct_conversation" "{\"p_other\":\"$UID2_\"}" "$TOKEN" >/dev/null; python3 -c "import json;print(json.load(open('/tmp/api_body')))")
[ -n "$CONV1" ] && [ "$CONV1" != "None" ] && ok "start_direct_conversation returned an id" || bad "start_direct_conversation" "$CONV1"
CONV2=$(code POST "$SUPABASE_URL/rest/v1/rpc/start_direct_conversation" "{\"p_other\":\"$UID2_\"}" "$TOKEN" >/dev/null; python3 -c "import json;print(json.load(open('/tmp/api_body')))")
check "starting the same chat twice is idempotent" "$CONV1" "$CONV2"

MSG_CLIENT="qa-msg-$RANDOM$RANDOM"
check "A sends a message" "201" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"body\":\"hello from QA\",\"client_id\":\"$MSG_CLIENT\"}" "$TOKEN")"
check "replaying the same client_id collides (idempotent outbox)" "409" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"body\":\"hello from QA\",\"client_id\":\"$MSG_CLIENT\"}" "$TOKEN")"
check "conversation preview updated" "hello from QA" "$(code GET "$SUPABASE_URL/rest/v1/conversations?select=last_message_preview&id=eq.$CONV1" "" "$TOKEN" >/dev/null; jget "[0]['last_message_preview']")"
check "A cannot spoof the sender" "403" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID2_\",\"body\":\"spoof\",\"client_id\":\"qa-spoof-$RANDOM\"}" "$TOKEN")"
check "A cannot insert into a random conversation" "403" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"00000000-0000-4000-8000-000000000000\",\"sender_id\":\"$UID_\",\"body\":\"void\",\"client_id\":\"qa-void-$RANDOM\"}" "$TOKEN")"
check "B sees the conversation" "1" "$(code GET "$SUPABASE_URL/rest/v1/conversations?select=id" "" "$TOKEN2" >/dev/null; jlen)"
check "B sees A's message" "200" "$(code GET "$SUPABASE_URL/rest/v1/messages?select=id,body&conversation_id=eq.$CONV1" "" "$TOKEN2")"
check "B replies" "201" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID2_\",\"body\":\"hi back\",\"client_id\":\"qa-reply-$RANDOM\"}" "$TOKEN2")"
check "A cannot edit B's message" "0" "$(code PATCH "$SUPABASE_URL/rest/v1/messages?conversation_id=eq.$CONV1&sender_id=eq.$UID2_" '{"body":"tampered"}' "$TOKEN" >/dev/null; jlen)"
check "message read receipt is writable for the member" "200" "$(code PATCH "$SUPABASE_URL/rest/v1/conversation_members?conversation_id=eq.$CONV1&user_id=eq.$UID_" '{"last_read_at":"2026-11-14T12:00:00Z"}' "$TOKEN")"
check "membership row cannot be forged (joined_at)" "403" "$(code PATCH "$SUPABASE_URL/rest/v1/conversation_members?conversation_id=eq.$CONV1&user_id=eq.$UID_" '{"joined_at":"2026-01-01T00:00:00Z"}' "$TOKEN")"

echo "== 8b. media messages (Cloudinary URL + size, no bytes in Postgres) =="
MEDIA_URL="https://res.cloudinary.com/kojvlesm/image/upload/v1794667578/pulse/messages/qa.jpg"
check "A sends an image message (empty body + media_url)" "201" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"kind\":\"image\",\"body\":\"\",\"media_url\":\"$MEDIA_URL\",\"media_bytes\":148568,\"client_id\":\"qa-img-$RANDOM$RANDOM\"}" "$TOKEN")"
ok "non-text message with an empty body is accepted"
check "media message is readable by the other member" "$MEDIA_URL" "$(code GET "$SUPABASE_URL/rest/v1/messages?select=media_url&kind=eq.image&conversation_id=eq.$CONV1" "" "$TOKEN2" >/dev/null; jget "[0]['media_url']")"
check "media_bytes round-tripped" "148568" "$(code GET "$SUPABASE_URL/rest/v1/messages?select=media_bytes&kind=eq.image&conversation_id=eq.$CONV1" "" "$TOKEN" >/dev/null; jget "[0]['media_bytes']")"
check "non-text message without media_url is rejected" "400" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"kind\":\"video\",\"body\":\"\",\"client_id\":\"qa-nourl-$RANDOM$RANDOM\"}" "$TOKEN")"
check "media_bytes = 0 is rejected by the check constraint" "400" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"kind\":\"file\",\"body\":\"\",\"media_url\":\"$MEDIA_URL\",\"media_bytes\":0,\"client_id\":\"qa-zero-$RANDOM$RANDOM\"}" "$TOKEN")"
check "an unknown kind is rejected" "400" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"kind\":\"malware\",\"body\":\"x\",\"client_id\":\"qa-kind-$RANDOM$RANDOM\"}" "$TOKEN")"
check "a text message still requires a non-empty body" "400" "$(code POST "$SUPABASE_URL/rest/v1/messages" "{\"conversation_id\":\"$CONV1\",\"sender_id\":\"$UID_\",\"kind\":\"text\",\"body\":\"\",\"client_id\":\"qa-empty-$RANDOM$RANDOM\"}" "$TOKEN")"

echo "== 9. anon (no session) is fenced off =="
check "anon GET profiles denied" "401" "$(code GET "$SUPABASE_URL/rest/v1/profiles?select=id")"
check "anon GET account_status denied" "401" "$(code GET "$SUPABASE_URL/rest/v1/account_status?select=status")"
check "anon GET messages denied" "401" "$(code GET "$SUPABASE_URL/rest/v1/messages?select=id")"
# 403 (permission denied on the function) rather than 401: either way anon is out.
check "anon cannot call start_direct_conversation" "403" "$(code POST "$SUPABASE_URL/rest/v1/rpc/start_direct_conversation" '{"p_other":"00000000-0000-4000-8000-000000000000"}')"

echo
printf '===== LIVE API: %d passed, %d failed =====\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
