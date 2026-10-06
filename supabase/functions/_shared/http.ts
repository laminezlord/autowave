// Shared helpers for AutoWave Edge Functions.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

export const env = (k: string) => Deno.env.get(k) ?? "";

/** Client acting as the caller (RLS applies) plus the caller's user id. */
export async function callerClient(req: Request): Promise<{ db: SupabaseClient; uid: string; email?: string } | null> {
  const auth = req.headers.get("Authorization");
  if (!auth) return null;
  const db = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: auth } } });
  const { data } = await db.auth.getUser();
  if (!data?.user) return null;
  return { db, uid: data.user.id, email: data.user.email ?? undefined };
}

/** Service-role client: bypasses RLS. Only use after checking the caller. */
export function adminClient() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
}
