-- ════════════════════════════════════════════════════════════
--  RLS für ghd_*, salon_*, einkauf_*, lager_bestellliste
--  (Projekt wrxlaltgtgkdomklgrlj). Alle Tabellen lieferten im
--  Live-RLS-Test HTTP 200 mit [] — RLS aktiv ODER nur leer, von
--  außen nicht unterscheidbar. Diese Migration aktiviert RLS
--  idempotent (ALTER ... ENABLE ist ein no-op, wenn schon an) und
--  legt Policies nur an, falls sie fehlen (DROP POLICY IF EXISTS
--  davor).
--
--  Vor dem Einspielen per MCP/Dashboard prüfen, ob abweichende
--  Policies bereits bestehen (z.B. spezifischere Chefin-only-Regeln)
--  — diese Migration überschreibt gleichnamige Policies, lässt
--  andere unangetastet.
--
--  Muster: authenticated darf lesen + schreiben (insert/update),
--  kein anon-Zugriff. Löschen ist bewusst nicht pauschal erlaubt —
--  wo die Apps löschen (z.B. Einkaufsartikel), wird das unten
--  gesondert freigegeben.
-- ════════════════════════════════════════════════════════════

-- ── ghd_ereignisse ─────────────────────────────────────────────
ALTER TABLE public.ghd_ereignisse ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ghd_ereignisse_select" ON public.ghd_ereignisse;
CREATE POLICY "ghd_ereignisse_select" ON public.ghd_ereignisse
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "ghd_ereignisse_insert" ON public.ghd_ereignisse;
CREATE POLICY "ghd_ereignisse_insert" ON public.ghd_ereignisse
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "ghd_ereignisse_update" ON public.ghd_ereignisse;
CREATE POLICY "ghd_ereignisse_update" ON public.ghd_ereignisse
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- ── ghd_aufgaben ───────────────────────────────────────────────
ALTER TABLE public.ghd_aufgaben ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ghd_aufgaben_select" ON public.ghd_aufgaben;
CREATE POLICY "ghd_aufgaben_select" ON public.ghd_aufgaben
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "ghd_aufgaben_insert" ON public.ghd_aufgaben;
CREATE POLICY "ghd_aufgaben_insert" ON public.ghd_aufgaben
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "ghd_aufgaben_update" ON public.ghd_aufgaben;
CREATE POLICY "ghd_aufgaben_update" ON public.ghd_aufgaben
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- ── ghd_aufgaben_vorlagen ──────────────────────────────────────
ALTER TABLE public.ghd_aufgaben_vorlagen ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ghd_aufgaben_vorlagen_select" ON public.ghd_aufgaben_vorlagen;
CREATE POLICY "ghd_aufgaben_vorlagen_select" ON public.ghd_aufgaben_vorlagen
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "ghd_aufgaben_vorlagen_insert" ON public.ghd_aufgaben_vorlagen;
CREATE POLICY "ghd_aufgaben_vorlagen_insert" ON public.ghd_aufgaben_vorlagen
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "ghd_aufgaben_vorlagen_update" ON public.ghd_aufgaben_vorlagen;
CREATE POLICY "ghd_aufgaben_vorlagen_update" ON public.ghd_aufgaben_vorlagen
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- ── ghd_aufgaben_verlauf ───────────────────────────────────────
ALTER TABLE public.ghd_aufgaben_verlauf ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ghd_aufgaben_verlauf_select" ON public.ghd_aufgaben_verlauf;
CREATE POLICY "ghd_aufgaben_verlauf_select" ON public.ghd_aufgaben_verlauf
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "ghd_aufgaben_verlauf_insert" ON public.ghd_aufgaben_verlauf;
CREATE POLICY "ghd_aufgaben_verlauf_insert" ON public.ghd_aufgaben_verlauf
  FOR INSERT TO authenticated WITH CHECK (true);

