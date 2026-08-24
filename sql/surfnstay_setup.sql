-- ============================================================================
--  SurfNStay — complete database setup
--
--  ONE FILE. Supabase Dashboard -> SQL Editor -> New query -> paste -> Run.
--
--  Covers everything: Plan A (security and correctness fixes) and Plan B
--  (search, maps, reviews, availability, verification, admin console).
--  Payments are deliberately not included.
--
--  ── PROPERTIES OF THIS FILE ────────────────────────────────────────────────
--  * One transaction. If anything fails, NOTHING is applied — fix the cause
--    and run it again.
--  * Re-runnable. Running it twice is harmless.
--  * It UPGRADES an existing SurfNStay database. It does not create the base
--    tables (properties, bookings, travellers, hosts, chats, messages,
--    notifications, ratings, reports) — those must already exist.
--
--  ── ONE DESTRUCTIVE STEP, IN SECTION 5 ─────────────────────────────────────
--  Two confirmed bookings on the same property with overlapping dates is the
--  exact bug this file prevents, and the constraint cannot be created while
--  such rows exist. Section 5 therefore CANCELS the losing bookings: per
--  property it keeps the earliest check-in and cancels anything overlapping
--  it. Nothing is deleted — status becomes 'cancelled' and the rows still
--  appear under Cancelled in the app. It prints what it changed.
--
--  ── AFTER RUNNING ──────────────────────────────────────────────────────────
--  1. Authentication -> Users -> Add user (this is your admin login), then:
--       insert into public.admins (id, email)
--       values ('<that-users-uuid>', 'admin@surfnstay.com');
--     Until this row exists nobody can open the admin console.
--  2. Storage -> New bucket -> name `host_cnic`, Public OFF.
--     CNIC verification uploads fail without it, and it must stay private.
--  3. Database -> Replication: confirm chats, messages and notifications are
--     in the supabase_realtime publication.
--  4. Test one traveller signup and one host signup immediately — see the
--     note above section 8.
-- ============================================================================

begin;


-- ═════════════════════════════════════════════════════════════════════════════
-- 1. EXTENSIONS
-- ═════════════════════════════════════════════════════════════════════════════
create extension if not exists btree_gist;
create extension if not exists pgcrypto;   -- gen_random_uuid()


-- ═════════════════════════════════════════════════════════════════════════════
-- 2. COLUMNS
-- ═════════════════════════════════════════════════════════════════════════════

-- ── properties: listing basics ───────────────────────────────────────────────
-- These five came from the older property_fields_update.sql; repeated here so
-- this file is the single source of truth.
alter table public.properties add column if not exists property_type    text    not null default 'Room';
alter table public.properties add column if not exists guest_preference text    not null default 'Any';
alter table public.properties add column if not exists bedrooms         integer not null default 1;
alter table public.properties add column if not exists bathrooms        integer not null default 1;
alter table public.properties add column if not exists max_guests       integer not null default 1;
alter table public.properties add column if not exists discount         numeric          default 0;

-- Listings had no name at all, so every card in the app rendered "Room".
alter table public.properties add column if not exists room_name text;

-- Coordinates and a real city column. `location` is one free-text field, which
-- is why the dashboard had five hardcoded cities and an "Other Cities" bucket.
alter table public.properties add column if not exists latitude  double precision;
alter table public.properties add column if not exists longitude double precision;
alter table public.properties add column if not exists city      text;

-- Visibility, stay length and cancellation terms.
alter table public.properties add column if not exists is_active   boolean not null default true;
alter table public.properties add column if not exists min_nights  integer not null default 1;
alter table public.properties add column if not exists max_nights  integer;
alter table public.properties
  add column if not exists cancellation_policy text not null default 'moderate';

-- Backfill room_name. Every branch is null-safe, so this cannot leave a NULL
-- behind and break the NOT NULL that follows.
update public.properties
   set room_name = coalesce(
         nullif(btrim(room_name), ''),
         nullif(btrim(coalesce(property_type, 'Stay') || ' in ' ||
                      split_part(coalesce(location, ''), ',', 1)), ''),
         'Untitled listing'
       )
 where room_name is null or btrim(room_name) = '';

alter table public.properties alter column room_name set not null;

update public.properties
   set city = initcap(btrim(split_part(coalesce(location, ''), ',', 1)))
 where city is null or btrim(city) = '';

-- ── bookings ─────────────────────────────────────────────────────────────────
-- A pending request holds its dates for one hour. Existing pending rows are
-- intentionally left NULL, which the app and the functions below both treat
-- as "hold already lapsed".
alter table public.bookings add column if not exists hold_expires_at timestamptz;
alter table public.bookings add column if not exists guests integer not null default 1;

-- ── travellers / hosts ───────────────────────────────────────────────────────
-- The blocked flag has to mean something at the database level, not just at
-- the login screen.
alter table public.travellers add column if not exists is_blocked boolean not null default false;
alter table public.hosts      add column if not exists is_blocked boolean not null default false;

-- Host identity verification (CNIC upload reviewed by an admin).
alter table public.hosts add column if not exists cnic_url            text;
alter table public.hosts add column if not exists cnic_number         text;
alter table public.hosts add column if not exists verification_status text not null default 'unverified';
alter table public.hosts add column if not exists verified_at         timestamptz;
alter table public.hosts add column if not exists verification_note   text;

-- ── ratings: written reviews ─────────────────────────────────────────────────
-- `ratings` was a bare number with no words and no right of reply.
alter table public.ratings add column if not exists review_text     text;
alter table public.ratings add column if not exists host_reply      text;
alter table public.ratings add column if not exists host_replied_at timestamptz;
alter table public.ratings add column if not exists created_at      timestamptz not null default now();

-- ── reports: resolution tracking ─────────────────────────────────────────────
alter table public.reports add column if not exists status          text not null default 'open';
alter table public.reports add column if not exists resolved_by     uuid references auth.users(id);
alter table public.reports add column if not exists resolved_at     timestamptz;
alter table public.reports add column if not exists resolution_note text;


-- ═════════════════════════════════════════════════════════════════════════════
-- 3. CHECK CONSTRAINTS
--    All NOT VALID: existing rows are not re-checked, so none of these can
--    fail on legacy data. Only new writes are constrained.
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare c record;
begin
  -- Drop any pre-existing status check so 'expired' and 'checked_in' can be
  -- added to the vocabulary.
  for c in
    select conname from pg_constraint
     where conrelid = 'public.bookings'::regclass and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.bookings drop constraint %I', c.conname);
  end loop;

  if not exists (select 1 from pg_constraint where conname = 'bookings_status_check') then
    alter table public.bookings add constraint bookings_status_check
      check (status in ('pending','confirmed','checked_in','cancelled','completed','expired'))
      not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'properties_lat_range') then
    alter table public.properties add constraint properties_lat_range
      check (latitude is null or latitude between -90 and 90) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'properties_lng_range') then
    alter table public.properties add constraint properties_lng_range
      check (longitude is null or longitude between -180 and 180) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'properties_nights_check') then
    alter table public.properties add constraint properties_nights_check
      check (min_nights >= 1 and (max_nights is null or max_nights >= min_nights)) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'properties_cancellation_policy_check') then
    alter table public.properties add constraint properties_cancellation_policy_check
      check (cancellation_policy in ('flexible','moderate','strict')) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'hosts_verification_status_check') then
    alter table public.hosts add constraint hosts_verification_status_check
      check (verification_status in ('unverified','pending','verified','rejected')) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'reports_status_check') then
    alter table public.reports add constraint reports_status_check
      check (status in ('open','resolved','dismissed')) not valid;
  end if;
