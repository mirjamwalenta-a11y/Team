-- ════════════════════════════════════════════════════════════
--  Team-App: Lohnzettel für Mitarbeiter:innen zum Herunterladen
--
--  Ablauf:
--    • Die Inhaberin lädt die Sammel-PDF vom Steuerberater in der
--      Team-App hoch. Der BROWSER teilt sie in einzelne Seiten auf
--      (die Sammeldatei selbst wird nirgends gespeichert) und ordnet
--      jede Seite über die Dienstnehmer-Nummer (DN) einer Person zu.
--    • Jeder Lohnzettel liegt danach als eigene PDF im PRIVATEN
--      Storage-Bucket „lohnzettel“:  lohnzettel/<person_id>/<datei>.pdf
--    • Mitarbeiter:innen sehen nur ihre eigenen — und nur, nachdem sie
--      in DIESER Anmeldesitzung zusätzlich ihr Lohnzettel-Passwort
--      eingegeben haben (die Team-App ist auch über Kennung + 4-stellige
--      PIN erreichbar, das ist für Gehaltsdaten zu schwach).
--
--  Sicherheit (CLAUDE.md, Regeln 1–4):
--    • Alle neuen Tabellen: RLS an, KEINE Policy für anon, keine
--      Schreib-Policies für authenticated — geschrieben wird nur über
--      die SECURITY-DEFINER-Funktionen unten, die selbst prüfen.
--    • Rolle „Inhaberin“ kommt aus teamapp_ist_inhaberin() (Datenbank),
--      nie aus dem Browser.
--    • Die Freischaltung hängt an der Supabase-Anmeldesitzung
--      (auth.jwt() ->> 'session_id'), läuft nach 10 Minuten ab und kann
--      vom Browser nicht selbst gesetzt werden.
--    • Lohnzettel-Passwort: nur als bcrypt-Hash (pgcrypto). Nach 5
--      Fehlversuchen 15 Minuten gesperrt.
--    • Wer ausgeschieden/deaktiviert ist (teamapp_persons.aktiv = false),
--      hat automatisch keinen Zugriff mehr.
--    • Jeder Abruf wird protokolliert (Nachweis der Zustellung).
--
--  Aufbewahrung: mit den Lohnunterlagen (7 Jahre). Deshalb verhindert
--  der Fremdschlüssel, dass eine Person mit Lohnzetteln gelöscht wird —
--  Ausgeschiedene bitte deaktivieren statt löschen.
--
--  Sicher mehrfach ausführbar (idempotent). Im Supabase SQL-Editor
--  ausführen. Am Ende steht eine Kontrollabfrage.
-- ════════════════════════════════════════════════════════════

begin;

create extension if not exists pgcrypto with schema extensions;

-- ── 0. Rollen-Hilfsfunktionen (identisch zu 20260920120000; hier nur
--       zur Sicherheit erneut angelegt, falls sie fehlen) ──────────
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

-- Eigene Person (nur aktive). NULL, wenn nicht angemeldet/deaktiviert.
create or replace function public.lohnzettel_meine_person_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select id from public.teamapp_persons
  where email = auth.email() and aktiv = true
  limit 1
$$;

-- ── 1. Tabellen ─────────────────────────────────────────────
-- Ein Lohnzettel = eine PDF im Bucket
create table if not exists public.lohnzettel (
  id              uuid primary key default gen_random_uuid(),
  person_id       text not null references public.teamapp_persons(id) on delete restrict,
  monat           date not null check (monat = date_trunc('month', monat)::date),
  pfad            text not null unique check (split_part(pfad, '/', 1) = person_id and pfad ~ '^[A-Za-z0-9_-]+/[0-9]{4}-[0-9]{2}_[0-9a-f-]{36}\.pdf$'),
  dateiname       text not null check (length(dateiname) between 1 and 120),
  groesse         integer not null check (groesse between 1 and 5242880),
  dn_nr           text check (dn_nr ~ '^[0-9]{1,6}$'),
  hochgeladen_von text not null,
  hochgeladen_am  timestamptz not null default now()
);
create index if not exists lohnzettel_person_idx on public.lohnzettel (person_id, monat desc);

-- Dienstnehmer-Nummer des Lohnprogramms → Person (einmal zuordnen, dann automatisch)
create table if not exists public.lohnzettel_dn_zuordnung (
  dn_nr     text primary key check (dn_nr ~ '^[0-9]{1,6}$'),
  person_id text not null references public.teamapp_persons(id) on delete cascade,
  geaendert timestamptz not null default now()
);

