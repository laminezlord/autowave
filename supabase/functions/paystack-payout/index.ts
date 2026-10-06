// Bank list, account-name lookup, and sending a withdrawal to the user's bank.
//   POST { "action": "banks" }                                     -> { banks: [{ name, code }] }
//   POST { "action": "resolve", "accountNumber": "...", "bankCode": "058" } -> { accountName }
//   POST { "action": "send", "withdrawalId": "<uuid>" }            -> { status }
// The wallet is debited by request_withdrawal() BEFORE this runs; if the
// transfer fails the money is returned with fail_withdrawal().
// Paystack: enable Transfers and disable "OTP for transfers" for API payouts.
// Secret: PAYSTACK_SECRET_KEY
import { adminClient, callerClient, cors, env, json } from "../_shared/http.ts";

const SECRET = env("PAYSTACK_SECRET_KEY");
const PS = "https://api.paystack.co";
const headers = () => ({ Authorization: `Bearer ${SECRET}`, "Content-Type": "application/json" });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!SECRET) return json({ error: "Bank payouts aren't connected yet" }, 503);
  const caller = await callerClient(req);
  if (!caller) return json({ error: "unauthorized" }, 401);

  let b: { action?: string; accountNumber?: string; bankCode?: string; withdrawalId?: string };
  try { b = await req.json(); } catch { return json({ error: "invalid json" }, 400); }

  try {
    if (b.action === "banks") {
      const r = await fetch(`${PS}/bank?country=nigeria&perPage=200`, { headers: headers() });
      const j = await r.json();
      return json({ banks: (j?.data ?? []).map((x: any) => ({ name: x.name, code: x.code })) });
    }

    if (b.action === "resolve") {
      if (!/^\d{10}$/.test(b.accountNumber ?? "") || !/^\w{2,10}$/.test(b.bankCode ?? "")) return json({ error: "Check the account number" }, 400);
      const r = await fetch(`${PS}/bank/resolve?account_number=${b.accountNumber}&bank_code=${b.bankCode}`, { headers: headers() });
      const j = await r.json();
      if (!r.ok || !j?.data?.account_name) return json({ error: "We couldn't find that account" }, 404);
      return json({ accountName: j.data.account_name });
    }

    if (b.action === "send") {
      const { data: w } = await caller.db.from("withdrawals").select("id, amount_kobo, status").eq("id", b.withdrawalId ?? "").maybeSingle();
      if (!w) return json({ error: "not found" }, 404);
      if (w.status !== "pending") return json({ status: w.status });

      const admin = adminClient();
      const { data: acct } = await admin.from("payout_accounts").select("*").eq("user_id", caller.uid).maybeSingle();
      if (!acct) return json({ error: "Add your bank account first" }, 400);

      let recipient = acct.recipient_code as string | null;
      if (!recipient) {
        const r = await fetch(`${PS}/transferrecipient`, {
          method: "POST",
          headers: headers(),
          body: JSON.stringify({ type: "nuban", name: acct.account_name ?? "AutoWave user", account_number: acct.account_number, bank_code: acct.bank_code, currency: "NGN" }),
        });
        const j = await r.json();
        recipient = j?.data?.recipient_code ?? null;
        if (!recipient) {
          await admin.rpc("fail_withdrawal", { p_id: w.id, p_reason: j?.message ?? "Bank account rejected" });
          return json({ status: "failed", error: j?.message ?? "Bank account rejected" });
        }
        await admin.from("payout_accounts").update({ recipient_code: recipient }).eq("user_id", caller.uid);
      }

      await admin.from("withdrawals").update({ status: "processing", updated_at: new Date().toISOString() }).eq("id", w.id);
      const r = await fetch(`${PS}/transfer`, {
        method: "POST",
        headers: headers(),
        body: JSON.stringify({ source: "balance", amount: w.amount_kobo, recipient, reference: w.id, reason: "AutoWave withdrawal" }),
      });
      const j = await r.json();
      if (!r.ok || !j?.status) {
        await admin.rpc("fail_withdrawal", { p_id: w.id, p_reason: j?.message ?? "Transfer failed" });
        return json({ status: "failed", error: j?.message ?? "Transfer failed" });
      }
      await admin.from("withdrawals").update({ transfer_code: j.data?.transfer_code ?? null }).eq("id", w.id);
      return json({ status: "processing" });
    }
    return json({ error: "unknown action" }, 400);
  } catch (_e) {
    return json({ error: "internal error" }, 500);
  }
});