end $$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 4. DATE COLUMN SANITY CHECK
--    An EXCLUDE constraint needs real `date` columns: casting text to date is
--    not immutable and cannot be indexed.
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_start text;
  v_end   text;
begin
  select format_type(atttypid, atttypmod) into v_start
    from pg_attribute
   where attrelid = 'public.bookings'::regclass and attname = 'start_date';

  select format_type(atttypid, atttypmod) into v_end
    from pg_attribute
   where attrelid = 'public.bookings'::regclass and attname = 'end_date';

  if v_start <> 'date' or v_end <> 'date' then
    raise exception
      'bookings.start_date/end_date are %/% but must be date. Convert first: '
      'alter table public.bookings alter column start_date type date using start_date::date; '
      'alter table public.bookings alter column end_date type date using end_date::date;',
      v_start, v_end;
  end if;
end $$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 5. RESOLVE PRE-EXISTING OVERLAPPING BOOKINGS   ← the destructive step
--
--    Per property, walks confirmed/completed bookings in check-in order and
--    keeps each one that does not overlap something already kept. Anything
--    that collides is set to 'cancelled'. Nothing is deleted.
--
--    Ordered by (start_date, id) rather than created_at, because created_at
--    may not exist on this table or may be stored as text.
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare
  r          record;
  v_prop     text := null;
  v_kept     daterange[];
  v_range    daterange;
  v_collides boolean;
  v_count    integer := 0;
begin
  for r in
    select b.id, b.property_id, b.start_date, b.end_date, b.traveller_id
      from public.bookings b
     where b.status in ('confirmed', 'completed')
     order by b.property_id::text, b.start_date, b.id::text
  loop
    if v_prop is distinct from r.property_id::text then
      v_prop := r.property_id::text;
      v_kept := '{}';
    end if;

    v_range := daterange(r.start_date, r.end_date, '[]');
    v_collides := false;

    for i in 1 .. coalesce(array_length(v_kept, 1), 0) loop
      if v_kept[i] && v_range then
        v_collides := true;
        exit;
      end if;
    end loop;

    if v_collides then
      update public.bookings set status = 'cancelled' where id = r.id;
      v_count := v_count + 1;
      raise notice
        'CANCELLED overlapping booking % (property %, % to %, traveller %)',
        r.id, r.property_id, r.start_date, r.end_date, r.traveller_id;
    else
      v_kept := v_kept || v_range;
    end if;
  end loop;

  if v_count = 0 then
    raise notice 'No overlapping bookings needed cancelling.';
  else
    raise notice '=== Cancelled % overlapping booking(s). ===', v_count;
  end if;
end $$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 6. BOOKING INTEGRITY
--    Two travellers could confirm the same dates, because availability was
--    read once when the page opened and never re-checked before the insert.
--
--    The one-hour pending hold is NOT expressed here — an EXCLUDE constraint
--    cannot call now(). Pending overlap is enforced inside create_booking().
--    This is the hard backstop for live bookings, and the only layer that can
--    actually guarantee it.
-- ═════════════════════════════════════════════════════════════════════════════
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bookings_no_overlap') then
    alter table public.bookings
      add constraint bookings_no_overlap
      exclude using gist (
        property_id with =,
        daterange(start_date, end_date, '[]') with &&
      ) where (status in ('confirmed', 'completed'));
  end if;
end $$;

create index if not exists bookings_traveller_start_idx on public.bookings (traveller_id, start_date desc);
create index if not exists bookings_property_status_idx on public.bookings (property_id, status);
create index if not exists properties_latlng_idx        on public.properties (latitude, longitude);
create index if not exists properties_city_idx          on public.properties (lower(city));
create index if not exists hosts_verification_idx       on public.hosts (verification_status)
  where verification_status = 'pending';


-- ═════════════════════════════════════════════════════════════════════════════
-- 7. ADMIN IDENTITY AND ROLE HELPERS
--    Replaces the hardcoded admin@surfNstay.com / 303136 branch that used to
--    live in login_screen.dart and ran with no session at all.
-- ═════════════════════════════════════════════════════════════════════════════
create table if not exists public.admins (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  created_at timestamptz not null default now()
);

-- SECURITY DEFINER so these bypass RLS. Without it a policy on `admins` that
-- calls is_admin() would recurse into itself forever.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where id = auth.uid());
$$;

create or replace function public.is_blocked()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select is_blocked from public.travellers where id = auth.uid()),
    (select is_blocked from public.hosts      where id = auth.uid()),
    false
  );
$$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 8. PROFILE CREATION ON SIGNUP
--    The client used to insert into travellers/hosts right after signUp. That
--    needs an unauthenticated write (impossible once RLS is on) and was
--    skipped silently when email confirmation was enabled, leaving an auth
--    user with no profile row and no way into the app.
--
--    IF SIGNUP FAILS AFTER RUNNING THIS FILE: this trigger inserts only
--    (id, name|fullName, email, phone, address). A NOT NULL column outside
--    that list on travellers/hosts will reject the insert. Add it to the
--    relevant branch below, or give it a default.
-- ═════════════════════════════════════════════════════════════════════════════
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role text := coalesce(new.raw_user_meta_data ->> 'role', 'traveller');
begin
  if v_role = 'host' then
    insert into public.hosts (id, "fullName", email, phone, address)
    values (new.id,
            new.raw_user_meta_data ->> 'fullName',
            new.email,
            new.raw_user_meta_data ->> 'phone',
            new.raw_user_meta_data ->> 'address')
    on conflict (id) do nothing;
  else
    insert into public.travellers (id, name, email, phone, address)
    values (new.id,
            new.raw_user_meta_data ->> 'name',
            new.email,
            new.raw_user_meta_data ->> 'phone',
            new.raw_user_meta_data ->> 'address')
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ═════════════════════════════════════════════════════════════════════════════
-- 9. NEW TABLES
--    Amenities as data so they can be filtered on; host-blocked dates;
--    host-to-guest reviews; an admin audit trail.
-- ═════════════════════════════════════════════════════════════════════════════
create table if not exists public.amenities (
  key        text primary key,
  label      text not null,
  icon       text,             -- Material icon name, resolved in Dart
  sort_order integer not null default 0
);

