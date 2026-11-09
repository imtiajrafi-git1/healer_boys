# Member Types, Executive Roles & Dynamic Designations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement two clear member categories (Permanent vs. Temporary), dynamic executive designations with the user's leadership committee, mutual exclusivity between General and Executive members, and dedicated profile-backed temporary members under "Donation From Others" with zero dues.

**Architecture:**
1. **Unified Schema & Database (`fix-supabase-schema.sql`):** Extend `public.members` with `member_kind` (`permanent` / `temporary`), `executive_tier` (`general` / `executive`), `designation`, and `sort_order`. Ensure non-breaking compatibility with existing payments, dues, and offline storage.
2. **API & Normalization Layer (`src/lib/membersApi.js`):** Support promotion/demotion payload updates, designation persistence, and temporary member registration with voluntary donations linking.
3. **Frontend State & Calculations (`index.html`):** Update `memberRows()`, `memberDues()`, `ScreenMemberOverview()`, and `ScreenMemberDetail()` so both General and Executive members calculate standard monthly dues (150 BDT), while Temporary members calculate 0 dues.
4. **Promotion & Dynamic Designations UI (`index.html` & `members.css`):** Add `+ Add Executive` picker on the Executive screen, dynamic designation select + custom input, promote/demote toggles in member edit sheets, and temporary member profiles under "Donation From Others".

**Tech Stack:** Vanilla JavaScript (ES6+), Supabase PostgREST, HTML5, CSS3 with existing design tokens (`glass.css`, `members.css`, `cards.css`).

## Global Constraints
- Strictly maintain current visual identity: glassmorphic lavender theme, 20px border radius, Plus Jakarta Sans font, and native sheet modals.
- Zero external dependencies.
- Mutual Exclusivity: A permanent member must only appear in Executive OR General, never both.
- Moving between General and Executive must preserve 100% of payment history, transaction records, and member IDs.
- Temporary members under "Donation From Others" must NEVER calculate dues or show monthly fee warnings.

---

### Task 1: Database Migration & Schema Compatibility Script

**Files:**
- Modify: `fix-supabase-schema.sql:50-86`
- Modify: `supabase/migrations/0008_member_types_and_designations.sql` (Create new migration)

**Interfaces:**
- Consumes: `public.members`, `public.payments`, `public.supporter_donations`
- Produces: Columns `member_kind`, `executive_tier`, `designation`, `sort_order` on `public.members`.

- [ ] **Step 1: Create migration file `supabase/migrations/0008_member_types_and_designations.sql`**

```sql
-- 0008_member_types_and_designations.sql
-- Add member types (permanent/temporary), executive tiers (general/executive), and dynamic designations.

alter table public.members
  add column if not exists member_kind text not null default 'permanent'
    check (member_kind in ('permanent', 'temporary')),
  add column if not exists executive_tier text not null default 'general'
    check (executive_tier in ('general', 'executive')),
  add column if not exists designation text,
  add column if not exists sort_order integer not null default 0;

-- Backfill from legacy member_type column if present
update public.members
set executive_tier = case
  when member_type = 'executive' then 'executive'
  else 'general'
end
where executive_tier is null or executive_tier = 'general';

-- Seed the initial executive leadership designations requested by the user
update public.members set executive_tier = 'executive', designation = 'President', sort_order = 1 where name ilike '%K%H%Rafi%' or name ilike '%Kamrul%Rafi%';
update public.members set executive_tier = 'executive', designation = 'General Secretary', sort_order = 2 where name ilike '%Khaled%Mahmud%';
update public.members set executive_tier = 'executive', designation = 'Financial Advisor', sort_order = 3 where name ilike '%Junaed%' or name ilike '%Junayed%';
update public.members set executive_tier = 'executive', designation = 'FA', sort_order = 4 where name ilike '%Istique%';
update public.members set executive_tier = 'executive', designation = 'Accountant', sort_order = 5 where name ilike '%Imtiaj%';
update public.members set executive_tier = 'executive', designation = 'Membership Advisor', sort_order = 6 where name ilike '%Sabbir%';
update public.members set executive_tier = 'executive', designation = 'MA', sort_order = 7 where name ilike '%Kafi%';

create index if not exists members_member_kind_tier_idx on public.members (member_kind, executive_tier, sort_order);
```

- [ ] **Step 2: Update `fix-supabase-schema.sql`**

Add the same idempotent column definitions and seed updates to `fix-supabase-schema.sql` so running the single repair script ensures full compatibility with Supabase.

