-- Idempotent seed for the normalized Members experience.
insert into public.executive_members
  (name, position, contribution, monthly_status, due_amount, due_months, sort_order)
values
  ('Abdullah H. Kafi', null, 4800, 'paid', 0, 0, 1),
  ('Afrahul Haque Orko', null, 1510, 'paid', 0, 0, 2),
  ('Imtiaj Ahmed Rafi', null, 1500, 'paid', 0, 0, 3),
  ('Istique Ahmed Chomok', null, 700, 'paid', 0, 0, 4),
  ('Junaed Hossain Toni', null, 5550, 'paid', 0, 0, 5),
  ('Kamrul H. Rafi', null, 3750, 'paid', 0, 0, 6),
  ('Khaled Mahmud', null, 4050, 'paid', 0, 0, 7),
  ('Sabbir Hossain', null, 4800, 'paid', 0, 0, 8)
on conflict (name) do update set
  contribution = excluded.contribution,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.general_members
  (name, email, photo_url, profile, legacy_data, payment_total, payment_count, monthly_fee, last_payment_date)
values
  ('Mehedi Hasan Saikot', 'mehedi.hasan.saikot@gmail.com', null, 'General member', '{"legacy_id":"mem_8","start":{"y":2025,"m":12},"count":5,"fee":100}'::jsonb, 500, 5, 100, '2026-04-05')
on conflict (name) do update set
  email = excluded.email,
  profile = excluded.profile,
  payment_total = excluded.payment_total,
  payment_count = excluded.payment_count,
  monthly_fee = excluded.monthly_fee,
  last_payment_date = excluded.last_payment_date,
  legacy_data = excluded.legacy_data,
  updated_at = now();

insert into public.donations (donor_name, is_anonymous, amount, note, created_at)
values
  (null, true, 2000, 'হরিপুরের প্রতিবন্ধী শিশুকে সাহায্য', '2026-01-22T00:00:00Z'),
  (null, true, 2000, 'নিশ্চিন্তপুর এর ফয়েজ কে চিকিৎসার জন্য সাহায্য', '2025-12-13T00:00:00Z'),
  (null, true, 2000, 'হীরাপুর জিহাদের গাড়ি এক্সিডেন্টে সাহায্য', '2025-11-18T00:00:00Z'),
  (null, true, 1000, 'প্রাথমিক ত্রাণ ও সহায়তা', '2024-11-11T00:00:00Z')
on conflict (note) do update set
  amount = excluded.amount,
  updated_at = now();
