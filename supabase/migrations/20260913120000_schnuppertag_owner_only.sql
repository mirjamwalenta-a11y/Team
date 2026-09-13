-- ════════════════════════════════════════════════════════════
--  Schnuppertag (Repo lernquiz.greathairday, Projekt wrxlaltgtgkdomklgrlj)
--  Verschärft RLS auf schnuppertage / probezeiten / probezeit_wochen /
--  probezeit_monats_feedback von "jede:r eingeloggte Person" auf
--  "nur die Inhaberin".
--
--  Befund: supabase_setup.sql (Repo lernquiz.greathairday) legt für diese
--  vier Tabellen die Policy "nur_auth" FOR ALL TO authenticated USING (true)
--  an. Im selben Supabase-Projekt kann sich aber jede Person über
--  lernquiz.html (Lehrlings-Registrierung: Name + 6-stellige PIN,
--  sb.auth.signUp) selbst einen "authenticated"-Account anlegen. Die
--  Policy deckt damit nicht nur die Inhaberin ab, sondern jeden
--  Lernquiz-Account — Bewerber-Archiv (schnuppertage) und
--  Probezeit-Daten (probezeit_*) sind serverseitig für diese Accounts
--  lesbar und schreibbar, unabhängig vom clientseitigen MEISTERIN_OK-Flag
--  in schnuppertag.html (das nur die Oberfläche steuert).
--
--  Frontend-Check (schnuppertag.html, loginMeisterin()): alle Schreib-
--  und Lesezugriffe auf diese vier Tabellen laufen ausschließlich über
--  die Inhaberinnen-Session (MEISTERIN_OK-Gate vor jedem Aufruf) — kein
--  Lehrling schreibt hier direkt. Die Verschärfung auf die Inhaberin
--  allein bricht daher keinen bestehenden Ablauf.
--
--  Sicher mehrfach ausführbar (DROP POLICY IF EXISTS vor jeder Änderung).
--  Im Supabase SQL-Editor des Projekts wrxlaltgtgkdomklgrlj ausführen.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION schnuppertag_is_owner() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT auth.jwt() ->> 'email' = 'mirjam.walenta@gmail.com';
$$;

ALTER TABLE public.schnuppertage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nur_auth" ON public.schnuppertage;
DROP POLICY IF EXISTS "nur_inhaberin" ON public.schnuppertage;
CREATE POLICY "nur_inhaberin" ON public.schnuppertage
  FOR ALL TO authenticated
  USING (schnuppertag_is_owner()) WITH CHECK (schnuppertag_is_owner());

ALTER TABLE public.probezeiten ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nur_auth" ON public.probezeiten;
DROP POLICY IF EXISTS "nur_inhaberin" ON public.probezeiten;
CREATE POLICY "nur_inhaberin" ON public.probezeiten
  FOR ALL TO authenticated
  USING (schnuppertag_is_owner()) WITH CHECK (schnuppertag_is_owner());

ALTER TABLE public.probezeit_wochen ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nur_auth" ON public.probezeit_wochen;
DROP POLICY IF EXISTS "nur_inhaberin" ON public.probezeit_wochen;
CREATE POLICY "nur_inhaberin" ON public.probezeit_wochen
  FOR ALL TO authenticated
  USING (schnuppertag_is_owner()) WITH CHECK (schnuppertag_is_owner());

ALTER TABLE public.probezeit_monats_feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nur_auth" ON public.probezeit_monats_feedback;
DROP POLICY IF EXISTS "nur_inhaberin" ON public.probezeit_monats_feedback;
CREATE POLICY "nur_inhaberin" ON public.probezeit_monats_feedback
  FOR ALL TO authenticated
  USING (schnuppertag_is_owner()) WITH CHECK (schnuppertag_is_owner());

-- Bewusst NICHT angefasst: der Eignungstest selbst (Fragen, Auswertung im
-- Browser) läuft komplett ohne Login und ohne diese Tabellen — das bleibt
-- unverändert offen, wie von der App für Bewerber:innen vorgesehen.
