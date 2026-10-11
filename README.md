# Healer Boy's — Fund Tracker

A single-file mobile web app (PWA) for the **Healer Boy's** club fund: member register,
monthly fees, dues, donations and the money the club gives back to people.

Everything lives in `index.html` (markup + all app logic). Styling is split into small
CSS files, and the database side lives in `supabase/` plus the paste-and-run SQL files
at the repository root.

---

## 1. Branding — the "Boy's - Boys" rule

| Where | Spelling | Example |
| --- | --- | --- |
| The club's **name** (a possessive) | `Healer Boy's` | title, headers, navbar label, footer, PWA manifest, receipts, reminder emails |
| The **plural noun** (the group of boys, not the name) | `Healer Boys` | "Healer Boys members", "the Healer Boys" |

Never "Healer Boys's" and never "Healer Boy's members".

In code use the constants instead of typing the name:

```js
const BRAND = "Healer Boy's";        // titles, headers, footers, metadata, PDFs, emails
const BRAND_PLURAL = "Healer Boys";  // plural noun phrases
```

The rule is applied in: `<title>`, meta/OG tags, the PWA manifest (`name`, `short_name`,
`description`), the login screen, the Home greeting, the Members register header, the
Donations screen, the Profile footer, the PDF receipt, the EmailJS/Edge-Function
reminder subject and body, and the Google-Sheet sync acknowledgement.

Internal identifiers keep their old spelling on purpose (cron job `healer-boys-daily-reminders`,
Supabase channel `healer-fee-report-live`, the Gmail address `yourhealerboys@gmail.com`)
— renaming those would break existing schedules, subscriptions and logins.

---

## 2. Members register (Members tab)

The Members screen is the dark-violet "register" skin (`members-premium.css`); every other
screen keeps the light lavender liquid-glass look. Three registers, top to bottom:

1. **Executive Members** — the leadership board. Each card carries the gold crown badge,
   its seat name (President, Vice President, General Secretary, Joint Secretary,
   Treasurer, Organizing Secretary, Office Secretary, Publicity Secretary), the
   membership counter, and paid/due tags (`Total paid`, `n fees`, `All cleared` / `Due …`).
2. **General Members** — the regular list with a per-row membership tag, fee counter,
   total paid and a paid/due pill.
3. **Donation from others** — the supporters who gave TO the club, with the total
   supporter amount, the year-to-date figure, named cards and dashed *anonymous* cards.

Hero card at the top totals members, executives, general members, paid, dues pending and
active counts. Search covers members *and* supporters; the sort button cycles
*top payer → highest due → A–Z*; the filter chips switch *All / Paid / Due*.

The eight executive seats and the seat order are defined once, in `EXEC_SEATS`
(`index.html`) and mirrored by the SQL backfill, so the leadership board always shows
the same 8 people in the same order.

---

## 3. Admin system

Sign in on the login screen with the admin Gmail + password (`ADMIN_EMAIL` /
`ADMIN_PASSWORD` in `index.html`). Admin-only powers, all live in the UI:

| Action | Where |
| --- | --- |
| Add executive / general member | **+ Add executive member** / **+ Add general member**, or the floating **+ Add member** button |
| Add supporter donation (`Donation from others`) | **+ Add supporter donation** |
| Edit a member (name, tier, seat, phone, e-mail, photo, display order) | `⋯` on any card → *Edit details & photo* |
| Promote / demote between executive and general | `⋯` → *Promote to executive* / *Move to general members* |
| Delete a member (and their payment rows) | `⋯` → *Delete member* (confirmation first) |
| Edit / delete a supporter donation | `⋯` on a supporter card |
| Add / edit / delete a donation the club gave away | Donations screen → **Add** / pencil / trash |
| Add a payment, delete a payment, send reminders | Member detail screen |
| Sync anything saved locally up to Supabase | Profile → **Sync register to Supabase** |

Viewers (signed in through the Google button, which runs in viewer mode on this project)
see the same registers read-only: no add buttons, no `⋯` controls. The real gate is RLS —
see below.

---

## 4. Supabase setup

1. **Schema + policies** — run, in the Supabase SQL editor, in this order:

   | # | File | What it does |
   | --- | --- | --- |
   | 1 | `supabase_policies.sql` | `public.is_admin()`, RLS on/for the four app tables, admin-only writes |
   | 2 | `upgrade-members-and-supporters.sql` | member tiers/seats (`tier`, `role_title`, `phone`, `sort_order`, `is_active`, `joined_at`), the `supporter_donations` table, backfill of the 8 executive seats, the `Mehedi Hasan Saikot` name fix, RLS for the new table, Realtime |
   | 3 | `supabase/migrations/0001_app_settings_and_cron.sql` | `app_settings` row + daily reminder cron |

   `upgrade-members-and-supporters.sql` is byte-for-byte the paste-and-run copy of
   `supabase/migrations/0002_member_tiers_and_supporters.sql` (use whichever fits your
   workflow — SQL editor or `supabase db push`). Both are idempotent: re-running is safe.

   > Running the migration is optional for the app to work — see "Schema drift" below —
   > but it is required for supporter donations to be shared across devices.

2. **Tables**

   | Table | Purpose |
   | --- | --- |
   | `members` | one row per member: `id`, `name`, `email`, `avatar_url`, `tier` (`executive`/`general`), `role_title` (seat), `phone`, `sort_order`, `is_active`, `joined_at` |
   | `payments` | fees collected: `id`, `member_id`, `amount`, `date`, `type` (e.g. `Monthly Fee (October 2026)`) |
   | `donations` | money the club **gave away**: `id`, `description`, `date`, `amount` |
   | `supporter_donations` | **Donation from others**: `id`, `donor_name` (null = anonymous), `amount`, `date`, `note`, `is_anonymous` |
   | `app_settings` | single row: reminder toggle, send day, bKash/Nagad numbers, last-sent info |

3. **RLS matrix** (`supabase_policies.sql` + migration 0002)

   | Role | members | payments | donations | supporter_donations | app_settings |
   | --- | --- | --- | --- | --- | --- |
   | `anon` (signed out) | — | — | — | — | — |
   | `authenticated` (viewer) | select | select | select | select | select |
   | admin Gmail | full | full | full | full | update |

   Writes are checked with `public.is_admin()`, which compares
   `auth.jwt() -›› 'email'` with the admin Gmail. Keep the frontend `ADMIN_EMAIL`
   constant in sync with the address inside `is_admin()`.

4. **Frontend config** (top of the `<script>` in `index.html`):
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`,
   `EMAILJS_*`, `IMGBB_KEY`, `SHEET_WEBHOOK_URL`.

