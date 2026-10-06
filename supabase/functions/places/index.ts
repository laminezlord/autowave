// Address search for the driver's search bar (Google Places API, New).
// Keeps the Google key on the server.
//   POST { "action": "autocomplete", "input": "herbert mac", "lat"?: 6.5, "lng"?: 3.3, "country"?: "ng" }
//   POST { "action": "details", "placeId": "ChIJ..." }
// Secret: GOOGLE_MAPS_API_KEY  (Places API (New) enabled on it)
import { callerClient, cors, env, json } from "../_shared/http.ts";

const KEY = env("GOOGLE_MAPS_API_KEY");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!KEY) return json({ error: "Address search isn't configured yet" }, 500);
  if (!(await callerClient(req))) return json({ error: "unauthorized" }, 401);

  let b: { action?: string; input?: string; placeId?: string; lat?: number; lng?: number; country?: string; session?: string };
  try { b = await req.json(); } catch { return json({ error: "invalid json" }, 400); }

  try {
    if (b.action === "autocomplete") {
      const input = String(b.input ?? "").trim().slice(0, 120);
      if (input.length < 2) return json({ predictions: [] });
      const body: Record<string, unknown> = { input };
      if (b.session) body.sessionToken = b.session;
      if (b.country && /^[a-z]{2}$/i.test(b.country)) body.includedRegionCodes = [b.country.toLowerCase()];
      if (typeof b.lat === "number" && typeof b.lng === "number") {
        body.locationBias = { circle: { center: { latitude: b.lat, longitude: b.lng }, radius: 30000 } };
      }
      const r = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Goog-Api-Key": KEY },
        body: JSON.stringify(body),
      });
      const j = await r.json();
      if (!r.ok) return json({ error: j?.error?.message ?? "search failed" }, 502);
      const predictions = (j.suggestions ?? [])
        .map((s: any) => s.placePrediction)
        .filter(Boolean)
        .map((p: any) => ({
          placeId: p.placeId,
          title: p.structuredFormat?.mainText?.text ?? p.text?.text ?? "",
          subtitle: p.structuredFormat?.secondaryText?.text ?? "",
        }));
      return json({ predictions });
    }

    if (b.action === "details") {
      if (!b.placeId || !/^[\w-]{10,300}$/.test(b.placeId)) return json({ error: "bad place id" }, 400);
      const qs = b.session ? `?sessionToken=${encodeURIComponent(b.session)}` : "";
      const r = await fetch(`https://places.googleapis.com/v1/places/${b.placeId}${qs}`, {
        headers: { "X-Goog-Api-Key": KEY, "X-Goog-FieldMask": "formattedAddress,location,displayName" },
      });
      const j = await r.json();
      if (!r.ok || !j.location) return json({ error: j?.error?.message ?? "place not found" }, 502);
      return json({
        placeId: b.placeId,
        name: j.displayName?.text ?? "",
        address: j.formattedAddress ?? j.displayName?.text ?? "",
        lat: j.location.latitude,
        lng: j.location.longitude,
      });
    }
    return json({ error: "unknown action" }, 400);
  } catch (_e) {
    return json({ error: "internal error" }, 500);
  }
});
