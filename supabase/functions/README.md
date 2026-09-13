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
supabase functions deploy rapid-service   # nach Prüfung der SYSTEM_PROMPTS, siehe TODO in der Datei
```

Danach im Anthropic-Dashboard ein monatliches Ausgabenlimit setzen.

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
