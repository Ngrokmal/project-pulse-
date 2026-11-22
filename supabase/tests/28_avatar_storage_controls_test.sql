-- Synthetic Storage RLS only; not a managed Storage API test.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('b1000000-0000-4000-8000-000000000001','admin28@example.invalid','{}'),
 ('b2000000-0000-4000-8000-000000000002','user28@example.invalid','{}');
insert into public.pulse_admin_accounts(user_id) values ('b1000000-0000-4000-8000-000000000001');
insert into storage.objects(bucket_id,name) values ('avatars','b2000000-0000-4000-8000-000000000002/old.png');
create policy synthetic_other_bucket on storage.objects for all to authenticated using (bucket_id='other') with check (bucket_id='other');
set local role authenticated;
set local request.jwt.claims='{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select public.pulse_admin_set_user_control('b2000000-0000-4000-8000-000000000002','change_profile_photo',false);
set local request.jwt.claims='{"sub":"b2000000-0000-4000-8000-000000000002","role":"authenticated"}';
do $$ declare n int; begin
  if public.pulse_own_photo_change_allowed() then raise exception 'disabled toggle not visible'; end if;
  begin insert into storage.objects(bucket_id,name) values ('avatars','b2000000-0000-4000-8000-000000000002/new.png'); raise exception 'disabled insert accepted'; exception when insufficient_privilege then null; end;
  update storage.objects set name='b2000000-0000-4000-8000-000000000002/changed.png' where bucket_id='avatars'; get diagnostics n=row_count;
  if n<>0 then raise exception 'disabled update accepted'; end if;
  delete from storage.objects where bucket_id='avatars'; get diagnostics n=row_count;
  if n<>0 then raise exception 'disabled delete accepted'; end if;
  if (select count(*) from storage.objects where bucket_id='avatars')<>1 then raise exception 'public read changed'; end if;
end $$;
insert into storage.objects(bucket_id,name) values ('other','other-object');
do $$ begin
  begin
    update storage.objects set bucket_id='avatars', name='b2000000-0000-4000-8000-000000000002/moved.png' where bucket_id='other' and name='other-object';
    raise exception 'disabled cross-bucket move accepted';
  exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claims='{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select public.pulse_admin_set_user_control('b2000000-0000-4000-8000-000000000002','change_profile_photo',true);
set local request.jwt.claims='{"sub":"b2000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into storage.objects(bucket_id,name) values ('avatars','b2000000-0000-4000-8000-000000000002/new.png');
update storage.objects set name='b2000000-0000-4000-8000-000000000002/changed.png' where name='b2000000-0000-4000-8000-000000000002/old.png';
delete from storage.objects where name='b2000000-0000-4000-8000-000000000002/changed.png';
do $$ begin
  if not public.pulse_own_photo_change_allowed() then raise exception 'enabled toggle not visible'; end if;
  begin insert into storage.objects(bucket_id,name) values ('avatars','b1000000-0000-4000-8000-000000000001/not-mine.png'); raise exception 'other folder accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'reconstructed 0020 synthetic storage tests passed' as result;
rollback;
