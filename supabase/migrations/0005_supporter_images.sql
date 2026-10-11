-- Add optional supporter photos for the Members > Donation From Others flow.
-- Safe to run repeatedly on existing installations.
alter table public.donations add column if not exists image_url text;

-- Keep uploads bounded when a hosted URL or compressed data URL is supplied.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.donations'::regclass
      and conname = 'donations_image_url_length_check'
  ) then
    alter table public.donations
      add constraint donations_image_url_length_check
      check (image_url is null or length(image_url) <= 200000);
  end if;
end $$;