insert into public.amenities (key, label, icon, sort_order) values
  ('wifi',         'WiFi',               'wifi',                  10),
  ('ac',           'Air Conditioning',   'ac_unit',               20),
  ('heating',      'Heating',            'local_fire_department',  30),
  ('hot_water',    'Hot Water',          'shower',                40),
  ('backup_power', 'Generator / UPS',    'bolt',                  50),
  ('kitchen',      'Kitchen',            'kitchen',               60),
  ('washing',      'Washing Machine',    'local_laundry_service', 70),
  ('tv',           'TV',                 'tv',                    80),
  ('workspace',    'Workspace',          'desk',                  90),
  ('parking',      'Free Parking',       'local_parking',        100),
  ('elevator',     'Elevator',           'elevator',             110),
  ('security',     'Security Guard',     'shield',               120),
  ('cctv',         'CCTV',               'videocam',             130),
  ('balcony',      'Balcony',            'balcony',              140),
  ('garden',       'Garden',             'yard',                 150),
  ('pool',         'Swimming Pool',      'pool',                 160),
  ('gym',          'Gym',                'fitness_center',       170),
  ('breakfast',    'Breakfast Included', 'free_breakfast',       180),
  ('pet_friendly', 'Pet Friendly',       'pets',                 190),
  ('accessible',   'Wheelchair Access',  'accessible',           200)
on conflict (key) do update
  set label = excluded.label, icon = excluded.icon, sort_order = excluded.sort_order;

-- These tables derive their foreign key column type from the parent, so this
-- file works whether your ids are bigint, uuid or text.
do $$
declare
  v_prop_type text := (select format_type(atttypid, atttypmod) from pg_attribute
                        where attrelid = 'public.properties'::regclass and attname = 'id');
  v_book_type text := (select format_type(atttypid, atttypmod) from pg_attribute
                        where attrelid = 'public.bookings'::regclass and attname = 'id');
begin
  execute format($f$
    create table if not exists public.property_amenities (
      property_id %s   not null references public.properties(id) on delete cascade,
      amenity_key text not null references public.amenities(key) on delete cascade,
      primary key (property_id, amenity_key)
    )$f$, v_prop_type);

  execute format($f$
    create table if not exists public.property_blocked_dates (
      property_id  %s   not null references public.properties(id) on delete cascade,
      blocked_date date not null,
      reason       text,
      created_at   timestamptz not null default now(),
      primary key (property_id, blocked_date)
    )$f$, v_prop_type);

  execute format($f$
    create table if not exists public.traveller_reviews (
      id           uuid primary key default gen_random_uuid(),
      booking_id   %s   not null references public.bookings(id) on delete cascade,
      traveller_id uuid not null references auth.users(id) on delete cascade,
      host_id      uuid not null references auth.users(id) on delete cascade,
      rating       numeric not null check (rating >= 1 and rating <= 5),
      review_text  text,
      created_at   timestamptz not null default now(),
      unique (booking_id)
    )$f$, v_book_type);
end $$;

create table if not exists public.admin_actions (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid not null references auth.users(id),
  action      text not null,
  target_type text not null,
  target_id   text,
  detail      text,
  created_at  timestamptz not null default now()
);

create index if not exists property_amenities_key_idx      on public.property_amenities (amenity_key);
create index if not exists property_blocked_dates_idx      on public.property_blocked_dates (property_id, blocked_date);
create index if not exists traveller_reviews_traveller_idx on public.traveller_reviews (traveller_id);
create index if not exists admin_actions_created_idx       on public.admin_actions (created_at desc);


-- ═════════════════════════════════════════════════════════════════════════════
-- 10. ROW LEVEL SECURITY
--
--     Until now the anon key shipped in main.dart could read and write every
--     table in this database. Read the comment above each policy before
--     changing it.
--
--     Design note: `properties` is readable by any signed-in user. That is
--     deliberate — it lets the booking policies use a plain subquery against
--     it with no recursion and no SECURITY DEFINER helper.
-- ═════════════════════════════════════════════════════════════════════════════
alter table public.travellers             enable row level security;
alter table public.hosts                  enable row level security;
alter table public.admins                 enable row level security;
alter table public.properties             enable row level security;
alter table public.bookings               enable row level security;
alter table public.notifications          enable row level security;
alter table public.messages               enable row level security;
alter table public.chats                  enable row level security;
alter table public.ratings                enable row level security;
alter table public.reports                enable row level security;
alter table public.amenities              enable row level security;
alter table public.property_amenities     enable row level security;
alter table public.property_blocked_dates enable row level security;
alter table public.traveller_reviews      enable row level security;
alter table public.admin_actions          enable row level security;

-- ── admins ───────────────────────────────────────────────────────────────────
-- You may confirm your own admin status. Nobody can grant it from the app;
-- rows are added by hand from the dashboard.
drop policy if exists admins_select_self on public.admins;
create policy admins_select_self on public.admins
  for select to authenticated using (id = auth.uid());

-- ── travellers ───────────────────────────────────────────────────────────────
-- Visible to yourself, admins, a host you have booked with, and anyone you
-- share a chat with. Previously: the entire internet.
drop policy if exists travellers_select on public.travellers;
create policy travellers_select on public.travellers
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.bookings b
                 join public.properties p on p.id = b.property_id
                where b.traveller_id = travellers.id and p.host_id = auth.uid())
    or exists (select 1 from public.chats c
                where (c.user1_id = travellers.id and c.user2_id = auth.uid())
                   or (c.user2_id = travellers.id and c.user1_id = auth.uid()))
  );

drop policy if exists travellers_update_self on public.travellers;
create policy travellers_update_self on public.travellers
  for update to authenticated
  using (id = auth.uid() and not public.is_blocked())
  with check (id = auth.uid());

drop policy if exists travellers_admin_all on public.travellers;
create policy travellers_admin_all on public.travellers
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── hosts ────────────────────────────────────────────────────────────────────
-- A host's name and phone are shown to guests on the property page, so any
-- signed-in user can read host rows.
drop policy if exists hosts_select on public.hosts;
create policy hosts_select on public.hosts
  for select to authenticated using (true);

drop policy if exists hosts_update_self on public.hosts;
create policy hosts_update_self on public.hosts
  for update to authenticated
  using (id = auth.uid() and not public.is_blocked())
  with check (id = auth.uid());

drop policy if exists hosts_admin_all on public.hosts;
create policy hosts_admin_all on public.hosts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── properties ───────────────────────────────────────────────────────────────
drop policy if exists properties_select on public.properties;
create policy properties_select on public.properties
  for select to authenticated using (true);

drop policy if exists properties_write_own on public.properties;
create policy properties_write_own on public.properties
  for all to authenticated
  using (host_id = auth.uid() and not public.is_blocked())
  with check (host_id = auth.uid() and not public.is_blocked());

drop policy if exists properties_admin_all on public.properties;
create policy properties_admin_all on public.properties
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── bookings ─────────────────────────────────────────────────────────────────
-- Readable by the traveller who made it and the host who owns the property.
-- There is deliberately no INSERT or UPDATE policy: all writes go through the
-- functions in section 12, which check availability under a lock.
drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings
  for select to authenticated
  using (
    traveller_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.properties p
                where p.id = bookings.property_id and p.host_id = auth.uid())
  );