- [ ] **Step 3: Test migration script syntax**

Verify SQL syntax with node/python script checking SQL validity.

---

### Task 2: Update `membersApi.js` to Support Dynamic Designations & Tiers

**Files:**
- Modify: `src/lib/membersApi.js:76-167`

**Interfaces:**
- Consumes: Member payloads containing `member_kind`, `executive_tier`, `designation`, `sort_order`
- Produces: API methods for fetching, promoting, demoting, and updating members.

- [ ] **Step 1: Update `memberPayload` in `src/lib/membersApi.js`**

```javascript
function memberPayload(input, kind) {
  const name = cleanText(input?.name, 160);
  if (!name) throw new Error("A member name is required.");
  const payload = {
    name,
    email: cleanText(input.email, 254) || null,
    photo_url: cleanText(input.photo_url || input.avatar_url, 1000) || null,
    avatar_url: cleanText(input.avatar_url || input.photo_url, 1000) || null,
    member_kind: cleanText(input.member_kind, 20) || "permanent",
    executive_tier: cleanText(input.executive_tier, 20) || (kind === "executive" ? "executive" : "general"),
    designation: cleanText(input.designation, 120) || null,
    sort_order: Math.max(0, Number(input.sort_order) || 0)
  };
  // Maintain backward compatibility with legacy columns
  payload.member_type = payload.executive_tier;
  payload.position = payload.designation;
  return payload;
}
```

- [ ] **Step 2: Add `promoteToExecutive` and `demoteToGeneral` helpers in `membersApi.js`**

Export:
```javascript
export async function setMemberExecutiveTier(id, { executive_tier, designation, sort_order = 0 }) {
  if (!validId(id)) return result(null, new Error("Invalid member id."));
  return run(async db => {
    const { data, error } = await db.from("members").update({
      executive_tier,
      member_type: executive_tier,
      designation: executive_tier === "executive" ? cleanText(designation, 120) : null,
      position: executive_tier === "executive" ? cleanText(designation, 120) : null,
      sort_order: Math.max(0, Number(sort_order) || 0)
    }).eq("id", id).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
```

- [ ] **Step 3: Verify module export integrity**

Expose on `window.HealerMembersApi`.

---

### Task 3: Unified Member Calculations & Mutual Exclusivity in `index.html`

**Files:**
- Modify: `index.html:2205-2240` (Seed Data)
- Modify: `index.html:3960-4060` (Member Overview & Section Rendering)
- Modify: `index.html:4205-4285` (Member Detail View)

**Interfaces:**
- Consumes: `state.members`, `state.payments`, `state.supporterDonations`
- Produces: Correct member categorisation, mutually exclusive list rendering, unified permanent dues calculation.

- [ ] **Step 1: Update Seed Data in `index.html`**

Update `db.seed()` in `index.html` to configure:
1. `K H Rafi`: Executive, `President` (fee: 150 BDT, start: Sep 2024)
2. `Khaleda Mahmud`: Executive, `General Secretary` (fee: 150 BDT, start: Sep 2024)
3. `Junayed`: Executive, `Financial Advisor` (fee: 150 BDT, start: Sep 2024)
4. `Istique`: Executive, `FA` (fee: 150 BDT, start: Sep 2024)
5. `Imtiaj`: Executive, `Accountant` (fee: 150 BDT, start: Sep 2024)
6. `Sabbir Hossen`: Executive, `Membership Advisor` (fee: 150 BDT, start: Sep 2024)
7. `A. H. Kafi`: Executive, `MA` (fee: 150 BDT, start: Sep 2024)
8. `Mehedi Hasan Saikat`: General, permanent (fee: 150 BDT, start: Sep 2024)
9. `Afrahul Haque Orko`: General, permanent (fee: 150 BDT, start: Sep 2024)

- [ ] **Step 2: Update `memberRows()` and Dues Handling**

Ensure both General and Executive members calculate standard monthly dues:
```javascript
function memberRows() {
  const yr = YEAR();
  return state.members.filter(m => (m.member_kind || "permanent") === "permanent").map(m => {
    const dues = memberDues(m.id);
    const pays = state.payments.filter(p => p.member_id === m.id);
    return {
      m,
      due: dues.count > 0,
      dueAmount: dues.amount,
      paidTotal: pays.reduce((sum, p) => sum + Number(p.amount || 0), 0),
      active: pays.some(p => p.date && p.date.startsWith(String(yr)))
    };
  });
}
```

