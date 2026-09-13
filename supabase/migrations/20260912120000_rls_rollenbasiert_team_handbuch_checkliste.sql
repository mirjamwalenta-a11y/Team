-- ════════════════════════════════════════════════════════════
--  Rollenbasierte RLS für Team, Handbuch, Checkliste
--
--  Hintergrund: Die Migrationen vom 8.9. (p0_teamapp_persons,
--  rls_ghd_checkliste_einkauf) haben RLS aktiviert und Policies
--  angelegt, die nur zwischen "angemeldet" (authenticated) und
--  "anonym" (anon) unterscheiden. Für "wer darf WAS als Rolle tun"
--  gab es serverseitig noch KEINE Prüfung — die _me.rolle-Checks in
--  team.html, Mitarbeiterhandbuch_App.html und salon-checklist.html
--  sind bisher NUR Oberfläche. Diese Migration holt das für die drei
--  konkret betroffenen Tabellen nach: teamapp_persons (Team-Verwaltung)
--  und wissensbank_artikel (Handbuch-Freigabe). Für salon_monatszuweisung
--  (Checkliste-Admin) siehe Abschnitt 3.
--
--  WICHTIG — vor dem Einspielen von einem Menschen mit Dashboard-/
--  SQL-Zugriff prüfen:
--    select * from pg_policies where tablename in
--      ('teamapp_persons','wissensbank_artikel','salon_monatszuweisung');
--  Postgres verknüpft mehrere Policies für denselben Befehl (z.B.
--  mehrere INSERT-Policies) mit ODER. Eine hier neu angelegte, enge
--  Policy schützt NICHTS, wenn daneben noch eine alte, weite Policy
--  (z.B. "authenticated ... using (true)") mit einem anderen Namen
--  existiert. Solche alten Policies müssen mit ihrem tatsächlichen
--  Namen gelöscht werden (DROP POLICY "<alter Name>" ON ...) — die
--  DROP-Befehle unten treffen nur die hier vergebenen Namen.
--
--  Sicher mehrfach ausführbar (idempotent), ersetzt aber keine fremden
--  Policy-Namen.
-- ════════════════════════════════════════════════════════════

-- ── 0. Rollen-Hilfsfunktionen ──────────────────────────────────
-- Ermittelt die Rolle der aufrufenden Person über die eigene
-- Session-E-Mail (auth.jwt()), nicht über eine vom Client mitgesendete
-- ID — kann daher nicht durch einen manipulierten Request umgangen
-- werden. SECURITY DEFINER, damit die Funktion selbst teamapp_persons
-- lesen darf, auch wenn die aufrufende Rolle das (künftig) nicht mehr
-- direkt dürfte.
create or replace function public.teamapp_aktuelle_rolle()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rolle from public.teamapp_persons
  where email = (auth.jwt() ->> 'email') and aktiv = true
  limit 1
$$;

create or replace function public.teamapp_ist_inhaberin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.teamapp_aktuelle_rolle() = 'inhaberin', false)
$$;

grant execute on function public.teamapp_aktuelle_rolle() to authenticated;
grant execute on function public.teamapp_ist_inhaberin() to authenticated;

-- ── 1. teamapp_persons — Team-Verwaltung nur Inhaberin ─────────
-- SELECT bleibt für alle angemeldeten Personen offen (das braucht
-- z.B. der Feed, um Namen anzuzeigen). Anlegen/Ändern/Löschen von
-- Personen — inkl. der rolle-Spalte selbst — nur für die Inhaberin.
-- Ohne das könnte sich jede angemeldete Person per direktem REST-
-- Aufruf selbst rolle:'inhaberin' setzen oder andere Personen löschen.
drop policy if exists "Nur Inhaberin legt Personen an" on public.teamapp_persons;
create policy "Nur Inhaberin legt Personen an" on public.teamapp_persons
  for insert to authenticated
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "Nur Inhaberin aendert Personen" on public.teamapp_persons;
create policy "Nur Inhaberin aendert Personen" on public.teamapp_persons
  for update to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "Nur Inhaberin loescht Personen" on public.teamapp_persons;
create policy "Nur Inhaberin loescht Personen" on public.teamapp_persons
  for delete to authenticated
  using (public.teamapp_ist_inhaberin());