-- Lohnzettel-Passwort (nur Hash) + Fehlversuche
create table if not exists public.lohnzettel_passwort (
  person_id    text primary key references public.teamapp_persons(id) on delete cascade,
  hash         text not null,
  gesetzt_am   timestamptz not null default now(),
  fehlversuche integer not null default 0,
  gesperrt_bis timestamptz
);

-- Freischaltung: gilt nur für die eine Anmeldesitzung und läuft ab
create table if not exists public.lohnzettel_freischaltung (
  person_id  text not null references public.teamapp_persons(id) on delete cascade,
  session_id text not null,
  bis        timestamptz not null,
  primary key (person_id, session_id)
);

-- Abruf-Protokoll (Nachweis). Bleibt erhalten, auch wenn der Lohnzettel gelöscht wird.
create table if not exists public.lohnzettel_abrufe (
  id            bigint generated always as identity primary key,
  lohnzettel_id uuid references public.lohnzettel(id) on delete set null,
  person_id     text not null,
  monat         date not null,
  abgerufen_von text not null,
  abgerufen_am  timestamptz not null default now()
);
create index if not exists lohnzettel_abrufe_lz_idx on public.lohnzettel_abrufe (lohnzettel_id);

-- RLS: an, keine anon-Policy, keine Schreib-Policies
alter table public.lohnzettel               enable row level security;
alter table public.lohnzettel_dn_zuordnung  enable row level security;
alter table public.lohnzettel_passwort      enable row level security;
alter table public.lohnzettel_freischaltung enable row level security;
alter table public.lohnzettel_abrufe        enable row level security;

revoke all on public.lohnzettel, public.lohnzettel_dn_zuordnung, public.lohnzettel_passwort,
              public.lohnzettel_freischaltung, public.lohnzettel_abrufe from anon, authenticated;
-- Lesen direkt aus den Tabellen nur für die Inhaberin (die App nutzt ohnehin die Funktionen)
grant select on public.lohnzettel, public.lohnzettel_dn_zuordnung, public.lohnzettel_abrufe to authenticated;

drop policy if exists "lohnzettel_select_inhaberin" on public.lohnzettel;
create policy "lohnzettel_select_inhaberin" on public.lohnzettel
  for select to authenticated using (public.teamapp_ist_inhaberin());
drop policy if exists "lohnzettel_dn_select_inhaberin" on public.lohnzettel_dn_zuordnung;
create policy "lohnzettel_dn_select_inhaberin" on public.lohnzettel_dn_zuordnung
  for select to authenticated using (public.teamapp_ist_inhaberin());
drop policy if exists "lohnzettel_abrufe_select_inhaberin" on public.lohnzettel_abrufe;
create policy "lohnzettel_abrufe_select_inhaberin" on public.lohnzettel_abrufe
  for select to authenticated using (public.teamapp_ist_inhaberin());
-- lohnzettel_passwort / lohnzettel_freischaltung: gar keine Policy → niemand liest direkt

-- ── 2. Freischaltung prüfen (wird auch von der Storage-Policy benutzt) ──
create or replace function public.lohnzettel_ist_freigeschaltet()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.lohnzettel_freischaltung
    where person_id = public.lohnzettel_meine_person_id()
      and session_id = coalesce(auth.jwt() ->> 'session_id', '')
      and bis > now()
  )
$$;

-- Darf die angemeldete Person den Lohnzettel dieser Person sehen?
create or replace function public.lohnzettel_darf_sehen(p_person text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.teamapp_ist_inhaberin()
      or (p_person is not null
          and p_person = public.lohnzettel_meine_person_id()
          and public.lohnzettel_ist_freigeschaltet())
$$;

-- interne Hilfe: Freischaltung für diese Sitzung setzen (10 Minuten)
create or replace function public.lohnzettel__freischalten(p_person text)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_sid text := auth.jwt() ->> 'session_id';
  v_bis timestamptz := now() + interval '10 minutes';
begin
  if v_sid is null or v_sid = '' then
    raise exception 'Anmeldesitzung unbekannt – bitte neu anmelden.';
  end if;
  delete from public.lohnzettel_freischaltung where bis < now() - interval '1 day';
  insert into public.lohnzettel_freischaltung (person_id, session_id, bis)
  values (p_person, v_sid, v_bis)
  on conflict (person_id, session_id) do update set bis = excluded.bis;
  return v_bis;
end
$$;

-- ── 3. Funktionen für Mitarbeiter:innen ───────────────────────
-- Status: Passwort schon eingerichtet? Gerade freigeschaltet? Gesperrt?
create or replace function public.lohnzettel_status()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'ist_inhaberin',     public.teamapp_ist_inhaberin(),
    'passwort_gesetzt',  exists (select 1 from public.lohnzettel_passwort where person_id = public.lohnzettel_meine_person_id()),
    'gesperrt_bis',      (select gesperrt_bis from public.lohnzettel_passwort
                          where person_id = public.lohnzettel_meine_person_id() and gesperrt_bis > now()),
    'freigeschaltet_bis',(select bis from public.lohnzettel_freischaltung
                          where person_id = public.lohnzettel_meine_person_id()
                            and session_id = coalesce(auth.jwt() ->> 'session_id', '')
                            and bis > now())
  )
