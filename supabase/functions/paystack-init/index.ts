// Starts a Paystack checkout to add money to the caller's AutoWave wallet.
//   POST { "amountKobo": 500000 }  ->  { "authorizationUrl": "...", "reference": "AW-..." }
// The wallet is credited only after Paystack confirms the payment
// (paystack-webhook, or paystack-verify when the user returns to the app).
// Secrets: PAYSTACK_SECRET_KEY, optional PAYSTACK_CALLBACK_URL
import { adminClient, callerClient, cors, env, json } from "../_shared/http.ts";

const SECRET = env("PAYSTACK_SECRET_KEY");
const MIN = 10_000;        // ₦100
const MAX = 50_000_000;    // ₦500,000 per top-up

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!SECRET) return json({ error: "Card payments aren't connected yet" }, 503);
  const caller = await callerClient(req);
  if (!caller) return json({ error: "unauthorized" }, 401);

  let b: { amountKobo?: number };
  try { b = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const amount = Math.round(Number(b.amountKobo));
  if (!Number.isFinite(amount) || amount < MIN || amount > MAX) {
    return json({ error: "Choose an amount between ₦100 and ₦500,000" }, 400);
  }

  const reference = `AW-${crypto.randomUUID().replaceAll("-", "").slice(0, 20)}`;
  const admin = adminClient();
  const { error: insErr } = await admin.from("payments").insert({ reference, user_id: caller.uid, amount_kobo: amount });
  if (insErr) return json({ error: "Couldn't start the payment" }, 500);

  // Paystack needs an email. Phone-only accounts get a stable placeholder.
  const email = caller.email ?? `${caller.uid}@users.autowave.app`;
  const res = await fetch("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: { Authorization: `Bearer ${SECRET}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      email,
      amount,
      currency: "NGN",
      reference,
      callback_url: env("PAYSTACK_CALLBACK_URL") || undefined,
      metadata: { user_id: caller.uid, purpose: "wallet_topup" },
    }),
  });
  const j = await res.json();
  if (!res.ok || !j?.status) {
    await admin.from("payments").update({ status: "failed", raw: j }).eq("reference", reference);
    return json({ error: j?.message ?? "Paystack didn't accept the payment" }, 502);
  }
  return json({ authorizationUrl: j.data.authorization_url, reference });
});
