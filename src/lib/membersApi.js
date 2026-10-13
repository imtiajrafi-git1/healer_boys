/* Healer Boys member/donation data access.
 * The Supabase URL and anon key are supplied by the host page through
 * window.__SUPABASE_CONFIG__; no credentials are stored in source control.
 */
const config = () => window.__SUPABASE_CONFIG__ || {};
let supabaseClient = null;

function client() {
  if (window.__HEALER_SUPABASE_CLIENT__) return window.__HEALER_SUPABASE_CLIENT__;
  const { url, anonKey } = config();
  if (!url || !anonKey || !window.supabase?.createClient) return null;
  if (!supabaseClient) supabaseClient = window.supabase.createClient(url, anonKey, { auth: { persistSession: true } });
  return supabaseClient;
}

const cleanText = (value, max = 500) => String(value ?? "").trim().slice(0, max);
const cleanAmount = (value) => {
  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? amount : null;
};
const validId = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ""));

/* ---------------------------------------------------------------------------
 * Schema cache / missing table detection.
 *
 * PostgREST answers "Could not find the table 'public.x' in the schema cache"
 * (PGRST205) when the table does not exist yet OR its schema cache is stale
 * (for example right after a migration). We recognise every flavour of that
 * error so callers can retry once and, if it still fails, fall back without
 * losing the admin's data.
 * ------------------------------------------------------------------------- */
function isSchemaError(error) {
  const message = String((error && (error.message || error.error_description || error)) || "");
  const code = String((error && (error.code || error.error_code || "")) || "");
  return code === "PGRST205" || code === "PGRST204" || code === "42P01" ||
    /schema cache|could not find the (table|column)|does not exist|relation .* does not exist/i.test(message);
}

/* One actionable sentence: the fix script creates the missing table/columns
 * and reloads the PostgREST schema cache. */
