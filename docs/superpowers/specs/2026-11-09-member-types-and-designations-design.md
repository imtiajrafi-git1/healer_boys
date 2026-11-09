# Member Types, Executive Roles & Dynamic Designations Design Spec

**Date:** 2026-11-09  
**Status:** Approved  
**Author:** Pair Programming Agent & User  
**Target Subsystems:** Database schema, Member API (`src/lib/membersApi.js`), Application Frontend (`index.html`), Styles (`members.css`)

---

## 1. Problem Statement & Motivation

The Healer Boys application currently tracks members across fragmented tables (`executive_members`, `general_members`, legacy `members`, and `supporter_donations`), making it cumbersome to reassign members between roles and causing schema-cache desync errors.

Furthermore, the organization needs clear structural separation between:
1. **Permanent Members:** Community members with recurring monthly payment obligations and due tracking.
   - **General Members:** The default group for permanent members.
   - **Executive Members:** Selected leadership members promoted from the permanent members, holding dynamic official designations (e.g., President, General Secretary).
   - **Mutual Exclusivity:** A permanent member belongs strictly to either General or Executive at any given time—never both.
2. **Temporary Members:** Voluntary supporters in the "Donation From Others" section who contribute arbitrary donation amounts at any time, with zero monthly dues or fee requirements.

---

## 2. Architecture & Data Model

### 2.1 Unified Member Model (`public.members`)
All individuals are maintained in a single primary `members` table to ensure unbroken transaction history and stable foreign keys:

```sql
alter table public.members
  add column if not exists member_kind text not null default 'permanent'
    check (member_kind in ('permanent', 'temporary')),
  add column if not exists executive_tier text not null default 'general'
    check (executive_tier in ('general', 'executive')),
  add column if not exists designation text,
  add column if not exists sort_order integer not null default 0;

create index if not exists members_member_kind_tier_idx 
  on public.members (member_kind, executive_tier, sort_order);
```

### 2.2 Member Type Definitions

| Attribute | Permanent: General | Permanent: Executive | Temporary Member |
| :--- | :--- | :--- | :--- |
| **`member_kind`** | `'permanent'` | `'permanent'` | `'temporary'` |
| **`executive_tier`** | `'general'` | `'executive'` | `'general'` |
| **`designation`** | `null` (or "General Member") | Official title (e.g., "President") | `null` |
| **Monthly Fee & Dues** | Yes (Standard 150 BDT, Paid/Due) | Yes (Standard 150 BDT, Paid/Due) | **No dues ever calculated (0 BDT)** |
| **Payment Storage** | `public.payments` | `public.payments` | `public.supporter_donations` |
| **UI Location** | "General Members" card | "Executive Members" card | "Donation From Others" card |

### 2.3 Dynamic Designations Management
Designations are dynamically configurable by administrators. The system seeds the initial leadership roles provided by the user:

1. **K H Rafi** — `President` (sort_order: 1)
2. **Khaleda Mahmud** — `General Secretary` (sort_order: 2)
3. **Junayed** — `Financial Advisor` (sort_order: 3)
4. **Istique** — `FA` (sort_order: 4)
5. **Imtiaj** — `Accountant` (sort_order: 5)
6. **Sabbir Hossen** — `Membership Advisor` (sort_order: 6)
7. **A. H. Kafi** — `MA` (sort_order: 7)

Admin UI provides a dropdown of these standard designations plus an *"Enter custom designation..."* text input for dynamic role creation.

---

## 3. UI/UX Workflows (Preserving App Visual Identity)

The UI maintains strict aesthetic consistency with `cards.css`, `glass.css`, and `members.css` (lavender glass background, 20px border radius, Plus Jakarta Sans typography, and native sheet modals).

### 3.1 Members Hub Screen
- **Executive Members Card (Purple gradient):** Displays count of active executive members and CTA to view leadership.
- **General Members Card (Blue gradient):** Displays count of regular permanent members.
- **Donation From Others Card (Teal/Emerald gradient):** Displays count of temporary supporters and aggregate voluntary fund.

### 3.2 Executive Promotion & Demotion Flow
- **Promotion (Admin):**
  1. On the Executive Members view, the admin clicks `+ Add Executive`.
  2. A glass bottom sheet appears with a search/dropdown of existing **General Members**.
  3. Admin selects a member and picks or enters a **Designation**.
  4. Upon saving, `executive_tier` is set to `'executive'` and `designation` is saved.
  5. The member is immediately moved from the General view into Executive view.
- **Demotion / Step Down:**
  1. Inside the member's profile, the admin can click "Step Down to General" or switch the tier toggle.
  2. `executive_tier` becomes `'general'` and `designation` is cleared.
  3. The member immediately reappears in General Members. All past payments, dates, dues, and transaction IDs remain 100% intact.

### 3.3 Temporary Members Management ("Donation From Others")
- **Listing:** Displays cards for all temporary members with total contributions, donation count, and last active date.
- **Member Detail:**
  - Header displays avatar, name, and badge `Temporary Member · Voluntary Supporter`.
  - **Dues Block is Hidden:** No monthly fees, no overdue alerts, no due calculations.
  - **Contribution Summary:** Total Donated, Number of Gifts, and chronological list of donations.
  - **Admin Action:** `+ Add Donation` button inside the profile pre-fills their donor record for instant entry.
- **Add Temporary Member:** Modal sheet with Name, optional Phone/Note, optional Initial Donation Amount, and optional photo.

---

## 4. Error Handling & Offline Resilience

1. **Schema Tolerance:** `membersApi.js` checks for missing columns and provides graceful backward-compatibility fallbacks without crashing the app.
2. **Local Storage Synchronization:** `localStorage` (`LS_DATA`) maintains mirror copies so offline navigation and instant paints work without latency.
3. **Data Integrity:** Because member records use a unified table, promotion/demotion requires zero row deletions or payment table foreign-key updates.

---

## 5. Verification & Testing Criteria

1. **Mutual Exclusivity:** Verifying that a member promoting to Executive disappears from General, and demoting returns them to General.
2. **Dues Verification:**
   - Permanent (General & Executive) calculate dues correctly based on standard monthly fee (150 BDT).
   - Temporary members strictly show `due = 0`, `due_months = 0`, and no due warnings.
3. **Designations:** Verifying that K H Rafi, Khaleda Mahmud, Junayed, Istique, Imtiaj, Sabbir Hossen, and A. H. Kafi are properly seeded and editable.
4. **Visual Consistency:** Ensuring all new sheets, inputs, and cards strictly match the existing CSS tokens.
