-- ============================================================================
--  SurfNStay — Plan A, part 1: schema, roles, constraints, RLS
--  Covers A1, A2, A3, A4, A6, A7, A10, A13.
--
--  DO NOT RUN THIS ON ITS OWN.
--  It enables Row Level Security and revokes the direct writes that the app
--  currently performs. The replacement database functions live in
--  sql/002_plan_a_functions.sql. Run 001 and 002 together, in that order,
--  inside a single SQL Editor session.
--
--  Before running: sql/000_introspect.sql section 6 must return zero rows,
--  otherwise the overlap constraint in step 4 cannot be created.
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Extensions
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists btree_gist;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Columns
-- ─────────────────────────────────────────────────────────────────────────────

-- A1: listings had no name. Every card in the app rendered the literal "Room".
alter table public.properties
  add column if not exists room_name text;

update public.properties
   set room_name = coalesce(nullif(trim(room_name), ''),
                            property_type || ' in ' || split_part(location, ',', 1))
 where room_name is null or trim(room_name) = '';

alter table public.properties
  alter column room_name set not null;

-- A7: a pending request holds the dates for one hour, then stops blocking.
alter table public.bookings
  add column if not exists hold_expires_at timestamptz;

update public.bookings
   set hold_expires_at = coalesce(created_at, now()) + interval '1 hour'
 where status = 'pending' and hold_expires_at is null;

-- A10: enforce the blocked flag in the database, not just at the login screen.
alter table public.travellers add column if not exists is_blocked boolean not null default false;
alter table public.hosts      add column if not exists is_blocked boolean not null default false;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Admin identity (A2)
--    Replaces the hardcoded admin@surfNstay.com / 303136 branch in the client.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.admins (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  created_at timestamptz not null default now()
);

-- SECURITY DEFINER so the function bypasses RLS on `admins`. Without this a
-- policy on `admins` that calls is_admin() would recurse infinitely.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where id = auth.uid());
$$;

create or replace function public.is_blocked()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_blocked from public.travellers where id = auth.uid()),
    (select is_blocked from public.hosts      where id = auth.uid()),
    false
  );
$$;

revoke all on function public.is_admin()   from public;
revoke all on function public.is_blocked() from public;
grant execute on function public.is_admin()   to authenticated;
grant execute on function public.is_blocked() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Booking integrity (A6)
--    Two travellers could confirm the same dates: availability was read once
--    when the page opened and never re-checked. This makes it impossible at
--    the only layer that can actually guarantee it.
--
--    Note: the one-hour pending hold is NOT expressed here. An EXCLUDE
--    constraint cannot reference now(), so pending overlap is enforced inside
--    create_booking() in part 2. This constraint is the hard backstop for
--    bookings that are actually live.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'bookings_no_overlap'
  ) then
    alter table public.bookings
      add constraint bookings_no_overlap
      exclude using gist (
        property_id with =,
        daterange(start_date, end_date, '[]') with &&
      ) where (status in ('confirmed', 'completed'));
  end if;
end $$;

create index if not exists bookings_traveller_start_idx
  on public.bookings (traveller_id, start_date desc);

create index if not exists bookings_property_status_idx
  on public.bookings (property_id, status);


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Profile creation on signup (A13)
--    The client used to insert into travellers/hosts straight after signUp.
--    That needs an unauthenticated write (impossible once RLS is on) and was
--    skipped entirely when email confirmation was enabled, leaving an auth
--    user with no profile row.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data ->> 'role', 'traveller');
begin
  if v_role = 'host' then
    insert into public.hosts (id, "fullName", email, phone, address)
    values (
      new.id,
      new.raw_user_meta_data ->> 'fullName',
      new.email,
      new.raw_user_meta_data ->> 'phone',
      new.raw_user_meta_data ->> 'address'
    )
    on conflict (id) do nothing;
  else
    insert into public.travellers (id, name, email, phone, address)
    values (
      new.id,
      new.raw_user_meta_data ->> 'name',
      new.email,
      new.raw_user_meta_data ->> 'phone',
      new.raw_user_meta_data ->> 'address'
    )
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Row Level Security (A3, A4, A10)
--
--    Until now the anon key shipped in main.dart could read and write every
--    table. Each policy below is deliberately narrow; read the comment above
--    each one before changing it.
--
--    Design note: `properties` is readable by any signed-in user, which lets
--    the booking policies use a plain subquery against it without recursion
--    or a SECURITY DEFINER helper.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.travellers    enable row level security;
alter table public.hosts         enable row level security;
alter table public.admins        enable row level security;
alter table public.properties    enable row level security;
alter table public.bookings      enable row level security;
alter table public.notifications enable row level security;
alter table public.messages      enable row level security;
alter table public.chats         enable row level security;
alter table public.ratings       enable row level security;
alter table public.reports       enable row level security;

-- ── admins ──────────────────────────────────────────────────────────────────
-- A user may confirm their own admin status; nobody may grant it from the app.
-- Add rows here manually from the Supabase dashboard.
drop policy if exists admins_select_self on public.admins;
create policy admins_select_self on public.admins
  for select to authenticated
  using (id = auth.uid());

-- ── travellers ──────────────────────────────────────────────────────────────
-- Visible to: yourself, admins, a host you have booked with, and anyone you
-- share a chat with. Not the whole world, which is what "RLS off" meant.
drop policy if exists travellers_select on public.travellers;
create policy travellers_select on public.travellers
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.bookings b
      join public.properties p on p.id = b.property_id
      where b.traveller_id = travellers.id and p.host_id = auth.uid()
    )
    or exists (
      select 1 from public.chats c
      where (c.user1_id = travellers.id and c.user2_id = auth.uid())
         or (c.user2_id = travellers.id and c.user1_id = auth.uid())
    )
  );