drop policy if exists bookings_admin_all on public.bookings;
create policy bookings_admin_all on public.bookings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── notifications ────────────────────────────────────────────────────────────
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- You may notify yourself, or the counterparty of a booking you are part of.
-- This is what keeps ReportRoomScreen / ReportUserScreen working without
-- letting any user push arbitrary notifications at any other user.
drop policy if exists notifications_insert_counterparty on public.notifications;
create policy notifications_insert_counterparty on public.notifications
  for insert to authenticated
  with check (
    not public.is_blocked()
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.bookings b
          join public.properties p on p.id = b.property_id
         where b.id = notifications.booking_id
           and (b.traveller_id = auth.uid() or p.host_id = auth.uid())
           and (b.traveller_id = notifications.user_id or p.host_id = notifications.user_id)
      )
    )
  );

-- ── chats ────────────────────────────────────────────────────────────────────
-- The chat list used to stream the entire table to every device. This is the
-- boundary that makes that impossible, over Realtime as well as REST.
drop policy if exists chats_select_participant on public.chats;
create policy chats_select_participant on public.chats
  for select to authenticated
  using (user1_id = auth.uid() or user2_id = auth.uid() or public.is_admin());

drop policy if exists chats_insert_participant on public.chats;
create policy chats_insert_participant on public.chats
  for insert to authenticated
  with check ((user1_id = auth.uid() or user2_id = auth.uid()) and not public.is_blocked());

drop policy if exists chats_update_participant on public.chats;
create policy chats_update_participant on public.chats
  for update to authenticated
  using (user1_id = auth.uid() or user2_id = auth.uid())
  with check (user1_id = auth.uid() or user2_id = auth.uid());

-- ── messages ─────────────────────────────────────────────────────────────────
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
  using (receiver_id = auth.uid()) with check (receiver_id = auth.uid());

-- ── ratings ──────────────────────────────────────────────────────────────────
-- Ratings are public: they drive the average shown on every card. But you may
-- only write one against your own booking, and only once the stay has begun.
drop policy if exists ratings_select_all on public.ratings;
create policy ratings_select_all on public.ratings
  for select to authenticated using (true);

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
         and b.status in ('confirmed','checked_in','completed')
    )
  );

-- A host may reply to a review on their own property.
drop policy if exists ratings_host_reply on public.ratings;
create policy ratings_host_reply on public.ratings
  for update to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = ratings.property_id and p.host_id = auth.uid()))
  with check (exists (select 1 from public.properties p
                       where p.id = ratings.property_id and p.host_id = auth.uid()));

-- ── reports ──────────────────────────────────────────────────────────────────
drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_admin());

drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert to authenticated
  with check (reporter_id = auth.uid() and not public.is_blocked());

drop policy if exists reports_admin_all on public.reports;
create policy reports_admin_all on public.reports
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── amenities and property_amenities ─────────────────────────────────────────
drop policy if exists amenities_read on public.amenities;
create policy amenities_read on public.amenities
  for select to authenticated using (true);

drop policy if exists property_amenities_read on public.property_amenities;
create policy property_amenities_read on public.property_amenities
  for select to authenticated using (true);

drop policy if exists property_amenities_write_own on public.property_amenities;
create policy property_amenities_write_own on public.property_amenities
  for all to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = property_amenities.property_id and p.host_id = auth.uid()))
  with check (exists (select 1 from public.properties p
                       where p.id = property_amenities.property_id
                         and p.host_id = auth.uid() and not public.is_blocked()));

-- ── property_blocked_dates ───────────────────────────────────────────────────
-- Readable by everyone: the guest calendar has to grey them out. Only the
-- owning host may write them.
drop policy if exists blocked_dates_read on public.property_blocked_dates;
create policy blocked_dates_read on public.property_blocked_dates
  for select to authenticated using (true);

drop policy if exists blocked_dates_write_own on public.property_blocked_dates;
create policy blocked_dates_write_own on public.property_blocked_dates
  for all to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = property_blocked_dates.property_id and p.host_id = auth.uid()))
  with check (exists (select 1 from public.properties p
                       where p.id = property_blocked_dates.property_id
                         and p.host_id = auth.uid() and not public.is_blocked()));

-- ── traveller_reviews ────────────────────────────────────────────────────────
drop policy if exists traveller_reviews_read on public.traveller_reviews;
create policy traveller_reviews_read on public.traveller_reviews
  for select to authenticated using (true);

drop policy if exists traveller_reviews_write_host on public.traveller_reviews;
create policy traveller_reviews_write_host on public.traveller_reviews
  for all to authenticated
  using (host_id = auth.uid())
  with check (
    host_id = auth.uid()
    and not public.is_blocked()
    and exists (
      select 1 from public.bookings b
        join public.properties p on p.id = b.property_id
       where b.id = traveller_reviews.booking_id
         and p.host_id = auth.uid()
         and b.traveller_id = traveller_reviews.traveller_id
         and b.start_date <= current_date
         and b.status in ('confirmed','checked_in','completed')
    )
  );

-- ── admin_actions ────────────────────────────────────────────────────────────
-- Admin-readable, never client-writable; the RPCs below write it as
-- SECURITY DEFINER.
drop policy if exists admin_actions_read on public.admin_actions;
create policy admin_actions_read on public.admin_actions
  for select to authenticated using (public.is_admin());


-- ═════════════════════════════════════════════════════════════════════════════
-- 11. VIEWS
--     Views have no policies of their own, and by default a view runs with its
--     owner's rights — which would let any signed-in user read
--     admin_report_view straight past everything above. security_invoker makes
--     the caller's RLS apply instead.
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare v record;
begin
  for v in select viewname from pg_views where schemaname = 'public'
  loop
    execute format('alter view public.%I set (security_invoker = on)', v.viewname);
  end loop;
end $$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 12. FUNCTIONS
--
--     WHY THE PARAMETERS ARE text
--     Your id columns may be bigint, uuid or text. Each function takes text
--     and immediately assigns it to a `<table>.<column>%TYPE` local; PL/pgSQL
--     applies an I/O conversion on assignment, so the value lands in the real
--     column type and a malformed id fails loudly at the call.
--
--     All are SECURITY DEFINER: they bypass RLS on purpose and do their own
--     authorisation. Every one establishes who the caller is first.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── refresh_booking_states ───────────────────────────────────────────────────
-- Retires lapsed one-hour holds, checks in current stays and closes out
-- finished ones. Nothing ever moved a booking to 'completed' before, which is
-- why host earnings counted unfinished stays as revenue. Called by the app on
-- dashboard load and by the functions below, so there is no cron to install.
create or replace function public.refresh_booking_states()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.bookings
     set status = 'expired'
   where status = 'pending'
     and (hold_expires_at is null or hold_expires_at <= now());

  update public.bookings
     set status = 'completed'
   where status in ('confirmed','checked_in') and end_date < current_date;

  update public.bookings
     set status = 'checked_in'
   where status = 'confirmed'
     and start_date <= current_date and end_date >= current_date;
end;
$$;


