-- ════════════════════════════════════════════════════════════
--  P0 — teamapp_persons: Rolle/Aktiv/E-Mail per Selbst-Update
--  änderbar. salon_monatszuweisung: weite Alt-Policies stehen
--  noch neben der (dadurch wirkungslosen) restriktiven Policy.
--
--  Live-Befund (pg_policies-Abfrage, 2026-09-20):
--
--  1) teamapp_persons hat eine Policy "Eigene Zeile oder Inhaberin
--     darf ändern" (UPDATE), die jeder Person erlaubt, ihre eigene
--     Zeile zu ändern — ohne Einschränkung, WELCHE Spalten. RLS
--     (USING/WITH CHECK) prüft nur OB eine Zeile geändert werden
--     darf, nicht welche Werte die neue Zeile im Vergleich zur
--     alten hat. Damit kann sich jede angemeldete Person per
--     direktem REST-Aufruf selbst rolle:'inhaberin' setzen, sich
--     nach einer Deaktivierung selbst aktiv:true setzen, oder ihre
--     email ändern. Das ist genau die Lücke, die im Dokument
--     ZUGRIFFSKONZEPT-TEAM-HANDBUCH-CHECKLISTE.md als größtes
--     Risiko benannt wurde ("könnte sich jede angemeldete
--     Mitarbeiterin selbst rolle:'inhaberin' setzen").
--
--     Die bestehende Policy bleibt unangetastet (Mitarbeiter:innen
--     sollen weiterhin z.B. Name/Telefonnummer selbst pflegen
--     können) — ein BEFORE-UPDATE-Trigger ergänzt sie um den
--     Spaltenschutz, weil RLS das strukturell nicht kann.
--
--  2) salon_monatszuweisung hat ZWEI Policy-Generationen gleich-
--     zeitig aktiv (mehrere PERMISSIVE-Policies pro Befehl werden
--     von Postgres mit ODER verknüpft):
--       - alt: "Team schreibt"/"Team ändert"/"Team löscht"
--         (jede angemeldete Person darf)
--       - alt: "salon_monatszuweisung_insert"/"_update"
--         (with_check/using = true, noch offener)
--     Die einzige einschränkende Policy "Monatszuweisung verwalten"
--     (nur auth.email() = eine hartcodierte private E-Mail) wird
--     dadurch komplett überstimmt — sie hat aktuell keine Wirkung.
--     Zusätzlich verstößt die hartcodierte E-Mail gegen die eigene
--     Regel "keine privaten E-Mail-Adressen im Klartext" (siehe
--     CLAUDE.md im Mitarbeiterhandbuch-Repo).
--
--  WICHTIG — vor dem Einspielen prüfen, ob sich die Policy-Namen
--  seit 2026-09-20 geändert haben:
--    select * from pg_policies
--    where tablename in ('teamapp_persons','salon_monatszuweisung');
--  Die DROP-Befehle unten treffen nur die zum Zeitpunkt dieser
--  Migration bekannten Namen.
--
--  Sicher mehrfach ausführbar (idempotent).
-- ════════════════════════════════════════════════════════════

-- ── 0. Rollen-Hilfsfunktionen (idempotent neu anlegen, falls noch
--       nicht vorhanden — die live gefundenen Policies nutzen
--       stattdessen inline EXISTS-Checks, die Funktion selbst war
--       also möglicherweise nie angelegt) ────────────────────────
create or replace function public.teamapp_aktuelle_rolle()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rolle from public.teamapp_persons
  where email = auth.email() and aktiv = true
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

-- ── 1. teamapp_persons — sensible Spalten per Trigger schützen ──
-- Ergänzt die bestehende "Eigene Zeile oder Inhaberin darf ändern"-
-- Policy: die Policy selbst bleibt, der Trigger blockt zusätzlich
-- jede Änderung an rolle/aktiv/email durch eine Person, die nicht
-- bereits Inhaberin ist.
create or replace function public.teamapp_schuetze_sensible_felder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.teamapp_ist_inhaberin() then
    if new.rolle is distinct from old.rolle
       or new.aktiv is distinct from old.aktiv
       or new.email is distinct from old.email then
      raise exception 'Nur die Inhaberin darf Rolle, Aktiv-Status oder E-Mail ändern';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists teamapp_persons_schuetze_sensible_felder on public.teamapp_persons;
create trigger teamapp_persons_schuetze_sensible_felder
  before update on public.teamapp_persons
  for each row
  execute function public.teamapp_schuetze_sensible_felder();

-- ── 2. salon_monatszuweisung — alte weite Policies entfernen,
--       rollenbasiert statt hartcodierter E-Mail ─────────────────
-- Lesen bleibt für alle offen (unverändert, keine der lesenden
-- Policies wird angetastet).
drop policy if exists "Team schreibt" on public.salon_monatszuweisung;
drop policy if exists "Team ändert" on public.salon_monatszuweisung;
drop policy if exists "Team löscht" on public.salon_monatszuweisung;
drop policy if exists "Monatszuweisung verwalten" on public.salon_monatszuweisung;

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
