#!/usr/bin/env python3
"""Phase 8 live acceptance: the call state machine over the REAL stack.

Two demo accounts call each other through PostgREST RPCs; every transition is
checked against the row, and the outsider/no-session paths are checked too.

Requires: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL,
          PULSE_TEST_EMAIL_A, PULSE_TEST_EMAIL_B, PULSE_TEST_PASSWORD
"""
import json
import os
import sys
import urllib.error
import urllib.request

import psycopg2

URL = os.environ["SUPABASE_URL"].rstrip("/")
ANON = os.environ["SUPABASE_ANON_KEY"]
DB = os.environ["SUPABASE_DB_URL"]
EMAIL_A = os.environ["PULSE_TEST_EMAIL_A"]
EMAIL_B = os.environ["PULSE_TEST_EMAIL_B"]
PW = os.environ["PULSE_TEST_PASSWORD"]

PASS = FAIL = 0


def check(name, expected, actual):
    global PASS, FAIL
    if str(expected) == str(actual):
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  (expected={expected} actual={actual})")


def req(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + path, data=data, method=method)
    r.add_header("apikey", ANON)
    r.add_header("Authorization", f"Bearer {token or ANON}")
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def sign_in(email):
    st, body = req(
        "POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": PW}
    )
    assert st == 200, (st, body)
    return body["access_token"], body["user"]["id"]


def rpc(name, params, token=None):
    return req("POST", f"/rest/v1/rpc/{name}", token, params)


def accepted(status):
    """PostgREST answers 204 for a void RPC and 200 when it returns a value."""
    return status in (200, 204)


def row_state(call_id, token):
    st, rows = req("GET", f"/rest/v1/calls?select=state,end_reason&id=eq.{call_id}", token)
    if not rows:
        return "<no row>"
    return rows[0]["state"]


def err(body):
    return str(body.get("message") or body).lower() if isinstance(body, dict) else str(body).lower()


def main():
    token_a, uid_a = sign_in(EMAIL_A)
    token_b, uid_b = sign_in(EMAIL_B)

    # a direct conversation between the two demo accounts
    st, conv = rpc("start_direct_conversation", {"p_other": uid_b}, token_a)
    assert st == 200, (st, conv)
    conv_id = conv if isinstance(conv, str) else conv[0]

    created = []
    try:
        print("== 1. placing a call ==")
        st, call_id = rpc("start_call", {"p_conversation": conv_id, "p_kind": "audio"}, token_a)
        check("the caller can start a call", 200, st)
        call_id = call_id if isinstance(call_id, str) else None
        created.append(call_id)
        check("…it starts in ringing", "ringing", row_state(call_id, token_a))

        st, body = rpc("start_call", {"p_conversation": conv_id, "p_kind": "audio"}, token_b)
        check("the callee cannot place a second call into the same chat while ringing", True, st in (400, 403, 409))

        print("== 2. the callee side ==")
        st, rows = req("GET", f"/rest/v1/calls?select=id,state&id=eq.{call_id}", token_b)
        check("the callee can see the call", 1, len(rows))
        st, body = rpc("accept_call", {"p_call": call_id}, token_a)
        check("the caller cannot accept their own call", True, st in (400, 403))
        st, body = rpc("accept_call", {"p_call": call_id}, token_b)
        check("the callee accepts", True, accepted(st))
        check("…the call is connecting, not connected", "connecting", row_state(call_id, token_b))

        print("== 3. media confirmation ==")
        st, body = rpc("confirm_call_connected", {"p_call": call_id}, token_b)
        check("only after media is up does it become active", True, accepted(st))
        check("…state is active", "active", row_state(call_id, token_a))

        st, body = rpc("set_call_reconnecting", {"p_call": call_id, "p_on": True}, token_a)
        check("a blip moves it to reconnecting", True, accepted(st))
        check("…state is reconnecting", "reconnecting", row_state(call_id, token_b))
        st, body = rpc("set_call_reconnecting", {"p_call": call_id, "p_on": False}, token_a)
        check("…and back to active", "active", row_state(call_id, token_a))

        print("== 4. hanging up ==")
        st, body = rpc("end_call", {"p_call": call_id, "p_reason": "hangup"}, token_a)
        check("a participant can end the call", True, accepted(st))
        check("…state is ended", "ended", row_state(call_id, token_b))
        st, body = rpc("end_call", {"p_call": call_id, "p_reason": "hangup"}, token_a)
        check("ending twice is idempotent", True, accepted(st))
        st, body = rpc("accept_call", {"p_call": call_id}, token_b)
        check("an ended call cannot be accepted again", True, st in (400, 403))

        print("== 5. declining and missing ==")
        st, call2 = rpc("start_call", {"p_conversation": conv_id, "p_kind": "video"}, token_a)
        created.append(call2 if isinstance(call2, str) else None)
        st, body = rpc("decline_call", {"p_call": call2}, token_b)
        check("the callee can decline", True, accepted(st))
        check("…state is declined", "declined", row_state(call2, token_a))

        st, call3 = rpc("start_call", {"p_conversation": conv_id, "p_kind": "audio"}, token_a)
        created.append(call3 if isinstance(call3, str) else None)
        st, body = rpc("end_call", {"p_call": call3, "p_reason": "timeout"}, token_a)
        check("a ringing call that times out becomes missed", "missed", row_state(call3, token_a))

        print("== 6. groups cannot be called ==")
        st, group = rpc("create_group", {"p_title": "Call QA", "p_members": [uid_b]}, token_a)
        group_id = group if isinstance(group, str) else None
        st, body = rpc("start_call", {"p_conversation": group_id, "p_kind": "audio"}, token_a)
        check("a group call is refused by name", True, st in (400, 403))
        check("…with a reason the app can show", True, "group_calls_not_supported" in err(body))
        psql_run("delete from public.conversations where id = %s", (group_id,))

        print("== 7. no session ==")
        st, _ = rpc("start_call", {"p_conversation": conv_id, "p_kind": "audio"})
        check("anon cannot start a call", True, st in (401, 403))
    finally:
        for cid in created:
            if cid:
                psql_run("delete from public.calls where id = %s", (cid,))
        print("  cleanup: removed the calls created by this run")

    print()
    print(f"===== LIVE CALLS API: {PASS} passed, {FAIL} failed =====")
    return 0 if FAIL == 0 else 1


def psql_run(sql, params):
    conn = psycopg2.connect(DB)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(sql, params)
    conn.close()


if __name__ == "__main__":
    sys.exit(main())