-- ── search_properties ────────────────────────────────────────────────────────
-- Replaces filtering in Dart over every row in the table. Handles text, city,
-- type, price band, guest count, date availability, amenities and radius, and
-- sorts by price, rating, distance or recency.
--
-- SECURITY DEFINER because the availability check must see bookings belonging
-- to other travellers. It returns only listing fields and aggregate ratings —
-- no booking or personal data leaves this function.
create or replace function public.search_properties(
  p_query      text             default null,
  p_city       text             default null,
  p_type       text             default null,
  p_min_price  numeric          default null,
  p_max_price  numeric          default null,
  p_guests     integer          default null,
  p_start_date date             default null,
  p_end_date   date             default null,
  p_amenities  text[]           default null,
  p_lat        double precision default null,
  p_lng        double precision default null,
  p_radius_km  double precision default null,
  p_sort       text             default 'recent',
  p_limit      integer          default 100,
  p_offset     integer          default 0
)
returns table (
  id text, host_id uuid, room_name text, location text, city text,
  property_type text, guest_preference text,
  price_per_night numeric, discount numeric, effective_price numeric,
  bedrooms integer, bathrooms integer, max_guests integer, min_nights integer,
  latitude double precision, longitude double precision,
  image1_url text, image2_url text, image3_url text,
  avg_rating numeric, total_reviews integer,
  distance_km double precision, amenity_keys text[],
  host_verified boolean
)
language sql stable security definer set search_path = public as $$
  with base as (
    select p.*,
      round((p.price_per_night::numeric
             * (1 - coalesce(p.discount,0)::numeric / 100))::numeric, 2) as eff_price,
      case
        when p_lat is null or p_lng is null
          or p.latitude is null or p.longitude is null then null
        else 6371 * acos(least(1, greatest(-1,
               cos(radians(p_lat)) * cos(radians(p.latitude))
             * cos(radians(p.longitude) - radians(p_lng))
             + sin(radians(p_lat)) * sin(radians(p.latitude)))))
      end as dist_km
    from public.properties p
    where coalesce(p.is_active, true)
  ),
  scored as (
    select b.*,
      (select coalesce(avg(r.rating),0)::numeric from public.ratings r
        where r.property_id = b.id) as rating_avg,
      (select count(*)::integer from public.ratings r
        where r.property_id = b.id) as rating_count,
      (select coalesce(array_agg(pa.amenity_key order by pa.amenity_key), '{}')
         from public.property_amenities pa where pa.property_id = b.id) as amenities
    from base b
  )
  select s.id::text, s.host_id, s.room_name, s.location, s.city,
         s.property_type, s.guest_preference,
         s.price_per_night::numeric, coalesce(s.discount,0)::numeric, s.eff_price,
         s.bedrooms::integer, s.bathrooms::integer, s.max_guests::integer,
         coalesce(s.min_nights,1)::integer,
         s.latitude, s.longitude,
         s.image1_url, s.image2_url, s.image3_url,
         s.rating_avg, s.rating_count, s.dist_km, s.amenities,
         coalesce((select h.verification_status = 'verified'
                     from public.hosts h where h.id = s.host_id), false)
  from scored s
  where (p_query is null or btrim(p_query) = ''
         or s.room_name ilike '%' || p_query || '%'
         or s.location  ilike '%' || p_query || '%'
         or s.city      ilike '%' || p_query || '%')
    and (p_city is null or lower(s.city) = lower(p_city))
    and (p_type is null or s.property_type = p_type)
    and (p_min_price is null or s.eff_price >= p_min_price)
    and (p_max_price is null or s.eff_price <= p_max_price)
    and (p_guests is null or coalesce(s.max_guests,1) >= p_guests)
    and (p_radius_km is null or (s.dist_km is not null and s.dist_km <= p_radius_km))
    and (p_amenities is null or cardinality(p_amenities) = 0
         or s.amenities @> p_amenities)
    and (
      p_start_date is null or p_end_date is null
      or (
        (p_end_date - p_start_date + 1) >= coalesce(s.min_nights,1)
        and (s.max_nights is null or (p_end_date - p_start_date + 1) <= s.max_nights)
        and not exists (
          select 1 from public.bookings bk
           where bk.property_id = s.id
             and daterange(bk.start_date, bk.end_date,'[]')
                 && daterange(p_start_date, p_end_date,'[]')
             and (bk.status in ('confirmed','checked_in','completed')
                  or (bk.status = 'pending' and bk.hold_expires_at > now())))
        and not exists (
          select 1 from public.property_blocked_dates bd
           where bd.property_id = s.id
             and bd.blocked_date between p_start_date and p_end_date)
      )
    )
  order by
    case when p_sort = 'price_asc'  then s.eff_price  end asc  nulls last,
    case when p_sort = 'price_desc' then s.eff_price  end desc nulls last,
    case when p_sort = 'rating'     then s.rating_avg end desc nulls last,
    case when p_sort = 'distance'   then s.dist_km    end asc  nulls last,
    case when p_sort = 'recent'     then s.created_at::timestamptz end desc nulls last
  limit  greatest(1, least(coalesce(p_limit,100), 200))
  offset greatest(0, coalesce(p_offset,0));
$$;


-- ── property_unavailable_dates ───────────────────────────────────────────────
-- One call for the guest calendar: live bookings plus host-blocked dates.
create or replace function public.property_unavailable_dates(p_property_id text)
returns table (d date, reason text)
language plpgsql stable security definer set search_path = public as $$
declare v_property_id public.properties.id%TYPE;
begin
  v_property_id := p_property_id;

  return query
    select gs::date, 'booked'::text
      from public.bookings b
      cross join lateral generate_series(b.start_date, b.end_date, interval '1 day') gs
     where b.property_id = v_property_id
       and (b.status in ('confirmed','checked_in','completed')
            or (b.status = 'pending' and b.hold_expires_at > now()))
    union
    select bd.blocked_date, coalesce(bd.reason, 'unavailable')
      from public.property_blocked_dates bd
     where bd.property_id = v_property_id;
end;
$$;


-- ── create_booking ───────────────────────────────────────────────────────────
-- Replaces the client-side insert in RoomDetailPage. Availability used to be
-- read once when the page opened and never re-checked, so two people on the
-- same screen could both book the same dates.
--
-- The property row is locked FOR UPDATE, serialising every concurrent attempt
-- against that property. Both notifications are written in the same
-- transaction, so a booking can no longer exist without the host being told.
drop function if exists public.create_booking(text, date, date, numeric);

create or replace function public.create_booking(
  p_property_id text,
  p_start_date  date,
  p_end_date    date,
  p_total_price numeric,
  p_guests      integer default 1
)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_uid         uuid := auth.uid();
  v_property_id public.properties.id%TYPE;
  v_booking_id  public.bookings.id%TYPE;
  v_host_id     uuid;
  v_room_name   text;
  v_traveller   text;
  v_nights      integer;
  v_min         integer;
  v_max         integer;
  v_cap         integer;
  v_active      boolean;
  v_from        text;
  v_to          text;
