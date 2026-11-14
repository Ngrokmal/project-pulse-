#!/usr/bin/env python3
"""Phase 7 live acceptance: groups + roles over the REAL stack.

GoTrue signup -> real JWT -> PostgREST/Postgres RPCs with RLS.

Uses the two demo accounts from the environment and creates one throwaway
outsider account, which is deleted at the end (finally block).

Requires: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL,
          PULSE_TEST_EMAIL_A, PULSE_TEST_PASSWORD, PULSE_TEST_EMAIL_B
"""
import json
import os
import random
import sys
import urllib.error
import urllib.request

import psycopg2

URL = os.environ["SUPABASE_URL"].rstrip("/")
ANON = os.environ["SUPABASE_ANON_KEY"]
DB = os.environ["SUPABASE_DB_URL"]
EMAIL = os.environ["PULSE_TEST_EMAIL_A"]
EMAIL_B = os.environ["PULSE_TEST_EMAIL_B"]
PW = os.environ["PULSE_TEST_PASSWORD"]

PASS = FAIL = 0
FAILED = []


def ok_or_no_content(status):
    """PostgREST answers 204 for a void RPC, 200 when it returns a value."""
    return status in (200, 204)


def check(name, expected, actual):
    global PASS, FAIL
    if str(expected) == str(actual):
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        FAILED.append(name)
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
        "POST",
        "/auth/v1/token?grant_type=password",
        body={"email": email, "password": PW},
    )
    assert st == 200, (st, body)
    return body["access_token"], body["user"]["id"]


def rpc(name, params, token):
    return req("POST", f"/rest/v1/rpc/{name}", token, params)


def err_text(body):
    """PostgREST puts the raised message in 'message' (or 'error')."""
    if isinstance(body, dict):
        return str(body.get("message") or body.get("error") or body).lower()
    return str(body).lower()