function schemaErrorMessage(error) {
  const raw = String((error && (error.message || error)) || "Unknown database error");
  const match = raw.match(/['"](?:public\.)?([a-z0-9_]+)['"]/i);
  const subject = match ? ` (${match[1]})` : "";
  return `Database schema is out of date${subject}. Run fix-supabase-schema.sql in the Supabase SQL Editor ` +
    `(it creates the missing table/columns and reloads the schema cache), then try again.`;
}

function result(data = null, error = null) { return { data, error }; }

/* run(): execute a PostgREST call. When `retryOnSchema` is set, a schema-cache
 * failure is retried once after a short pause — this covers the race where the
 * admin just ran the fix script but PostgREST has not reloaded its cache yet. */
async function run(work, options = {}) {
  const db = client();
  if (!db) return result(null, new Error("Supabase is not configured."));
  const attempt = async () => {
    try {
      return result(await work(db));
    } catch (error) { return result(null, error); }
  };
  let out = await attempt();
  if (out.error && isSchemaError(out.error) && options.retryOnSchema) {
    await new Promise(r => setTimeout(r, 1200));
    out = await attempt();
  }
  if (out.error && isSchemaError(out.error)) {
    const friendly = new Error(schemaErrorMessage(out.error));
    friendly.schemaError = true;
    friendly.original = out.error;
    out = result(null, friendly);
  }
  return out;
}

function memberPayload(input, kind) {
  const name = cleanText(input?.name, 160);
  if (!name) throw new Error("A member name is required.");
  const payload = { name };
  if (kind === "executive") {
    payload.position = cleanText(input.position, 120) || null;
    payload.photo_url = cleanText(input.photo_url, 1000) || null;
    payload.contribution = cleanAmount(input.contribution) ?? 0;
    payload.monthly_status = cleanText(input.monthly_status, 40) || "paid";
    payload.due_amount = cleanAmount(input.due_amount) ?? 0;
    payload.due_months = Math.max(0, Number(input.due_months) || 0);
    payload.sort_order = Math.max(0, Number(input.sort_order) || 0);
  } else {
    payload.email = cleanText(input.email, 254) || null;
    payload.photo_url = cleanText(input.photo_url, 1000) || null;
    payload.profile = cleanText(input.profile, 1000) || null;
    payload.payment_total = cleanAmount(input.payment_total) ?? 0;
    payload.payment_count = Math.max(0, Number(input.payment_count) || 0);
    payload.monthly_fee = cleanAmount(input.monthly_fee) ?? 0;
    payload.last_payment_date = cleanText(input.last_payment_date, 10) || null;
  }
  return payload;
}

function donationPayload(input, { requireMonth = false } = {}) {
  const note = cleanText(input?.note, 500);
  const amount = cleanAmount(input?.amount);
  if (!note || amount === null) {
    throw new Error("Donation note and a non-negative amount are required.");
  }
  const payload = {
    donor_name: input.is_anonymous ? null : cleanText(input.donor_name, 160) || null,
    is_anonymous: Boolean(input.is_anonymous),
    amount,
    note,
    image_url: cleanText(input.image_url, 200000) || null
  };
  if (requireMonth) {
    const month = cleanText(input?.donation_month, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(month)) {
      throw new Error("Supporter month, note and a non-negative amount are required.");
    }
    payload.donation_month = month;
    payload.created_at = `${month}T00:00:00Z`;
  }
  return payload;
}

export async function fetchExecutiveMembers() {
  return run(async db => { const { data, error } = await db.from("executive_members").select("*").order("sort_order").order("name"); if (error) throw error; return data || []; });
}
export async function fetchGeneralMembers() {
  return run(async db => { const { data, error } = await db.from("general_members").select("*").order("name"); if (error) throw error; return data || []; });
}
export async function fetchDonations() {
  return run(async db => { const { data, error } = await db.from("donations").select("*").order("created_at", { ascending: false }); if (error) throw error; return data || []; });
}
export async function fetchSupporterDonations() {
  return run(async db => { const { data, error } = await db.from("supporter_donations").select("*").order("created_at", { ascending: false }); if (error) throw error; return data || []; }, { retryOnSchema: true });
}
async function add(kind, input) {
  const payload = memberPayload(input, kind);
  return run(async db => {
    const { data, error } = await db.from(kind === "executive" ? "executive_members" : "general_members").insert(payload).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
async function update(kind, id, input) {
  if (!validId(id)) return result(null, new Error("Invalid member id."));
  const payload = memberPayload(input, kind);
  return run(async db => {
    const { data, error } = await db.from(kind === "executive" ? "executive_members" : "general_members").update(payload).eq("id", id).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
async function remove(kind, id) {
  if (!validId(id)) return result(null, new Error("Invalid member id."));
  return run(async db => {
    const { error } = await db.from(kind === "executive" ? "executive_members" : "general_members").delete().eq("id", id);
    if (error) throw error;
    return true;
  });
}
export const addExecutiveMember = input => add("executive", input);
export const updateExecutiveMember = (id, input) => update("executive", id, input);
export const deleteExecutiveMember = id => remove("executive", id);
export const addGeneralMember = input => add("general", input);
export const updateGeneralMember = (id, input) => update("general", id, input);
export const deleteGeneralMember = id => remove("general", id);

export async function addDonation(input) {
  const payload = donationPayload(input);
  return run(async db => {
    const { data, error } = await db.from("donations").insert(payload).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
export async function updateDonation(id, input) {
  if (!validId(id)) return result(null, new Error("Invalid donation id."));
  const payload = donationPayload(input);
  return run(async db => {
    const { data, error } = await db.from("donations").update(payload).eq("id", id).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
export async function deleteDonation(id) {
  if (!validId(id)) return result(null, new Error("Invalid donation id."));
  return run(async db => {
    const { error } = await db.from("donations").delete().eq("id", id);
    if (error) throw error;
    return true;
  });
}

/* Donation From Others (supporter_gifts). Rows live ONLY in
 * supporter_donations — never mixed with the main donations table. */
export async function addSupporterDonation(input) {
  const payload = donationPayload(input, { requireMonth: true });
  return run(async db => {
    const { data, error } = await db.from("supporter_donations").insert(payload).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
export async function updateSupporterDonation(id, input) {
  if (!validId(id)) return result(null, new Error("Invalid supporter donation id."));
  const payload = donationPayload(input, { requireMonth: true });
  return run(async db => {
    const { data, error } = await db.from("supporter_donations").update(payload).eq("id", id).select().single();
    if (error) throw error;
    return data;
  }, { retryOnSchema: true });
}
export async function deleteSupporterDonation(id) {
  if (!validId(id)) return result(null, new Error("Invalid supporter donation id."));
  return run(async db => {
    const { error } = await db.from("supporter_donations").delete().eq("id", id);
    if (error) throw error;
    return true;
  });
}

export function subscribeToMemberChanges(onChange) {
  const db = client();
  if (!db) return () => {};
  const channel = db.channel("healerboys-members")
    .on("postgres_changes", { event: "*", schema: "public", table: "executive_members" }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "general_members" }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "donations" }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "supporter_donations" }, onChange)
    .subscribe();
  return () => { db.removeChannel(channel); };
}

window.HealerMembersApi = {
  fetchExecutiveMembers, fetchGeneralMembers, fetchDonations, fetchSupporterDonations,
  addExecutiveMember, updateExecutiveMember, deleteExecutiveMember,
  addGeneralMember, updateGeneralMember, deleteGeneralMember,
  addDonation, updateDonation, deleteDonation,
  addSupporterDonation, updateSupporterDonation, deleteSupporterDonation,
  subscribeToMemberChanges,
  isSchemaError
};
