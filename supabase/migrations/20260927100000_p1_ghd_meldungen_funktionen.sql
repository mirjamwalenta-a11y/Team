-- ════════════════════════════════════════════════════════════
--  P1 — Wörni-Meldungen über Serverfunktionen statt direkt in die
--  Tabellen (Stufe 1 von 3). Projekt wrxlaltgtgkdomklgrlj.
--
--  Hintergrund: ghd_aufgaben, ghd_aufgaben_vorlagen,
--  ghd_aufgaben_verlauf und ghd_ereignisse sind laut
--  20260908144500_rls_ghd_checkliste_einkauf.sql für ALLE
--  Angemeldeten lesbar und änderbar. „Wörni nur für die Chefin“
--  wird damit nur im Browser geprüft (CLAUDE.md Regel 3).
--  Gleichzeitig schreiben rund zehn Apps (Team, Checkliste, Lager,
--  Abwesenheiten, Innung, Belege, Dokumentenschrank, Lernquiz,
--  Schnuppertag, Reichweite) Meldungen in diese Tabellen und lesen
--  dafür vorher nach, ob es die Meldung schon gibt.
--
--  Plan:
--    Stufe 1 (diese Datei): Serverfunktionen anlegen, die das
--      „schon da? dann aktualisieren, sonst anlegen“ selbst machen
--      und nichts zurückgeben. Ändert nichts am Bestehenden und
--      kann sofort eingespielt werden.
--    Stufe 2: die Apps rufen nur noch diese Funktionen auf.
--    Stufe 3 (eigene, spätere Migration): Lesen/Ändern/Löschen der
--      Wörni-Tabellen nur noch für die Inhaberin.
--
--  Dazu (Abschnitt 6) eine eng begrenzte öffentliche Meldefunktion für
--  die drei Stellen, die ohne Login melden.
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

-- ── 0. Rollen-Hilfsfunktionen (identisch zu 20260920120000,
--       hier wiederholt, damit diese Datei für sich allein läuft) ─
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