-- ── 2. wissensbank_artikel (Handbuch) ──────────────────────────
-- Aktuell (Live-Stand unbekannt, nicht Teil der bisherigen Migrationen)
-- lädt Mitarbeiterhandbuch_App.html per `select=*` ALLE Artikel,
-- filtert nur clientseitig nach status. Wer noch nicht freigegebene
-- Vorschläge anderer Personen sehen will, muss dafür nur die Netzwerk-
-- Antwort öffnen. Diese Policy liefert serverseitig nur noch das, was
-- die Person auch sehen soll: freigegebene Artikel, die eigenen
-- Entwürfe/Vorschläge, oder (Inhaberin) alles.
alter table public.wissensbank_artikel enable row level security;

drop policy if exists "wissensbank_select" on public.wissensbank_artikel;
create policy "wissensbank_select" on public.wissensbank_artikel
  for select to authenticated
  using (
    status = 'freigegeben'
    or ersteller_email = (auth.jwt() ->> 'email')
    or public.teamapp_ist_inhaberin()
  );

-- Anlegen: nur im eigenen Namen (ersteller_email = eigene E-Mail).
-- Mitarbeiter:innen dürfen nur mit status 'eingereicht' anlegen (kein
-- Selbst-Freigeben über einen direkten REST-Call); die Inhaberin darf
-- direkt mit status 'freigegeben' anlegen, wie es die App bereits vorsieht.
drop policy if exists "wissensbank_insert" on public.wissensbank_artikel;
create policy "wissensbank_insert" on public.wissensbank_artikel
  for insert to authenticated
  with check (
    ersteller_email = (auth.jwt() ->> 'email')
    and (
      (status = 'eingereicht' and freigegeben_von is null and freigegeben_am is null)
      or (status = 'freigegeben' and public.teamapp_ist_inhaberin())
    )
  );

-- Ändern (insb. Freigeben/Ablehnen im Review): nur Inhaberin.
drop policy if exists "wissensbank_update" on public.wissensbank_artikel;
create policy "wissensbank_update" on public.wissensbank_artikel
  for update to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());

-- Löschen: entspricht genau der bisherigen Client-Logik (darfLoeschen
-- in Mitarbeiterhandbuch_App.html) — jetzt zusätzlich serverseitig
-- erzwungen statt nur in der Oberfläche.
drop policy if exists "wissensbank_delete" on public.wissensbank_artikel;
create policy "wissensbank_delete" on public.wissensbank_artikel
  for delete to authenticated
  using (
    public.teamapp_ist_inhaberin()
    or (ersteller_email = (auth.jwt() ->> 'email') and status <> 'freigegeben')
  );

-- ── 3. salon_monatszuweisung (Checkliste-Admin) ────────────────
-- salon-checklist.html sperrt den Admin-Bereich (Monatszuweisung
-- ändern) bisher nur über einen clientseitigen E-Mail-Vergleich
-- (CHEFIN_EMAIL). Die Tabelle selbst erlaubte laut Migration vom 8.9.
-- jeder angemeldeten Person INSERT/UPDATE (keine DELETE-Policy, obwohl
-- die App zum Ändern erst löscht und neu anlegt). Lesen bleibt für
-- alle offen (jede Person soll sehen, wer zuständig ist); Schreiben
-- wird auf die Inhaberin begrenzt, wie es die Oberfläche ohnehin
-- vorgibt.
drop policy if exists "salon_monatszuweisung_insert" on public.salon_monatszuweisung;
create policy "salon_monatszuweisung_insert" on public.salon_monatszuweisung
  for insert to authenticated
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "salon_monatszuweisung_update" on public.salon_monatszuweisung;
create policy "salon_monatszuweisung_update" on public.salon_monatszuweisung
  for update to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "salon_monatszuweisung_delete" on public.salon_monatszuweisung;
create policy "salon_monatszuweisung_delete" on public.salon_monatszuweisung
  for delete to authenticated
  using (public.teamapp_ist_inhaberin());

-- ── Nicht Teil dieser Migration ─────────────────────────────────
-- salon_checks, einkauf_*, lager_bestellliste, ghd_*: bleiben bewusst
-- für alle angemeldeten Team-Mitglieder gleichberechtigt lesbar/
-- schreibbar — das sind die eigentlichen, gemeinsam genutzten
-- Tagesabläufe der 6 Mitarbeiter-Apps, keine Inhaberinnen-Funktionen.
