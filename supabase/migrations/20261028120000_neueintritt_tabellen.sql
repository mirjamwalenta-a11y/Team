-- ════════════════════════════════════════════════════════════
--  Neueintritt-App (anmeldung.html): Daten in Supabase sichern
--
--  Bisher lagen alle Daten nur im Browser des jeweiligen Geräts
--  (localStorage/IndexedDB) und waren weg, sobald der Browser seinen
--  Speicher geleert hat oder man an einem anderen Gerät nachgesehen
--  hat. Ab jetzt ist Supabase der feste Speicher, der Browser nur
--  noch Zwischenspeicher (auch für offline).
--
--  Inhalt: SV-Nummer, IBAN, Adressen, Daten von Minderjährigen und
--  ihren Eltern, Fotos von Ausweisen. Deshalb:
--    • NUR die Inhaberin darf lesen, anlegen, ändern, löschen
--      (teamapp_ist_inhaberin(), gleiche Prüfung wie in den übrigen
--      Migrationen) — Mitarbeiter:innen sehen nichts.
--    • anon (nicht angemeldet) hat überhaupt keinen Zugriff.
--  Der Lehrling selbst schreibt NICHT in diese Tabellen — er füllt
--  am eigenen Handy aus und schickt eine Datei zurück (unverändert).
--
--  Tabellen:
--    neueintritt_personen  – eine Zeile pro Lehrling/Mitarbeiter:in
--    neueintritt_anhaenge  – Dokumentfotos (JPEG als data-URL)
--    neueintritt_betrieb   – Lehrbetrieb-/Steuerberater-Daten (1 Zeile)
--
--  Sicher mehrfach ausführbar (idempotent).
-- ════════════════════════════════════════════════════════════

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

-- ── 1. Tabellen ─────────────────────────────────────────────
create table if not exists public.neueintritt_personen (
  id        text primary key check (length(id) between 1 and 64),
  art       text not null check (art in ('lehrling', 'ma')),
  daten     jsonb not null default '{}'::jsonb,
  erledigt  jsonb not null default '{}'::jsonb,
  meta      jsonb not null default '{}'::jsonb,
  erstellt  timestamptz not null default now(),
  geaendert timestamptz not null default now()
);

create table if not exists public.neueintritt_anhaenge (
  id        uuid primary key,
  person_id text not null references public.neueintritt_personen(id) on delete cascade,
  typ       text not null check (length(typ) between 1 and 40),
  w         integer not null check (w between 1 and 4000),
  h         integer not null check (h between 1 and 4000),
  datum     date,
  data_url  text not null check (data_url like 'data:image/jpeg;base64,%' and length(data_url) <= 4000000),
  erstellt  timestamptz not null default now()
);
create index if not exists neueintritt_anhaenge_person_idx on public.neueintritt_anhaenge (person_id);

create table if not exists public.neueintritt_betrieb (
  id        integer primary key default 1 check (id = 1),
  daten     jsonb not null default '{}'::jsonb,
  geaendert timestamptz not null default now()
);

-- geaendert immer vom Server setzen
create or replace function public.neueintritt_geaendert_setzen()
returns trigger
language plpgsql
as $$
begin
  new.geaendert := now();
  return new;
end
$$;

drop trigger if exists neueintritt_personen_geaendert on public.neueintritt_personen;
create trigger neueintritt_personen_geaendert
  before insert or update on public.neueintritt_personen
  for each row execute function public.neueintritt_geaendert_setzen();

drop trigger if exists neueintritt_betrieb_geaendert on public.neueintritt_betrieb;
create trigger neueintritt_betrieb_geaendert
  before insert or update on public.neueintritt_betrieb
  for each row execute function public.neueintritt_geaendert_setzen();

-- ── 2. Zugriff: nur die Inhaberin ───────────────────────────
alter table public.neueintritt_personen enable row level security;
alter table public.neueintritt_anhaenge enable row level security;
alter table public.neueintritt_betrieb  enable row level security;

revoke all on public.neueintritt_personen from anon;
revoke all on public.neueintritt_anhaenge from anon;
revoke all on public.neueintritt_betrieb  from anon;
grant select, insert, update, delete on public.neueintritt_personen to authenticated;
grant select, insert, update, delete on public.neueintritt_anhaenge to authenticated;
grant select, insert, update, delete on public.neueintritt_betrieb  to authenticated;

drop policy if exists "Neueintritt nur Inhaberin" on public.neueintritt_personen;
create policy "Neueintritt nur Inhaberin" on public.neueintritt_personen
  for all to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "Neueintritt nur Inhaberin" on public.neueintritt_anhaenge;
create policy "Neueintritt nur Inhaberin" on public.neueintritt_anhaenge
  for all to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());

drop policy if exists "Neueintritt nur Inhaberin" on public.neueintritt_betrieb;
create policy "Neueintritt nur Inhaberin" on public.neueintritt_betrieb
  for all to authenticated
  using (public.teamapp_ist_inhaberin())
  with check (public.teamapp_ist_inhaberin());

-- ── 3. Kontrolle (Ergebnis sollte 3 Zeilen mit rowsecurity = true zeigen) ──
-- select relname, relrowsecurity as rowsecurity from pg_class
-- where relname in ('neueintritt_personen', 'neueintritt_anhaenge', 'neueintritt_betrieb');
