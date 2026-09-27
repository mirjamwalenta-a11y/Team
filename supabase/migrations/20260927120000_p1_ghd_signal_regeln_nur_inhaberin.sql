-- ════════════════════════════════════════════════════════════
--  P1 — ghd_signal_regeln nur für die Inhaberin
--  Projekt wrxlaltgtgkdomklgrlj.
--
--  ghd_signal_regeln steuert die Signal-Chips auf der Startseite
--  (index.greathairday/index.html): welche Tabelle gezählt wird,
--  mit welchem Filter, welcher Text und welche App beim Antippen
--  aufgeht. Für diese Tabelle gab es in keinem Repo eine Migration,
--  der RLS-Zustand war unbekannt. Wäre sie offen, könnte jemand die
--  Texte der Signale ändern oder Signale abschalten.
--
--  Einziger Leser ist die Startseite, und die ist der Inhaberin
--  vorbehalten. Deshalb: alles nur für die Inhaberin, nichts für anon.
--  (Links auf fremde Seiten sind ohnehin nicht möglich: die Startseite
--  öffnet nur App-Namen aus einer festen Liste, SIGNAL_APP_WHITELIST.)
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

-- Rollen-Hilfsfunktionen (identisch zu 20260920120000 / 20260927100000)
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

alter table public.ghd_signal_regeln enable row level security;

-- Alle bestehenden Policies entfernen (Namen unbekannt), dann eine klare.
do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'ghd_signal_regeln' loop
    execute format('drop policy %I on public.ghd_signal_regeln', p.policyname);
  end loop;
end $$;

create policy "ghd_signal_regeln_nur_inhaberin" on public.ghd_signal_regeln
  for all to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());
