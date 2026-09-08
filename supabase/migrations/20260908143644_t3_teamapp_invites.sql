-- ════════════════════════════════════════════════════════════
--  T3 — teamapp_invites muss vor dem Login anonym lesbar sein
--  (Onboarding-Link), aber ohne Ablaufdatum blieben Einladungen
--  für immer gültig. Sofortmaßnahme laut FIX-ANLEITUNG-AGENT.md:
--  Ablaufdatum + nur nicht-abgelaufene Einladungen anonym lesbar,
--  Anlegen/Löschen nur für angemeldete (Inhaberin-)Sessions.
--
--  Mittelfristig (nicht Teil dieser Migration): Prüfung in eine
--  Edge Function verlagern, die den Token serverseitig nachschlägt
--  und nur { gueltig, name } zurückgibt — dann kann teamapp_invites
--  komplett von anon SELECT ausgenommen werden.
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.teamapp_invites
  ADD COLUMN IF NOT EXISTS laeuft_ab timestamptz;

-- Bestehende Einladungen ohne Ablaufdatum: 7 Tage ab jetzt (einmalig,
-- damit die neue Policy sie nicht sofort verwirft).
UPDATE public.teamapp_invites
  SET laeuft_ab = now() + interval '7 days'
  WHERE laeuft_ab IS NULL;

ALTER TABLE public.teamapp_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anonym nur nicht abgelaufene Einladungen lesen" ON public.teamapp_invites;
CREATE POLICY "Anonym nur nicht abgelaufene Einladungen lesen" ON public.teamapp_invites
  FOR SELECT TO anon, authenticated
  USING (laeuft_ab IS NOT NULL AND laeuft_ab > now());

DROP POLICY IF EXISTS "Angemeldete legen Einladungen an" ON public.teamapp_invites;
CREATE POLICY "Angemeldete legen Einladungen an" ON public.teamapp_invites
  FOR INSERT TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Angemeldete loeschen Einladungen" ON public.teamapp_invites;
CREATE POLICY "Angemeldete loeschen Einladungen" ON public.teamapp_invites
  FOR DELETE TO authenticated
  USING (true);