$$;

-- Passwort prüfen → bei Erfolg für 10 Minuten freischalten.
-- Gibt json {ok, gesperrt_bis, freigeschaltet_bis} zurück (KEIN raise bei falschem
-- Passwort — sonst würde der Fehlversuch mit zurückgerollt und nie gezählt).
create or replace function public.lohnzettel_entsperren(p_passwort text)
returns json
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_person text := public.lohnzettel_meine_person_id();
  v_pw     public.lohnzettel_passwort;
  v_bis    timestamptz;
begin
  if v_person is null then raise exception 'Nicht angemeldet.'; end if;
  select * into v_pw from public.lohnzettel_passwort where person_id = v_person for update;
  if not found then raise exception 'Noch kein Lohnzettel-Passwort eingerichtet.'; end if;
  if v_pw.gesperrt_bis is not null and v_pw.gesperrt_bis > now() then
    return json_build_object('ok', false, 'gesperrt_bis', v_pw.gesperrt_bis);
  end if;
  if p_passwort is null or extensions.crypt(p_passwort, v_pw.hash) <> v_pw.hash then
    update public.lohnzettel_passwort
       set fehlversuche = case when fehlversuche + 1 >= 5 then 0 else fehlversuche + 1 end,
           gesperrt_bis = case when fehlversuche + 1 >= 5 then now() + interval '15 minutes' else null end
     where person_id = v_person
     returning gesperrt_bis into v_bis;
    return json_build_object('ok', false, 'gesperrt_bis', v_bis);
  end if;
  update public.lohnzettel_passwort set fehlversuche = 0, gesperrt_bis = null where person_id = v_person;
  v_bis := public.lohnzettel__freischalten(v_person);
  return json_build_object('ok', true, 'freigeschaltet_bis', v_bis);
end
$$;

-- Passwort einrichten (erstes Mal) oder ändern (dann altes Passwort nötig).
create or replace function public.lohnzettel_passwort_setzen(p_neu text, p_alt text default null)
returns json
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_person text := public.lohnzettel_meine_person_id();
  v_pw     public.lohnzettel_passwort;
  v_pruef  json;
begin
  if v_person is null then raise exception 'Nicht angemeldet.'; end if;
  if p_neu is null or length(p_neu) < 8 or length(p_neu) > 72 then
    raise exception 'Das Passwort muss 8 bis 72 Zeichen lang sein.';
  end if;
  select * into v_pw from public.lohnzettel_passwort where person_id = v_person;
  if found then
    -- Ändern: altes Passwort über denselben Weg prüfen (zählt als Versuch)
    v_pruef := public.lohnzettel_entsperren(p_alt);
    if not (v_pruef ->> 'ok')::boolean then return v_pruef; end if;
    update public.lohnzettel_passwort
       set hash = extensions.crypt(p_neu, extensions.gen_salt('bf', 10)), gesetzt_am = now()
     where person_id = v_person;
  else
    insert into public.lohnzettel_passwort (person_id, hash)
    values (v_person, extensions.crypt(p_neu, extensions.gen_salt('bf', 10)));
  end if;
  return json_build_object('ok', true, 'freigeschaltet_bis', public.lohnzettel__freischalten(v_person));
end
$$;

-- Wieder sperren (Knopf „Sperren“ / beim Abmelden)
create or replace function public.lohnzettel_sperren()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  delete from public.lohnzettel_freischaltung
  where person_id = public.lohnzettel_meine_person_id()
    and session_id = coalesce(auth.jwt() ->> 'session_id', '')
$$;

