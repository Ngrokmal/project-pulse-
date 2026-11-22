-- STAGING ONLY. Requires message_change_journal.sql and journal_read_receipt.sql.
-- For real rollout install atomically with the journal backfill; old journal
-- histories that reused a message ID cannot be reconstructed safely.
begin;
lock table public.messages in share row exclusive mode;
-- Existing message history cannot prove whether an ID was deleted/reinserted.
-- Fail closed; a production migration must backfill origins atomically with
-- initial journal construction, not execute this candidate on live history.
do $$ begin
  if exists(select 1 from public.messages) then
    raise exception 'requires empty test messages; production needs atomic journal/origins backfill';
  end if;
end $$;
alter table public.conversation_members alter column last_read_revision drop not null;
alter table public.conversation_members alter column last_read_revision drop default;
create table public.pulse_message_origins (
  message_id uuid primary key references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  creation_revision bigint not null check (creation_revision > 0)
);
alter table public.pulse_message_origins enable row level security;
revoke all on public.pulse_message_origins from public,anon,authenticated;
-- Only safe if the journal was just backfilled from existing messages and no
-- delete/reinsert with the same ID has happened since backfill. The rollout
-- migration must enforce that prerequisite; this file does not prove it.
insert into public.pulse_message_origins(message_id,conversation_id,creation_revision)
select m.id,m.conversation_id,min(j.revision) from public.messages m
join public.pulse_message_changes j on j.conversation_id=m.conversation_id and j.message_id=m.id
group by m.id,m.conversation_id;
create or replace function public.pulse_journal_message_trigger()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare r bigint;
begin
  if tg_op='DELETE' then
    if exists(select 1 from public.conversations where id=old.conversation_id) then
      perform public.pulse_append_message_change(old.conversation_id,old.id);
    end if;
    return old;
  end if;
  if tg_op='UPDATE' and (old.conversation_id,old.id) is distinct from (new.conversation_id,new.id) then
    perform public.pulse_append_message_change(old.conversation_id,old.id);
    delete from public.pulse_message_origins where message_id=old.id;
  end if;
  perform public.pulse_append_message_change(new.conversation_id,new.id);
  if tg_op='INSERT' or (old.conversation_id,old.id) is distinct from (new.conversation_id,new.id) then
    select revision into r from public.pulse_message_revision_heads where conversation_id=new.conversation_id;
    insert into public.pulse_message_origins(message_id,conversation_id,creation_revision) values(new.id,new.conversation_id,r);
  end if;
  return new;
end $$;
create or replace function public.pulse_message_changes_since(p_conversation uuid,p_after bigint,p_limit integer default 100)
returns table(revision bigint,message_id uuid,message jsonb)
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare head bigint;
begin
  if auth.uid() is null or not public.is_account_active(auth.uid()) or not public.is_conversation_member(p_conversation) then raise exception 'not authorized' using errcode='42501'; end if;
  if p_after is null or p_after<0 or p_limit is null or p_limit<1 or p_limit>500 then raise exception 'invalid cursor or limit' using errcode='22023'; end if;
  select coalesce((select h.revision from public.pulse_message_revision_heads h where h.conversation_id=p_conversation),0) into head;
  if p_after>head then raise exception 'cursor beyond journal head' using errcode='22023'; end if;
  return query select j.revision,j.message_id,
    case when m.id is null then null else to_jsonb(m)||jsonb_build_object('creation_revision',o.creation_revision) end
    from public.pulse_message_changes j
    left join public.messages m on m.id=j.message_id and m.conversation_id=j.conversation_id
    left join public.pulse_message_origins o on o.message_id=m.id and o.conversation_id=m.conversation_id
    where j.conversation_id=p_conversation and j.revision>p_after order by j.revision limit p_limit;
end $$;
commit;
