// Supabase Edge Function: reconcile PayMongo checkout state on demand.
// Called by the app "Refresh" button as a fallback if webhooks are delayed.
//
// Env vars required:
// - PAYMONGO_SECRET_KEY
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

async function applyEntitlement(
  supabaseAdmin: ReturnType<typeof createClient>,
  checkout: { id: string; user_id: string; product: string; gig_id: string | null },
) {
  const nowUtc = new Date();
  const userId = checkout.user_id;
  if (checkout.product === "worker_sub") {
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
    return;
  }
  if (checkout.product === "employer_sub") {
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
        .update({ subscription_expires_at: until, updated_at: nowUtc.toISOString() })
        .eq("business_id", userId);
    } else {
      await supabaseAdmin.from("employer_entitlements").insert({
        business_id: userId,
        jobs_posted_count: 0,
        subscription_expires_at: until,
        updated_at: nowUtc.toISOString(),
      });
    }
    return;
  }
  if (checkout.product === "gig_boost") {
    if (!checkout.gig_id) return;
    const until = new Date(nowUtc.getTime() + 3 * 24 * 60 * 60 * 1000).toISOString();
    await supabaseAdmin.from("gigs").update({ boosted_until: until }).eq("id", checkout.gig_id);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = mustEnv("SUPABASE_URL");
    const serviceRoleKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
    const paymongoSecretKey = mustEnv("PAYMONGO_SECRET_KEY");

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseAuthed = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userRes, error: userErr } = await supabaseAuthed.auth.getUser();
    if (userErr || !userRes?.user) return json(401, { error: "Unauthorized" });
    const userId = userRes.user.id;

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Find most recent checkout for this user that isn't paid yet.
    const { data: co, error: coErr } = await supabaseAdmin
      .from("billing_checkouts")
      .select("id,user_id,product,gig_id,paymongo_checkout_session_id,status")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(5);
    if (coErr) return json(500, { error: "Failed to load checkouts" });
    const list = (co ?? []) as Array<any>;
    const pending = list.find((x) => x?.status !== "paid" && x?.paymongo_checkout_session_id);
    if (!pending) return json(200, { ok: true, reconciled: false });

    const csId = pending.paymongo_checkout_session_id as string;
    const basic = btoa(`${paymongoSecretKey}:`);
    const pmRes = await fetch(
      `https://api.paymongo.com/v1/checkout_sessions/${encodeURIComponent(csId)}`,
      { headers: { Authorization: `Basic ${basic}` } },
    );
    const pmJson = await pmRes.json().catch(() => ({}));
    if (!pmRes.ok) {
      return json(502, { error: "PayMongo retrieve checkout failed", details: pmJson });
    }

    const payments = pmJson?.data?.attributes?.payments;
    const paid =
      Array.isArray(payments) &&
      payments.some((p: any) => p?.attributes?.status === "paid");

    if (!paid) return json(200, { ok: true, reconciled: false });

    await supabaseAdmin
      .from("billing_checkouts")
      .update({ status: "paid", updated_at: new Date().toISOString() })
      .eq("id", pending.id as string);

    await applyEntitlement(supabaseAdmin, {
      id: pending.id as string,
      user_id: userId,
      product: pending.product as string,
      gig_id: (pending.gig_id as string | null) ?? null,
    });

    return json(200, { ok: true, reconciled: true, checkout_id: pending.id });
  } catch (e) {
    return json(500, { error: String(e?.message ?? e) });
  }
});

