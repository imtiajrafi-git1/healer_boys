-- Donation From Others has its own dataset. It must never share totals or
-- rows with the main Donations screen.
create table if not exists public.supporter_donations (
  id uuid primary key default gen_random_uuid(),
  donor_name text,
  is_anonymous boolean not null default true,
  amount numeric(12,2) not null check (amount >= 0),
  note text not null check (length(trim(note)) > 0),
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint supporter_donations_image_url_length_check check (image_url is null or length(image_url) <= 200000)
);

create index if not exists supporter_donations_created_at_idx on public.supporter_donations (created_at desc);

drop trigger if exists supporter_donations_touch on public.supporter_donations;
create trigger supporter_donations_touch before update on public.supporter_donations
for each row execute function public.touch_updated_at();

alter table public.supporter_donations enable row level security;
drop policy if exists supporter_donations_public_select on public.supporter_donations;
create policy supporter_donations_public_select on public.supporter_donations
for select to anon, authenticated using (true);
drop policy if exists supporter_donations_insert_admin on public.supporter_donations;
create policy supporter_donations_insert_admin on public.supporter_donations
for insert to authenticated with check (public.is_admin());
drop policy if exists supporter_donations_update_admin on public.supporter_donations;
create policy supporter_donations_update_admin on public.supporter_donations
for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists supporter_donations_delete_admin on public.supporter_donations;
create policy supporter_donations_delete_admin on public.supporter_donations
for delete to authenticated using (public.is_admin());
