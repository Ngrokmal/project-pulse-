-- EXPERIMENTAL STAGING CANDIDATE ONLY. Do not run on production.
-- Requires independent security review, lock/size assessment, retention policy,
-- rollback plan and missing migrations 0019/0020 restored. Backfill blocks
-- message writes for the duration of the transaction. Journal stores no body.
begin;
lock table public.messages in share row exclusive mode;

create table public.pulse_message_revision_heads (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  revision bigint not null check (revision >= 0)
);
create table public.pulse_message_changes (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  revision bigint not null check (revision > 0),
  message_id uuid not null,
  primary key (conversation_id, revision)
);
alter table public.pulse_message_revision_heads enable row level security;
alter table public.pulse_message_changes enable row level security;
revoke all on public.pulse_message_revision_heads, public.pulse_message_changes from public, anon, authenticated;

-- Backfill current rows under a write lock; each conversation has 1..N.
insert into public.pulse_message_changes(conversation_id, revision, message_id)
select conversation_id, row_number() over (partition by conversation_id order by created_at, id), id
from public.messages;
insert into public.pulse_message_revision_heads(conversation_id, revision)
select conversation_id, max(revision) from public.pulse_message_changes group by conversation_id;

-- Head updates serialize writers for a conversation. Unlike a PostgreSQL
-- sequence, this increment rolls back with its transaction and remains locked
-- until commit, so a later committed revision cannot overtake it.
create function public.pulse_append_message_change(p_conversation uuid, p_message uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare r bigint;
begin
  insert into public.pulse_message_revision_heads(conversation_id, revision)
  values (p_conversation, 1)
  on conflict (conversation_id) do update set revision = public.pulse_message_revision_heads.revision + 1
  returning revision into r;
  insert into public.pulse_message_changes(conversation_id, revision, message_id)
  values (p_conversation, r, p_message);
end $$;
revoke all on function public.pulse_append_message_change(uuid, uuid) from public, anon, authenticated;

create function public.pulse_journal_message_trigger()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    -- A conversation cascade removes its journal with the parent. Do not
    -- insert a child record while the parent itself is being deleted.
    if exists(select 1 from public.conversations where id = old.conversation_id) then
      perform public.pulse_append_message_change(old.conversation_id, old.id);
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and (old.conversation_id,old.id) is distinct from (new.conversation_id,new.id) then
    perform public.pulse_append_message_change(old.conversation_id, old.id);
  end if;
  perform public.pulse_append_message_change(new.conversation_id, new.id);
  return new;
end $$;
revoke all on function public.pulse_journal_message_trigger() from public, anon, authenticated;
create trigger pulse_message_journal after insert or update or delete on public.messages
for each row execute function public.pulse_journal_message_trigger();

-- Return current visible state for each changed ID, never historical content:
-- hard-deleted/moved rows become tombstones, so the journal cannot resurrect a
-- removed body. Both journal and row are read in the caller's statement snapshot.
create function public.pulse_message_changes_since(p_conversation uuid, p_after bigint, p_limit integer default 100)
returns table(revision bigint, message_id uuid, message jsonb)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare head bigint;
begin
  if auth.uid() is null or not public.is_account_active(auth.uid()) or not public.is_conversation_member(p_conversation) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if p_after is null or p_after < 0 or p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'invalid cursor or limit' using errcode = '22023';
  end if;
  select coalesce((select h.revision from public.pulse_message_revision_heads h where h.conversation_id = p_conversation),0) into head;
  if p_after > head then
    raise exception 'cursor beyond journal head' using errcode = '22023';
  end if;
  return query
    select j.revision, j.message_id, to_jsonb(m)
    from public.pulse_message_changes j
    left join public.messages m on m.id = j.message_id and m.conversation_id = j.conversation_id
    where j.conversation_id = p_conversation and j.revision > p_after
    order by j.revision limit p_limit;
end $$;
revoke all on function public.pulse_message_changes_since(uuid, bigint, integer) from public, anon;
grant execute on function public.pulse_message_changes_since(uuid, bigint, integer) to authenticated;
commit;
