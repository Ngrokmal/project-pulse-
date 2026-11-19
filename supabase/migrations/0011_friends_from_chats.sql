-- =============================================================================
-- 0011_friends_from_chats.sql
--
-- One circle, two doors.
--
-- Home lists the people you actually talk to. Explore lists the people in your
-- circle. Until now those were two different populations: a conversation did not
-- make a friendship, so someone you message every day could be a stranger in
-- Explore, and "Add" would send them a request you had both already answered by
-- talking.
--
-- This migration makes a **direct conversation a friendship**, in both
-- directions, and keeps it that way:
--
--   • backfill — every existing 1:1 chat becomes a symmetric `friendships` edge;
--   • trigger  — every new 1:1 chat does the same the moment its second member
--                joins, so the two screens can never disagree;
--   • settle   — an open request between two people who now chat is marked
--                accepted, so the Sent tab stops showing an ask that the
--                conversation has already answered.
--
-- Groups are deliberately untouched: a group is a room, not a relationship.
-- Leaving a chat does not unfriend anyone — friendships are only ended by the
-- person, never as a side effect of a delete.
--
-- Forward-only and idempotent, like every other migration here.
-- =============================================================================

begin;

-- ------------------------------------------------------------- the backfill
insert into public.friendships (user_id, friend_id)
select a.user_id, b.user_id
from public.conversations c
join public.conversation_members a on a.conversation_id = c.id
join public.conversation_members b
  on b.conversation_id = a.conversation_id
 and b.user_id <> a.user_id
where c.kind = 'direct'
on conflict do nothing;

-- Requests already answered by the existence of the chat.
update public.friend_requests r
set status = 'accepted',
    responded_at = coalesce(r.responded_at, now())
where r.status = 'pending'
  and exists (
    select 1
    from public.conversations c
    join public.conversation_members a on a.conversation_id = c.id
    join public.conversation_members b
      on b.conversation_id = a.conversation_id
     and b.user_id <> a.user_id
    where c.kind = 'direct'
      and a.user_id = r.requester_id
      and b.user_id = r.addressee_id
  );

-- --------------------------------------------------------------- the keeper
create or replace function public.sync_direct_chat_friendship()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  is_direct boolean;
begin
  select c.kind = 'direct'
    into is_direct
    from public.conversations c
   where c.id = new.conversation_id;

  if not coalesce(is_direct, false) then
    return new;
  end if;

  -- Both directions in one statement; `on conflict do nothing` makes the second
  -- member joining (and any later re-join) a no-op instead of a duplicate.
  insert into public.friendships (user_id, friend_id)
  select a.user_id, b.user_id
  from public.conversation_members a
  join public.conversation_members b
    on b.conversation_id = a.conversation_id
   and b.user_id <> a.user_id
  where a.conversation_id = new.conversation_id
  on conflict do nothing;

  update public.friend_requests r
  set status = 'accepted',
      responded_at = coalesce(r.responded_at, now())
  where r.status = 'pending'
    and exists (
      select 1
      from public.conversation_members a
      join public.conversation_members b
        on b.conversation_id = a.conversation_id
       and b.user_id <> a.user_id
      where a.conversation_id = new.conversation_id
        and a.user_id = r.requester_id
        and b.user_id = r.addressee_id
    );

  return new;
end;
$$;

revoke all on function public.sync_direct_chat_friendship() from public;

drop trigger if exists conversation_members_sync_friendship
  on public.conversation_members;

create trigger conversation_members_sync_friendship
after insert on public.conversation_members
for each row
execute function public.sync_direct_chat_friendship();

commit;
