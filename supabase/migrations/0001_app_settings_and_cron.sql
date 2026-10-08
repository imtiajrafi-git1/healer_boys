-- ============================================================================
-- 0001_app_settings_and_cron.sql  —  Healer Boy's
-- Settings row for the reminder job + the daily cron schedule.
-- Run this AFTER supabase_policies.sql.
--
-- REPLACE: <PROJECT_REF> and <SERVICE_ROLE_KEY> in step 3.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Settings table (single row, id = 1)
-- ----------------------------------------------------------------------------
create table if not exists public.app_settings (
  id                  int primary key default 1 check (id = 1),
  auto_email_reminder boolean not null default true,
  send_day            int    not null default 5 check (send_day between 1 and 28),
  channel             text   not null default 'Email',
  bkash_number        text   not null default '',
  nagad_number        text   not null default '',
  last_sent_at        timestamptz,
  last_sent_count     int    not null default 0,
  updated_at          timestamptz not null default now()
);

insert into public.app_settings (id, auto_email_reminder, send_day, channel, bkash_number, nagad_number)
values (1, true, 5, 'Email', '', '')
on conflict (id) do nothing;

-- keep updated_at fresh
create or replace function public.touch_app_settings()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists app_settings_touch on public.app_settings;
create trigger app_settings_touch
  before update on public.app_settings
  for each row execute function public.touch_app_settings();

-- ----------------------------------------------------------------------------
-- 2. Enable the extensions we need
--    pg_cron = scheduler, pg_net = async HTTP out of the database
-- ----------------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ----------------------------------------------------------------------------
-- 3. Daily schedule. The Edge Function itself decides whether today is
--    day 5 (Asia/Dhaka) and whether auto_email_reminder is on, so the cron
--    simply fires once every morning at 06:00 UTC.
-- ----------------------------------------------------------------------------
select cron.schedule(
  'healer-boys-daily-reminders',
  '0 6 * * *',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
    ),
    body    := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 60000
  );
  $$
);

-- ----------------------------------------------------------------------------
-- 4. Useful checks
--    select * from cron.job;                -- see the scheduled job
--    select * from cron.job_run_details
--      order by start_time desc limit 10;   -- see recent runs
--    select * from public.app_settings;     -- last_sent_at / last_sent_count
--
-- To unschedule:
--    select cron.unschedule('healer-boys-daily-reminders');
-- ----------------------------------------------------------------------------