def main():
    global PASS, FAIL
    outsider_email = f"pulse.grp.{int(random.random()*1e9)}@mailinator.com"

    token_a, uid_a = sign_in(EMAIL)
    token_b, uid_b = sign_in(EMAIL_B)

    # the outsider: a real account that is in no group
    st, body = req(
        "POST",
        "/auth/v1/signup",
        body={"email": outsider_email, "password": PW},
    )
    assert st in (200, 201), (st, body)
    token_c, uid_c = sign_in(outsider_email)

    gid = None
    try:
        print("== 1. create a group ==")
        st, body = rpc(
            "create_group",
            {"p_title": "QA group", "p_members": [uid_b]},
            token_a,
        )
        check("the owner can create a group", 200, st)
        gid = body if isinstance(body, str) else None
        check("…and gets a conversation id back", "str", type(gid).__name__)

        st, rows = req(
            "GET",
            f"/rest/v1/conversations?select=id,kind,title&id=eq.{gid}",
            token_a,
        )
        check("the group row is kind=group", "group", rows[0]["kind"])
        check("…with the title asked for", "QA group", rows[0]["title"])

        print("== 2. the other member sees it, as a member ==")
        st, rows = req(
            "GET",
            f"/rest/v1/conversations?select=id,title&id=eq.{gid}",
            token_b,
        )
        check("the member can read the group", 1, len(rows))
        st, rows = req(
            "GET",
            f"/rest/v1/conversation_members?select=user_id,role&conversation_id=eq.{gid}",
            token_b,
        )
        roles = {r["user_id"]: r["role"] for r in rows}
        check("the creator is the owner", "owner", roles.get(uid_a))
        check("the invited person is a member", "member", roles.get(uid_b))

        print("== 3. role enforcement ==")
        st, body = rpc("rename_group", {"p_conversation": gid, "p_title": "Hacked"}, token_b)
        check("a plain member cannot rename the group", 403, st)
        check("…server says not_allowed", "not_allowed", err_text(body))

        st, body = rpc(
            "add_group_member", {"p_conversation": gid, "p_user": uid_c}, token_b
        )
        check("a plain member cannot add members", 403, st)

        st, body = rpc("set_group_role", {"p_conversation": gid, "p_user": uid_b, "p_role": "admin"}, token_a)
        check("the owner can promote an admin", True, ok_or_no_content(st))
        st, body = rpc("rename_group", {"p_conversation": gid, "p_title": "QA group v2"}, token_b)
        check("…and the new admin can rename", True, ok_or_no_content(st))
        st, rows = req("GET", f"/rest/v1/conversations?select=title&id=eq.{gid}", token_a)
        check("…the rename really landed", "QA group v2", rows[0]["title"])

        st, body = rpc("set_group_role", {"p_conversation": gid, "p_user": uid_b, "p_role": "owner"}, token_b)
        check("an admin cannot hand out ownership", 403, st)
        st, body = rpc("remove_group_member", {"p_conversation": gid, "p_user": uid_a}, token_b)
        check("an admin cannot remove the owner", 403, st)

        print("== 4. the outsider is fenced off by RLS ==")
        st, rows = req("GET", f"/rest/v1/conversations?select=id&id=eq.{gid}", token_c)
        check("a non-member sees no group row", 0, len(rows))
        st, rows = req(
            "GET",
            f"/rest/v1/conversation_members?select=user_id&conversation_id=eq.{gid}",
            token_c,
        )
        check("a non-member sees no membership rows", 0, len(rows))
        st, rows = req(
            "GET", f"/rest/v1/messages?select=id&conversation_id=eq.{gid}", token_c
        )
        check("a non-member sees no messages", 0, len(rows))
        st, body = rpc(
            "add_group_member", {"p_conversation": gid, "p_user": uid_c}, token_c
        )
        check("a non-member cannot add themselves", 403, st)
        check(
            "…server refuses with a typed reason",
            True,
            err_text(body) in ("not_a_member", "not_allowed"),
        )
        st, body = req(
            "POST",
            "/rest/v1/messages",
            token_c,
            {
                "conversation_id": gid,
                "client_id": "grp-outsider-1",
                "body": "let me in",
            },
        )
        check("a non-member cannot post into the group", 403, st)

        print("== 5. membership rows are not client-writable ==")
        st, body = req(
            "POST",
            "/rest/v1/conversation_members",
            token_c,
            {"conversation_id": gid, "user_id": uid_c},
        )
        check("a client cannot insert itself into conversation_members", 403, st)

        print("== 6. leaving ==")
        st, body = rpc("leave_group", {"p_conversation": gid}, token_b)
        check("a member can leave", True, ok_or_no_content(st))
        st, rows = req("GET", f"/rest/v1/conversations?select=id&id=eq.{gid}", token_b)
        check("…and stops seeing the group", 0, len(rows))
        st, rows = req(
            "GET",
            f"/rest/v1/conversation_members?select=user_id,role&conversation_id=eq.{gid}",
            token_a,
        )
        check("…the owner is left alone", 1, len(rows))
        check("…still as owner", "owner", rows[0]["role"])

        st, body = rpc("leave_group", {"p_conversation": gid}, token_c)
        check("a non-member cannot leave", True, st in (400, 403))

        print("== 7. the last member deletes the group ==")
        st, body = rpc("leave_group", {"p_conversation": gid}, token_a)
        check("the owner can leave too", True, ok_or_no_content(st))
        st, rows = req("GET", f"/rest/v1/conversations?select=id&id=eq.{gid}", token_a)
        check("…and the group is gone", 0, len(rows))
        gid_left = gid
        gid = None
        print(f"  (group {gid_left} removed by the last member leaving)")
    finally:
        conn = psycopg2.connect(DB)
        conn.autocommit = True
        cur = conn.cursor()
        if gid:
            cur.execute("delete from public.conversations where id = %s", (gid,))
            print(f"  cleanup: deleted leftover group {gid}")
        cur.execute("delete from auth.users where id = %s", (uid_c,))
        print(f"  cleanup: deleted throwaway outsider {uid_c}")
        conn.close()

    print()
    print(f"===== LIVE GROUPS API: {PASS} passed, {FAIL} failed =====")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
