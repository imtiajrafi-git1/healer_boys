-- Healer Boys normalized member model. Safe to run after 0001/0002.
create extension if not exists pgcrypto;

create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (position('@' in email) > 1),
  created_at timestamptz not null default now()
);
insert into public.admins (email) values ('yourhealerboys@gmail.com') on conflict (email) do nothing;

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

-- Fresh installations get the normalized table. Existing installations keep
-- description/date legacy columns so the payment and report screens continue.
create table if not exists public.donations (
  id uuid primary key default gen_random_uuid(),
  donor_name text,
  is_anonymous boolean not null default true,
  amount numeric(12,2) not null check (amount >= 0),
  note text not null check (length(trim(note)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Existing installations already have donations. Add normalized fields without
-- dropping description/date/legacy payment data used by the current reports.
alter table public.donations add column if not exists donor_name text;
alter table public.donations add column if not exists note text;
alter table public.donations add column if not exists created_at timestamptz not null default now();
alter table public.donations add column if not exists updated_at timestamptz not null default now();
update public.donations set note = coalesce(note, description, 'Donation') where note is null;

create index if not exists executive_members_sort_idx on public.executive_members (sort_order, name);
create index if not exists general_members_name_idx on public.general_members (name);
create index if not exists donations_created_at_idx on public.donations (created_at desc);
create unique index if not exists executive_members_name_uidx on public.executive_members (name);
create unique index if not exists general_members_name_uidx on public.general_members (name);
create unique index if not exists donations_note_uidx on public.donations (note);

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists executive_members_touch on public.executive_members;
create trigger executive_members_touch before update on public.executive_members for each row execute function public.touch_updated_at();
drop trigger if exists general_members_touch on public.general_members;
create trigger general_members_touch before update on public.general_members for each row execute function public.touch_updated_at();
drop trigger if exists donations_touch on public.donations;
create trigger donations_touch before update on public.donations for each row execute function public.touch_updated_at();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins a where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
grant execute on function public.is_admin() to anon, authenticated;

alter table public.admins enable row level security;
alter table public.executive_members enable row level security;
alter table public.general_members enable row level security;

drop policy if exists admins_select_authenticated on public.admins;
create policy admins_select_authenticated on public.admins for select to authenticated using (public.is_admin());

do $$ declare t text; begin
  foreach t in array array['executive_members','general_members'] loop
    execute format('drop policy if exists %I on public.%I', t || '_public_select', t);
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t || '_public_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin_insert', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.is_admin())', t || '_admin_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin_update', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.is_admin()) with check (public.is_admin())', t || '_admin_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin_delete', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.is_admin())', t || '_admin_delete', t);
  end loop;
end $$;

-- Normalize donation access for both old and new clients.
drop policy if exists donations_public_select on public.donations;
create policy donations_public_select on public.donations for select to anon, authenticated using (true);
drop policy if exists donations_insert_admin on public.donations;
create policy donations_insert_admin on public.donations for insert to authenticated with check (public.is_admin());
drop policy if exists donations_update_admin on public.donations;
create policy donations_update_admin on public.donations for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists donations_delete_admin on public.donations;
create policy donations_delete_admin on public.donations for delete to authenticated using (public.is_admin());
