-- ════════════════════════════════════════════════════════════
--  P0 — teamapp_persons und salon_personen nicht mehr ohne Login lesbar
--  Projekt wrxlaltgtgkdomklgrlj. Fund der wöchentlichen RLS-Prüfung
--  (Mitarbeiterhandbuch, Issue #35):
--    teamapp_persons  „Lesen bleibt wie bisher“ (SELECT) für anon
--      → Namen, E-Mails, Rollen des Teams für jede:n im Internet lesbar
--    salon_personen   „Team liest“ (SELECT) für anon
--    teamapp_invites  anon liest ALLE gültigen Einladungen (Namen, Codes)
--
--  Einziger Grund für den anon-Zugriff auf teamapp_persons/-invites war
--  der Einladungslink der Team-App (vor dem ersten Login). Dafür gibt es
--  jetzt teamapp_einladung_person(token): liefert genau eine Person
--  (id, name, email) und nur bei gültigem, nicht abgelaufenem Code.
--
--  salon_personen liest keine App mehr direkt; der PIN-Login läuft über
--  login_mit_pin / session_by_token. Abschnitt 3 entfernt den anon-Zugriff
--  nur, wenn diese Funktionen SECURITY DEFINER sind (also ohne die Policy
--  weiter funktionieren) — sonst bricht er mit einer Meldung ab.
--
--  Reihenfolge: Team-App-Update (handleInvite nutzt die Funktion) kann vor
--  oder nach dieser Datei live gehen; die Funktion stört die alte App nicht,
--  aber erst mit beiden funktioniert der Einladungslink ohne anon-Lesezugriff.
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

-- ── 1. Einladungslink: eine Person per gültigem Code ─────────────
create or replace function public.teamapp_einladung_person(p_token text)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object('id', p.id, 'name', p.name, 'email', p.email)
  from public.teamapp_invites i
  join public.teamapp_persons p on p.name = i.name
  where i.token = p_token
    and i.laeuft_ab is not null and i.laeuft_ab > now()
    and coalesce(p.aktiv, true)
  limit 1
$$;

revoke all on function public.teamapp_einladung_person(text) from public;
grant execute on function public.teamapp_einladung_person(text) to anon, authenticated;

-- ── 2. teamapp_persons / teamapp_invites: kein anon mehr ─────────
alter table public.teamapp_persons enable row level security;
alter table public.teamapp_invites enable row level security;

do $$
declare p record;
begin
  -- alle Policies, die anon oder public (= alle Rollen) einschließen
  for p in select tablename, policyname from pg_policies
           where schemaname = 'public'
             and tablename in ('teamapp_persons', 'teamapp_invites')
             and roles && array['anon', 'public']::name[] loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Angemeldete lesen weiter (wie in 20260908143643).
drop policy if exists "Angemeldete lesen Personen" on public.teamapp_persons;
create policy "Angemeldete lesen Personen" on public.teamapp_persons
  for select to authenticated using (true);

-- Einladungen: nur noch Angemeldete lesen die gültigen.
drop policy if exists "Angemeldete lesen gueltige Einladungen" on public.teamapp_invites;
create policy "Angemeldete lesen gueltige Einladungen" on public.teamapp_invites
  for select to authenticated
  using (laeuft_ab is not null and laeuft_ab > now());

-- ── 3. salon_personen: kein anon mehr (nur wenn der PIN-Login das verträgt) ─
do $$
declare
  v_unsicher text;
  p record;
begin
  select string_agg(proname, ', ') into v_unsicher
  from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
  where n.nspname = 'public'
    and proname in ('login_mit_pin', 'session_by_token', 'logout_session')
    and not prosecdef;
  if v_unsicher is not null then
    raise exception 'Abgebrochen, nichts geändert: % ist nicht SECURITY DEFINER und bräuchte den anon-Zugriff auf salon_personen noch. Bitte Claude Bescheid geben.', v_unsicher;
  end if;

  alter table public.salon_personen enable row level security;
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'salon_personen'
             and roles && array['anon', 'public']::name[] loop
    execute format('drop policy %I on public.salon_personen', p.policyname);
  end loop;
end $$;