begin
  if v_uid is null then
    raise exception 'Please sign in to book.' using errcode = '42501';
  end if;
  if public.is_blocked() then
    raise exception 'Your account has been blocked. Please contact support.'
      using errcode = '42501';
  end if;
  if p_end_date < p_start_date then
    raise exception 'The checkout date cannot be before the check-in date.';
  end if;
  if p_start_date < current_date then
    raise exception 'You cannot book dates in the past.';
  end if;
  if p_total_price is null or p_total_price < 0 then
    raise exception 'Invalid total price.';
  end if;

  v_property_id := p_property_id;
  v_nights := (p_end_date - p_start_date) + 1;

  select p.host_id, p.room_name, coalesce(p.min_nights,1), p.max_nights,
         coalesce(p.max_guests,1), coalesce(p.is_active,true)
    into v_host_id, v_room_name, v_min, v_max, v_cap, v_active
    from public.properties p
   where p.id = v_property_id
   for update;

  if not found then
    raise exception 'That property is no longer available.';
  end if;
  if not v_active then
    raise exception 'This listing is not accepting bookings right now.';
  end if;
  if v_host_id = v_uid then
    raise exception 'You cannot book your own property.';
  end if;
  if coalesce(p_guests,1) < 1 then
    raise exception 'Guest count must be at least 1.';
  end if;
  if coalesce(p_guests,1) > v_cap then
    raise exception 'This place takes at most % guest(s).', v_cap;
  end if;
  if v_nights < v_min then
    raise exception 'This host requires a minimum stay of % night(s).', v_min;
  end if;
  if v_max is not null and v_nights > v_max then
    raise exception 'This host allows a maximum stay of % night(s).', v_max;
  end if;

  perform public.refresh_booking_states();

  if exists (select 1 from public.property_blocked_dates bd
              where bd.property_id = v_property_id
                and bd.blocked_date between p_start_date and p_end_date) then
    raise exception 'The host has marked some of those dates as unavailable.';
  end if;

  if exists (
    select 1 from public.bookings b
     where b.property_id = v_property_id
       and daterange(b.start_date, b.end_date,'[]')
           && daterange(p_start_date, p_end_date,'[]')
       and (b.status in ('confirmed','checked_in','completed')
            or (b.status = 'pending' and b.hold_expires_at > now()))
  ) then
    raise exception 'Those dates have just been taken. Please choose different dates.';
  end if;

  select coalesce(nullif(btrim(t.name),''), 'A traveller')
    into v_traveller from public.travellers t where t.id = v_uid;

  if v_traveller is null then
    raise exception 'Only travellers can book. This account is not a traveller.'
      using errcode = '42501';
  end if;

  insert into public.bookings (property_id, traveller_id, start_date, end_date,
                               total_price, status, hold_expires_at, guests)
  values (v_property_id, v_uid, p_start_date, p_end_date,
          p_total_price, 'pending', now() + interval '1 hour', coalesce(p_guests,1))
  returning id into v_booking_id;

  v_from := to_char(p_start_date, 'Mon DD, YYYY');
  v_to   := to_char(p_end_date,   'Mon DD, YYYY');

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_uid, v_booking_id, 'booking_info',
          format('Your booking request for %s from %s to %s has been sent to the host!',
                 coalesce(v_room_name,'the property'), v_from, v_to));

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_host_id, v_booking_id, 'booking_request',
          format('%s has requested to book %s from %s to %s for %s guest(s). Held for 1 hour.',
                 v_traveller, coalesce(v_room_name,'your property'),
                 v_from, v_to, coalesce(p_guests,1)));

  return v_booking_id::text;
end;
$$;


-- ── accept_booking ───────────────────────────────────────────────────────────
-- Was four separate client writes: update status, read details, insert two
-- notifications, mark the source notification read. A dropped connection
-- part-way left a confirmed booking nobody was told about.
--
-- Also resolves the competing requests: any other pending request overlapping
-- the accepted dates is cancelled and its traveller notified, atomically.
create or replace function public.accept_booking(
  p_booking_id text, p_notification_id text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid          uuid := auth.uid();
  v_booking_id   public.bookings.id%TYPE;
  v_notif_id     public.notifications.id%TYPE;
  v_property_id  public.properties.id%TYPE;
  v_traveller_id uuid;
  v_host_id      uuid;
  v_room_name    text;
  v_traveller    text;
  v_start        date;
  v_end          date;
  v_from         text;
  v_to           text;
  r              record;
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = '42501';
  end if;

  v_booking_id := p_booking_id;

  select b.property_id, b.traveller_id, b.start_date, b.end_date
    into v_property_id, v_traveller_id, v_start, v_end
    from public.bookings b where b.id = v_booking_id for update;

  if not found then
    raise exception 'That booking no longer exists.';
  end if;

  select p.host_id, p.room_name into v_host_id, v_room_name
    from public.properties p where p.id = v_property_id for update;

  if v_host_id is distinct from v_uid then
    raise exception 'Only the host of this property can accept this booking.'
      using errcode = '42501';
  end if;

  if exists (select 1 from public.bookings b2
              where b2.property_id = v_property_id
                and b2.id <> v_booking_id
                and b2.status in ('confirmed','checked_in','completed')
                and daterange(b2.start_date, b2.end_date,'[]')
                    && daterange(v_start, v_end,'[]')) then
    raise exception 'Another booking is already confirmed for those dates.';
  end if;

  update public.bookings
     set status = 'confirmed', hold_expires_at = null
   where id = v_booking_id;

  v_from := to_char(v_start,'Mon DD, YYYY');
  v_to   := to_char(v_end,  'Mon DD, YYYY');

  select coalesce(nullif(btrim(t.name),''),'Traveller') into v_traveller
    from public.travellers t where t.id = v_traveller_id;

  for r in
    select b2.id, b2.traveller_id from public.bookings b2
     where b2.property_id = v_property_id
       and b2.id <> v_booking_id
       and b2.status = 'pending'
       and daterange(b2.start_date, b2.end_date,'[]')
           && daterange(v_start, v_end,'[]')
  loop
    update public.bookings set status = 'cancelled' where id = r.id;
    insert into public.notifications (user_id, booking_id, category, message)
    values (r.traveller_id, r.id, 'booking_info',
            format('Your request for %s was declined because those dates have now been booked.',
                   coalesce(v_room_name,'the property')));
  end loop;

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_traveller_id, v_booking_id, 'booking_accepted',
          format('Stay Confirmed! Your booking for %s (%s to %s) has been accepted by the host.',
                 coalesce(v_room_name,'the property'), v_from, v_to));

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_host_id, v_booking_id, 'booking_accepted',
          format('Booking Confirmed! You accepted %s''s request for %s (%s to %s).',
                 coalesce(v_traveller,'a traveller'),
                 coalesce(v_room_name,'your property'), v_from, v_to));

  if p_notification_id is not null and btrim(p_notification_id) <> '' then
    v_notif_id := p_notification_id;
    update public.notifications set is_read = true where id = v_notif_id;
  end if;
end;
$$;


