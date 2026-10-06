// AutoLearn: an AI tutor for STEM, automotive engineering, batteries and
// sustainable mobility, for young learners (7-18) and drivers.
//   POST { "message": "...", "level": "11-14", "language": "English", "topic"?: "Batteries" }
//   -> { "reply": "..." }
// Conversation history is stored in learn_messages (private to the user).
// Secret: GEMINI_API_KEY. Optional: GEMINI_MODEL to pin a model.
import { adminClient, callerClient, cors, env, json } from "../_shared/http.ts";

const GEMINI_KEY = env("GEMINI_API_KEY");
const MODELS = [env("GEMINI_MODEL"), "gemini-flash-latest", "gemini-3.5-flash", "gemini-2.5-flash"].filter(Boolean);
const HOURLY_LIMIT = 40;

const LEVELS: Record<string, string> = {
  "7-10": "a child aged 7 to 10. Use very short sentences, everyday comparisons (toys, bicycles, cooking), and no jargon. At most 120 words.",
  "11-14": "a learner aged 11 to 14. Explain clearly with one simple example and introduce at most two technical words, defining them. At most 180 words.",
  "15-18": "a secondary-school student aged 15 to 18. Use correct technical terms, simple numbers or formulas where they help, and link to real careers. At most 250 words.",
  "adult": "an adult driver or vehicle owner. Be practical and direct. At most 220 words.",
};
const LANGUAGES = ["English", "Nigerian Pidgin", "Yoruba", "Hausa", "Igbo", "French", "Swahili", "Arabic", "Portuguese", "Amharic", "Zulu"];

function systemPrompt(level: string, language: string) {
  return `You are AutoLearn, the learning companion inside the AutoWave app, built to widen access to STEM and practical skills for African young people, including those out of school, and for drivers.

You teach: science, technology, engineering and maths through vehicles; how engines, brakes, batteries and electrics work; electric vehicles and batteries; sustainable mobility; carbon emissions and climate; recycling and the circular economy; road safety; and career pathways into the green and digital economy.

You are talking to ${LEVELS[level] ?? LEVELS["11-14"]}
Reply in ${language}. If that language is not English, keep widely used technical terms (like "battery" or "engine") in English in brackets the first time.

How to teach:
- Start with the direct answer, then explain why.
- Use examples from everyday African life (danfo buses, okadas, keke, generators, solar panels, markets).
- When it helps, end with one short "Try this" activity or question that needs no special equipment.
- If the learner asks for a quiz, ask ONE multiple-choice question with options A-D and wait for their answer before revealing it; then explain.
- Plain text only. You may use short lists with "-" but no markdown headings or tables.

Safety:
- Never give step-by-step instructions that are dangerous for the learner's age: working on high-voltage EV systems, opening batteries, handling battery acid or fuel, lifting cars, or anything involving fire. Explain the idea and say an adult or a trained mechanic must do it.
- For a real fault in someone's vehicle (brakes, steering, overheating, smells of fuel or burning), give general guidance and advise them to stop driving and request a mechanic in the AutoWave app.
- Stay on learning topics. If asked about something unrelated or inappropriate for young people, kindly steer back to learning.
- Never ask for personal information such as full name, school, address or phone number.`;
}

async function askGemini(system: string, contents: unknown[]) {
  let lastErr = "";
  for (const model of MODELS) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents,
        generationConfig: { temperature: 0.6, maxOutputTokens: 1200 },
        safetySettings: [
          { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_LOW_AND_ABOVE" },
          { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_LOW_AND_ABOVE" },
          { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_LOW_AND_ABOVE" },
          { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_LOW_AND_ABOVE" },
        ],
      }),
    });
    const j = await r.json().catch(() => ({}));
    if (r.ok) {
      const text = (j?.candidates?.[0]?.content?.parts ?? [])
        .filter((p: any) => typeof p.text === "string" && !p.thought)
        .map((p: any) => p.text)
        .join("")
        .trim();
      if (text) return text;
      lastErr = "empty";
      continue;
    }
    lastErr = j?.error?.message ?? String(r.status);
    // Model retired or busy: try the next one.
    if (![404, 429, 500, 503].includes(r.status)) break;
  }
  throw new Error(lastErr);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!GEMINI_KEY) return json({ error: "AutoLearn isn't configured yet" }, 503);
  const caller = await callerClient(req);
  if (!caller) return json({ error: "unauthorized" }, 401);

  let b: { message?: string; level?: string; language?: string; topic?: string };
  try { b = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const message = String(b.message ?? "").trim().slice(0, 1500);
  if (!message) return json({ error: "Type a question first" }, 400);
  const level = LEVELS[b.level ?? ""] ? b.level! : "11-14";
  const language = LANGUAGES.includes(b.language ?? "") ? b.language! : "English";
  const topic = b.topic ? String(b.topic).slice(0, 60) : null;

  const admin = adminClient();
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await admin.from("learn_messages").select("id", { count: "exact", head: true })
    .eq("user_id", caller.uid).eq("role", "user").gte("created_at", since);
  if ((count ?? 0) >= HOURLY_LIMIT) {
    return json({ error: "You've asked a lot of questions this hour. Take a short break and try again soon." }, 429);
  }

  const { data: history } = await admin.from("learn_messages").select("role, content")
    .eq("user_id", caller.uid).order("created_at", { ascending: false }).limit(12);
  const contents = [...(history ?? [])].reverse().map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: m.content }],
  }));
  contents.push({ role: "user", parts: [{ text: message }] });

  let reply: string;
  try {
    reply = await askGemini(systemPrompt(level, language), contents);
  } catch (_e) {
    return json({ error: "AutoLearn is busy right now. Try again in a moment." }, 502);
  }
  reply = reply.slice(0, 7900);

  await admin.from("learn_messages").insert([
    { user_id: caller.uid, role: "user", content: message, topic, level, language },
    { user_id: caller.uid, role: "assistant", content: reply, topic, level, language },
  ]);
  return json({ reply });
});
