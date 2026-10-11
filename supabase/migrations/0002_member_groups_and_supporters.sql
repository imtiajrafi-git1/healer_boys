-- Healer Boys: member groups and donation supporter metadata.
-- Safe to run after the original members/payments/donations tables exist.

alter table public.members
  add column if not exists member_type text not null default 'general'
    check (member_type in ('executive', 'general'));

alter table public.members
  add column if not exists profile text not null default '';

alter table public.donations
  add column if not exists supporter_name text;

alter table public.donations
  add column if not exists is_anonymous boolean not null default true;

-- The canonical seed has eight executives; Mehedi Hasan Saikot is general.
update public.members
set member_type = case
  when name in (
    'Abdullah H. Kafi', 'Afrahul Haque Orko', 'Imtiaj Ahmed Rafi',
    'Istique Ahmed Chomok', 'Junaed Hossain Toni', 'Kamrul H. Rafi',
    'Khaled Mahmud', 'Sabbir Hossain'
  ) then 'executive'
  else 'general'
end;

create index if not exists members_member_type_idx on public.members (member_type);
create index if not exists donations_supporter_idx on public.donations (is_anonymous, supporter_name);

comment on column public.members.member_type is 'UI group: executive or general';
comment on column public.donations.is_anonymous is 'Whether supporter identity is hidden in the public card';