5. **Realtime** — the register, the live fee report and the Home hero refresh on
   `postgres_changes` for `members`, `payments` and `supporter_donations`
   (plus a polling fallback). The migration adds the tables to the
   `supabase_realtime` publication.

6. **Reminder job** — `supabase/functions/send-reminders` + the cron entry in
   migration `0001`.

### Schema drift — why inserts never fail

`index.html` probes each optional column/table once (`probeCapabilities()`), caches the
result in `CAPS`, and the write helpers (`sbInsertOne` / `sbUpdateOne`) retry without
anything the database does not have yet:

* a `uuid` primary key rejects an app-generated `mem_x` id → the row is re-inserted and
  the server id is used;
* a pending migration (no `tier`, `role_title`, `phone`, `is_active`, `sort_order`, no
  `supporter_donations`) → those fields are dropped for that session, the capability flag
  is turned off, and the register still renders because tiers fall back to the built-in
  seat map (`EXEC_SEATS`);
* Row-Level-Security / permission errors surface as a friendly
  "sign in with the admin Gmail" toast instead of a raw Postgres message;
* supporters saved before the migration are kept in `localStorage` and can be uploaded
  later from **Profile → Sync register to Supabase** (`db.pushLocalRegister()`).

Demo mode (no Supabase keys, or offline) seeds a full roster in `localStorage`:
8 executives with their seats, general members (Mehedi Hasan Saikot included) with
payment history, the donations given away, and 5 supporter donations. That seed data is
demo/offline only — live mode always reads what is in Supabase.

---

## 5. Files

| File | Role |
| --- | --- |
| `index.html` | the whole app: markup, screens, router, data access, admin sheets, PDF receipt |
| `members.css` | light Members skin (still used by the member-detail pieces) |
| `members-premium.css` | **new** — dark violet Members register: hero, executive/general/supporter cards, manage sheets, dark bottom nav |
| `glass.css`, `cards.css`, `home.css`, `payment.css`, `report.css`, `bottom-nav.css` | screen-level styling |
| `supabase_policies.sql` | RLS + `is_admin()` |
| `supabase/migrations/0002_member_tiers_and_supporters.sql` | tiers, seats, `supporter_donations`, backfill, RLS, realtime |
| `upgrade-members-and-supporters.sql` | paste-and-run copy of the migration above |
| `fix-members-payments.sql`, `supabase/migrations/0001_…`, `supabase/functions/send-reminders`, `supabase/config.toml` | earlier fixes, settings/cron, e-mail job |
| `google-apps-script.gs`, `useCopy.js` | optional Sheets mirror + the copy helper the app mirrors |

---

## 6. Fund maths

```
fund = fees collected (payments) + support from others (supporter_donations)
       − donations given away (donations)
```

Home shows the net balance with that formula under the *Total Fund* title; the monthly
trend uses the same rule. Supporter donations therefore raise the fund, which is why
they are stored separately from the `donations` table.
