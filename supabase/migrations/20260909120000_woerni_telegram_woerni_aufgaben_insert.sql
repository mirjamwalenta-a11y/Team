-- ════════════════════════════════════════════════════════════
--  Wörni Telegram Phase 1 · woerni_aufgaben
--  Erlaubt dem Wörni-Telegram-Service-Konto, eigene Notizen/Besprechungen
--  in woerni_aufgaben ANZULEGEN (INSERT) — ausschließlich das.
--  Lesen/Ändern/Löschen bleibt exklusiv bei der bestehenden "Nur Boss"-Policy.
--  Diese Zusatzpolicy wurde am 09.09.2026 live im SQL-Editor ausgeführt;
--  diese Datei zieht sie zur Dokumentation/Reproduzierbarkeit nach.
--  Sicher mehrfach ausführbar (DROP POLICY IF EXISTS vor CREATE).
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Woerni Telegram legt Notizen an" ON woerni_aufgaben;
CREATE POLICY "Woerni Telegram legt Notizen an" ON woerni_aufgaben
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = '6d4fccff-72ff-49f6-b4dc-20fdc80ad5dd');
