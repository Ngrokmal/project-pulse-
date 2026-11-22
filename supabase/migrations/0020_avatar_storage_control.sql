-- RECONSTRUCTED STAGING CANDIDATE, not the lost original. Not yet verified
-- against the managed Storage API. Existing read and ownership policies remain.
begin;
do $$
declare probe text := 'pulse_preflight_' || substr(replace(gen_random_uuid()::text,'-',''),1,20);
begin
  if to_regclass('storage.objects') is null then raise exception 'storage.objects missing; cannot enforce avatar control'; end if;
  -- Supabase may allow policy DDL without owner-role membership. Test the
  -- capability itself, using a unique restrictive no-op policy inside this
  -- migration transaction; it is dropped before any real policy is changed.
  -- Failure rolls back the whole migration; never alter role ownership.
  begin
    execute format('create policy %I on storage.objects as restrictive for insert to authenticated with check (true)',probe);
    execute format('drop policy %I on storage.objects',probe);
    execute format('create policy %I on storage.objects as restrictive for update to authenticated using (true) with check (true)',probe);
    execute format('drop policy %I on storage.objects',probe);
    execute format('create policy %I on storage.objects as restrictive for delete to authenticated using (true)',probe);
    execute format('drop policy %I on storage.objects',probe);
  exception when insufficient_privilege then
    raise exception 'storage.objects policy management permission required' using errcode='42501';
  end;
end $$;

create or replace function public.pulse_own_photo_change_allowed()
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select auth.uid() is not null and public.is_account_active(auth.uid())
    and coalesce((select can_change_profile_photo from public.pulse_user_controls where user_id=auth.uid()),true);
$$;
revoke all on function public.pulse_own_photo_change_allowed() from public,anon,authenticated;
grant execute on function public.pulse_own_photo_change_allowed() to authenticated;

-- Restrictive policies AND with existing permissive ownership policies, so
-- other buckets and public reads are unchanged. Both USING and WITH CHECK are
-- necessary to prevent changing an object into or out of the avatar bucket.
drop policy if exists pulse_avatar_control_insert on storage.objects;
create policy pulse_avatar_control_insert on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'avatars' or public.pulse_own_photo_change_allowed());
drop policy if exists pulse_avatar_control_update on storage.objects;
create policy pulse_avatar_control_update on storage.objects as restrictive for update to authenticated
  using (bucket_id <> 'avatars' or public.pulse_own_photo_change_allowed())
  with check (bucket_id <> 'avatars' or public.pulse_own_photo_change_allowed());
drop policy if exists pulse_avatar_control_delete on storage.objects;
create policy pulse_avatar_control_delete on storage.objects as restrictive for delete to authenticated
  using (bucket_id <> 'avatars' or public.pulse_own_photo_change_allowed());
commit;