-- Eigene Lohnzettel (nur freigeschaltet)
create or replace function public.lohnzettel_meine()
returns table (id uuid, monat date, dateiname text, groesse integer, hochgeladen_am timestamptz, zuletzt_abgerufen timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_person text := public.lohnzettel_meine_person_id();
begin
  if not public.lohnzettel_darf_sehen(v_person) then
    raise exception 'Lohnzettel sind gesperrt – bitte Lohnzettel-Passwort eingeben.';
  end if;
  return query
    select l.id, l.monat, l.dateiname, l.groesse, l.hochgeladen_am,
           (select max(a.abgerufen_am) from public.lohnzettel_abrufe a
             where a.lohnzettel_id = l.id and a.abgerufen_von = v_person)
    from public.lohnzettel l
    where l.person_id = v_person
    order by l.monat desc, l.hochgeladen_am desc;
end
$$;

-- Abruf vorbereiten: prüft, protokolliert, gibt den Speicherpfad zurück.
-- Den eigentlichen Download-Link erstellt danach Supabase Storage — dort
-- prüft die Storage-Policy (lohnzettel_darf_sehen) noch einmal selbst.
create or replace function public.lohnzettel_abruf(p_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_lz public.lohnzettel;
  v_ich text := public.lohnzettel_meine_person_id();
begin
  select * into v_lz from public.lohnzettel where id = p_id;
  if not found or not public.lohnzettel_darf_sehen(v_lz.person_id) then
    raise exception 'Kein Zugriff auf diesen Lohnzettel.';
  end if;
  insert into public.lohnzettel_abrufe (lohnzettel_id, person_id, monat, abgerufen_von)
  values (v_lz.id, v_lz.person_id, v_lz.monat, coalesce(v_ich, auth.email(), '?'));
  return v_lz.pfad;
end
$$;

-- ── 4. Funktionen nur für die Inhaberin ───────────────────────
create or replace function public.lohnzettel__nur_inhaberin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.teamapp_ist_inhaberin() then
    raise exception 'Nur die Inhaberin darf das.';
  end if;
end
$$;

-- Nach dem Hochladen der PDF in den Bucket: Eintrag anlegen
create or replace function public.lohnzettel_eintragen(
  p_person text, p_monat date, p_pfad text, p_dateiname text, p_groesse integer, p_dn_nr text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.lohnzettel__nur_inhaberin();
  if not exists (select 1 from storage.objects where bucket_id = 'lohnzettel' and name = p_pfad) then
    raise exception 'Die Datei wurde nicht gefunden – bitte erneut hochladen.';
  end if;
  insert into public.lohnzettel (person_id, monat, pfad, dateiname, groesse, dn_nr, hochgeladen_von)
  values (p_person, date_trunc('month', p_monat)::date, p_pfad, p_dateiname, p_groesse,
          nullif(p_dn_nr, ''), coalesce(public.lohnzettel_meine_person_id(), auth.email()))
  returning id into v_id;
  if nullif(p_dn_nr, '') is not null then
    insert into public.lohnzettel_dn_zuordnung (dn_nr, person_id) values (p_dn_nr, p_person)
    on conflict (dn_nr) do update set person_id = excluded.person_id, geaendert = now();
  end if;
  return v_id;
end
$$;

-- Übersicht für die Inhaberin: alle Lohnzettel mit Abruf-Info
create or replace function public.lohnzettel_uebersicht()
returns table (id uuid, person_id text, person_name text, monat date, dateiname text, pfad text,
               hochgeladen_am timestamptz, abrufe bigint, zuletzt_abgerufen timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.lohnzettel__nur_inhaberin();
  return query
    select l.id, l.person_id, p.name, l.monat, l.dateiname, l.pfad, l.hochgeladen_am,
           (select count(*) from public.lohnzettel_abrufe a where a.lohnzettel_id = l.id and a.abgerufen_von = l.person_id),
           (select max(a.abgerufen_am) from public.lohnzettel_abrufe a where a.lohnzettel_id = l.id and a.abgerufen_von = l.person_id)
    from public.lohnzettel l
    join public.teamapp_persons p on p.id = l.person_id
    order by l.monat desc, p.name;
end
$$;

-- Bekannte Dienstnehmer-Nummern → Person (für die automatische Zuordnung beim Hochladen)
create or replace function public.lohnzettel_dn_liste()
returns table (dn_nr text, person_id text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.lohnzettel__nur_inhaberin();
  return query select z.dn_nr, z.person_id from public.lohnzettel_dn_zuordnung z;
end
$$;

-- Wer hat schon ein Lohnzettel-Passwort? (für die Inhaberin; nie der Hash)
create or replace function public.lohnzettel_passwort_liste()
returns table (person_id text, gesetzt_am timestamptz, gesperrt_bis timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.lohnzettel__nur_inhaberin();
  return query select pw.person_id, pw.gesetzt_am, pw.gesperrt_bis from public.lohnzettel_passwort pw;
end
$$;

-- Passwort vergessen: Inhaberin setzt zurück → Person richtet beim nächsten Öffnen neu ein
create or replace function public.lohnzettel_passwort_zuruecksetzen(p_person text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform public.lohnzettel__nur_inhaberin();
  delete from public.lohnzettel_passwort where person_id = p_person;
  delete from public.lohnzettel_freischaltung where person_id = p_person;
end
$$;

-- Lohnzettel-Eintrag löschen (die Datei löscht die App danach selbst aus dem Bucket)
create or replace function public.lohnzettel_loeschen(p_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_pfad text;
begin
  perform public.lohnzettel__nur_inhaberin();
  delete from public.lohnzettel where id = p_id returning pfad into v_pfad;
  return v_pfad;
end
$$;

-- Funktionen: nicht für anon (Supabase gibt sonst PUBLIC/anon EXECUTE)
revoke all on function
  public.lohnzettel_meine_person_id(), public.lohnzettel_ist_freigeschaltet(), public.lohnzettel_darf_sehen(text),
  public.lohnzettel__freischalten(text), public.lohnzettel_status(), public.lohnzettel_entsperren(text),
  public.lohnzettel_passwort_setzen(text, text), public.lohnzettel_sperren(), public.lohnzettel_meine(),
  public.lohnzettel_abruf(uuid), public.lohnzettel__nur_inhaberin(),
  public.lohnzettel_eintragen(text, date, text, text, integer, text), public.lohnzettel_uebersicht(), public.lohnzettel_dn_liste(),
  public.lohnzettel_passwort_liste(), public.lohnzettel_passwort_zuruecksetzen(text), public.lohnzettel_loeschen(uuid)
  from public, anon;
grant execute on function
  public.lohnzettel_meine_person_id(), public.lohnzettel_ist_freigeschaltet(), public.lohnzettel_darf_sehen(text),
  public.lohnzettel_status(), public.lohnzettel_entsperren(text),
  public.lohnzettel_passwort_setzen(text, text), public.lohnzettel_sperren(), public.lohnzettel_meine(),
  public.lohnzettel_abruf(uuid),
  public.lohnzettel_eintragen(text, date, text, text, integer, text), public.lohnzettel_uebersicht(), public.lohnzettel_dn_liste(),
  public.lohnzettel_passwort_liste(), public.lohnzettel_passwort_zuruecksetzen(text), public.lohnzettel_loeschen(uuid)
  to authenticated;
-- lohnzettel__freischalten / lohnzettel__nur_inhaberin: nur intern (kein direkter Aufruf)

-- ── 5. Privater Storage-Bucket ───────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lohnzettel', 'lohnzettel', false, 5242880, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 5242880, allowed_mime_types = array['application/pdf'];

-- Lesen (auch Download-Link erzeugen): Inhaberin oder die Person selbst, freigeschaltet
drop policy if exists "lohnzettel_lesen" on storage.objects;
create policy "lohnzettel_lesen" on storage.objects for select to authenticated
  using (bucket_id = 'lohnzettel' and public.lohnzettel_darf_sehen(split_part(name, '/', 1)));
-- Hochladen / Löschen: nur Inhaberin
drop policy if exists "lohnzettel_hochladen" on storage.objects;
create policy "lohnzettel_hochladen" on storage.objects for insert to authenticated
  with check (bucket_id = 'lohnzettel' and public.teamapp_ist_inhaberin());
drop policy if exists "lohnzettel_loeschen" on storage.objects;
create policy "lohnzettel_loeschen" on storage.objects for delete to authenticated
  using (bucket_id = 'lohnzettel' and public.teamapp_ist_inhaberin());
-- kein UPDATE: ein Lohnzettel wird nicht überschrieben (Korrektur = neuer Lohnzettel)

commit;

-- ── Kontrolle: alle neuen Tabellen haben RLS (Spalte rls muss überall true sein) ──
select c.relname as tabelle, c.relrowsecurity as rls
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'lohnzettel%'
order by 1;
