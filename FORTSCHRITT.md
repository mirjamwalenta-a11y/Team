# Fortschritt — Security-Hardening Great Hair Day Apps

Stand: 2026-09-08. Bearbeitet nach `FIX-ANLEITUNG-AGENT.md` / `CODE-VORSCHLAEGE-AGENT.md` /
`00-START-CLAUDE-CODE.md`. **Wichtige Abweichung vom Runbook:** Die vier Apps liegen nicht als
Ordner in einem Repo, sondern in vier getrennten GitHub-Repos:

| App | Repo | Branch |
|---|---|---|
| team.html | `mirjamwalenta-a11y/Team` | `claude/new-session-hazqcn` |
| salon-checklist.html | `mirjamwalenta-a11y/salon-checklist` | `claude/security-hardening` |
| Lager_index.html | `mirjamwalenta-a11y/lager.greathairday` | `claude/security-hardening` |
| abwesenheiten.html | `mirjamwalenta-a11y/abwesenheiten-ghd` | `claude/security-hardening` |

`team.html` war im Team-Repo zum Sitzungsbeginn gelöscht (letzter Commit: "Delete index.html") —
aus der Git-Historie wiederhergestellt, siehe erster Commit auf dem Branch.

Diese Session hatte **keinen Netzwerkzugriff** auf `*.supabase.co`, GitHub ausgenommen, und
**keine** Supabase-CLI/-PAT/-MCP-Anbindung (Schritt 2 aus `00-START-CLAUDE-CODE.md` war nicht
möglich). Alle DB-Änderungen liegen deshalb als reviewbare `.sql`-Dateien vor, nicht eingespielt.
Alle Edge Functions liegen als Code vor, nicht deployed.

## Erledigt (Client-Code, gepusht)

- [x] **P0** `teamapp_persons`: `hashPw`/`pw_hash` komplett aus team.html entfernt.
- [x] `supa()` (team.html), `sb()` (abwesenheiten.html), `sbFetch()`/`ekSbFetch()`/`ghdWrite()`
      (salon-checklist.html), `blFetch()` (Lager_index.html): kein anon-Key-Fallback mehr bei
      Schreibzugriffen ohne Session (Golden Rule 2), durchgängig.
- [x] Alle vier `claudeAnfrage()`-Funktionen: Session-Token statt anon-Key, kein
      model/max_tokens/system mehr aus dem Browser (fester `zweck`: `checkliste`, `einkauf`,
      `team`, `abwesenheiten`).
- [x] GHD-Schreibzugriffe (ghd_ereignisse, ghd_aufgaben) in allen vier Apps auf Session-Token.
- [x] team.html: Storage-Upload auf Session-Token, Einladungs-Token mit 7-Tage-Ablauf.
- [x] Lager_index.html: `lager_data`-Sync auf Session-Token + Hauptprojekt umgestellt (siehe
      L0-Migration unten — **Sync ist erst nach der Datenmigration wieder funktionsfähig**).
- [x] esc()/XSS: Lager_index.html (2 Stellen) und salon-checklist.html (esc() neu eingeführt,
      alle bekannten Stellen + ein paar zusätzliche in der Einkaufsliste). team.html hatte
      bereits eine esc()-Funktion und war größtenteils schon abgesichert — 2 zusätzliche
      Stellen im lokalen Protokoll-Tab ergänzt (siehe Abweichung unten). abwesenheiten.html
      ist echtes React/JSX ohne dangerouslySetInnerHTML — kein Escaping nötig.
- [x] Fehlermeldungen (I2): rohe `e.message` in `innerHTML`-Stellen entfernt (team.html,
      salon-checklist.html). `alert('Fehler: '+e.message)`-Aufrufe (viele, v.a. team.html)
      **nicht** angefasst — geringes Risiko (natives Dialogfeld, kein HTML-Kontext), aber
      offen für einen späteren Durchgang.
- [x] Logout (I3): salon-checklist.html hatte bereits einen Button, localStorage-Cache-Löschung
      ergänzt. abwesenheiten.html hatte einen Button, der aber nur lokalen State zurücksetzte —
      ruft jetzt echtes `sbAuth.auth.signOut()` auf.
- [x] CSP (I4): Meta-Tag in allen vier Dateien ergänzt.

## Abweichung vom Runbook (eigener Fund)

`00-START-CLAUDE-CODE.md` ging davon aus, team.html rendere über React mit automatischem
Escaping. Tatsächlich ist team.html Vanilla-JS mit `innerHTML`. Eigene Prüfung aller 18
`innerHTML`-Stellen ergab: fast alles war bereits über eine vorhandene, aber vom Report nicht
erwähnte `esc()`-Funktion abgesichert. Zwei Lücken (lokaler Protokoll-Tab: `p.titel`, `p.text`)
wurden ergänzt — Risiko dort gering, da rein lokal in `localStorage` und nicht mit anderen
Nutzern geteilt.

