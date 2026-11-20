-- =============================================================================
-- 0012_profile_card.sql
--
-- The card people actually read.
--
-- Until now a profile was a name, a handle and a bio. The redesigned Profile
-- screen (the "Right now" grid) also shows a status line, a place, the account's
-- own timezone, personal labels, and five privacy switches — and every one of
-- those values has to come from the database rather than from a fixture.
--
-- Two rules are baked into the schema:
--
--   • **where_text is typed by a person.** There is no latitude, no longitude,
--     no geocoded IP and no timezone-to-city guess anywhere in this table — the
--     only way a place appears is if its owner wrote it, and an empty string
--     means the row disappears from the card.
--   • **the timezone is a stored offset, not a lookup.** `utc_offset_minutes`
--     is captured from the owner's own device when they save their card, so
--     "6:11 PM · Dhaka" is arithmetic on a number they can see, not an
--     inference about where they are.
--
-- Forward-only and idempotent, like every migration in this folder.
-- =============================================================================

begin;

alter table public.profiles
  add column if not exists status_text        text,
  add column if not exists where_text         text,
  add column if not exists timezone           text,
  add column if not exists utc_offset_minutes integer,
  add column if not exists labels             text[] not null default '{}'::text[],
  add column if not exists last_seen_visible  boolean not null default true,
  add column if not exists read_receipts      boolean not null default false,
  add column if not exists photo_visible      boolean not null default true,
  add column if not exists push_notifications boolean not null default true,
  add column if not exists chat_lock          boolean not null default false;

-- Lengths only. A person may write anything short in their own status and
-- place; nothing here is ever derived.
alter table public.profiles
  drop constraint if exists profiles_status_len,
  drop constraint if exists profiles_where_len,
  drop constraint if exists profiles_timezone_len,
  drop constraint if exists profiles_labels_shape,
  drop constraint if exists profiles_offset_range;

alter table public.profiles
  add constraint profiles_status_len
    check (status_text is null or char_length(status_text) <= 80),
  add constraint profiles_where_len
    check (where_text is null or char_length(where_text) <= 40),
  add constraint profiles_timezone_len
    check (timezone is null or char_length(timezone) <= 40),
  -- At most six labels, each short: the card shows them as chips, not a list.
  -- (A CHECK may not contain a subquery, so the per-label budget is expressed
  -- as a total character budget instead: 6 × 20.)
  add constraint profiles_labels_shape
    check (
      cardinality(labels) <= 6
      and coalesce(array_position(labels, ''), 0) = 0
      and char_length(array_to_string(labels, '')) <= 120
    ),
  -- A real-world offset is never finer than 15 minutes, and never ± more than
  -- a day. Anything else is a bug in the client, not a timezone.
  add constraint profiles_offset_range
    check (
      utc_offset_minutes is null
      or (utc_offset_minutes between -840 and 840 and utc_offset_minutes % 15 = 0)
    );

create index if not exists profiles_labels_gin
  on public.profiles using gin (labels);

comment on column public.profiles.where_text is
  'Place the owner typed by hand. Never from GPS, IP or timezone.';
comment on column public.profiles.utc_offset_minutes is
  'Owner''s own device offset, captured when the card was saved.';
comment on column public.profiles.labels is
  'Personal labels ("Family", "Work") shown under Kept close.';

-- Column-level grants: 0001 granted only the original five columns, so a new
-- column is invisible to the client until it is named here.
grant update (
  status_text,
  where_text,
  timezone,
  utc_offset_minutes,
  labels,
  last_seen_visible,
  read_receipts,
  photo_visible,
  push_notifications,
  chat_lock
) on public.profiles to authenticated;

commit;
