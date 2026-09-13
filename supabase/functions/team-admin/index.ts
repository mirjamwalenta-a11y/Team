// supabase/functions/team-admin/index.ts
//
// Von team.html aufgerufen für: create_user, set_password, deactivate, reactivate.
// Ersetzt eine bisher live deployte, aber in keinem Repo einsehbare ältere Version
// dieser Funktion, die noch versucht hat, eine Spalte `pw_hash` in
// `teamapp_persons` zu beschreiben — genau die Spalte, die die P0-Migration
// (20260908143643_p0_teamapp_persons.sql) bewusst gelöscht hat. Dadurch schlug
// "Passwort setzen" für jede Person mit PGRST204 ("pw_hash column not found")
// fehl. Diese Version fasst ausschließlich das echte Supabase-Auth-Konto an,
// nie teamapp_persons.
//
// Serverseitige Berechtigung: nur eine Person mit rolle='inhaberin' in
// teamapp_persons darf diese Aktionen ausführen — geprüft über den echten
// Session-Token der aufrufenden Person, nicht über einen vom Client
// mitgeschickten Wert.
//
// Deploy: supabase functions deploy team-admin
// Braucht (zusätzlich zu den von Supabase automatisch gesetzten SUPABASE_URL/
// SUPABASE_ANON_KEY) keine weiteren Secrets — SUPABASE_SERVICE_ROLE_KEY wird
// von der Supabase-Laufzeit automatisch bereitgestellt.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// admin.listUsers() unterstützt kein direktes E-Mail-Filter über alle
// supabase-js-Versionen hinweg zuverlässig — deshalb Seiten durchsuchen.
// Für ein Team dieser Größe (eine handvoll Konten) unproblematisch.
async function findUserByEmail(admin: ReturnType<typeof createClient>, email: string) {
  let page = 1;
  const perPage = 200;
  for (;;) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const hit = data.users.find((u) => u.email?.toLowerCase() === email.toLowerCase());
    if (hit) return hit;
    if (data.users.length < perPage) return null;
    page++;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // 1) Aufrufer identifizieren (eigener Token, kein Service-Role nötig dafür)
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const asCaller = createClient(SUPABASE_URL, SUPABASE_ANON, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authErr } = await asCaller.auth.getUser(jwt);
  if (authErr || !user?.email) return json({ error: "Nicht angemeldet" }, 401);

  // 2) Serverseitig prüfen: nur Inhaberin darf weiter
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { data: rows, error: personErr } = await admin
    .from("teamapp_persons")
    .select("rolle")
    .eq("email", user.email)
    .eq("aktiv", true)
    .limit(1);
  if (personErr) return json({ error: "Rollenprüfung fehlgeschlagen: " + personErr.message }, 500);
  if (!rows || rows.length === 0 || rows[0].rolle !== "inhaberin") {
    return json({ error: "Nur die Inhaberin darf das." }, 403);
  }

  // 3) Body lesen
  let body: { action?: string; email?: string; password?: string };
  try { body = await req.json(); }
  catch { return json({ error: "Ungültiger Body" }, 400); }
  const { action, email, password } = body;
  if (!action || !email) return json({ error: "action und email erforderlich" }, 400);

  try {
    if (action === "create_user") {
      if (!password) throw new Error("password erforderlich");
      const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      if (error) throw error;
      return json({ ok: true, id: data.user?.id });
    }

    if (action === "set_password") {
      if (!password) throw new Error("password erforderlich");
      const existing = await findUserByEmail(admin, email);
      if (existing) {
        const { error } = await admin.auth.admin.updateUserById(existing.id, { password });
        if (error) throw error;
        return json({ ok: true, id: existing.id });
      }
      // Person ohne Konto (z.B. aus der Zeit vor der echten Supabase-Auth-Anbindung) —
      // Konto jetzt nachträglich anlegen.
      const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      if (error) throw error;
      return json({ ok: true, id: data.user?.id });
    }

    if (action === "deactivate" || action === "reactivate") {
      const existing = await findUserByEmail(admin, email);
      if (!existing) throw new Error("Kein Konto für diese E-Mail gefunden");
      const ban_duration = action === "deactivate" ? "876000h" : "none"; // ~100 Jahre / aufheben
      const { error } = await admin.auth.admin.updateUserById(existing.id, { ban_duration });
      if (error) throw error;
      return json({ ok: true, id: existing.id });
    }

    return json({ error: "Unbekannte action" }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 400);
  }
});
