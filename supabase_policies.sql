-- ============================================================================
-- supabase_policies.sql  —  Healer Boy's
-- Replaces the previous "anon full access" policies.
--
-- RULES
--   * SELECT  -> any authenticated user (Google viewers + admin)
--   * INSERT / UPDATE / DELETE -> only the fixed admin Gmail
--   * anon (signed-out) gets nothing.
--
-- Fixed admin Gmail: yourhealerboys@gmail.com
-- The frontend ADMIN_EMAIL must match this value. Every write policy below
-- calls public.is_admin(), so this is the one RLS identity check to maintain.
--
-- The frontend also has an ADMIN_EMAIL constant — set it to the same address
-- so the UI can show/hide admin controls. RLS stays the real security layer.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Helper: is the current request from the admin account?
--    SECURITY DEFINER so the check is stable and never recursive on RLS.
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
-- 1. Remove every existing policy on the app tables (including the old
--    anon full-access ones). Names do not need to be known in advance.
-- ----------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('members', 'payments', 'donations', 'app_settings')
  loop
    execute format('drop policy if exists %I on %I.%I;', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Enable RLS everywhere
-- ----------------------------------------------------------------------------
alter table public.members    enable row level security;
alter table public.payments   enable row level security;
alter table public.donations  enable row level security;
alter table public.app_settings enable row level security;

-- force RLS even for the table owner (defence in depth)
alter table public.members      force row level security;
alter table public.payments     force row level security;
alter table public.donations    force row level security;
alter table public.app_settings force row level security;

-- ----------------------------------------------------------------------------
-- 3. Hardening: the anonymous role can never write, even if RLS is bypassed
-- ----------------------------------------------------------------------------
revoke insert, update, delete, truncate on public.members   from anon;
revoke insert, update, delete, truncate on public.payments  from anon;
revoke insert, update, delete, truncate on public.donations from anon;
revoke insert, update, delete, truncate on public.app_settings from anon;

-- ----------------------------------------------------------------------------
-- 4. SELECT — every signed-in user (Google viewer or admin)
-- ----------------------------------------------------------------------------
create policy "members_select_authenticated"
  on public.members for select to authenticated using (true);

create policy "payments_select_authenticated"
  on public.payments for select to authenticated using (true);

create policy "donations_select_authenticated"
  on public.donations for select to authenticated using (true);

create policy "app_settings_select_authenticated"
  on public.app_settings for select to authenticated using (true);

-- ----------------------------------------------------------------------------
-- 5. INSERT — admin only
-- ----------------------------------------------------------------------------
create policy "members_insert_admin"
  on public.members for insert to authenticated
  with check (public.is_admin());

create policy "payments_insert_admin"
  on public.payments for insert to authenticated
  with check (public.is_admin());

create policy "donations_insert_admin"
  on public.donations for insert to authenticated
  with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 6. UPDATE — admin only
-- ----------------------------------------------------------------------------
create policy "members_update_admin"
  on public.members for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "payments_update_admin"
  on public.payments for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "donations_update_admin"
  on public.donations for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- app_settings: only the admin may change the reminder settings
create policy "app_settings_update_admin"
  on public.app_settings for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 7. DELETE — admin only
-- ----------------------------------------------------------------------------
create policy "members_delete_admin"
  on public.members for delete to authenticated
  using (public.is_admin());

create policy "payments_delete_admin"
  on public.payments for delete to authenticated
  using (public.is_admin());

create policy "donations_delete_admin"
  on public.donations for delete to authenticated
  using (public.is_admin());

-- ----------------------------------------------------------------------------
-- 8. Optional: member email addresses (used by the reminder job).
--    Skip this block if you already store emails somewhere else.
-- ----------------------------------------------------------------------------
-- alter table public.members add column if not exists email text;

-- ----------------------------------------------------------------------------
-- 9. Optional: index that makes the "who owes what" query fast
-- ----------------------------------------------------------------------------
create index if not exists payments_member_id_idx on public.payments (member_id);
create index if not exists payments_date_idx      on public.payments (date);
create index if not exists donations_date_idx     on public.donations (date desc);