## NICHT erledigt — braucht Supabase-Zugriff (Mensch)

1. ~~**Migrationen einspielen**~~ — **erledigt (bestätigt 2026-09-20).** Live-Check
   (`pg_policies`/`pg_class`) zeigt RLS aktiv + Policies vorhanden für alle Tabellen aus
   `20260908143643_p0_teamapp_persons.sql`, `20260908143644_t3_teamapp_invites.sql` und
   `20260908144500_rls_ghd_checkliste_einkauf.sql` (teamapp_persons, teamapp_invites,
   ghd_ereignisse, ghd_aufgaben, ghd_aufgaben_vorlagen, ghd_aufgaben_verlauf, salon_checks,
   einkauf_items, einkauf_listen, einkauf_flex, lager_bestellliste).
   `20260908144000_l0_lager_data_umzug.sql`: Tabelle `lager_data` existiert im Hauptprojekt
   mit RLS, ist aber leer — **kein Problem**, laut Mirjam läuft `Lager_index.html` im Alltag
   normal. Die Annahme dieser Migration, es gäbe ein separates "altes Lager-Projekt"
   (`lpuxvvfrrcnbuzafscyk`), war überholt/falsch — dieses Projekt ist tatsächlich das
   **Belege**-Projekt (siehe `BELEGE_URL` in team.html), alle anderen Apps inkl. Lager hängen
   am Hauptprojekt. `abw_team` RLS war laut Live-Test schon vor dieser Session aktiv (siehe
   unten, "Nicht angefasst").
2. ~~**Passwörter zurücksetzen**~~ — **erledigt (bestätigt 2026-09-20 von Mirjam).** Die
   `pw_hash`-Werte in `teamapp_persons` waren im Klartext öffentlich lesbar; alle betroffenen
   Supabase-Auth-Passwörter wurden neu gesetzt. Die Spalte `pw_hash` selbst ist laut Live-Check
   vom 20.9. auch aus der Tabelle verschwunden (`information_schema.columns` zeigt sie nicht
   mehr). Hinweis für später: `auth.users.updated_at` ist **kein** verlässlicher Nachweis für
   einen Passwort-Reset — es wird bei jedem Login aktualisiert, nicht nur bei einer
   Passwort-Änderung.
3. **Edge Functions deployen** (`supabase/functions/` in diesem Repo): `rapid-function` und
   `rapid-service` sind fertig codiert, aber nicht deployed. `supabase/functions/README.md`
   hat die genauen Schritte (Login, Secret setzen, Deploy, Test).
   **Stand 2026-09-20:** `rapid-function`s SYSTEM_PROMPTS sind bereits korrekt für alle vier
   bekannten Apps befüllt (`checkliste`/`einkauf`/`team`/`abwesenheiten`) — code-seitig fertig
   zum Deployen. `rapid-service`s SYSTEM_PROMPTS-Liste ist weiterhin ein Platzhalter: nach
   `rapid-service` in sieben Repos gesucht (Team, Mitarbeiterhandbuch, salon-checklist,
   lager.greathairday, abwesenheiten-ghd, belege.greathairday, moment.greathairday) — kein
   Aufrufer gefunden. Entweder ungenutzt/für später geplant, oder der Aufrufer liegt in einem
   der übrigen Repos (dokumentenschrank-ghd, Lernquiz-Apps, haarnetzwerk, innungsapp,
   index.greathairday) — auf Wunsch von Mirjam nicht weiter durchsucht. Der eigentliche Deploy
   (`supabase login`/`deploy`) bleibt in jedem Fall Handarbeit mit CLI-Zugriff.
4. ~~**team-admin verifizieren**~~ — **erledigt (2026-09-20).** Liegt jetzt fertig im Team-Repo
   (`supabase/functions/team-admin/index.ts`, aus einer früheren Session). Code gegengelesen:
   prüft serverseitig über den echten Session-Token, dass nur `rolle='inhaberin'` Konten
   anlegen/Passwörter setzen/deaktivieren/reaktivieren darf — keine Client-seitige Prüfung,
   kein vom Client mitgeschickter Rollenwert. Noch nicht deployed (siehe Punkt 3), aber der
   Code selbst ist verifiziert.
   **swift-worker weiterhin nicht auffindbar** — in denselben sieben Repos wie oben gesucht,
   kein Treffer. Liegt vermutlich in einem der übrigen Repos oder muss direkt im
   Supabase-Dashboard (Edge Functions-Liste) oder per `supabase functions download`
   verifiziert werden.
5. ~~**Anthropic-Dashboard:** monatliches Ausgabenlimit setzen.~~ — **erledigt** (von Mirjam
   schon vor einiger Zeit gesetzt, am 2026-09-20 bestätigt).
