-- 0008_member_types_and_designations.sql
-- Healer Boys: member types (permanent/temporary), executive tiers (general/executive), and dynamic designations.

alter table public.members
  add column if not exists member_kind text not null default 'permanent'
    check (member_kind in ('permanent', 'temporary')),
  add column if not exists executive_tier text not null default 'general'
    check (executive_tier in ('general', 'executive')),
  add column if not exists designation text,
  add column if not exists sort_order integer not null default 0;

-- Backfill executive_tier from legacy member_type column if present
update public.members
set executive_tier = case
  when member_type = 'executive' then 'executive'
  else 'general'
end
where executive_tier is null or executive_tier = 'general';

-- Seed the initial executive leadership committee requested by the team
update public.members set executive_tier = 'executive', designation = 'President', sort_order = 1 where name ilike '%K%H%Rafi%' or name ilike '%Kamrul%Rafi%';
update public.members set executive_tier = 'executive', designation = 'General Secretary', sort_order = 2 where name ilike '%Khaled%Mahmud%';
update public.members set executive_tier = 'executive', designation = 'Financial Advisor', sort_order = 3 where name ilike '%Junaed%' or name ilike '%Junayed%';
update public.members set executive_tier = 'executive', designation = 'FA', sort_order = 4 where name ilike '%Istique%';
update public.members set executive_tier = 'executive', designation = 'Accountant', sort_order = 5 where name ilike '%Imtiaj%';
update public.members set executive_tier = 'executive', designation = 'Membership Advisor', sort_order = 6 where name ilike '%Sabbir%';
update public.members set executive_tier = 'executive', designation = 'MA', sort_order = 7 where name ilike '%Kafi%';

create index if not exists members_member_kind_tier_idx on public.members (member_kind, executive_tier, sort_order);