- [ ] **Step 3: Ensure Strict Mutual Exclusivity in `ScreenMembers()`**

Filter rows cleanly:
```javascript
const isExecSection = state.memberSection === "executive";
const visibleRows = rows.filter(r => isExecSection ? (r.m.executive_tier === "executive" || r.m.member_type === "executive") : (r.m.executive_tier !== "executive" && r.m.member_type !== "executive"));
```

- [ ] **Step 4: Update Member Detail View (`ScreenMemberDetail`)**

Display for permanent members:
- For Executive: Official designation badge (`President`, `General Secretary`, etc.) alongside name.
- For both Executive & General: Monthly dues grid, payment total, due amount, and PDF receipt.
- Admin action: "Change Designation / Step Down" button for Executives; "Promote to Executive" button for General members.

---

### Task 4: Dynamic Designation Picker & Promotion Modal

**Files:**
- Modify: `index.html:4085-4160` (Add / Promote Member Sheets)
- Modify: `index.html:4960-5050` (Event Handlers)

**Interfaces:**
- Consumes: `DEFAULT_DESIGNATIONS` array, list of general members
- Produces: Dynamic dropdown with custom option for designation selection.

- [ ] **Step 1: Define Dynamic Designations List**

```javascript
const DEFAULT_DESIGNATIONS = [
  "President",
  "General Secretary",
  "Financial Advisor",
  "FA",
  "Accountant",
  "Membership Advisor",
  "MA"
];
```

- [ ] **Step 2: Build `openPromoteModal(memberId)` Sheet**

Create a modal sheet allowing the admin to:
1. Select a General member (if opening from Executive screen `+ Add Executive`).
2. Choose from the dynamic designation dropdown or enter a custom designation in a revealed text input.
3. Save: sets `executive_tier = 'executive'` and `designation = chosenDesignation`.
4. Shows success toast and re-renders view.

- [ ] **Step 3: Add "Step Down to General" action**

In `ScreenMemberDetail`, for an Executive member, clicking "Step Down to General":
1. Sets `executive_tier = 'general'`, clears `designation`.
2. Shows toast: *"Moved to General Members"*.
3. Keeps all payment history intact.

---

### Task 5: Temporary Members Profiles & "Donation From Others" Integration

**Files:**
- Modify: `index.html:3986-3995` (`ScreenDonationSupporters`)
- Modify: `index.html:4205-4265` (`ScreenMemberDetail` for temporary members)
- Modify: `index.html:5200-5230` (Donation Handlers)

**Interfaces:**
- Consumes: `state.members` (with `member_kind === "temporary"`), `state.supporterDonations`
- Produces: Profile-backed temporary members with voluntary gifts and 0 dues.

- [ ] **Step 1: Upgrade "Donation From Others" Card & Screen**

1. Group supporter contributions by member or show registered temporary members.
2. Clicking a temporary member opens their dedicated detail view:
   - Header with `Temporary Member · Voluntary Supporter` badge.
   - **Zero dues card:** Dues grid is omitted; displays Total Voluntary Gifts and number of donations.
   - Chronological list of contributions.
   - Quick action button: `+ Log Donation` (pre-selects this supporter).

- [ ] **Step 2: Add Temporary Member Modal**

Add sheet for creating a Temporary Member:
- Full Name
- Optional initial gift (Amount, Month, Purpose)
- Optional Photo

---

### Task 6: Verification, Local Server Testing & Final Commit

**Files:**
- Test with Node / Python scripts and local browser at `http://localhost:8080`.

- [ ] **Step 1: Syntax & Linter Verification**
Verify inline scripts in `index.html` and `src/lib/membersApi.js` parse without errors.

- [ ] **Step 2: Functional Verification Checklist**
- [ ] Verify K H Rafi, Khaleda Mahmud, Junayed, Istique, Imtiaj, Sabbir Hossen, and A. H. Kafi appear in Executive Members with their designations.
- [ ] Verify General Members show Mehedi Hasan Saikat and Afrahul Haque Orko.
- [ ] Verify promoting a General member moves them to Executive with their designation.
- [ ] Verify stepping down moves them back to General with all payment history intact.
- [ ] Verify Temporary members in "Donation From Others" calculate 0 dues.
- [ ] Verify CSS consistency matches `cards.css`, `glass.css`, `members.css`.

- [ ] **Step 3: Git Commit**
Commit all changes to `feat/smooth-nav-switching`.
