// Paystack calls this after payments and transfers. Deploy WITHOUT JWT checks:
//   supabase functions deploy paystack-webhook --no-verify-jwt
// Then set the webhook URL in Paystack (Settings -> API Keys & Webhooks):
//   https://<project-ref>.supabase.co/functions/v1/paystack-webhook
// Every request is authenticated by Paystack's HMAC-SHA512 signature instead.
// Secret: PAYSTACK_SECRET_KEY
import { adminClient, env } from "../_shared/http.ts";

const SECRET = env("PAYSTACK_SECRET_KEY");

async function hmacSha512Hex(key: string, body: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST" || !SECRET) return new Response("ignored", { status: 200 });
  const raw = await req.text();
  const signature = req.headers.get("x-paystack-signature") ?? "";
  if (!safeEqual(await hmacSha512Hex(SECRET, raw), signature)) return new Response("bad signature", { status: 401 });

  let evt: { event?: string; data?: any };
  try { evt = JSON.parse(raw); } catch { return new Response("bad json", { status: 400 }); }
  const admin = adminClient();
  const d = evt.data ?? {};

  try {
    if (evt.event === "charge.success" && typeof d.reference === "string" && d.reference.startsWith("AW-")) {
      if (d.currency === "NGN") {
        await admin.rpc("credit_topup", { p_reference: d.reference, p_amount_kobo: d.amount, p_raw: d });
      }
    } else if (evt.event === "transfer.success" && d.reference) {
      await admin.from("withdrawals").update({ status: "paid", updated_at: new Date().toISOString() }).eq("id", d.reference);
    } else if ((evt.event === "transfer.failed" || evt.event === "transfer.reversed") && d.reference) {
      await admin.rpc("fail_withdrawal", { p_id: d.reference, p_reason: d.reason ?? evt.event });
    }
  } catch (_e) {
    // Paystack retries non-2xx responses; credit_topup is idempotent, so let it retry.
    return new Response("error", { status: 500 });
  }
  return new Response("ok", { status: 200 });
});
