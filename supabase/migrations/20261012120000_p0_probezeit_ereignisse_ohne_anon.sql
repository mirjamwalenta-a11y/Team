-- ════════════════════════════════════════════════════════════
--  P0 — Probezeit-Daten und Schaltzentrale-Meldungen nicht mehr ohne Login
--  Projekt wrxlaltgtgkdomklgrlj. Fund der wöchentlichen RLS-Prüfung
--  (Mitarbeiterhandbuch, Issue #35), bestätigt am 2026-10-12:
--    probezeiten       „Anon liest Probezeit-ID“ (SELECT) für anon
--      → Name, Beginn/Ende, Status, Entscheidung und Abschlussnotizen
--        jeder Probezeit für jede:n im Internet lesbar
--    probezeit_ziele   „Anon liest Ziele“ (SELECT) für anon
--      → Ziele aller Lehrlinge ohne Login lesbar
--    ghd_ereignisse    „anon_insert“ (INSERT) für anon
--      → Fremde können Meldungen in die Schaltzentrale schreiben
--
--  Warum das gefahrlos entfernt werden kann:
--    * Der Wochenquiz-Link (schnuppertag.html?modus=lehrling-quiz) bekommt
--      die Probezeit-ID über den Link und liest nur probezeit_quiz_fragen
--      bzw. schreibt probezeit_quiz. Die beiden Regeln dafür („Anon liest
--      Fragen“, „Anon kann Quiz einreichen“) bleiben unverändert.
--      probezeiten und probezeit_ziele liest nur die Meisterin (eingeloggt,
--      Regeln *_meisterin aus lernquiz 20261010_rls_lernquiz_aktuell.sql).
--    * Alle Apps melden Ereignisse über ghd_ereignis_melden /
--      ghd_ereignis_melden_oeffentlich (SECURITY DEFINER, Migration
--      20260927100000); keine App schreibt mehr direkt in ghd_ereignisse.
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════
begin;

drop policy if exists "Anon liest Probezeit-ID" on public.probezeiten;
drop policy if exists "Anon liest Ziele"        on public.probezeit_ziele;
drop policy if exists "anon_insert"             on public.ghd_ereignisse;

commit;

-- ── Kontrolle: erwartet 0 ────────────────────────────────────────
select count(*) as noch_offen
from pg_policies
where schemaname = 'public'
  and ((tablename = 'probezeiten'     and policyname = 'Anon liest Probezeit-ID')
    or (tablename = 'probezeit_ziele' and policyname = 'Anon liest Ziele')
    or (tablename = 'ghd_ereignisse'  and policyname = 'anon_insert'));
