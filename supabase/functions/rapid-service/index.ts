// supabase/functions/rapid-service/index.ts
//
// Sicherer Proxy für Wörni (Startseite und Schaltzentrale in
// index.greathairday). Gleiches Muster wie rapid-function:
// - Ohne gültige Supabase-Session gibt es 401.
// - Nur die Inhaberin darf Wörni nutzen: Die Rolle wird hier auf dem
//   Server geprüft (teamapp_persons, rolle = 'inhaberin', aktiv = true),
//   nicht nur im Browser. Alle anderen bekommen 403.
// - Der Browser schickt NIE model/max_tokens/system, nur einen festen
//   "zweck" und den Nutzertext. Modell, Anleitung und Antwortlänge
//   stehen hier fest.
//
// Aufrufer (grep nach "rapid-service" in index.greathairday):
//   index.html        → zweck "woerni-start"
//   schaltzentrale.html → "woerni-sprache", "woerni-schaltzentrale", "woerni-fokus"
//
// Deploy: supabase functions deploy rapid-service
// Secret: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// Muss gleichzeitig mit dem passenden Pull Request in index.greathairday
// live gehen: die alte Fassung der Aufrufer schickt noch keinen "zweck"
// und bekommt von dieser Funktion 400.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

// Anleitungen und Antwortlängen serverseitig festgelegt; der Browser wählt
// nur per `zweck`. Texte unverändert aus den bisherigen Aufrufern übernommen.
const ZWECKE: Record<string, { system: string; maxTokens: number }> = {
  // Startseite (index.html), Sprechen-Knopf: kurz, aufs Handy optimiert
  "woerni-start": {
    maxTokens: 300,
    system: "Du bist \"Wörni\", der zentrale KI-Betriebsassistent und die operative Schaltzentrale für den Friseursalon \"A great hair day\" in Wien (Rechte Wienzeile 47, 1050 Wien). Deine Hauptaufgabe ist es, die Salonleitung (Mirjam Walenta) und das Team bei allen täglichen Abläufen, der Organisation, der Lehrlingsausbildung und administrativen Aufgaben zu unterstützen. TONFALL: Professionell, warmherzig, strukturiert, verlässlich und mit einem leichten Wiener Charm. Direkt auf den Punkt, klar strukturiert, lösungsorientiert. Du antwortest hier über die HTML-Schaltzentrale/Startseite — halte Antworten kurz, präzise und aufs Handy optimiert: max. 2–3 Sätze, Bullet Points und Emojis erlaubt. Antworte immer auf Deutsch (Österreich).",
  },
  // Schaltzentrale, direkte Sprachantwort
  "woerni-sprache": {
    maxTokens: 300,
    system: "Du bist Wörni, der KI-Assistent von Mirjam Walenta, Friseurmeisterin in Wien. Antworte auf Deutsch, kurz und freundlich. Max. 2–3 Sätze.",
  },
  // Schaltzentrale, Antwort beim Bestätigen einer Sprach-Aufgabe
  "woerni-schaltzentrale": {
    maxTokens: 300,
    system: "Du bist \"Wörni\", der zentrale KI-Betriebsassistent und die operative Schaltzentrale für den Friseursalon \"A great hair day\" in Wien (Rechte Wienzeile 47, 1050 Wien). Deine Hauptaufgabe ist es, die Salonleitung (Mirjam Walenta) und das Team bei allen täglichen Abläufen, der Organisation, der Lehrlingsausbildung und administrativen Aufgaben zu unterstützen. TONFALL: Professionell, warmherzig, strukturiert, verlässlich und mit einem leichten Wiener Charm. Direkt auf den Punkt, klar strukturiert, lösungsorientiert. Du antwortest hier über die HTML-Schaltzentrale — antworte ausführlicher und strukturiert, nutze Bullet Points und Emojis. Antworte immer auf Deutsch (Österreich).",
  },
  // Schaltzentrale, ein Satz, warum die Fokus-Aufgabe oben steht
  "woerni-fokus": {
    maxTokens: 60,
    system: "Du erklärst in genau einem kurzen Satz auf Deutsch, warum eine Aufgabe gerade an erster Stelle steht. Beginne mit \"Zuerst, weil\". Ruhig, konkret, keine Floskeln, keine Anrede, kein \"scheint\"/\"vielleicht\"/\"könnte\". Maximal 15 Wörter. Antworte nur mit dem Satz, sonst nichts.",
  },
};

const MODEL = "claude-sonnet-4-6";
const MAX_INPUT_CHARS = 2000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body),
    { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")
    return new Response("Method not allowed", { status: 405, headers: cors });

  // 1) Token prüfen — ohne gültigen Benutzer 401
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
  if (authErr || !user || !user.email) return json({ error: "Nicht angemeldet" }, 401);

  // 2) Rolle prüfen — Wörni ist der Inhaberin vorbehalten. Die E-Mail kommt
  //    aus dem geprüften Token, nicht aus dem Body.
  const { data: person, error: rolleErr } = await supabase
    .from("teamapp_persons")
    .select("rolle")
    .eq("email", user.email)
    .eq("aktiv", true)
    .maybeSingle();
  if (rolleErr || person?.rolle !== "inhaberin")
    return json({ error: "Kein Zugriff — Wörni ist der Chefin vorbehalten" }, 403);

  // 3) Body validieren — nur zweck + text zählen
  let body: { zweck?: string; text?: string };
  try { body = await req.json(); }
  catch { return json({ error: "Ungültiger Body" }, 400); }

  const zweck = ZWECKE[body.zweck ?? ""];
  if (!zweck) return json({ error: "Unbekannter zweck" }, 400);

  const userText = String(body.text ?? "").slice(0, MAX_INPUT_CHARS);
  if (!userText.trim()) return json({ error: "Kein Text" }, 400);

  // 4) Anthropic aufrufen — Modell/Anleitung/Limit fest
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: zweck.maxTokens,
      system: zweck.system,
      messages: [{ role: "user", content: userText }],
    }),
  });
  const data = await r.json();
  return json(data, r.status);
});
