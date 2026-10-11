-- ============================================================================
-- 0002_member_tiers_and_supporters.sql  —  Healer Boy's
-- ----------------------------------------------------------------------------
-- Adds everything the new Members register needs:
--
--   * members.tier        'executive' | 'general'   (Executive vs General)
--   * members.role_title  leadership seat, e.g. 'President'
--   * members.phone       optional contact number
--   * members.sort_order  manual ordering inside a section
--   * members.is_active   soft "still a member" flag
--   * members.joined_at   optional join date
--
--   * public.supporter_donations — "Donation from others": money supporters
--     gave TO the club (named or anonymous). Kept separate from
--     public.donations, which records money the club GAVE AWAY.
--
--   * Backfill: the 8 executive members get their tier + seat;
--               'Mehedi Hasan Saikat' is corrected to 'Mehedi Hasan Saikot'.
--   * RLS: authenticated may read, only the admin Gmail may write.
--
-- Safe to run more than once (idempotent). Run in Supabase → SQL Editor,
-- or apply with `supabase db push` when using the Supabase CLI.
-- Prerequisite: supabase_policies.sql / 0001 (creates public.is_admin()).
-- This file re-creates is_admin() if it is missing, so order does not matter.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Admin identity helper (idempotent — same definition as supabase_policies)
--    The frontend ADMIN_EMAIL constant must stay in sync with this address.
-- ----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'yourhealerboys@gmail.com';
$$;

grant execute on function public.is_admin() to authenticated, anon;

-- ----------------------------------------------------------------------------
-- 1. members — new columns
-- ----------------------------------------------------------------------------
create table if not exists public.members (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  email      text,
  avatar_url text
);

alter table public.members add column if not exists tier        text;
alter table public.members add column if not exists role_title  text;
alter table public.members add column if not exists phone       text;
alter table public.members add column if not exists sort_order  integer not null default 0;
alter table public.members add column if not exists is_active   boolean not null default true;
alter table public.members add column if not exists joined_at   date;
alter table public.members add column if not exists created_at  timestamptz not null default now();

-- members.id must always be filled, whatever type it is (text or uuid)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'members'
      and column_name = 'id'
      and data_type in ('text', 'character varying')
      and column_default is null
  ) then
    execute 'alter table public.members alter column id set default gen_random_uuid()::text';
  elsif exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'members'
      and column_name = 'id'
      and data_type = 'uuid'
      and column_default is null
  ) then
    execute 'alter table public.members alter column id set default gen_random_uuid()';
  end if;
end $$;

-- normalise the tier values and give every row a real value
update public.members set tier = 'general' where tier is null or btrim(tier) = '';

alter table public.members alter column tier set default 'general';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'members_tier_check' and conrelid = 'public.members'::regclass
  ) then
    alter table public.members
      add constraint members_tier_check check (tier in ('executive', 'general'));
  end if;
end $$;

create index if not exists members_tier_idx on public.members (tier, sort_order, name);

-- ----------------------------------------------------------------------------
-- 2. supporter_donations — "Donation from others"
-- ----------------------------------------------------------------------------
create table if not exists public.supporter_donations (
  id           uuid primary key default gen_random_uuid(),
  donor_name   text,
  amount       numeric(12,2) not null default 0 check (amount >= 0),
  date         date not null default current_date,
  note         text,
  is_anonymous boolean not null default false,
  created_at   timestamptz not null default now()
);

-- keep the app's "id defaults to a uuid" guarantee on older installs
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supporter_donations'
      and column_name = 'id'
      and column_default is null
  ) then
    execute 'alter table public.supporter_donations alter column id set default gen_random_uuid()';
  end if;
end $$;

create index if not exists supporter_donations_date_idx   on public.supporter_donations (date desc);
create index if not exists supporter_donations_amount_idx on public.supporter_donations (amount desc);

-- ----------------------------------------------------------------------------
-- 3. Backfill — the eight leadership seats
--    Names must match the members table exactly; extra/missing names are fine,
--    the update simply touches the rows it finds.
-- ----------------------------------------------------------------------------
update public.members set tier = 'executive',
       role_title = 'President',           sort_order = 1, is_active = true
 where name = 'Abdullah H. Kafi';

update public.members set tier = 'executive',
       role_title = 'Vice President',      sort_order = 2, is_active = true
 where name = 'Junaed Hossain Toni';

update public.members set tier = 'executive',
       role_title = 'General Secretary',   sort_order = 3, is_active = true
 where name = 'Imtiaj Ahmed Rafi';

update public.members set tier = 'executive',
       role_title = 'Joint Secretary',     sort_order = 4, is_active = true
 where name = 'Kamrul H. Rafi';

