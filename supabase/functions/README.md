# Edge Functions — Deploy-Hinweise

`rapid-function` und `rapid-service` liegen hier vorbereitet, sind aber
**noch nicht deployed**. Das braucht Zugriff, den dieser Agent nicht hat
(Supabase CLI-Login mit einem Personal Access Token, den laut Runbook ein
Mensch erzeugt).

## Schritte für einen Menschen

```bash
supabase login                       # PAT aus dashboard/account/tokens
supabase link --project-ref wrxlaltgtgkdomklgrlj
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy rapid-function
supabase functions deploy rapid-service   # nur zusammen mit dem Wörni-PR in index.greathairday, siehe unten
```

Danach im Anthropic-Dashboard ein monatliches Ausgabenlimit setzen.

## rapid-service (Wörni) — nur zusammen mit index.greathairday einspielen

`rapid-service` ist der Proxy für Wörni auf der Startseite und in der
Schaltzentrale (`index.greathairday`). Die neue Fassung nimmt nur noch
`{ zweck, text }` an und lässt nur die Inhaberin durch (Rolle wird auf dem
Server gegen `teamapp_persons` geprüft). Die alte Fassung der Aufrufer
schickt noch `model`/`system`/`messages` und bekommt dann 400.

Reihenfolge, damit Wörni nicht ausfällt:

1. PR in `index.greathairday` („Wörni: nur noch zweck + text“) mergen.
2. Direkt danach `supabase functions deploy rapid-service`.
3. Startseite neu laden, einmal mit Wörni sprechen, in der Schaltzentrale
   einmal eine Sprach-Aufgabe anlegen: alle drei müssen antworten.

Voraussetzung: `20260920120000_p0_teamapp_rolle_schutz_und_monatszuweisung.sql`
ist eingespielt. Ohne den Trigger dort könnte sich eine Mitarbeiter:in
selbst `rolle = 'inhaberin'` geben und damit auch diese Prüfung umgehen.

## swift-worker

Existiert live, liegt aber in keinem der Repos und war für diesen Agenten
nicht einsehbar. Laut Anleitung prüft `swift-worker` die Inhaberinnen-Rolle
bereits serverseitig — das muss ein Mensch mit Supabase-Zugriff (Dashboard
oder `supabase functions download`) verifizieren, nicht nur am Kommentar im
Code glauben.

## team-admin — hier jetzt neu vorbereitet, ersetzt die live deployte Version

Die bisher live deployte Version dieser Funktion (aufgerufen aus team.html
für create_user/set_password/deactivate/reactivate) war ebenfalls in keinem
Repo einsehbar — und laut Live-Fehler (`PGRST204: Could not find the
'pw_hash' column of 'teamapp_persons'`) noch auf dem Stand vor der
P0-Migration (`20260908143643_p0_teamapp_persons.sql`), die diese Spalte
bewusst gelöscht hat. Dadurch schlug "Passwort setzen" für jede Person fehl.

Die hier neu vorbereitete Version (`supabase/functions/team-admin/index.ts`)
fasst ausschließlich das echte Supabase-Auth-Konto an (createUser/
updateUserById), nie `teamapp_persons`, und prüft serverseitig über den
echten Session-Token, dass nur `rolle='inhaberin'` diese Aktionen ausführen
darf. Vor dem Deploy kurz gegenlesen und danach:

```bash
supabase functions deploy team-admin
```

Test nach Deploy: In team.html als Inhaberin "Passwort setzen" für eine
Person versuchen — sollte jetzt ohne PGRST204-Fehler durchlaufen und in
`auth.users` (`select email, email_confirmed_at from auth.users where
email = '...'`) eine Zeile erzeugen/aktualisieren.

## Test nach Deploy

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://wrxlaltgtgkdomklgrlj.supabase.co/functions/v1/rapid-function" \
  -H "Content-Type: application/json" \
  -H "apikey: <anon-key>" \
  -d '{"zweck":"checkliste","text":"test"}'
# Erwartung: 401 (kein gültiges User-Token)
```

## team-sso — Einstieg in die Team-App über den Team-Login (Kennung + PIN)

Neu (2026-11-04). Wer sich auf der Startseite über „Team-Login“ anmeldet,
kommt damit direkt in die Team-App, ohne E-Mail-Login. Die Funktion prüft
den Team-Login-Token serverseitig (`session_by_token`), sucht die passende
aktive Person in `teamapp_persons` (über den Namen, nie `rolle='inhaberin'`)
und gibt einen einmaligen Anmelde-Code für deren bestehendes Konto zurück
(es wird keine Mail verschickt). Personen ohne Team-App-Konto bekommen eine
Meldung „bitte Mirjam Bescheid geben“ – Konten legt weiterhin nur die
Chefin an (`team-admin`).

```bash
supabase functions deploy team-sso
```

Danach testen: auf der Startseite als Mitarbeiter:in über „Team-Login“
anmelden → Kachel „Team“ → die Team-App muss sich ohne E-Mail-Abfrage
mit dem Namen dieser Person öffnen.

## bewerbung-ki — KI-Gesprächsleitfaden für Bewerbungen

Neu (2026-11-04). Aufgerufen aus `bewerbungen.html` in `index.greathairday`
(Karte „Gesprächsleitfaden (KI-Vorschlag)“). Der Browser schickt nur die
Bewerbungs-ID. Die Funktion holt die Daten mit dem Token der angemeldeten
Person über `bewerbung_ki_eingabe` (prüft selbst `rolle = 'inhaberin'`, gibt
keinen Namen und keine Kontaktdaten heraus), lässt Claude 5–6 Fragen
vorschlagen und speichert sie über `bewerbung_ki_leitfaden_speichern`.

Reihenfolge:

1. In `index.greathairday` die Migration
   `supabase/migrations/20261104120000_ki_gespraechsleitfaden.sql` im
   SQL-Editor ausführen.
2. `supabase functions deploy bewerbung-ki` (nutzt dasselbe Secret
   `ANTHROPIC_API_KEY` wie `rapid-service`).
3. Die Seiten aus `index.greathairday` live stellen (PR mergen).

Test nach Deploy:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://wrxlaltgtgkdomklgrlj.supabase.co/functions/v1/bewerbung-ki" \
  -H "Content-Type: application/json" -H "apikey: <anon-key>" \
  -d '{"id":"00000000-0000-0000-0000-000000000000"}'
# Erwartung: 401 (kein gültiges User-Token)
```

Dann in `bewerbungen.html` als Inhaberin bei einer grünen oder gelben
Bewerbung „Leitfaden erstellen“ drücken: Nach bis zu einer Minute stehen die
Fragen in der Karte, im Verlauf steht „KI-Gesprächsleitfaden erstellt“.
