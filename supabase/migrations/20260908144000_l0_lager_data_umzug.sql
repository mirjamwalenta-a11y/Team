-- ════════════════════════════════════════════════════════════
--  L0 — lager_data ins Hauptprojekt (wrxlaltgtgkdomklgrlj) holen.
--
--  Hintergrund: Lager_index.html loggt sich über AUTH_CLIENT im
--  HAUPTPROJEKT ein (wie schon lager_bestellliste/-historie), aber
--  lager_data lag bisher im separaten Lager-Projekt
--  (lpuxvvfrrcnbuzafscyk) — ein Session-Token aus dem Hauptprojekt
--  validiert dort nicht. Der Client-Fix (BL_URL/BL_KEY statt
--  SUPA_URL/SUPA_KEY in syncToSupabase/loadFromSupabase) ist bereits
--  gepusht und setzt voraus, dass diese Migration hier gelaufen ist
--  UND die bestehenden Daten übertragen wurden (siehe Schritt 2 unten)
--  — bis dahin schlägt der Cloud-Sync mit "Nicht angemeldet" fehl
--  (kein stiller Anon-Key-Fallback mehr, siehe blFetch/syncToSupabase).
--
--  Schritt 1 — in DIESEM Projekt (wrxlaltgtgkdomklgrlj) ausführen:
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.lager_data (
  id text PRIMARY KEY,
  data jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.lager_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Nur angemeldete lesen" ON public.lager_data;
CREATE POLICY "Nur angemeldete lesen" ON public.lager_data
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Nur angemeldete aendern" ON public.lager_data;
CREATE POLICY "Nur angemeldete aendern" ON public.lager_data
  FOR UPDATE TO authenticated
  USING (true) WITH CHECK (true);
-- Kein INSERT/DELETE-Policy für Clients — die App tut nur PATCH auf die
-- bereits bestehende "singleton"-Zeile (siehe Schritt 2).

-- ════════════════════════════════════════════════════════════
--  Schritt 2 — Daten übertragen (einmalig, von Hand):
--
--  a) Im ALTEN Projekt (lpuxvvfrrcnbuzafscyk), SQL-Editor:
--       select data from public.lager_data where id = 'singleton';
--     Ergebnis (das JSON) kopieren.
--
--  b) In DIESEM Projekt (wrxlaltgtgkdomklgrlj), SQL-Editor, das
--     kopierte JSON anstelle von '<HIER-EINFUEGEN>' einsetzen:
--
--       insert into public.lager_data (id, data, updated_at)
--       values ('singleton', '<HIER-EINFUEGEN>'::jsonb, now())
--       on conflict (id) do update set data = excluded.data, updated_at = now();
--
--  c) Erst DANACH ist der bereits gepushte Client-Fix funktionsfähig.
--     Zum Schluss im alten Projekt die Tabelle NICHT sofort löschen —
--     ein paar Tage als Backup stehen lassen, bis der Sync im neuen
--     Projekt bestätigt läuft.
-- ════════════════════════════════════════════════════════════