drop policy if exists travellers_update_self on public.travellers;
create policy travellers_update_self on public.travellers
  for update to authenticated
  using (id = auth.uid() and not public.is_blocked())
  with check (id = auth.uid());

-- Only admins may change the blocked flag; guarded by the admin-wide policy
-- below rather than by a column privilege, since RLS is row-level only.
drop policy if exists travellers_admin_all on public.travellers;
create policy travellers_admin_all on public.travellers
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── hosts ───────────────────────────────────────────────────────────────────
-- A host's name and phone are shown to guests on the property page, so any
-- signed-in user may read host rows.
drop policy if exists hosts_select on public.hosts;
create policy hosts_select on public.hosts
  for select to authenticated
  using (true);

drop policy if exists hosts_update_self on public.hosts;
create policy hosts_update_self on public.hosts
  for update to authenticated
  using (id = auth.uid() and not public.is_blocked())
  with check (id = auth.uid());

drop policy if exists hosts_admin_all on public.hosts;
create policy hosts_admin_all on public.hosts
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── properties ──────────────────────────────────────────────────────────────
drop policy if exists properties_select on public.properties;
create policy properties_select on public.properties
  for select to authenticated
  using (true);

drop policy if exists properties_write_own on public.properties;
create policy properties_write_own on public.properties
  for all to authenticated
  using (host_id = auth.uid() and not public.is_blocked())
  with check (host_id = auth.uid() and not public.is_blocked());

drop policy if exists properties_admin_all on public.properties;
create policy properties_admin_all on public.properties
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── bookings ────────────────────────────────────────────────────────────────
-- Readable by the traveller who made it and the host who owns the property.
-- Writes go through the functions in part 2 — there is deliberately no
-- INSERT or UPDATE policy for clients here.
drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings
  for select to authenticated
  using (
    traveller_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.properties p
      where p.id = bookings.property_id and p.host_id = auth.uid()
    )
  );

drop policy if exists bookings_admin_all on public.bookings;
create policy bookings_admin_all on public.bookings
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── notifications ───────────────────────────────────────────────────────────
-- You see only your own. Inserts are performed by SECURITY DEFINER functions
-- in part 2, so that one user cannot fabricate notifications for another.
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── chats (A4) ──────────────────────────────────────────────────────────────
-- The chat list previously streamed the entire table to every device. This is
-- the boundary that makes that impossible, including over Realtime.
drop policy if exists chats_select_participant on public.chats;
create policy chats_select_participant on public.chats
  for select to authenticated
  using (user1_id = auth.uid() or user2_id = auth.uid() or public.is_admin());

drop policy if exists chats_insert_participant on public.chats;
create policy chats_insert_participant on public.chats
  for insert to authenticated
  with check (
    (user1_id = auth.uid() or user2_id = auth.uid())
    and not public.is_blocked()
  );

drop policy if exists chats_update_participant on public.chats;
create policy chats_update_participant on public.chats
  for update to authenticated
  using (user1_id = auth.uid() or user2_id = auth.uid())
  with check (user1_id = auth.uid() or user2_id = auth.uid());

-- ── messages ────────────────────────────────────────────────────────────────
drop policy if exists messages_select_participant on public.messages;
create policy messages_select_participant on public.messages
  for select to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid() or public.is_admin());

drop policy if exists messages_insert_sender on public.messages;
create policy messages_insert_sender on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and not public.is_blocked());

-- Only the recipient may flip is_read.
drop policy if exists messages_update_receiver on public.messages;
create policy messages_update_receiver on public.messages
  for update to authenticated
  using (receiver_id = auth.uid())
  with check (receiver_id = auth.uid());

-- ── ratings ─────────────────────────────────────────────────────────────────
-- Ratings are public (they drive the average on every card), but you may only
-- write one against your own booking, and only once the stay has begun (A8).
drop policy if exists ratings_select_all on public.ratings;
create policy ratings_select_all on public.ratings
  for select to authenticated
  using (true);

drop policy if exists ratings_write_own on public.ratings;
create policy ratings_write_own on public.ratings
  for all to authenticated
  using (traveller_id = auth.uid())
  with check (
    traveller_id = auth.uid()
    and not public.is_blocked()
    and exists (
      select 1 from public.bookings b
      where b.id = ratings.booking_id
        and b.traveller_id = auth.uid()
        and b.property_id  = ratings.property_id
        and b.start_date  <= current_date
        and b.status in ('confirmed', 'completed')
    )
  );

-- ── reports ─────────────────────────────────────────────────────────────────
drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports
  for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());

drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert to authenticated
  with check (reporter_id = auth.uid() and not public.is_blocked());

drop policy if exists reports_admin_all on public.reports;
create policy reports_admin_all on public.reports
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ─────────────────────────────────────────────────────────────────────────────
-- 6b. Views do not have policies of their own, and by default a view executes
--     with its owner's rights — which would let any signed-in user read
--     admin_report_view straight past every policy above. security_invoker
--     makes the caller's RLS apply, so only admins see the full report list.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_views
              where schemaname = 'public' and viewname = 'admin_report_view') then
    execute 'alter view public.admin_report_view set (security_invoker = on)';
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Revoke anon access outright.
--    Nothing in the app is usable while signed out, so the anon role has no
--    reason to reach any table.
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

commit;