-- ── reject_booking ───────────────────────────────────────────────────────────
create or replace function public.reject_booking(
  p_booking_id text, p_notification_id text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid          uuid := auth.uid();
  v_booking_id   public.bookings.id%TYPE;
  v_notif_id     public.notifications.id%TYPE;
  v_property_id  public.properties.id%TYPE;
  v_traveller_id uuid;
  v_host_id      uuid;
  v_room_name    text;
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = '42501';
  end if;

  v_booking_id := p_booking_id;

  select b.property_id, b.traveller_id into v_property_id, v_traveller_id
    from public.bookings b where b.id = v_booking_id for update;

  if not found then
    raise exception 'That booking no longer exists.';
  end if;

  select p.host_id, p.room_name into v_host_id, v_room_name
    from public.properties p where p.id = v_property_id;

  if v_host_id is distinct from v_uid then
    raise exception 'Only the host of this property can decline this booking.'
      using errcode = '42501';
  end if;

  update public.bookings
     set status = 'cancelled', hold_expires_at = null
   where id = v_booking_id;

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_traveller_id, v_booking_id, 'booking_info',
          format('Sorry, your booking request for %s was declined by the host.',
                 coalesce(v_room_name,'the property')));

  if p_notification_id is not null and btrim(p_notification_id) <> '' then
    v_notif_id := p_notification_id;
    update public.notifications set is_read = true where id = v_notif_id;
  end if;
end;
$$;


-- ── cancel_booking (traveller) ───────────────────────────────────────────────
-- A traveller may withdraw a pending request or cancel a confirmed stay, but
-- only before it starts — once the stay has begun it is the host's to resolve.
create or replace function public.cancel_booking(p_booking_id text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid          uuid := auth.uid();
  v_booking_id   public.bookings.id%TYPE;
  v_property_id  public.properties.id%TYPE;
  v_traveller_id uuid;
  v_status       text;
  v_start        date;
  v_end          date;
  v_host_id      uuid;
  v_room_name    text;
  v_traveller    text;
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = '42501';
  end if;

  v_booking_id := p_booking_id;

  select b.property_id, b.traveller_id, b.status, b.start_date, b.end_date
    into v_property_id, v_traveller_id, v_status, v_start, v_end
    from public.bookings b where b.id = v_booking_id for update;

  if not found then
    raise exception 'That booking no longer exists.';
  end if;
  if v_traveller_id is distinct from v_uid then
    raise exception 'You can only cancel your own bookings.' using errcode = '42501';
  end if;
  if v_status not in ('pending','confirmed') then
    raise exception 'This booking can no longer be cancelled.';
  end if;
  if v_start <= current_date then
    raise exception 'Your stay has already started. Please message the host to sort this out.';
  end if;

  update public.bookings
     set status = 'cancelled', hold_expires_at = null
   where id = v_booking_id;

  select p.host_id, p.room_name into v_host_id, v_room_name
    from public.properties p where p.id = v_property_id;

  select coalesce(nullif(btrim(t.name),''),'A traveller') into v_traveller
    from public.travellers t where t.id = v_uid;

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_host_id, v_booking_id, 'booking_info',
          format('%s cancelled their booking for %s (%s to %s). Those dates are open again.',
                 coalesce(v_traveller,'A traveller'),
                 coalesce(v_room_name,'your property'),
                 to_char(v_start,'Mon DD, YYYY'), to_char(v_end,'Mon DD, YYYY')));
end;
$$;


-- ── host_cancel_booking ──────────────────────────────────────────────────────
-- Hosts could accept and decline but never cancel a stay they had already
-- confirmed, so a host with a burst pipe had no route other than messaging.
create or replace function public.host_cancel_booking(
  p_booking_id text, p_reason text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid          uuid := auth.uid();
  v_booking_id   public.bookings.id%TYPE;
  v_property_id  public.properties.id%TYPE;
  v_traveller_id uuid;
  v_host_id      uuid;
  v_room_name    text;
  v_status       text;
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = '42501';
  end if;

  v_booking_id := p_booking_id;

  select b.property_id, b.traveller_id, b.status
    into v_property_id, v_traveller_id, v_status
    from public.bookings b where b.id = v_booking_id for update;

  if not found then
    raise exception 'That booking no longer exists.';
  end if;

  select p.host_id, p.room_name into v_host_id, v_room_name
    from public.properties p where p.id = v_property_id;

  if v_host_id is distinct from v_uid then
    raise exception 'Only the host of this property can cancel this booking.'
      using errcode = '42501';
  end if;
  if v_status not in ('pending','confirmed') then
    raise exception 'This booking can no longer be cancelled.';
  end if;

  update public.bookings
     set status = 'cancelled', hold_expires_at = null
   where id = v_booking_id;

  insert into public.notifications (user_id, booking_id, category, message)
  values (v_traveller_id, v_booking_id, 'booking_info',
          format('Your host has cancelled your stay at %s.%s',
                 coalesce(v_room_name,'the property'),
                 case when coalesce(btrim(p_reason),'') = '' then ''
                      else ' Reason: ' || p_reason end));
end;
$$;


-- ── submit_host_verification ─────────────────────────────────────────────────
-- The host uploads their CNIC to the private `host_cnic` bucket, then calls
-- this with the object PATH (not a public URL).
create or replace function public.submit_host_verification(
  p_cnic_url text, p_cnic_number text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_cnic_url),'') = '' then
    raise exception 'A CNIC image is required.';
  end if;

  update public.hosts
     set cnic_url = p_cnic_url,
         cnic_number = p_cnic_number,
         verification_status = 'pending',
         verification_note = null
   where id = v_uid;

  if not found then
    raise exception 'Only hosts can submit verification.' using errcode = '42501';
  end if;
end;
$$;


