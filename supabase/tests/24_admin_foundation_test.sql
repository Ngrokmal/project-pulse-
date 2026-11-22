-- Local synthetic admin authorization contract; always rolls back.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE admin_checks (label text, ok boolean) ON COMMIT DROP;
GRANT SELECT,INSERT ON admin_checks TO authenticated;
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('a1000000-0000-4000-8000-000000000001','test-admin@example.invalid','{"display_name":"Admin"}'),
 ('a2000000-0000-4000-8000-000000000002','test-user@example.invalid','{"display_name":"User"}');
INSERT INTO public.pulse_admin_accounts(user_id) VALUES ('a1000000-0000-4000-8000-000000000001');
INSERT INTO public.conversations(id,kind,created_by) VALUES ('a3000000-0000-4000-8000-000000000003','direct','a1000000-0000-4000-8000-000000000001');
INSERT INTO public.conversation_members(conversation_id,user_id) VALUES
 ('a3000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000001'),
 ('a3000000-0000-4000-8000-000000000003','a2000000-0000-4000-8000-000000000002');
INSERT INTO admin_checks VALUES ('ordinary role cannot read admin membership',not has_table_privilege('authenticated','public.pulse_admin_accounts','SELECT')),
 ('ordinary role cannot truncate admin membership',not has_table_privilege('authenticated','public.pulse_admin_accounts','TRUNCATE')),
 ('anonymous role cannot call admin setter',not has_function_privilege('anon','public.pulse_admin_set_user_control(uuid,text,boolean)','EXECUTE'));
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated","is_admin":true}';
INSERT INTO admin_checks VALUES ('forged claim is not admin',not public.pulse_is_admin());
DO $$ BEGIN
  BEGIN
    PERFORM public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','send_messages',false);
    INSERT INTO admin_checks VALUES ('non-admin cannot change control',false);
  EXCEPTION WHEN insufficient_privilege THEN INSERT INTO admin_checks VALUES ('non-admin cannot change control',SQLERRM='admin_required'); END;
  BEGIN
    PERFORM public.pulse_admin_set_error_message('message_send_disabled','forged');
    INSERT INTO admin_checks VALUES ('non-admin cannot change message',false);
  EXCEPTION WHEN insufficient_privilege THEN INSERT INTO admin_checks VALUES ('non-admin cannot change message',SQLERRM='admin_required'); END;
END $$;
SET LOCAL request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
INSERT INTO admin_checks VALUES ('assigned admin recognized',public.pulse_is_admin());
SELECT public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','send_messages',false);
SELECT public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','change_profile_photo',false);
SELECT public.pulse_admin_set_error_message('message_send_disabled','এই account থেকে message পাঠানো বন্ধ আছে।');
DO $$ BEGIN
  BEGIN
    PERFORM public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002',NULL,true);
    INSERT INTO admin_checks VALUES ('null control rejected',false);
  EXCEPTION WHEN invalid_parameter_value THEN INSERT INTO admin_checks VALUES ('null control rejected',true); END;
END $$;
SET LOCAL request.jwt.claims = '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated"}';
INSERT INTO admin_checks SELECT 'server error message readable',public.pulse_error_message('message_send_disabled')='এই account থেকে message পাঠানো বন্ধ আছে।';
DO $$ BEGIN
  BEGIN
    INSERT INTO public.messages(conversation_id,sender_id,body,client_id) VALUES ('a3000000-0000-4000-8000-000000000003','a2000000-0000-4000-8000-000000000002','test only','admin-test-0001');
    INSERT INTO admin_checks VALUES ('restricted message denied',false);
  EXCEPTION WHEN SQLSTATE 'PCTRL' THEN INSERT INTO admin_checks VALUES ('restricted message denied',SQLERRM='message_send_disabled'); END;
  BEGIN
    UPDATE public.profiles SET avatar_url='https://example.invalid/demo.png' WHERE id='a2000000-0000-4000-8000-000000000002';
    INSERT INTO admin_checks VALUES ('restricted photo update denied',false);
  EXCEPTION WHEN SQLSTATE 'PCTRL' THEN INSERT INTO admin_checks VALUES ('restricted photo update denied',SQLERRM='profile_photo_change_disabled'); END;
END $$;
SET LOCAL request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
SELECT public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','send_messages',true);
SELECT public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','change_profile_photo',true);
SET LOCAL request.jwt.claims = '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated"}';
INSERT INTO public.messages(conversation_id,sender_id,body,client_id) VALUES ('a3000000-0000-4000-8000-000000000003','a2000000-0000-4000-8000-000000000002','after enabling','admin-test-0002');
INSERT INTO admin_checks VALUES ('message allowed after enabling',true);
RESET ROLE;
INSERT INTO admin_checks SELECT 'four control changes audited',count(*)=4 FROM public.pulse_admin_audit WHERE action='user_control';
UPDATE public.pulse_admin_accounts SET enabled=false WHERE user_id='a1000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
INSERT INTO admin_checks VALUES ('disabled admin loses access',not public.pulse_is_admin());
DO $$ BEGIN
  BEGIN
    PERFORM public.pulse_admin_set_error_message('message_send_disabled','unauthorized');
    INSERT INTO admin_checks VALUES ('disabled admin cannot change message',false);
  EXCEPTION WHEN insufficient_privilege THEN INSERT INTO admin_checks VALUES ('disabled admin cannot change message',SQLERRM='admin_required'); END;
END $$;
RESET ROLE;
SELECT * FROM admin_checks ORDER BY label;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM admin_checks WHERE NOT ok) THEN RAISE EXCEPTION 'admin foundation test failed'; END IF; END $$;
ROLLBACK;
