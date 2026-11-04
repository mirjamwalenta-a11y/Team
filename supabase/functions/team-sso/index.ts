// supabase/functions/team-sso/index.ts
//
// Einstieg in die Team-App über den Team-Login der Startseite (apps.html:
// Kennung + PIN). Bisher kannte die Team-App nur ihr eigenes E-Mail-Konto
// pro Person — wer über Kennung + PIN angemeldet war, landete in team.html
// trotzdem auf dem E-Mail-Login und kam ohne die Chefin nicht hinein.
//
// Ablauf:
//   1. team.html schickt den Sitzungs-Token aus dem Team-Login
//      (localStorage „ghd_session_token“, zufällig und ablaufend, siehe
//      salon_sessions / session_by_token).
//   2. Diese Funktion prüft den Token SERVERSEITIG über session_by_token —
//      nie über vom Client mitgeschickte Namen/Rollen (CLAUDE.md Regel 3/4).
//   3. Sie sucht die passende aktive Person in teamapp_persons (über den
//      Namen) — NIE eine Person mit rolle='inhaberin'. Die Chefin meldet
//      sich weiterhin nur mit E-Mail + Passwort an.
//   4. Sie erzeugt für deren bestehendes Auth-Konto einen einmaligen
//      Anmelde-Code (generateLink, es wird KEINE Mail verschickt) und gibt
//      nur den gehashten Code zurück. team.html tauscht ihn mit
//      verifyOtp gegen eine normale Sitzung dieser Person — damit gelten
//      in der Team-App genau dieselben RLS-Regeln wie beim E-Mail-Login.
//
// Keine neue Tabelle, keine neuen Grants.
// Deploy: supabase functions deploy team-sso
// (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY stellt die Laufzeit selbst bereit.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// Wie in team-admin: Seiten durchsuchen (kleines Team, wenige Konten).
async function findUserByEmail(admin: ReturnType<typeof createClient>, email: string) {
  let page = 1;
  const perPage = 200;
  for (;;) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const hit = data.users.find((u) => u.email?.toLowerCase() === email);
    if (hit) return hit;
    if (data.users.length < perPage) return null;
    page++;
  }
}

const norm = (s: unknown) => String(s ?? "").trim().toLowerCase().replace(/\s+/g, " ");
const vorname = (s: unknown) => norm(s).split(" ")[0];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { token?: string };
  try { body = await req.json(); } catch { return json({ error: "Ungültiger Body" }, 400); }
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token || token.length > 200) return json({ error: "Nicht angemeldet" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

  // 1) Team-Login-Sitzung serverseitig prüfen
  const { data: sitzung, error: sErr } = await admin.rpc("session_by_token", { p_token: token });
  if (sErr) return json({ error: "Anmeldung konnte nicht geprüft werden" }, 500);
  const salon = Array.isArray(sitzung) ? sitzung[0] : sitzung;
  if (!salon || !salon.name) return json({ error: "Team-Login abgelaufen – bitte neu anmelden" }, 401);
  if (salon.rolle === "chefin" || salon.rolle === "inhaberin") {
    return json({ error: "Die Inhaberin meldet sich mit E-Mail und Passwort an" }, 403);
  }

  // 2) Passende Person in der Team-App (nie die Inhaberin)
  const { data: personen, error: pErr } = await admin
    .from("teamapp_persons")
    .select("name,email,rolle,aktiv")
    .eq("aktiv", true)
    .neq("rolle", "inhaberin");
  if (pErr) return json({ error: "Team-App nicht erreichbar" }, 500);
  const liste = (personen ?? []).filter((p) => p.email);
  let treffer = liste.filter((p) => norm(p.name) === norm(salon.name));
  if (treffer.length === 0) treffer = liste.filter((p) => vorname(p.name) === vorname(salon.name));
  if (treffer.length !== 1) {
    return json({ error: "Für dich ist in der Team-App noch kein Zugang eingerichtet – bitte Mirjam Bescheid geben" }, 404);
  }
  const email = String(treffer[0].email).toLowerCase();

  // 3) Nur für ein BESTEHENDES, nicht gesperrtes Konto (generateLink würde sonst
  //    eines neu anlegen). Konten legt weiterhin nur die Chefin an (team-admin).
  let konto;
  try { konto = await findUserByEmail(admin, email); } catch { return json({ error: "Team-App nicht erreichbar" }, 500); }
  if (!konto) {
    return json({ error: "Für dich ist in der Team-App noch kein Zugang eingerichtet – bitte Mirjam Bescheid geben" }, 404);
  }
  if (konto.banned_until && new Date(konto.banned_until) > new Date()) {
    return json({ error: "Dein Team-App-Zugang ist deaktiviert" }, 403);
  }

  // 4) Einmaligen Anmelde-Code für dieses Konto erzeugen (es wird keine Mail verschickt)
  const { data: link, error: lErr } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const hashed = link?.properties?.hashed_token;
  if (lErr || !hashed) {
    return json({ error: "Für dich ist in der Team-App noch kein Zugang eingerichtet – bitte Mirjam Bescheid geben" }, 404);
  }
  return json({ ok: true, token_hash: hashed, email });
});
