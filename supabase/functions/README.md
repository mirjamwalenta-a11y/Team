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

## swift-worker und team-admin

Beide existierenden Functions liegen nicht in einem der vier
App-Repos (Team, salon-checklist, lager.greathairday, abwesenheiten-ghd)
und waren für diesen Agenten nicht einsehbar. Laut Anleitung prüft
`swift-worker` die Inhaberinnen-Rolle bereits serverseitig — das muss
ein Mensch mit Supabase-Zugriff (Dashboard oder `supabase functions
download`) verifizieren, nicht nur am Kommentar im Code glauben.
`team-admin` (aufgerufen aus team.html für create_user/set_password)
sollte ebenso auf echte `auth.getUser()`-Prüfung + Inhaberinnen-Check
kontrolliert werden.

## Test nach Deploy

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://wrxlaltgtgkdomklgrlj.supabase.co/functions/v1/rapid-function" \
  -H "Content-Type: application/json" \
  -H "apikey: <anon-key>" \
  -d '{"zweck":"checkliste","text":"test"}'
# Erwartung: 401 (kein gültiges User-Token)
```
