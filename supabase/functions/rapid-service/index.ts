// supabase/functions/rapid-service/index.ts
//
// Gleiches Muster wie rapid-function (siehe dort für Details) — Token-
// Pflicht, festes Modell/Limit, Systemprompt nur per "zweck" wählbar.
//
// WICHTIG vor dem Deploy: Dieses Repo (Team) kennt die Aufrufer von
// rapid-service nicht — die SYSTEM_PROMPTS-Liste unten ist ein Platzhalter.
// Vor dem Deploy in den jeweils aufrufenden Apps (grep nach
// "rapid-service") nachsehen, welche zweck-Werte/Prompts tatsächlich
// gebraucht werden, und die Liste entsprechend ergänzen.
//
// Deploy: supabase functions deploy rapid-service
// Secret: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

// TODO (Mensch): reale zweck-Werte aus den aufrufenden Apps eintragen.
const SYSTEM_PROMPTS: Record<string, string> = {
  allgemein: "Du bist ein knapper, hilfreicher Assistent für A Great Hair Day. Antworte auf Deutsch, maximal 4 Sätze.",
};

const MODEL = "claude-sonnet-4-6";
const MAX_TOKENS = 400;
const MAX_INPUT_CHARS = 2000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")
    return new Response("Method not allowed", { status: 405, headers: cors });

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
  if (authErr || !user)
    return new Response(JSON.stringify({ error: "Nicht angemeldet" }),
      { status: 401, headers: { ...cors, "Content-Type": "application/json" } });

  let body: { zweck?: string; text?: string };
  try { body = await req.json(); }
  catch { return new Response(JSON.stringify({ error: "Ungültiger Body" }),
    { status: 400, headers: { ...cors, "Content-Type": "application/json" } }); }

  const system = SYSTEM_PROMPTS[body.zweck ?? ""];
  if (!system)
    return new Response(JSON.stringify({ error: "Unbekannter zweck" }),
      { status: 400, headers: { ...cors, "Content-Type": "application/json" } });

  const userText = String(body.text ?? "").slice(0, MAX_INPUT_CHARS);
  if (!userText.trim())
    return new Response(JSON.stringify({ error: "Kein Text" }),
      { status: 400, headers: { ...cors, "Content-Type": "application/json" } });

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system,
      messages: [{ role: "user", content: userText }],
    }),
  });
  const data = await r.json();
  return new Response(JSON.stringify(data),
    { status: r.status, headers: { ...cors, "Content-Type": "application/json" } });
});
