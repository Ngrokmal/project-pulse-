-- RECONSTRUCTED tests, synthetic disposable data only.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('a1000000-0000-4000-8000-000000000001','admin27@example.invalid','{"display_name":"Alpha Admin"}'),
 ('a2000000-0000-4000-8000-000000000002','user27@example.invalid','{"display_name":"Beta User"}'),
 ('a3000000-0000-4000-8000-000000000003','admin-other27@example.invalid','{"display_name":"Other Admin"}'),
 ('a4000000-0000-4000-8000-000000000004','bad27@example.invalid','{"display_name":"Restricted"}');
insert into public.pulse_admin_accounts(user_id) values ('a1000000-0000-4000-8000-000000000001'),('a3000000-0000-4000-8000-000000000003');
insert into public.conversations(id,kind,created_by) values ('a5000000-0000-4000-8000-000000000005','direct','a1000000-0000-4000-8000-000000000001');
insert into public.conversation_members(conversation_id,user_id) values ('a5000000-0000-4000-8000-000000000005','a1000000-0000-4000-8000-000000000001'),('a5000000-0000-4000-8000-000000000005','a2000000-0000-4000-8000-000000000002');
insert into auth.sessions(id,user_id) values ('a6000000-0000-4000-8000-000000000006','a2000000-0000-4000-8000-000000000002');
set local role authenticated;
set local request.jwt.claims='{"sub":"a2000000-0000-4000-8000-000000000002","is_admin":true,"role":"authenticated"}';
do $$ begin
  begin perform * from public.pulse_admin_list_users('',25,0); raise exception 'non-admin list succeeded'; exception when insufficient_privilege then null; end;
  begin perform public.pulse_admin_set_suspension('a2000000-0000-4000-8000-000000000002',true,null,null); raise exception 'non-admin suspend succeeded'; exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$ begin
  if (select count(*) from public.pulse_admin_list_users('user27@example.invalid',25,0))<>1 then raise exception 'search failed'; end if;
  begin perform * from public.pulse_admin_list_users('',101,0); raise exception 'invalid search accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.pulse_admin_set_user_control('a3000000-0000-4000-8000-000000000003','start_calls',false); raise exception 'admin target control accepted'; exception when insufficient_privilege then null; end;
  begin perform public.pulse_admin_set_suspension('a3000000-0000-4000-8000-000000000003',true,null,null); raise exception 'admin target suspension accepted'; exception when insufficient_privilege then null; end;
  begin perform public.pulse_admin_set_suspension('a2000000-0000-4000-8000-000000000002',true,now()-interval '1 hour',null); raise exception 'expired suspension accepted'; exception when invalid_parameter_value then null; end;
end $$;
select public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','start_calls',false);
set local request.jwt.claims='{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated"}';
do $$ begin
  begin perform public.start_call('a5000000-0000-4000-8000-000000000005','audio'); raise exception 'disabled call accepted'; exception when sqlstate 'PCTRL' then if sqlerrm<>'call_start_disabled' then raise; end if; end;
end $$;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select public.pulse_admin_set_user_control('a2000000-0000-4000-8000-000000000002','start_calls',true);
set local request.jwt.claims='{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated"}';
select public.start_call('a5000000-0000-4000-8000-000000000005','audio');
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select public.pulse_admin_set_suspension('a2000000-0000-4000-8000-000000000002',true,now()+interval '1 hour','test');
reset role;
do $$ begin
  if exists(select 1 from auth.sessions where user_id='a2000000-0000-4000-8000-000000000002') then raise exception 'session not revoked'; end if;
  if (select status from public.account_status where user_id='a2000000-0000-4000-8000-000000000002')<>'suspended' then raise exception 'suspension failed'; end if;
  if (select count(*) from public.pulse_admin_audit where action='user_control')<>2 then raise exception 'control audit missing'; end if;
end $$;
set local role authenticated;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select public.pulse_admin_set_suspension('a2000000-0000-4000-8000-000000000002',false,null,null);
reset role;
update public.account_status set status='banned' where user_id='a4000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$ begin
  begin perform public.pulse_admin_set_suspension('a4000000-0000-4000-8000-000000000004',false,null,null); raise exception 'ban restored'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.account_status set status='under_review' where user_id='a4000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$ begin
  begin perform public.pulse_admin_set_suspension('a4000000-0000-4000-8000-000000000004',true,null,null); raise exception 'review overwritten'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'reconstructed 0019 admin tests passed' as result;
rollback;