-- ── 1. Aufgabe melden (ghd_aufgaben, über signal_key) ──────────
-- Gibt es schon eine offene Aufgabe mit diesem signal_key, werden
-- nur Titel und nächster Schritt aktualisiert (der nur, wenn
-- mitgeschickt). Priorität, Fälligkeit usw. bleiben, wie die
-- Inhaberin sie gesetzt hat. Sonst wird die Aufgabe neu angelegt.
-- p_nur_neu = true: vorhandene offene Aufgabe unverändert lassen.
-- Erlaubte Felder in p_daten: typ, titel, naechster_schritt,
-- verantwortlich, prioritaet, faellig_am, app_kontext, fach_kontext,
-- erstellt_von. Alles andere wird ignoriert.
create or replace function public.ghd_aufgabe_melden(
  p_signal_key text,
  p_daten jsonb,
  p_nur_neu boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titel text := left(nullif(trim(p_daten->>'titel'), ''), 300);
  v_schritt text := left(nullif(trim(p_daten->>'naechster_schritt'), ''), 500);
  v_prio text := left(nullif(trim(p_daten->>'prioritaet'), ''), 40);
begin
  if p_signal_key is null or length(trim(p_signal_key)) = 0 or length(p_signal_key) > 200 then
    raise exception 'signal_key fehlt oder ist zu lang';
  end if;
  if v_titel is null then
    raise exception 'titel fehlt';
  end if;

  if exists (select 1 from public.ghd_aufgaben
             where signal_key = p_signal_key and status is distinct from 'erledigt') then
    if p_nur_neu then return; end if;
    update public.ghd_aufgaben
       set titel = v_titel,
           naechster_schritt = coalesce(v_schritt, naechster_schritt),
           geaendert_am = now()
     where signal_key = p_signal_key and status is distinct from 'erledigt';
  else
    insert into public.ghd_aufgaben
      (typ, titel, naechster_schritt, verantwortlich, prioritaet, faellig_am,
       status, app_kontext, fach_kontext, signal_key, erstellt_von, erstellt_am)
    values
      (left(coalesce(p_daten->>'typ', 'betrieb'), 40),
       v_titel,
       v_schritt,
       left(coalesce(p_daten->>'verantwortlich', 'mirjam'), 60),
       coalesce(v_prio, 'diese-woche'),
       nullif(p_daten->>'faellig_am', '')::date,
       'neu',
       left(p_daten->>'app_kontext', 60),
       left(p_daten->>'fach_kontext', 60),
       p_signal_key,
       left(coalesce(p_daten->>'erstellt_von', 'system'), 60),
       now());
  end if;
end;
$$;

-- ── 2. Aufgabe erledigt melden (ghd_aufgaben, über signal_key) ──
create or replace function public.ghd_aufgabe_erledigt(
  p_signal_key text,
  p_erledigt_von text default 'system'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_signal_key is null or length(trim(p_signal_key)) = 0 then
    raise exception 'signal_key fehlt';
  end if;
  update public.ghd_aufgaben
     set status = 'erledigt',
         erledigt_am = now(),
         erledigt_von = left(coalesce(p_erledigt_von, 'system'), 60),
         geaendert_am = now()
   where signal_key = p_signal_key and status is distinct from 'erledigt';
end;
$$;

-- ── 3. Ereignis melden (ghd_ereignisse, über app + typ) ─────────
-- p_zusammenfassen = true (Standard): Gibt es schon ungelesene
-- Ereignisse mit gleicher app + typ, wird das neueste aktualisiert
-- und ältere Doppelte werden als gelesen markiert. Sonst neu.
-- p_zusammenfassen = false: immer neu anlegen (z. B. je Protokoll).
create or replace function public.ghd_ereignis_melden(
  p_app text,
  p_typ text,
  p_titel text,
  p_prioritaet text default null,
  p_payload jsonb default null,
  p_zusammenfassen boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_neuestes public.ghd_ereignisse.id%type;
  v_titel text := left(nullif(trim(p_titel), ''), 300);
begin
  if coalesce(trim(p_app), '') = '' or coalesce(trim(p_typ), '') = '' or v_titel is null then
    raise exception 'app, typ und titel sind nötig';
  end if;
  if p_payload is not null and length(p_payload::text) > 10000 then
    raise exception 'payload ist zu groß';
  end if;

  if p_zusammenfassen then
    select id into v_neuestes from public.ghd_ereignisse
     where app = p_app and typ = p_typ and gelesen = false
     order by erstellt_am desc nulls last, id desc
     limit 1;
  end if;

  if v_neuestes is not null then
    update public.ghd_ereignisse
       set titel = v_titel,
           prioritaet = coalesce(left(p_prioritaet, 40), prioritaet),
           payload = p_payload,
           erstellt_am = now()
     where id = v_neuestes;
    update public.ghd_ereignisse
       set gelesen = true
     where app = p_app and typ = p_typ and gelesen = false and id <> v_neuestes;
  else
    insert into public.ghd_ereignisse (app, typ, titel, prioritaet, payload, gelesen, erstellt_am)
    values (left(p_app, 60), left(p_typ, 60), v_titel, left(p_prioritaet, 40), p_payload, false, now());
  end if;
end;
$$;

-- ── 4. Ereignisse erledigt melden (ghd_ereignisse, app + typ) ───
create or replace function public.ghd_ereignis_erledigt(p_app text, p_typ text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.ghd_ereignisse
     set gelesen = true
   where app = p_app and typ = p_typ and gelesen = false;
end;
$$;

-- ── 5. Rechte: nur Angemeldete, nie anon ────────────────────────
-- Supabase gibt neuen Funktionen standardmäßig EXECUTE für anon.
revoke all on function public.ghd_aufgabe_melden(text, jsonb, boolean) from public, anon;
revoke all on function public.ghd_aufgabe_erledigt(text, text) from public, anon;
revoke all on function public.ghd_ereignis_melden(text, text, text, text, jsonb, boolean) from public, anon;
revoke all on function public.ghd_ereignis_erledigt(text, text) from public, anon;
grant execute on function public.ghd_aufgabe_melden(text, jsonb, boolean) to authenticated;
grant execute on function public.ghd_aufgabe_erledigt(text, text) to authenticated;
grant execute on function public.ghd_ereignis_melden(text, text, text, text, jsonb, boolean) to authenticated;
grant execute on function public.ghd_ereignis_erledigt(text, text) to authenticated;

-- ── 6. Öffentliche Meldung ohne Login (eng begrenzt) ────────────
-- Für die drei Stellen, die ohne Login im Hauptprojekt melden:
--   Belege (Login liegt im Belege-Projekt), Innung (Trainer:innen mit
--   Kennung + PIN), Schnuppertag (Bewerber:innen schicken den Test ab).
-- Grenzen:
--   * nur diese drei Meldungsarten (app + typ fest), sonst Fehler
--   * kann nur melden, nie lesen; kein payload
--   * Priorität nur aus einer festen Liste
--   * höchstens max_offen ungelesene Einträge je Art; darüber hinaus
--     wird nur der neueste überschrieben — wer die Funktion
--     missbraucht, kann das Postfach der Inhaberin nicht fluten
create or replace function public.ghd_ereignis_melden_oeffentlich(
  p_app text,
  p_typ text,
  p_titel text,
  p_prioritaet text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max_offen int;
  v_standard_prio text;
  v_offen int;
  v_neuestes public.ghd_ereignisse.id%type;
  v_titel text := left(nullif(trim(p_titel), ''), 200);
  v_prio text;
begin
  select m.max_offen, m.prio into v_max_offen, v_standard_prio
    from (values
      ('Belege',       'beleg_neu',                 1, 'diese-woche'),
      ('Innung',       'interesse_gemeldet',        5, 'diese-woche'),
      ('Schnuppertag', 'lehrling_test_abgeschickt', 5, 'heute')
    ) as m(app, typ, max_offen, prio)
   where m.app = p_app and m.typ = p_typ;
  if v_max_offen is null then
    raise exception 'Diese Meldung ist ohne Login nicht erlaubt';
  end if;
  if v_titel is null then
    raise exception 'titel fehlt';
  end if;
  v_prio := case when p_prioritaet in ('heute', 'diese-woche', 'wann-moeglich')
                 then p_prioritaet else v_standard_prio end;

  select count(*) into v_offen from public.ghd_ereignisse
   where app = p_app and typ = p_typ and gelesen = false;

  if v_offen < v_max_offen then
    insert into public.ghd_ereignisse (app, typ, titel, prioritaet, gelesen, erstellt_am)
    values (p_app, p_typ, v_titel, v_prio, false, now());
  else
    select id into v_neuestes from public.ghd_ereignisse
     where app = p_app and typ = p_typ and gelesen = false
     order by erstellt_am desc nulls last, id desc
     limit 1;
    update public.ghd_ereignisse
       set titel = v_titel, prioritaet = v_prio, erstellt_am = now()
     where id = v_neuestes;
  end if;
end;
$$;

revoke all on function public.ghd_ereignis_melden_oeffentlich(text, text, text, text) from public;
grant execute on function public.ghd_ereignis_melden_oeffentlich(text, text, text, text) to anon, authenticated;
