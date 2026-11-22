-- STAGING CANDIDATE ONLY. Requires message_change_journal.sql. Existing
-- timestamp-based clients are not automatically upgraded by this migration.
begin;
alter table public.conversation_members add column if not exists last_read_revision bigint not null default 0 check (last_read_revision >= 0);

create or replace function public.pulse_mark_read_revision(p_conversation uuid,p_revision bigint)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid(); head bigint; result bigint;
begin
  if me is null or not public.is_account_active(me) or not public.is_conversation_member(p_conversation) then
    raise exception 'not authorized' using errcode='42501';
  end if;
  if p_revision is null or p_revision < 0 then raise exception 'invalid revision' using errcode='22023'; end if;
  select coalesce((select revision from public.pulse_message_revision_heads where conversation_id=p_conversation),0) into head;
  if p_revision > head then raise exception 'revision beyond head' using errcode='22023'; end if;
  update public.conversation_members set last_read_revision=greatest(last_read_revision,p_revision)
    where conversation_id=p_conversation and user_id=me returning last_read_revision into result;
  if not found then raise exception 'not authorized' using errcode='42501'; end if;
  return result;
end $$;
revoke all on function public.pulse_mark_read_revision(uuid,bigint) from public,anon,authenticated;
grant execute on function public.pulse_mark_read_revision(uuid,bigint) to authenticated;
commit;