-- ── admin actions ────────────────────────────────────────────────────────────
-- Each writes an audit row. The Reports tab already claimed "Audit Trail
-- Logged" while logging nothing at all.
create or replace function public.admin_log(
  p_action text, p_target_type text, p_target_id text, p_detail text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.admin_actions (actor_id, action, target_type, target_id, detail)
  values (auth.uid(), p_action, p_target_type, p_target_id, p_detail);
end;
$$;

create or replace function public.admin_set_user_blocked(
  p_user_id uuid, p_role text, p_blocked boolean, p_reason text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;

  if lower(p_role) = 'host' then
    update public.hosts set is_blocked = p_blocked where id = p_user_id;
  else
    update public.travellers set is_blocked = p_blocked where id = p_user_id;
  end if;

  if not found then
    raise exception 'That user does not exist.';
  end if;

  perform public.admin_log(
    case when p_blocked then 'block_user' else 'unblock_user' end,
    lower(p_role), p_user_id::text, p_reason);
end;
$$;

create or replace function public.admin_resolve_report(
  p_report_id text, p_status text, p_note text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_report_id public.reports.id%TYPE;
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;
  if p_status not in ('resolved','dismissed','open') then
    raise exception 'Status must be resolved, dismissed or open.';
  end if;

  v_report_id := p_report_id;

  update public.reports
     set status = p_status,
         resolved_by = case when p_status = 'open' then null else auth.uid() end,
         resolved_at = case when p_status = 'open' then null else now() end,
         resolution_note = p_note
   where id = v_report_id;

  if not found then
    raise exception 'That report no longer exists.';
  end if;

  perform public.admin_log('resolve_report','report', p_report_id,
                           p_status || coalesce(': ' || p_note, ''));
end;
$$;

create or replace function public.admin_set_property_active(
  p_property_id text, p_active boolean, p_reason text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_property_id public.properties.id%TYPE;
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;

  v_property_id := p_property_id;
  update public.properties set is_active = p_active where id = v_property_id;

  if not found then
    raise exception 'That property no longer exists.';
  end if;

  perform public.admin_log(
    case when p_active then 'restore_listing' else 'take_down_listing' end,
    'property', p_property_id, p_reason);
end;
$$;

create or replace function public.admin_review_host_verification(
  p_host_id uuid, p_approve boolean, p_note text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;

  update public.hosts
     set verification_status = case when p_approve then 'verified' else 'rejected' end,
         verified_at = case when p_approve then now() else null end,
         verification_note = p_note
   where id = p_host_id;

  if not found then
    raise exception 'That host does not exist.';
  end if;

  insert into public.notifications (user_id, category, message)
  values (p_host_id, 'booking_info',
          case when p_approve
               then 'Your identity has been verified. A Verified badge now appears on your listings.'
               else 'Your verification was not approved.' || coalesce(' ' || p_note, '')
          end);

  perform public.admin_log(
    case when p_approve then 'verify_host' else 'reject_host_verification' end,
    'host', p_host_id::text, p_note);
end;
$$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 13. GRANTS
--     The anon role has no reason to touch anything: nothing in the app works
--     while signed out.
-- ═════════════════════════════════════════════════════════════════════════════
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

do $$
declare f text;
begin
  foreach f in array array[
    'public.is_admin()',
    'public.is_blocked()',
    'public.refresh_booking_states()',
    'public.search_properties(text,text,text,numeric,numeric,integer,date,date,text[],double precision,double precision,double precision,text,integer,integer)',
    'public.property_unavailable_dates(text)',
    'public.create_booking(text,date,date,numeric,integer)',
    'public.accept_booking(text,text)',
    'public.reject_booking(text,text)',
    'public.cancel_booking(text)',
    'public.host_cancel_booking(text,text)',
    'public.submit_host_verification(text,text)',
    'public.admin_set_user_blocked(uuid,text,boolean,text)',
    'public.admin_resolve_report(text,text,text)',
    'public.admin_set_property_active(text,boolean,text)',
    'public.admin_review_host_verification(uuid,boolean,text)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- admin_log is internal: only the SECURITY DEFINER functions above call it.
revoke all on function public.admin_log(text,text,text,text)
  from public, anon, authenticated;


-- ═════════════════════════════════════════════════════════════════════════════
-- 14. STORAGE: the private host_cnic bucket and its policies
--
--     A CNIC is a national ID document, so this bucket is private and the app
--     stores the object PATH rather than a public URL. Admins view it through
--     a 5-minute signed URL.
--
--     A private bucket starts with no policies at all, which means
--     storage.objects RLS denies everything — including the host's own
--     upload. These three policies are what make it work.
--
--     File naming convention, set by host_profile_page.dart:
--       cnic_<host-uuid>_<millis>.jpg
--     The policies key off that prefix, so one host cannot write or read
--     another host's document.
-- ═════════════════════════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public)
values ('host_cnic', 'host_cnic', false)
on conflict (id) do update set public = false;

drop policy if exists "cnic host insert own" on storage.objects;
create policy "cnic host insert own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'host_cnic'
    and name like 'cnic_' || auth.uid()::text || '_%'
  );

drop policy if exists "cnic host read own" on storage.objects;
create policy "cnic host read own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'host_cnic'
    and name like 'cnic_' || auth.uid()::text || '_%'
  );

-- Admins need read access to review submissions and to mint signed URLs.
drop policy if exists "cnic admin read all" on storage.objects;
create policy "cnic admin read all" on storage.objects
  for select to authenticated
  using (bucket_id = 'host_cnic' and public.is_admin());


-- ═════════════════════════════════════════════════════════════════════════════
-- 15. ADMIN PROMOTION
--
--     An auth user cannot be created safely from SQL (password hashing and the
--     auth.identities row are handled by GoTrue), so that one step is manual:
--
--       Supabase -> Authentication -> Users -> Add user -> Create new user
--         Email:    the address below
--         Password: your choice
--         Auto Confirm User: TICK IT, or the account cannot log in
--
--     Then re-run this file — the block below finds that user by email and
--     promotes it. Change the address on the next line if you used a
--     different one.
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_admin_email text := 'admin@surfnstay.com';   -- <<< EDIT IF YOURS DIFFERS
  v_id          uuid;
begin
  select id into v_id from auth.users where lower(email) = lower(v_admin_email);

  if v_id is null then
    raise notice '';
    raise notice '>>> ADMIN NOT CREATED YET <<<';
    raise notice '    No auth user found with email %.', v_admin_email;
    raise notice '    Create it under Authentication -> Users (tick Auto Confirm),';
    raise notice '    then run this file again to finish promoting it.';
  else
    insert into public.admins (id, email)
    values (v_id, v_admin_email)
    on conflict (id) do nothing;

    -- The signup trigger in section 8 fires for dashboard-created users too,
    -- and with no 'role' in the metadata it defaults to traveller. So the
    -- admin account picks up a stray travellers row and would show up in the
    -- Community tab as a guest.
    --
    -- Only removed when it is genuinely unused, so promoting a real traveller
    -- to admin can never destroy their booking or review history.
    delete from public.travellers t
     where t.id = v_id
       and not exists (select 1 from public.bookings b where b.traveller_id = t.id)
       and not exists (select 1 from public.ratings   r where r.traveller_id = t.id)
       and not exists (select 1 from public.chats     c
                        where c.user1_id = t.id or c.user2_id = t.id);

    raise notice 'Admin ready: % (%).', v_admin_email, v_id;
  end if;
end $$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 16. DONE
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_rls_off integer;
  v_funcs   integer;
  v_admins  integer;
  v_bucket  integer;
begin
  select count(*) into v_admins from public.admins;
  select count(*) into v_bucket from storage.buckets
   where id = 'host_cnic' and public = false;

  select count(*) into v_rls_off
    from pg_class
   where relnamespace = 'public'::regnamespace
     and relkind = 'r'
     and not relrowsecurity
     and relname in ('travellers','hosts','admins','properties','bookings',
                     'notifications','messages','chats','ratings','reports',
                     'amenities','property_amenities','property_blocked_dates',
                     'traveller_reviews','admin_actions');

  select count(*) into v_funcs
    from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('is_admin','is_blocked','refresh_booking_states',
                     'search_properties','property_unavailable_dates',
                     'create_booking','accept_booking','reject_booking',
                     'cancel_booking','host_cancel_booking',
                     'submit_host_verification','admin_set_user_blocked',
                     'admin_resolve_report','admin_set_property_active',
                     'admin_review_host_verification');

  raise notice '=====================================================';
  raise notice 'SurfNStay setup complete.';
  raise notice '  Tables without RLS (must be 0):   %', v_rls_off;
  raise notice '  Functions created (expect 15):    %', v_funcs;
  raise notice '  Private host_cnic bucket (1 = ok): %', v_bucket;
  raise notice '  Rows in public.admins:            %', v_admins;
  raise notice '';
  if v_admins = 0 then
    raise notice 'ACTION REQUIRED: create the admin auth user, then re-run';
    raise notice '                 this file. See section 15.';
  end if;
  raise notice 'Then test one traveller signup and one host signup.';
  raise notice '=====================================================';
end $$;

commit;
