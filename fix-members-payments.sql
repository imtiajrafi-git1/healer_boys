-- ============================================================================
-- fix-members-payments.sql  —  Healer Boy's
-- Fixes the two admin-panel errors:
--   1) Could not find the 'email' column of 'members'
--   2) null value in column "id" of relation "payments"
-- Run this once in Supabase → SQL Editor.
-- Safe to re-run.
-- ============================================================================

-- 1) members.email  (used for reminders; may be null)
alter table public.members
  add column if not exists email text;

alter table public.members
  add column if not exists avatar_url text;

-- 2) members.id: always filled (the app sends its own id, but a default is safer)
--    Only needed if id is text and has no default.
--    If your members.id is already uuid with gen_random_uuid(), skip this block.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'members'
      and column_name  = 'id'
      and data_type in ('text', 'character varying')
      and column_default is null
  ) then
    execute 'alter table public.members alter column id set default gen_random_uuid()::text';
  end if;
end $$;

-- 3) payments.id: the reported error — give it a default so inserts never send NULL.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'payments'
      and column_name  = 'id'
      and data_type in ('text', 'character varying')
      and column_default is null
  ) then
    execute 'alter table public.payments alter column id set default gen_random_uuid()::text';
  end if;
end $$;

-- 4) payments.id is uuid without a default? Then generate one.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'payments'
      and column_name  = 'id'
      and data_type = 'uuid'
      and column_default is null
  ) then
    execute 'alter table public.payments alter column id set default gen_random_uuid()';
  end if;
end $$;

-- 5) donations.id: same protection
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'donations'
      and column_name  = 'id'
      and column_default is null
  ) then
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name   = 'donations'
        and column_name  = 'id'
        and data_type = 'uuid'
    ) then
      execute 'alter table public.donations alter column id set default gen_random_uuid()';
    else
      execute 'alter table public.donations alter column id set default gen_random_uuid()::text';
    end if;
  end if;
end $$;

-- 6) indexes that make the fee report fast
create index if not exists payments_member_id_idx on public.payments (member_id);
create index if not exists payments_date_idx      on public.payments (date);
create index if not exists donations_date_idx     on public.donations (date desc);

-- ---------------------------------------------------------------------------
-- If Realtime was enabled for the live fee-report refresh, re-enable it here
-- (Supabase → Database → Replication) or run:
-- alter publication supabase_realtime add table public.members;
-- alter publication supabase_realtime add table public.payments;
-- ---------------------------------------------------------------------------
