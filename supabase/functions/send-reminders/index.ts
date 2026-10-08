// ============================================================================
// supabase/functions/send-reminders/index.ts  —  Healer Boy's
//
// Runs DAILY from pg_cron (see supabase/migrations/0001_app_settings_and_cron.sql).
// It exits early unless "today" is the configured send day (default 5) in the
// club timezone, so the scheduling logic lives here, not in the cron expression.
//
// Only writes happen with the service-role key. Members are emailed through
// EmailJS's REST endpoint (server side, so no keys are ever in the app bundle).
//
// Required Edge Function secrets  (supabase secrets set KEY=value):
//   EMAILJS_SERVICE_ID
//   EMAILJS_TEMPLATE_ID
//   EMAILJS_PUBLIC_KEY
//   EMAILJS_PRIVATE_KEY      (only if your EmailJS account uses strict mode)
//   ADMIN_EMAIL              (optional, used for the failure notification)
//   APP_TIMEZONE_OFFSET_MIN  (optional, default 360 = UTC+6 / Asia-Dhaka)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
const DEFAULT_FEE = 150;
const TZ_OFFSET_MIN = Number(Deno.env.get("APP_TIMEZONE_OFFSET_MIN") ?? "360");
// Club dues started in September 2024. Unpaid months carry forward across years.
const FEE_START_INDEX = 2024 * 12 + (9 - 1);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const log: string[] = [];
  try {
    // ---------------------------------------------------------------- auth
    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    // Accept either the service-role key (cron) or Supabase's own scheduler header.
    const isTrusted =
      (serviceKey && authHeader === `Bearer ${serviceKey}`) ||
      req.headers.has("x-supabase-signature");

    if (!isTrusted) {
      return json({ error: "unauthorized" }, 401);
    }

    // ------------------------------------------------------------- clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ------------------------------------------------------- local date
    const now = new Date();
    const local = new Date(now.getTime() + (TZ_OFFSET_MIN + now.getTimezoneOffset()) * 60000);
    const year = local.getUTCFullYear();
    const month = local.getUTCMonth() + 1;
    const day = local.getUTCDate();
    log.push(`local date ${year}-${month}-${day}`);

    // --------------------------------------------------------- settings
    const { data: settings, error: sErr } = await admin
      .from("app_settings").select("*").eq("id", 1).maybeSingle();
    if (sErr) throw sErr;

    const cfg = {
      auto_email_reminder: settings?.auto_email_reminder ?? true,
      send_day: settings?.send_day ?? 5,
      channel: settings?.channel ?? "Email",
      bkash_number: settings?.bkash_number ?? "",
      nagad_number: settings?.nagad_number ?? "",
    };

    if (!cfg.auto_email_reminder) return json({ skipped: "auto_email_reminder is off", log });
    if (day !== cfg.send_day) {
      return json({ skipped: `day ${day} is not send_day ${cfg.send_day}`, log });
    }
    if (cfg.channel.toLowerCase() !== "email") {
      return json({ skipped: `channel ${cfg.channel} is not email`, log });
    }

    // ------------------------------------------------------------ data
    const { data: members, error: mErr } = await admin.from("members").select("id,name,email");
    if (mErr) throw mErr;
    const { data: payments, error: pErr } = await admin.from("payments").select("member_id,amount,date,type");
    if (pErr) throw pErr;

    // --------------------------------------------------- who owes what
    const monthIndex = (y: number, m: number) => y * 12 + (m - 1);
    const monthParts = (type: string | null, date: string | null): { y: number; m: number } | null => {
      if (type) {
        const m = /\(([A-Za-z]+)\s+(\d{4})\)/.exec(type);
        if (m) {
          const i = MONTHS.findIndex((x) => x.toLowerCase() === m[1].toLowerCase());
          if (i > -1) return { y: Number(m[2]), m: i + 1 };
        }
      }
      if (date) {
        const [y, mo] = date.slice(0, 10).split("-").map(Number);
        if (y && mo) return { y, m: mo };
      }
      return null;
    };

    const paidByMember = new Map<string, Set<number>>();
    const lastPaidByMember = new Map<string, number>();
    const feeByMember = new Map<string, number>();
    for (const p of payments ?? []) {
      const type = String(p.type ?? "");
      if (!/Monthly Fee|Advanced Fee/i.test(type)) continue;
      const part = monthParts(type, p.date);
      if (!part) continue;
      const idx = monthIndex(part.y, part.m);
      if (!paidByMember.has(p.member_id)) paidByMember.set(p.member_id, new Set());
      paidByMember.get(p.member_id)!.add(idx);
      lastPaidByMember.set(p.member_id, Math.max(lastPaidByMember.get(p.member_id) ?? -1, idx));
      // Keep a member's real monthly fee (rather than the generic fallback).
      if (/Monthly Fee/i.test(type)) feeByMember.set(p.member_id, Number(p.amount) || DEFAULT_FEE);
    }

    const currentIndex = monthIndex(year, month);
    const queue = (members ?? []).map((m) => {
      const paid = paidByMember.get(m.id) ?? new Set<number>();
      const lastPaid = lastPaidByMember.get(m.id);
      const startIndex = lastPaid == null ? FEE_START_INDEX : lastPaid + 1;
      const months: { year: number; month: number; index: number }[] = [];
      for (let i = startIndex; i <= currentIndex; i++) {
        if (!paid.has(i)) months.push({ year: Math.floor(i / 12), month: (i % 12) + 1, index: i });
      }
      return { member: m, months, fee: feeByMember.get(m.id) ?? DEFAULT_FEE };
    }).filter((r) => r.months.length > 0);

    if (!queue.length) {
      await stamp(admin, 0);
      return json({ ok: true, sent: 0, log: [...log, "nobody has dues"] });
    }

    // ------------------------------------------------------- send loop
    const serviceId = Deno.env.get("EMAILJS_SERVICE_ID");
    const templateId = Deno.env.get("EMAILJS_TEMPLATE_ID");
    const publicKey = Deno.env.get("EMAILJS_PUBLIC_KEY");
    const privateKey = Deno.env.get("EMAILJS_PRIVATE_KEY");

    if (!serviceId || !templateId || !publicKey) {
      return json({ error: "EmailJS secrets missing", wouldSend: queue.length, log }, 500);
    }

    let sent = 0;
    const failures: { member: string; error: string }[] = [];

    for (const row of queue) {
      const firstDue = row.months[0];
      const monthLabel = `${MONTHS[firstDue.month - 1]} ${firstDue.year}`;
      const to_email = row.member.email ??
        `${row.member.name.toLowerCase().replace(/[^a-z]+/g, ".")}@gmail.com`;

      const body =
        `Hi ${row.member.name}, your fee for ${monthLabel} is still due: BDT ${row.fee}. ` +
        `Please pay by bKash or Nagad: ${cfg.bkash_number || "-"} / ${cfg.nagad_number || "-"}.`;

      try {
        const res = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            service_id: serviceId,
            template_id: templateId,
            user_id: publicKey,
            accessToken: privateKey || undefined,
            template_params: {
              to_name: row.member.name,
              to_email,
              subject: "Monthly fee reminder",
              month: monthLabel,
              amount: String(row.fee),
              bkash: cfg.bkash_number,
              nagad: cfg.nagad_number,
              message: body,
            },
          }),
        });
        if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
        sent++;
      } catch (e) {
        failures.push({ member: row.member.name, error: String(e) });
      }
      // EmailJS free tier is rate limited — keep a small gap between sends.
      await new Promise((r) => setTimeout(r, 400));
    }

    await stamp(admin, sent);

    return json({
      ok: true,
      year,
      send_day: cfg.send_day,
      eligible: queue.length,
      sent,
      failures,
      log,
    });
  } catch (e) {
    console.error(e);
    return json({ error: String(e), log }, 500);
  }
});

async function stamp(admin: ReturnType<typeof createClient>, count: number) {
  await admin.from("app_settings").update({
    last_sent_at: new Date().toISOString(),
    last_sent_count: count,
  }).eq("id", 1);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}
