-- ============================================================================
-- fix-supabase-schema.sql  —  Healer Boys
-- ----------------------------------------------------------------------------
-- One-shot repair for the admin panel ("supervisor panel") and the
-- "Could not find the table 'public.supporter_donations' in the schema cache"
-- (PGRST205) family of errors.
--
-- Run this ONCE in Supabase -> SQL Editor. It is safe to re-run at any time.
--
-- What it does:
--   1) Creates/repairs every table the app reads or writes:
--        admins, members, payments, donations, supporter_donations,
--        general_members, executive_members, app_settings
--   2) Adds every column the frontend sends (missing columns cause
--      "Could not find the 'x' column ... in the schema cache" errors).
--   3) Restores RLS: everyone signed in can read, only the admin can write.
--   4) Reloads the PostgREST schema cache with NOTIFY pgrst, 'reload schema',
--      so the API sees the new tables/columns immediately.
--
-- Note: the "Donation From Others" card stores rows ONLY in
-- supporter_donations. They are added to Total Fund on top of the fees and
-- are never mixed with the main donations table.
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 0. Admin allow-list + is_admin() helper
-- ----------------------------------------------------------------------------
create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (position('@' in email) > 1),
  created_at timestamptz not null default now()
);
insert into public.admins (email) values ('yourhealerboys@gmail.com') on conflict (email) do nothing;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins a where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- shared updated_at trigger
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end $$;

-- ----------------------------------------------------------------------------
-- 1. Legacy members table (kept in sync as a compatibility mirror)
-- ----------------------------------------------------------------------------
create table if not exists public.members (
  id text primary key,
  name text not null,
  created_at timestamptz not null default now()
);
alter table public.members add column if not exists email text;
alter table public.members add column if not exists avatar_url text;
alter table public.members add column if not exists member_type text not null default 'general';
alter table public.members add column if not exists profile text not null default '';
do $$ begin
  if not exists (
    select 1 from pg_constraint where conrelid = 'public.members'::regclass
      and conname = 'members_member_type_check'
  ) then
    alter table public.members add constraint members_member_type_check
      check (member_type in ('executive', 'general'));
  end if;
end $$;

-- members.id may be uuid on some installs — give it a default either way.
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'members'
               and column_name = 'id' and data_type in ('text', 'character varying')
               and column_default is null) then
    execute 'alter table public.members alter column id set default gen_random_uuid()::text';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'members'
               and column_name = 'id' and data_type = 'uuid'
               and column_default is null) then
    execute 'alter table public.members alter column id set default gen_random_uuid()';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 2. payments (member fees) — id must never insert as NULL
-- ----------------------------------------------------------------------------
create table if not exists public.payments (
  id text primary key default gen_random_uuid()::text,
  member_id text not null,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  date date,
  type text
);
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'payments'
               and column_name = 'id' and data_type in ('text', 'character varying')
               and column_default is null) then
    execute 'alter table public.payments alter column id set default gen_random_uuid()::text';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'payments'
               and column_name = 'id' and data_type = 'uuid'
               and column_default is null) then
    execute 'alter table public.payments alter column id set default gen_random_uuid()';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 3. donations (money GIVEN OUT to people in need — subtracted from the fund)
