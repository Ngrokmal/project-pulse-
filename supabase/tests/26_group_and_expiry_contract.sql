-- LOCAL/SYNTHETIC ONLY. This defines desired behavior, not a migration.
-- On failure PostgreSQL exits with an error and rolls the transaction back.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE phase0_contract (name text PRIMARY KEY, ok boolean NOT NULL, detail text) ON COMMIT DROP;
GRANT SELECT, INSERT ON phase0_contract TO authenticated;
INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES
 ('10000000-0000-4000-8000-000000000001','contract-a@example.invalid','{"display_name":"Synthetic A"}'),
 ('20000000-0000-4000-8000-000000000002','contract-b@example.invalid','{"display_name":"Synthetic B"}'),
 ('30000000-0000-4000-8000-000000000003','contract-c@example.invalid','{"display_name":"Synthetic C"}'),
 ('40000000-0000-4000-8000-000000000004','contract-d@example.invalid','{"display_name":"Synthetic D"}'),
 ('60000000-0000-4000-8000-000000000006','contract-e@example.invalid','{"display_name":"Synthetic E"}');
INSERT INTO public.conversations(id,kind,title,created_by) VALUES
 ('50000000-0000-4000-8000-000000000005','group','Synthetic group','10000000-0000-4000-8000-000000000001'),
 ('70000000-0000-4000-8000-000000000007','direct',null,'10000000-0000-4000-8000-000000000001');
INSERT INTO public.conversation_members(conversation_id,user_id,role) VALUES
 ('50000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000001','owner'),
 ('50000000-0000-4000-8000-000000000005','20000000-0000-4000-8000-000000000002','member'),
 ('50000000-0000-4000-8000-000000000005','30000000-0000-4000-8000-000000000003','member'),
 ('70000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000001','member'),
 ('70000000-0000-4000-8000-000000000007','20000000-0000-4000-8000-000000000002','member');
INSERT INTO public.blocks(blocker,blocked) VALUES
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002'),
 ('10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000003');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
DO $$ BEGIN
  BEGIN
    INSERT INTO public.messages(conversation_id,sender_id,body,client_id) VALUES ('50000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000001','synthetic group text','contract-group-001');
    INSERT INTO phase0_contract VALUES ('group message allowed despite direct block',true,null);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO phase0_contract VALUES ('group message allowed despite direct block',false,SQLSTATE||' '||SQLERRM);
  END;
  BEGIN
    INSERT INTO public.messages(conversation_id,sender_id,body,client_id) VALUES ('70000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000001','synthetic direct text','contract-direct-01');
    INSERT INTO phase0_contract VALUES ('direct message blocked',false,'insert accepted');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO phase0_contract VALUES ('direct message blocked',SQLSTATE='42501' AND SQLERRM='blocked',SQLSTATE||' '||SQLERRM);
  END;
END $$;
RESET ROLE;
-- A group member who is blocked in direct chat must still be able to see the group message.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
INSERT INTO phase0_contract SELECT 'blocked group member sees group message',count(*)=1,'visible rows='||count(*) FROM public.messages WHERE conversation_id='50000000-0000-4000-8000-000000000005' AND client_id='contract-group-001';
RESET ROLE;
-- Inserting a row with just the boolean true must suspend.
DELETE FROM public.account_status WHERE user_id='40000000-0000-4000-8000-000000000004';
INSERT INTO public.account_status(user_id,suspended) VALUES ('40000000-0000-4000-8000-000000000004',true);
INSERT INTO phase0_contract SELECT 'new row suspended=true is restrictive',suspended AND status='suspended' AND NOT public.is_account_active(user_id),format('flag=%s status=%s',suspended,status) FROM public.account_status WHERE user_id='40000000-0000-4000-8000-000000000004';
-- Timed suspension expires, active accounts with old end dates remain active.
UPDATE public.account_status SET status='suspended' WHERE user_id='40000000-0000-4000-8000-000000000004';
UPDATE public.account_status SET starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' WHERE user_id='40000000-0000-4000-8000-000000000004';
INSERT INTO phase0_contract SELECT 'timed suspension expires automatically',public.is_account_active(user_id),format('flag=%s status=%s',suspended,status) FROM public.account_status WHERE user_id='40000000-0000-4000-8000-000000000004';
UPDATE public.account_status SET starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' WHERE user_id='60000000-0000-4000-8000-000000000006';
INSERT INTO phase0_contract SELECT 'active account with elapsed end remains active',public.is_account_active(user_id),format('flag=%s status=%s',suspended,status) FROM public.account_status WHERE user_id='60000000-0000-4000-8000-000000000006';
SELECT * FROM phase0_contract ORDER BY name;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM phase0_contract WHERE NOT ok) THEN RAISE EXCEPTION 'contract failures: %', (SELECT count(*) FROM phase0_contract WHERE NOT ok); END IF; END $$;
ROLLBACK;