-- ── salon_checks ───────────────────────────────────────────────
ALTER TABLE public.salon_checks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "salon_checks_select" ON public.salon_checks;
CREATE POLICY "salon_checks_select" ON public.salon_checks
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "salon_checks_insert" ON public.salon_checks;
CREATE POLICY "salon_checks_insert" ON public.salon_checks
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "salon_checks_update" ON public.salon_checks;
CREATE POLICY "salon_checks_update" ON public.salon_checks
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- ── salon_monatszuweisung ──────────────────────────────────────
ALTER TABLE public.salon_monatszuweisung ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "salon_monatszuweisung_select" ON public.salon_monatszuweisung;
CREATE POLICY "salon_monatszuweisung_select" ON public.salon_monatszuweisung
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "salon_monatszuweisung_insert" ON public.salon_monatszuweisung;
CREATE POLICY "salon_monatszuweisung_insert" ON public.salon_monatszuweisung
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "salon_monatszuweisung_update" ON public.salon_monatszuweisung;
CREATE POLICY "salon_monatszuweisung_update" ON public.salon_monatszuweisung
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- ── einkauf_items (Artikel; Apps löschen einzelne Items) ───────
ALTER TABLE public.einkauf_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "einkauf_items_select" ON public.einkauf_items;
CREATE POLICY "einkauf_items_select" ON public.einkauf_items
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "einkauf_items_insert" ON public.einkauf_items;
CREATE POLICY "einkauf_items_insert" ON public.einkauf_items
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "einkauf_items_update" ON public.einkauf_items;
CREATE POLICY "einkauf_items_update" ON public.einkauf_items
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "einkauf_items_delete" ON public.einkauf_items;
CREATE POLICY "einkauf_items_delete" ON public.einkauf_items
  FOR DELETE TO authenticated USING (true);

-- ── einkauf_listen (Apps löschen ganze Listen) ─────────────────
ALTER TABLE public.einkauf_listen ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "einkauf_listen_select" ON public.einkauf_listen;
CREATE POLICY "einkauf_listen_select" ON public.einkauf_listen
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "einkauf_listen_insert" ON public.einkauf_listen;
CREATE POLICY "einkauf_listen_insert" ON public.einkauf_listen
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "einkauf_listen_update" ON public.einkauf_listen;
CREATE POLICY "einkauf_listen_update" ON public.einkauf_listen
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "einkauf_listen_delete" ON public.einkauf_listen;
CREATE POLICY "einkauf_listen_delete" ON public.einkauf_listen
  FOR DELETE TO authenticated USING (true);

-- ── einkauf_flex ───────────────────────────────────────────────
ALTER TABLE public.einkauf_flex ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "einkauf_flex_select" ON public.einkauf_flex;
CREATE POLICY "einkauf_flex_select" ON public.einkauf_flex
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "einkauf_flex_insert" ON public.einkauf_flex;
CREATE POLICY "einkauf_flex_insert" ON public.einkauf_flex
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "einkauf_flex_update" ON public.einkauf_flex;
CREATE POLICY "einkauf_flex_update" ON public.einkauf_flex
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "einkauf_flex_delete" ON public.einkauf_flex;
CREATE POLICY "einkauf_flex_delete" ON public.einkauf_flex
  FOR DELETE TO authenticated USING (true);

-- ── lager_bestellliste (liegt bereits im Hauptprojekt) ─────────
ALTER TABLE public.lager_bestellliste ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "lager_bestellliste_select" ON public.lager_bestellliste;
CREATE POLICY "lager_bestellliste_select" ON public.lager_bestellliste
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "lager_bestellliste_insert" ON public.lager_bestellliste;
CREATE POLICY "lager_bestellliste_insert" ON public.lager_bestellliste
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "lager_bestellliste_update" ON public.lager_bestellliste;
CREATE POLICY "lager_bestellliste_update" ON public.lager_bestellliste
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "lager_bestellliste_delete" ON public.lager_bestellliste;
CREATE POLICY "lager_bestellliste_delete" ON public.lager_bestellliste
  FOR DELETE TO authenticated USING (true);

-- Falls eine dieser Tabellen in diesem Projekt nicht existiert (z.B. weil
-- sie unter anderem Namen läuft), schlägt genau diese Anweisung fehl —
-- die übrigen sind unabhängig und können einzeln erneut eingespielt werden.