-- ----------------------------------------------------------------------------
create table if not exists public.donations (
  id uuid primary key default gen_random_uuid(),
  donor_name text,
  is_anonymous boolean not null default true,
  amount numeric(12,2) not null check (amount >= 0),
  note text not null check (length(trim(note)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.donations add column if not exists donor_name text;
alter table public.donations add column if not exists is_anonymous boolean not null default true;
alter table public.donations add column if not exists note text;
alter table public.donations add column if not exists description text;
alter table public.donations add column if not exists date date;
alter table public.donations add column if not exists image_url text;
alter table public.donations add column if not exists created_at timestamptz not null default now();
alter table public.donations add column if not exists updated_at timestamptz not null default now();
update public.donations set note = coalesce(note, description, 'Donation') where note is null;
do $$ begin
  if not exists (
    select 1 from pg_constraint where conrelid = 'public.donations'::regclass
      and conname = 'donations_image_url_length_check'
  ) then
    alter table public.donations add constraint donations_image_url_length_check
      check (image_url is null or length(image_url) <= 200000);
  end if;
  if not exists (
    select 1 from pg_constraint where conrelid = 'public.donations'::regclass
      and conname = 'donations_note_length_check'
  ) then
    alter table public.donations add constraint donations_note_length_check
      check (length(trim(note)) > 0);
  end if;
end $$;
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'donations'
               and column_name = 'id' and column_default is null) then
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'donations'
                 and column_name = 'id' and data_type = 'uuid') then
      execute 'alter table public.donations alter column id set default gen_random_uuid()';
    else
      execute 'alter table public.donations alter column id set default gen_random_uuid()::text';
    end if;
  end if;
end $$;

drop trigger if exists donations_touch on public.donations;
create trigger donations_touch before update on public.donations
for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 4. supporter_donations — "Donation From Others" card
--    Each row is one supporter (member) contribution. These amounts are
--    ADDED to Total Fund Collection; they never mix with public.donations.
-- ----------------------------------------------------------------------------
create table if not exists public.supporter_donations (
  id uuid primary key default gen_random_uuid(),
  donor_name text,
  is_anonymous boolean not null default true,
  amount numeric(12,2) not null check (amount >= 0),
  note text not null check (length(trim(note)) > 0),
  image_url text,
  donation_month date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Older installs created the table without donation_month / image_url limits.
alter table public.supporter_donations add column if not exists donation_month date;
update public.supporter_donations set donation_month = coalesce(donation_month, created_at::date) where donation_month is null;
alter table public.supporter_donations
  alter column donation_month set default current_date,
  alter column donation_month set not null;
alter table public.supporter_donations add column if not exists image_url text;
alter table public.supporter_donations add column if not exists created_at timestamptz not null default now();
alter table public.supporter_donations add column if not exists updated_at timestamptz not null default now();
do $$ begin
  if not exists (
    select 1 from pg_constraint where conrelid = 'public.supporter_donations'::regclass
      and conname = 'supporter_donations_image_url_length_check'
  ) then
    alter table public.supporter_donations add constraint supporter_donations_image_url_length_check
      check (image_url is null or length(image_url) <= 200000);
  end if;
end $$;

create index if not exists supporter_donations_created_at_idx on public.supporter_donations (created_at desc);
create index if not exists supporter_donations_donor_month_idx on public.supporter_donations (donor_name, donation_month desc);

drop trigger if exists supporter_donations_touch on public.supporter_donations;
create trigger supporter_donations_touch before update on public.supporter_donations
for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 5. Normalized member tables used by the Members screen
-- ----------------------------------------------------------------------------
create table if not exists public.executive_members (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  position text,
  photo_url text,
  contribution numeric(12,2) not null default 0 check (contribution >= 0),
  monthly_status text not null default 'paid' check (monthly_status in ('paid', 'due', 'advance')),
  due_amount numeric(12,2) not null default 0 check (due_amount >= 0),
  due_months integer not null default 0 check (due_months >= 0),
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.general_members (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  email text,
  photo_url text,
  profile text,
  legacy_data jsonb not null default '{}'::jsonb,
  payment_total numeric(12,2) not null default 0 check (payment_total >= 0),
  payment_count integer not null default 0 check (payment_count >= 0),
  monthly_fee numeric(12,2) not null default 0 check (monthly_fee >= 0),
  last_payment_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.executive_members add column if not exists photo_url text;
alter table public.general_members  add column if not exists photo_url text;
alter table public.general_members  add column if not exists email text;
alter table public.general_members  add column if not exists profile text;

create index if not exists executive_members_sort_idx on public.executive_members (sort_order, name);
create index if not exists general_members_name_idx on public.general_members (name);
create index if not exists donations_created_at_idx on public.donations (created_at desc);

-- unique name indexes (used by the idempotent seeds). Tolerate dirty legacy
-- data so the repair script can never abort halfway.
do $$ begin
  begin
    create unique index if not exists executive_members_name_uidx on public.executive_members (name);
  exception when others then null;
  end;
  begin
    create unique index if not exists general_members_name_uidx on public.general_members (name);
  exception when others then null;
  end;
end $$;

drop trigger if exists executive_members_touch on public.executive_members;
create trigger executive_members_touch before update on public.executive_members
for each row execute function public.touch_updated_at();
drop trigger if exists general_members_touch on public.general_members;
create trigger general_members_touch before update on public.general_members
for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 6. app_settings (single row, id = 1) — reminder settings
-- ----------------------------------------------------------------------------
create table if not exists public.app_settings (
  id int primary key default 1 check (id = 1),
  auto_email_reminder boolean not null default true,
  send_day int not null default 5 check (send_day between 1 and 28),
  channel text not null default 'Email',
  bkash_number text not null default '',
  nagad_number text not null default '',
  last_sent_at timestamptz,
  last_sent_count int not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 7. Row Level Security: read for everyone signed in, writes only for admin
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
  r record;
begin
  foreach t in array array['members','payments','donations','supporter_donations',
                          'executive_members','general_members','app_settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    -- drop every existing policy on the table, then recreate ours
    for r in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t
    loop
      execute format('drop policy if exists %I on public.%I', r.policyname, t);
    end loop;
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t || '_public_select', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.is_admin())', t || '_admin_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.is_admin()) with check (public.is_admin())', t || '_admin_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.is_admin())', t || '_admin_delete', t);
  end loop;
end $$;

alter table public.admins enable row level security;
drop policy if exists admins_select_authenticated on public.admins;
create policy admins_select_authenticated on public.admins for select to authenticated using (public.is_admin());

-- anon (signed-out) can never write, even if RLS is bypassed
do $$ declare t text; begin
  foreach t in array array['members','payments','donations','supporter_donations',
                          'executive_members','general_members','app_settings'] loop
    execute format('revoke insert, update, delete, truncate on public.%I from anon', t);
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('grant insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 8. Realtime: let the app listen for member/donation changes (best effort).
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['members','payments','donations','supporter_donations',
                            'executive_members','general_members'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) and exists (
        select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = t and c.relkind = 'r'
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 9. Reload the PostgREST schema cache.
--    Without this, freshly created tables/columns keep raising
--    "Could not find the table 'public.supporter_donations' in the schema cache".
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- Done. The app will pick up supporter_donations, general_members and the
-- rest on the next load — no more table-not-found / schema cache errors.
