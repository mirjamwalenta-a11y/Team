-- ════════════════════════════════════════════════════════════
--  P0 — teamapp_persons war anonym lesbar und enthielt eine
--  pw_hash-Spalte mit Klartext-artigen Zugangsdaten (Live-Befund
--  im Security-Report, Runde 2 / rlstest.sh).
--
--  pw_hash wird ersatzlos entfernt: Der echte Login läuft über
--  Supabase Auth (sbAuth.auth.signInWithPassword / updateUser /
--  die team-admin Edge Function). Kein Code-Pfad in team.html
--  liest pw_hash zurück, um irgendeine Prüfung durchzuführen —
--  die Spalte war reine Redundanz, die zusätzlich als Datenleck
--  wirkte. Vor dem Drop sicherstellen (siehe FIX-ANLEITUNG-AGENT.md
--  P0.1), dass ein Mensch alle betroffenen Passwörter zurückgesetzt
--  hat (Mirjam zuerst) — die aktuellen Werte gelten als kompromittiert.
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.teamapp_persons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Angemeldete lesen Personen" ON public.teamapp_persons;
CREATE POLICY "Angemeldete lesen Personen" ON public.teamapp_persons
  FOR SELECT TO authenticated
  USING (true);
-- Bewusst KEINE Policy für anon — anonymes Lesen ist damit für alle
-- Befehle (SELECT/INSERT/UPDATE/DELETE) gesperrt, RLS ohne passende
-- Policy verweigert per Default.

-- Erst nach bestätigtem Passwort-Reset ausführen (siehe Kommentar oben):
ALTER TABLE public.teamapp_persons DROP COLUMN IF EXISTS pw_hash;
