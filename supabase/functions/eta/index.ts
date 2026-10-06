// How long the mechanic needs to reach the driver (Google Routes API, live traffic).
// Stores the result on the request so both phones show the same number.
//   POST { "requestId": "<uuid>", "includeRoute": true }
// Secret: GOOGLE_MAPS_API_KEY (Routes API enabled on it)
// Safety: the caller's JWT loads the request, so RLS limits this to the job's
// driver or mechanic. Results are cached for 20 s so Google isn't billed per call.
import { adminClient, callerClient, cors, env, json } from "../_shared/http.ts";

const KEY = env("GOOGLE_MAPS_API_KEY");
const CACHE_SECONDS = 20;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const caller = await callerClient(req);
  if (!caller) return json({ error: "unauthorized" }, 401);

  let body: { requestId?: string; includeRoute?: boolean };
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  if (!body.requestId || !UUID.test(body.requestId)) return json({ error: "bad request id" }, 400);

  try {
    const { data: r } = await caller.db
      .from("service_requests")
      .select("id, status, mechanic_id, pickup_lat, pickup_lng, eta_seconds, distance_m, eta_updated_at")
      .eq("id", body.requestId)
      .maybeSingle();
    if (!r) return json({ error: "not found" }, 404);

    const { data: loc } = await caller.db
      .from("mechanic_locations")
      .select("latitude, longitude, updated_at")
      .eq("mechanic_id", r.mechanic_id)
      .maybeSingle();
    const mechanic = loc ? { lat: loc.latitude, lng: loc.longitude, updatedAt: loc.updated_at } : null;

    if (r.status !== "en_route" || !mechanic || !KEY) {
      return json({ seconds: r.eta_seconds ?? null, meters: r.distance_m ?? null, route: null, mechanic });
    }

    const ageMs = r.eta_updated_at ? Date.now() - new Date(r.eta_updated_at).getTime() : Infinity;
    if (ageMs < CACHE_SECONDS * 1000 && !body.includeRoute) {
      return json({ seconds: r.eta_seconds, meters: r.distance_m, route: null, mechanic });
    }

    const res = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": KEY,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: mechanic.lat, longitude: mechanic.lng } } },
        destination: { location: { latLng: { latitude: r.pickup_lat, longitude: r.pickup_lng } } },
        travelMode: "DRIVE",
        routingPreference: "TRAFFIC_AWARE",
      }),
    });
    const j = await res.json();
    const route = j?.routes?.[0];
    if (!res.ok || !route) {
      return json({ seconds: r.eta_seconds ?? null, meters: r.distance_m ?? null, route: null, mechanic });
    }

    const seconds = Math.max(60, Math.round(parseFloat(String(route.duration ?? "0").replace("s", ""))));
    const meters = Math.round(route.distanceMeters ?? 0);
    await adminClient()
      .from("service_requests")
      .update({ eta_seconds: seconds, distance_m: meters, eta_updated_at: new Date().toISOString() })
      .eq("id", r.id);

    return json({ seconds, meters, route: route.polyline?.encodedPolyline ?? null, mechanic });
  } catch (_e) {
    return json({ error: "internal error" }, 500);
  }
});