update public.members set tier = 'executive',
       role_title = 'Treasurer',           sort_order = 5, is_active = true
 where name = 'Khaled Mahmud';

update public.members set tier = 'executive',
       role_title = 'Organizing Secretary', sort_order = 6, is_active = true
 where name = 'Afrahul Haque Orko';

update public.members set tier = 'executive',
       role_title = 'Office Secretary',    sort_order = 7, is_active = true
 where name = 'Istique Ahmed Chomok';

update public.members set tier = 'executive',
       role_title = 'Publicity Secretary', sort_order = 8, is_active = true
 where name = 'Sabbir Hossain';

-- everyone else is a general member, with a tidy default seat label
update public.members
   set tier = 'general'
 where tier is null or btrim(tier) = '';

update public.members
   set role_title = 'General Member'
 where tier = 'general' and (role_title is null or btrim(role_title) = '');

-- ----------------------------------------------------------------------------
-- 3b. Name fix — Mehedi Hasan Saikot (the register spelling)
-- ----------------------------------------------------------------------------
update public.members
   set name = 'Mehedi Hasan Saikot'
 where name in ('Mehedi Hasan Saikat', 'Mehedi Hasan Saikat ', 'Mehedi hasan saikot');

-- ----------------------------------------------------------------------------
-- 3c. Optional fresh-install roster (ONLY runs when members is empty)
--     Delete this block if you do not want the roster pre-created.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.members) then
    insert into public.members (name, tier, role_title, sort_order) values
      ('Abdullah H. Kafi',      'executive', 'President',            1),
      ('Junaed Hossain Toni',   'executive', 'Vice President',       2),
      ('Imtiaj Ahmed Rafi',     'executive', 'General Secretary',    3),
      ('Kamrul H. Rafi',        'executive', 'Joint Secretary',      4),
      ('Khaled Mahmud',         'executive', 'Treasurer',            5),
      ('Afrahul Haque Orko',    'executive', 'Organizing Secretary', 6),
      ('Istique Ahmed Chomok',  'executive', 'Office Secretary',     7),
      ('Sabbir Hossain',        'executive', 'Publicity Secretary',  8),
      ('Mehedi Hasan Saikot',   'general',   'General Member',       9);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 4. Row Level Security
--    read  -> any signed-in user
--    write -> admin Gmail only (public.is_admin())
-- ----------------------------------------------------------------------------
alter table public.members             enable row level security;
alter table public.supporter_donations enable row level security;

alter table public.members             force row level security;
alter table public.supporter_donations force row level security;

-- anonymous (signed-out) can never write, even if a policy is misconfigured
revoke insert, update, delete, truncate on public.supporter_donations from anon;
revoke insert, update, delete, truncate on public.members             from anon;

grant select on public.supporter_donations to authenticated;
grant insert, update, delete on public.supporter_donations to authenticated;
grant select on public.members to authenticated;

-- policies: members (re-created with the tier-aware names)
drop policy if exists "members_select_authenticated" on public.members;
create policy "members_select_authenticated"
  on public.members for select to authenticated using (true);

drop policy if exists "members_insert_admin" on public.members;
create policy "members_insert_admin"
  on public.members for insert to authenticated
  with check (public.is_admin());

drop policy if exists "members_update_admin" on public.members;
create policy "members_update_admin"
  on public.members for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "members_delete_admin" on public.members;
create policy "members_delete_admin"
  on public.members for delete to authenticated
  using (public.is_admin());

-- policies: supporter_donations
drop policy if exists "supporter_donations_select_authenticated" on public.supporter_donations;
create policy "supporter_donations_select_authenticated"
  on public.supporter_donations for select to authenticated using (true);

drop policy if exists "supporter_donations_insert_admin" on public.supporter_donations;
create policy "supporter_donations_insert_admin"
  on public.supporter_donations for insert to authenticated
  with check (public.is_admin());

drop policy if exists "supporter_donations_update_admin" on public.supporter_donations;
create policy "supporter_donations_update_admin"
  on public.supporter_donations for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "supporter_donations_delete_admin" on public.supporter_donations;
create policy "supporter_donations_delete_admin"
  on public.supporter_donations for delete to authenticated
  using (public.is_admin());

-- ----------------------------------------------------------------------------
-- 5. Realtime (used by the live Members / fee-report refresh)
-- ----------------------------------------------------------------------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.supporter_donations;
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table public.members;
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table public.payments;
  exception when others then null;
  end;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Checks
--    select tier, count(*) from public.members group by tier;
--    select name, role_title, sort_order from public.members
--      where tier = 'executive' order by sort_order;
--    select coalesce(nullif(donor_name,''),'Anonymous') as supporter,
--           amount, date, is_anonymous from public.supporter_donations
--      order by date desc;
-- ----------------------------------------------------------------------------
