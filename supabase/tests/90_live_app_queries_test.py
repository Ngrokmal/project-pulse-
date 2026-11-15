#!/usr/bin/env python3
"""Phase 10 follow-up: every PostgREST query the app actually issues.

Why this exists: the inbox broke in production with

    PGRST200 Could not find a relationship between 'conversation_members'
    and 'profiles'

...because the table referenced `auth.users`, not `public.profiles`, so
PostgREST could not resolve the embed. RLS suites passed, unit tests passed, the
APK built — nothing checked the *shape* of the queries the client sends.

This suite runs those queries verbatim, as a signed-in user, and fails on
anything but a 200. Add a query here whenever the app adds one.

Requires: SUPABASE_URL, SUPABASE_ANON_KEY, PULSE_TEST_EMAIL_A/B, PULSE_TEST_PASSWORD
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ["SUPABASE_URL"].rstrip("/")
ANON = os.environ["SUPABASE_ANON_KEY"]
EMAIL_A = os.environ["PULSE_TEST_EMAIL_A"]
EMAIL_B = os.environ["PULSE_TEST_EMAIL_B"]
PW = os.environ["PULSE_TEST_PASSWORD"]

PASS = FAIL = 0


def check(name, expected, actual, extra=""):
    global PASS, FAIL
    if str(expected) == str(actual):
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  (expected={expected} actual={actual}) {extra}")


def sign_in(email):
    r = urllib.request.Request(
        URL + "/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": PW}).encode(),
        method="POST",
    )
    r.add_header("apikey", ANON)
    r.add_header("Content-Type", "application/json")
    body = json.loads(urllib.request.urlopen(r, timeout=30).read())
    return body["access_token"], body["user"]["id"]


def get(path, token):
    r = urllib.request.Request(URL + path)
    r.add_header("apikey", ANON)
    r.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def post(path, token, body, prefer=None):
    r = urllib.request.Request(URL + path, data=json.dumps(body).encode(), method="POST")
    r.add_header("apikey", ANON)
    r.add_header("Authorization", f"Bearer {token}")
    r.add_header("Content-Type", "application/json")
    if prefer:
        r.add_header("Prefer", prefer)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def main():
    token_a, uid_a = sign_in(EMAIL_A)
    token_b, uid_b = sign_in(EMAIL_B)

    print("== 1. the inbox query (this is what broke) ==")
    inbox = (
        "/rest/v1/conversations?select=id,kind,title,avatar_url,last_message_at,"
        "last_message_preview,last_message_sender,"
        "conversation_members(user_id,role,last_read_at,"
        "profiles(id,display_name,username,avatar_url))"
        "&order=last_message_at.desc.nullslast"
    )
    st, rows = get(inbox, token_a)
    check("conversations + members + profiles embed", 200, st, str(rows)[:180] if st != 200 else "")
    if st == 200:
        check("…returns a list", True, isinstance(rows, list))
        if rows:
            first = rows[0]
            check("…with a kind column", True, "kind" in first)
            members = first.get("conversation_members") or []
            check("…and each member carries its profile", True,
                  all("profiles" in m for m in members) if members else True,
                  str(members[:1])[:160])

    # make sure at least one row goes through the members->profiles path
    st, conv = post(
        "/rest/v1/rpc/start_direct_conversation",
        token_a,
        {"p_other": uid_b},
    )
    check("start_direct_conversation still works", 200, st, str(conv)[:160])
    st, rows = get(inbox, token_a)
    check("…and the inbox resolves it to a named conversation", 200, st)
    if st == 200:
        named = [
            r
            for r in rows
            if any(
                (m.get("profiles") or {}).get("display_name")
                for m in (r.get("conversation_members") or [])
            )
        ]
        check("…with at least one peer profile present", True, bool(named))

    conv_id = conv if isinstance(conv, str) else (conv[0] if conv else None)
    if not conv_id:
        print("  (no conversation id; skipping the per-conversation queries)")
        return finish()

    print("== 2. the chat thread query ==")
    st, rows = get(
        f"/rest/v1/messages?select=*&conversation_id=eq.{conv_id}"
        "&order=created_at.desc&limit=100",
        token_a,
    )
    check("messages for a conversation", 200, st, str(rows)[:160])

    print("== 3. the group member query ==")
    st, gid = post("/rest/v1/rpc/create_group", token_a, {"p_title": "Embed QA", "p_members": [uid_b]})
    check("create_group", 200, st, str(gid)[:160])
    if isinstance(gid, str):
        st, rows = get(
            f"/rest/v1/conversation_members?select=user_id,role,profiles(id,display_name,username)"
            f"&conversation_id=eq.{gid}",
            token_a,
        )
        check("group members with profiles", 200, st, str(rows)[:160])
        if st == 200:
            check("…both members resolved", 2, len(rows))
            check(
                "…and the owner is marked",
                "owner",
                next((r["role"] for r in rows if r["user_id"] == uid_a), None),
            )
        post("/rest/v1/rpc/leave_group", token_a, {"p_conversation": gid})

    print("== 4. people picker, profile, devices, tokens ==")
    st, rows = get("/rest/v1/profiles?select=id,display_name,username,avatar_url"
                   f"&id=neq.{uid_a}&order=display_name&limit=100", token_a)
    check("people picker", 200, st, str(rows)[:160])
    st, rows = get(f"/rest/v1/profiles?select=*&id=eq.{uid_a}&limit=1", token_a)
    check("my profile", 200, st, str(rows)[:160])
    st, rows = get("/rest/v1/devices?select=*&limit=1", token_a)
    check("my devices", 200, st, str(rows)[:160])
    st, rows = get("/rest/v1/fcm_tokens?select=*&limit=1", token_a)
    check("my push tokens", 200, st, str(rows)[:160])

    print("== 5. force audio + calls ==")
    st, rows = get("/rest/v1/force_audio_alerts?select=*&limit=1", token_a)
    check("force audio alerts", 200, st, str(rows)[:160])
    st, call = post("/rest/v1/rpc/start_call", token_a, {"p_conversation": conv_id, "p_kind": "audio"})
    check("start_call", 200, st, str(call)[:160])
    if isinstance(call, str):
        st, rows = get(f"/rest/v1/calls?select=*&id=eq.{call}", token_a)
        check("the call row", 200, st, str(rows)[:160])
        post("/rest/v1/rpc/end_call", token_a, {"p_call": call, "p_reason": "hangup"})

    return finish()


def finish():
    print()
    print(f"===== LIVE APP QUERIES: {PASS} passed, {FAIL} failed =====")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
