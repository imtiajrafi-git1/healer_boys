-- Each row is one monthly contribution. The same supporter may have many rows.
alter table public.supporter_donations
  add column if not exists donation_month date;

update public.supporter_donations
set donation_month = coalesce(donation_month, created_at::date);

alter table public.supporter_donations
  alter column donation_month set default current_date,
  alter column donation_month set not null;

create index if not exists supporter_donations_donor_month_idx
  on public.supporter_donations (donor_name, donation_month desc);