6. **CDN-Pinning + SRI (I1)** — bewusst NICHT gemacht: kein Netzwerkzugriff, um
   echte SRI-Hashes zu berechnen oder zu prüfen, ob eine gepinnte Versionsnummer überhaupt
   existiert. Ein falscher/erfundener Hash hätte die Seiten in Produktion lahmgelegt (Browser
   blockiert Skripte bei SRI-Mismatch). Aktuell betroffen: `cdn.jsdelivr.net` (supabase-js, alle
   vier Apps), `cdnjs.cloudflare.com` (xlsx, Lager_index.html), `unpkg.com` (React/ReactDOM/
   Babel, abwesenheiten.html), `cdn.tailwindcss.com`.
   **Stand 2026-09-20:** erneut versucht, weiterhin kein Netzwerkzugriff — die Sandbox-Umgebung
   blockt `cdn.jsdelivr.net`/`cdnjs.cloudflare.com`/`unpkg.com`/`srihash.org` über die
   Proxy-Policy (`EGRESS_BLOCKED`, bestätigt per curl und WebFetch). Das ist eine feste
   Einstellung der jeweiligen Session/Umgebung, keine, die sich während einer laufenden
   Session ändert. Genauer Ablauf für eine Session/einen Menschen mit Netzwerkzugriff:
   1. Für jede der vier CDN-URLs die aktuell tatsächlich ausgelieferte Version ermitteln
      (z. B. `curl -sI <URL>` oder die Redirect-Ziel-URL bei "latest"-Pfaden ansehen).
   2. Die `<script src="...">`-Tags in allen vier Apps auf diese exakte Version umstellen
      (kein `@latest`/ungepinnter Pfad mehr).
   3. Für jede gepinnte Datei den Hash über https://www.srihash.org/ (oder
      `openssl dgst -sha384 -binary <Datei> | openssl base64 -A`) ziehen und als
      `integrity="sha384-..."`- sowie `crossorigin="anonymous"`-Attribut ergänzen.
   4. Danach die Seiten einmal im Browser laden und die Konsole auf SRI-Mismatch-Fehler
      prüfen, bevor gepusht wird.
7. **Live-Verifikation (Schritt 5 im Runbook)** — `bash rlstest.sh`, der Edge-Function-curl-Test
   und die MCP-Abfragen ("Tabellen ohne RLS" / "Policies mit anon-Zugriff") brauchen echten
   Supabase-Zugriff.
   **Stand 2026-09-20:** ebenfalls weiterhin nicht möglich, gleicher Grund (`EGRESS_BLOCKED`
   auf `*.supabase.co`). Die Live-Prüfungen in dieser Session liefen deshalb nicht über
   `rlstest.sh`, sondern manuell per SQL-Abfragen, die Mirjam im Supabase-SQL-Editor
   ausgeführt und deren Ergebnis sie hier eingefügt hat (siehe Session-Verlauf 2026-09-20:
   `pg_policies`/`pg_class`-Checks für alle relevanten Tabellen, `pg_trigger`-Check für
   `teamapp_persons_schuetze_sensible_felder`). Für eine vollautomatische Prüfung braucht es
   entweder eine Session mit direktem Supabase-Zugriff (MCP oder CLI mit Service-Role-Key)
   oder weiterhin diesen manuellen SQL-Editor-Umweg.
8. **os_aufgaben in Lager_index.html** (Zeilen ~1286-1304) — schreibt weiterhin mit dem
   anon-Key des Lager-Projekts. Gleiches Muster wie L1, aber laut `CODE-VORSCHLAEGE-AGENT.md`
   "nicht Teil dieser GHD-Absicherung" — bewusst nicht angefasst, hier nur notiert.
9. ~~**`alert('Fehler: '+e.message)`**~~ — **erledigt (2026-09-20).** Alle 12 generischen
   Stellen in team.html durch verständliche, handlungsbezogene Meldungen ersetzt; die
   technische Meldung landet per `console.error` in der Entwicklerkonsole statt im Dialog.
   Die zwei `updErr.message`-Stellen bei `sbAuth.auth.updateUser()` (Passwort setzen/ändern)
   bewusst unverändert gelassen — von Supabase selbst gestaltete, für Endnutzer:innen sichere
   Hinweise, kein Backend-Detail.

## Nicht angefasst (bereits sicher / bewusst unverändert)

- `abw_team` RLS — laut Live-Test bereits HTTP 401, nicht verändert.
- A2 (Client-seitige Rollenprüfung `_istChefin()`) — bleibt für die Oberfläche, echte
  Absicherung ist RLS (siehe Migrationen).
- A3 (PIN-Login-Härtung) — reine Konfigurationsempfehlung (Rate-Limits im Dashboard), kein Code.

## Definition of Done — noch offen

Kann von dieser Session aus nicht abschließend bestätigt werden (kein Supabase-Zugriff). Nach
Erledigung der Punkte oben: `bash rlstest.sh` laufen lassen und gegen die Ziel-Ausgabe in
`FIX-ANLEITUNG-AGENT.md` prüfen.
