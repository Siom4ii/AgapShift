// Supabase Edge Function: PayMongo webhook receiver.
//
// Configure in PayMongo dashboard to send `checkout_session.payment.paid`
// events to:
//   https://<project-ref>.functions.supabase.co/paymongo_webhook
//
// Env vars required:
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY
//
// Optional but recommended:
// - PAYMONGO_WEBHOOK_SECRET (for signature verification; not implemented here
//   because PayMongo signature spec varies by version—add once confirmed).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, paymongo-signature",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function mustEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

function extendExpiry(nowUtc: Date, currentIso: string | null, days: number): string {
  const cur = currentIso ? new Date(currentIso) : null;
  const base = cur && cur.getTime() > nowUtc.getTime() ? cur : nowUtc;
  const until = new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
  return until.toISOString();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = mustEnv("SUPABASE_URL");
    const serviceRoleKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const evt = await req.json().catch(() => null);
    const type = evt?.data?.attributes?.type as string | undefined;
    if (!type) return json(400, { error: "Missing event type" });

    // We care about checkout-session paid events.
    if (type !== "checkout_session.payment.paid") {
      return json(200, { ok: true, ignored: true });
    }

    const cs = evt?.data?.attributes?.data;
    const csId = cs?.id as string | undefined;
    const meta = cs?.attributes?.metadata ?? {};
    const checkoutIdFromMeta = (meta?.checkout_id ?? cs?.attributes?.reference_number) as
      | string
      | undefined;

    // Prefer DB lookup by checkout session id (more reliable than metadata).
    const { data: checkoutRow, error: checkoutErr } = checkoutIdFromMeta
      ? await supabaseAdmin
          .from("billing_checkouts")
          .select("id,user_id,product,gig_id,paymongo_checkout_session_id")
          .eq("id", checkoutIdFromMeta)
          .maybeSingle()
      : csId
        ? await supabaseAdmin
            .from("billing_checkouts")
            .select("id,user_id,product,gig_id,paymongo_checkout_session_id")
            .eq("paymongo_checkout_session_id", csId)
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle()
        : { data: null, error: null };

    if (checkoutErr) {
      return json(500, { error: "Failed to look up checkout", details: checkoutErr.message });
    }
    if (!checkoutRow) {
      return json(400, {
        error:
          "Checkout not found in billing_checkouts. Ensure migrations ran and create-checkout stored paymongo session id.",
        cs_id: csId ?? null,
        checkout_id: checkoutIdFromMeta ?? null,
      });
    }

    const checkoutId = checkoutRow.id as string;
    const product = checkoutRow.product as string;
    const userId = checkoutRow.user_id as string;
    const gigId = (checkoutRow.gig_id as string | null) ?? undefined;

    // Mark checkout as paid (idempotent).
    await supabaseAdmin
      .from("billing_checkouts")
      .update({
        status: "paid",
        paymongo_checkout_session_id: csId ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", checkoutId);

    const nowUtc = new Date();

    if (product === "worker_sub") {
      const { data: row } = await supabaseAdmin
        .from("worker_entitlements")
        .select("subscription_expires_at")
        .eq("user_id", userId)
        .maybeSingle();
      const cur = (row?.subscription_expires_at ?? null) as string | null;
      const until = extendExpiry(nowUtc, cur, 30);
      await supabaseAdmin.from("worker_entitlements").upsert({
        user_id: userId,
        subscription_expires_at: until,
        updated_at: nowUtc.toISOString(),
      });
      return json(200, { ok: true });
    }

    if (product === "employer_sub") {
      const { data: row } = await supabaseAdmin
        .from("employer_entitlements")
        .select("subscription_expires_at")
        .eq("business_id", userId)
        .maybeSingle();
      const cur = (row?.subscription_expires_at ?? null) as string | null;
      const until = extendExpiry(nowUtc, cur, 30);
      if (row) {
        await supabaseAdmin
          .from("employer_entitlements")
          .update({
            subscription_expires_at: until,
            updated_at: nowUtc.toISOString(),
          })
          .eq("business_id", userId);
      } else {
        await supabaseAdmin.from("employer_entitlements").insert({
          business_id: userId,
          jobs_posted_count: 0,
          subscription_expires_at: until,
          updated_at: nowUtc.toISOString(),
        });
      }
      return json(200, { ok: true });
    }

    if (product === "gig_boost") {
      if (!gigId) return json(400, { error: "Missing gig_id for boost" });
      const until = new Date(nowUtc.getTime() + 3 * 24 * 60 * 60 * 1000).toISOString();
      await supabaseAdmin
        .from("gigs")
        .update({ boosted_until: until })
        .eq("id", gigId);
      return json(200, { ok: true });
    }

    return json(400, { error: "Unknown product" });
  } catch (e) {
    return json(500, { error: String(e?.message ?? e) });
  }
});

