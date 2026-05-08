// Supabase Edge Function: create a PayMongo Checkout Session.
// Env vars required (set via `supabase secrets set`):
// - PAYMONGO_SECRET_KEY
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY
//
// Webhook should call `paymongo_webhook` to grant entitlements.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type Product = "worker_sub" | "employer_sub" | "gig_boost";

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

function productAmountCentavos(p: Product): number {
  switch (p) {
    case "worker_sub":
      return 99 * 100;
    case "employer_sub":
      return 149 * 100;
    case "gig_boost":
      return 49 * 100;
  }
}

function productName(p: Product): string {
  switch (p) {
    case "worker_sub":
      return "AgapShift Worker Subscription (30 days)";
    case "employer_sub":
      return "AgapShift Employer Subscription (30 days)";
    case "gig_boost":
      return "AgapShift Job Boost (3 days)";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = mustEnv("SUPABASE_URL");
    const serviceRoleKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
    const paymongoSecretKey = mustEnv("PAYMONGO_SECRET_KEY");

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Verify caller identity using the JWT from the request.
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseAuthed = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userRes, error: userErr } = await supabaseAuthed.auth.getUser();
    if (userErr || !userRes?.user) return json(401, { error: "Unauthorized" });

    const userId = userRes.user.id;
    const body = await req.json().catch(() => ({}));
    const product = (body?.product ?? "") as Product;
    const gigId = (body?.gig_id ?? body?.gigId ?? null) as string | null;
    if (product !== "worker_sub" && product !== "employer_sub" && product !== "gig_boost") {
      return json(400, { error: "Invalid product" });
    }
    if (product === "gig_boost" && (!gigId || typeof gigId !== "string")) {
      return json(400, { error: "gig_id required for boost" });
    }

    const amount = productAmountCentavos(product);

    // Create local checkout record first (used as reference_number + metadata).
    const { data: ins, error: insErr } = await supabaseAdmin
      .from("billing_checkouts")
      .insert({
        user_id: userId,
        product,
        gig_id: product === "gig_boost" ? gigId : null,
        amount_centavos: amount,
        currency: "PHP",
        status: "created",
      })
      .select("id")
      .single();
    if (insErr || !ins?.id) {
      return json(500, { error: "Failed to create checkout record" });
    }
    const checkoutId = ins.id as string;

    const basic = btoa(`${paymongoSecretKey}:`);
    const payload = {
      data: {
        attributes: {
          cancel_url: "https://example.com/agapshift/cancel",
          success_url: "https://example.com/agapshift/success",
          description: productName(product),
          reference_number: checkoutId,
          line_items: [
            {
              name: productName(product),
              quantity: 1,
              amount,
              currency: "PHP",
            },
          ],
          payment_method_types: [
            "gcash",
            "paymaya",
            "grab_pay",
            "shopee_pay",
            "qrph",
            "billease",
            "card",
          ],
          send_email_receipt: true,
          metadata: {
            checkout_id: checkoutId,
            product,
            user_id: userId,
            gig_id: gigId ?? "",
          },
        },
      },
    };

    const pmRes = await fetch("https://api.paymongo.com/v1/checkout_sessions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${basic}`,
      },
      body: JSON.stringify(payload),
    });

    const pmJson = await pmRes.json().catch(() => ({}));
    if (!pmRes.ok) {
      // Keep record for debugging, but return error.
      await supabaseAdmin
        .from("billing_checkouts")
        .update({ status: "failed", updated_at: new Date().toISOString() })
        .eq("id", checkoutId);
      return json(502, { error: "PayMongo create checkout failed", details: pmJson });
    }

    const csId = pmJson?.data?.id as string | undefined;
    const checkoutUrl = pmJson?.data?.attributes?.checkout_url as string | undefined;
    if (!csId || !checkoutUrl) {
      return json(502, { error: "PayMongo response missing checkout_url" });
    }

    await supabaseAdmin
      .from("billing_checkouts")
      .update({
        paymongo_checkout_session_id: csId,
        updated_at: new Date().toISOString(),
      })
      .eq("id", checkoutId);

    return json(200, { checkout_id: checkoutId, checkout_url: checkoutUrl });
  } catch (e) {
    return json(500, { error: String(e?.message ?? e) });
  }
});

