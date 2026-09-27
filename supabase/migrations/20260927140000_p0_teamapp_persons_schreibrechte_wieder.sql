-- ════════════════════════════════════════════════════════════
--  P0 — Korrektur zu 20260927130000: Schreibrechte auf teamapp_persons
--  wiederherstellen (nur für Angemeldete, mit Rollenprüfung).
--
--  20260927130000 hat alle Policies mit Rolle public/anon entfernt. Die
--  Schreib-Policies der Team-App (anlegen, ändern/deaktivieren, löschen)
--  waren live ebenfalls „für public“ angelegt und sind dabei mit
--  verschwunden. Folge: Die Inhaberin konnte in der Team-App keine Person
--  mehr anlegen, deaktivieren oder löschen.
--
--  Neu, nur für authenticated:
--    insert  nur Inhaberin
--    update  eigene Zeile oder Inhaberin (Rolle/Aktiv/E-Mail schützt
--            zusätzlich der Trigger aus 20260920120000)
--    delete  nur Inhaberin
--  Dazu die Einladungs-Policies aus 20260908143644 (anlegen/löschen für
--  Angemeldete) idempotent neu, falls sie live ebenfalls public waren.
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

create or replace function public.teamapp_aktuelle_rolle()
returns text language sql stable security definer set search_path = public as $$
  select rolle from public.teamapp_persons
  where email = auth.email() and aktiv = true
  limit 1
$$;

create or replace function public.teamapp_ist_inhaberin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.teamapp_aktuelle_rolle() = 'inhaberin', false)
$$;

grant execute on function public.teamapp_aktuelle_rolle() to authenticated;
grant execute on function public.teamapp_ist_inhaberin() to authenticated;

drop policy if exists "Inhaberin legt Personen an" on public.teamapp_persons;
create policy "Inhaberin legt Personen an" on public.teamapp_persons
  for insert to authenticated
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "Eigene Zeile oder Inhaberin aendert" on public.teamapp_persons;
create policy "Eigene Zeile oder Inhaberin aendert" on public.teamapp_persons
  for update to authenticated
  using (email = auth.email() or public.teamapp_ist_inhaberin())
  with check (email = auth.email() or public.teamapp_ist_inhaberin());

drop policy if exists "Inhaberin loescht Personen" on public.teamapp_persons;
create policy "Inhaberin loescht Personen" on public.teamapp_persons
  for delete to authenticated
  using (public.teamapp_ist_inhaberin());

drop policy if exists "Angemeldete legen Einladungen an" on public.teamapp_invites;
create policy "Angemeldete legen Einladungen an" on public.teamapp_invites
  for insert to authenticated
  with check (true);

drop policy if exists "Angemeldete loeschen Einladungen" on public.teamapp_invites;
create policy "Angemeldete loeschen Einladungen" on public.teamapp_invites
  for delete to authenticated
  using (true);
