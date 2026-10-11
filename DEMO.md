# ডেমো গাইড — Healer Boy's register

লাইভ অ্যাপ চালু আছে (`python3 -m http.server 8080` → পোর্ট **8080** এর LIVE PREVIEW)।
নিচের ধাপগুলো ফলো করলে নতুন Members register, Admin সিস্টেম আর Supabase sync — সব একবারে দেখতে পাবেন।

---

## ১. এক ক্লিকে ডেমো (১ ক্লিক, কোনো সেটআপ লাগবে না)

1. LIVE PREVIEW প্যানেল খুলুন।
2. Login স্ক্রিনে নিচের দিকে ড্যাশ-বর্ডার বাটন:
   **“See the demo register (sample data)”** — এটাতে ক্লিক করুন।
3. অ্যাপ নিজেই **ডেমো অ্যাডমিন** হিসেবে সাইন-ইন করে সরাসরি **Members** রেজিস্টারে নিয়ে যাবে।

`#/demo` লিংক দিয়েও সরাসরি ঢোকা যায়। শুধু ডেটা চাইলে কিন্তু নিজে সাইন-ইন করতে চাইলে `?demo=1` ব্যবহার করুন।

> ডেমো মোডে **Supabase-এ একটাও লেখা যায় না** (Supabase client বন্ধ, আলাদা localStorage bucket)।
> তাই ডেমোতে যা-ই add/edit/delete করুন, আসল রেজিস্টার একদম অক্ষত থাকবে।
> বেরোতে চাইলে **Profile → Sign out** — তখন ডেমো বন্ধ হয়ে আসল অ্যাপে ফিরে যাবে।

---

## ২. Members register — কী কী আছে

ডেমো ডেটা দিয়ে যা দেখবেন:

| সেকশন | ডেমোতে কী আছে |
| --- | --- |
| **Executive Members** | ঠিক **৮ জন** — President (Abdullah H. Kafi), Vice President (Junaed Hossain Toni), General Secretary (Imtiaj Ahmed Rafi), Joint Secretary (Kamrul H. Rafi), Treasurer (Khaled Mahmud), Organizing Secretary (Afrahul Haque Orko), Office Secretary (Istique Ahmed Chomok), Publicity Secretary (Sabbir Hossain) |
| **General Members** | ৪ জন — **Mehedi Hasan Saikot** (DS-এর নাম-বানান ঠিক করা), Rakibul Hasan Nayem, Shakil Ahmed, Tanvir Islam |
| **Donation from others** | ৫টি supporter entry, মোট **৳২০,০০০**, ২টি anonymous card |

প্রতিটি section-এ আছে —

* **Leadership badge** (👑 seat name, gold), **counter** (“8 members”)
* **Paid / Due tags** — `Total paid ৳…`, `n fees`, `All cleared` বা `Due ৳… · n months`
* **Top hero card** — Total members, Executive/General/Paid/Due/Active chips
* Search (member + supporter একসাথে), sort (top payer → highest due → A–Z), All/Paid/Due ফিল্টার
* গভীর violet glass কার্ড, glow, gradient — Members ট্যাবে ডার্ক থিম, বাকি অ্যাপ আগের হালকা থিমেই

---

## ৩. অ্যাডমিন সিস্টেম ডেমো (৭টা ধাপ)

1. **Executive/General সেকশনে** ড্যাশ করা বাটন — **“+ Add executive member” / “+ Add general member”** →
   নাম লিখুন, Membership type (Executive/General) বেছে নিন, designation সেট করুন, ফোন, ছবি → **Add member**।
2. **“⋯” (manage) বাটনে** ক্লিক → *Edit details & photo*, *Add a payment*, *Promote to executive / Move to general members*, *Open full profile*, *Delete member* — সব এক জায়গায়।
3. **Supporter**: **“+ Add supporter donation”** → নাম + amount + date, অথবা *anonymous supporter* চেক করুন।
4. কোনো supporter কার্ডে **“⋯”** → Edit / Delete।
5. **Donations ট্যাব** (নিচের নেভ) → **Add** থেকে ক্লাবের দেওয়া টাকা যোগ/এডিট/ডিলিট।
6. কোনো সদস্যে ট্যাপ করলে **Member detail** — Monthly dues grid, payment list, **Edit / Delete** চিপ, PDF receipt, reminder।
7. সব পরিবর্তন সাথে সাথে UI-তে (optimistic update) — টোস্ট মেসেজসহ।

---

## ৪. আসল (live) ডেটায় চালাতে

1. Supabase → **SQL Editor** → চালান:
   1. `supabase_policies.sql`
   2. `upgrade-members-and-supporters.sql`
      (এতে আছে `members.tier` / `role_title` / `phone` / `sort_order` / `is_active`,
      নতুন `supporter_donations` টেবিল, ৮ executive-এর backfill, “Mehedi Hasan Saikot” নাম-সংশোধন, RLS ও Realtime)
2. তারপর login স্ক্রিনে **admin Gmail + password** দিয়ে সাইন-ইন করুন (কোডের `ADMIN_EMAIL` / `ADMIN_PASSWORD`)।
3. একবার **Profile → “Sync register to Supabase”** চাপুন — seat/role আর device-এ জমে থাকা supporter entry গুলো server-এ উঠে যাবে।
4. Realtime চালু থাকায় অন্য ডিভাইস থেকে বদলালেও রেজিস্টার নিজে নিজে আপডেট হবে।

> মাইগ্রেশন না চালালেও অ্যাপ চলে: tier না থাকলে ৮ নাম থেকে seat ধরে নেয়,
> supporter গুলো ডিভাইসে জমা থাকে, আর কোনো insert ভাঙবে না
> (`CAPS` capability-probe + নিঃশব্দ column fallback + নির্দিষ্ট admin-only error message)।

---

## ৫. যদি পরীক্ষা করতে চান

* `python3 -m http.server 8080 --bind 0.0.0.0` — লোকাল সার্ভার (এখন চলছে)।
* `#/demo` — ডেমো অ্যাডমিন হিসেবে রেজিস্টার।
* `?demo=1` — ডেমো ডেটা, নিজে সাইন-ইন।
* স্বাভাবিক URL — আসল Supabase মোড (ডেমো ফ্ল্যাগ ছাড়া)।
* ডেমো/আসল আলাদা রাখা হয়েছে: `hb_demo_data_v1`, `hb_demo_session_v1` বনাম `hb_data_v2`, `hb_session_v2`।
