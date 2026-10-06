// Confirms a Paystack top-up when the user returns to the app (the webhook
// normally gets there first; crediting is idempotent either way).
//   POST { "reference": "AW-..." }  ->  { "status": "success" | "pending" | "failed" }
// Secret: PAYSTACK_SECRET_KEY
import { adminClient, callerClient, cors, env, json } from "../_shared/http.ts";

const SECRET = env("PAYSTACK_SECRET_KEY");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!SECRET) return json({ error: "Card payments aren't connected yet" }, 503);
  const caller = await callerClient(req);
  if (!caller) return json({ error: "unauthorized" }, 401);

  let b: { reference?: string };
  try { b = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const ref = String(b.reference ?? "");
  if (!/^AW-[a-f0-9]{20}$/.test(ref)) return json({ error: "bad reference" }, 400);

  // RLS: only the owner can see this payment row.
  const { data: p } = await caller.db.from("payments").select("reference, amount_kobo, status").eq("reference", ref).maybeSingle();
  if (!p) return json({ error: "not found" }, 404);
  if (p.status === "success") return json({ status: "success" });

  const res = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(ref)}`, {
    headers: { Authorization: `Bearer ${SECRET}` },
  });
  const j = await res.json();
  const d = j?.data;
  if (!res.ok || !d) return json({ status: "pending" });
  if (d.status === "success" && d.currency === "NGN" && Number(d.amount) === Number(p.amount_kobo)) {
    const { error } = await adminClient().rpc("credit_topup", { p_reference: ref, p_amount_kobo: d.amount, p_raw: d });
    if (error) return json({ error: "Couldn't credit your wallet. Contact support with " + ref }, 500);
    return json({ status: "success" });
  }
  if (["failed", "abandoned", "reversed"].includes(d.status)) {
    await adminClient().from("payments").update({ status: "failed", raw: d }).eq("reference", ref).eq("status", "pending");
    return json({ status: "failed" });
  }
  return json({ status: "pending" });
});
