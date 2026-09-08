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

1. **Migrationen einspielen** (`supabase/migrations/` in diesem Repo, Reihenfolge nach
   Zeitstempel):
   - `20260908143643_p0_teamapp_persons.sql` — **zuerst lesen**: der `drop column pw_hash`
     darf erst nach dem Passwort-Reset laufen (siehe Punkt 2).
   - `20260908143644_t3_teamapp_invites.sql`
   - `20260908144000_l0_lager_data_umzug.sql` — enthält den manuellen Datenübertrag aus dem
     Lager-Projekt (Schritt 2 in der Datei). **Ohne diesen Schritt bleibt der Lager-Sync in
     Lager_index.html kaputt** (der Client-Fix ist bereits gepusht und erwartet die Tabelle
     im Hauptprojekt).
   - `20260908144500_rls_ghd_checkliste_einkauf.sql`
   - Zusätzlich bereits vorhanden (nicht von mir verändert, aus einer früheren Session):
     `abwesenheiten-ghd/rls_haertung_abwesenheit.sql` und
     `abwesenheiten-ghd/rls_haertung_abw_team_spalten.sql` — prüfen, ob diese schon eingespielt
     sind (Live-Test zeigte `abw_team` bereits als HTTP 401).
2. **Passwörter zurücksetzen** — die `pw_hash`-Werte in `teamapp_persons` waren im Klartext
   öffentlich lesbar. Alle betroffenen Supabase-Auth-Passwörter neu setzen, **Mirjam zuerst**.
3. **Edge Functions deployen** (`supabase/functions/` in diesem Repo): `rapid-function` und
   `rapid-service` sind fertig codiert, aber nicht deployed. `supabase/functions/README.md`
   hat die genauen Schritte (Login, Secret setzen, Deploy, Test). `rapid-service`s
   SYSTEM_PROMPTS-Liste ist ein Platzhalter — vor dem Deploy die echten Aufrufer prüfen.
4. **swift-worker und team-admin verifizieren** — beide existieren bereits (team.html ruft
   `team-admin` auf), lagen aber in keinem der vier Repos und waren für mich nicht einsehbar.
   Laut Anleitung prüft `swift-worker` die Inhaberinnen-Rolle serverseitig — das per Dashboard
   oder `supabase functions download` verifizieren, nicht nur dem Kommentar im Code glauben.
5. **Anthropic-Dashboard:** monatliches Ausgabenlimit setzen.
6. **CDN-Pinning + SRI (I1)** — bewusst NICHT gemacht: ich hatte keinen Netzwerkzugriff, um
   echte SRI-Hashes zu berechnen oder zu prüfen, ob eine gepinnte Versionsnummer überhaupt
   existiert. Ein falscher/erfundener Hash hätte die Seiten in Produktion lahmgelegt (Browser
   blockiert Skripte bei SRI-Mismatch). Aktuell betroffen: `cdn.jsdelivr.net` (supabase-js, alle
   vier Apps), `cdnjs.cloudflare.com` (xlsx, Lager_index.html), `unpkg.com` (React/ReactDOM/
   Babel, abwesenheiten.html), `cdn.tailwindcss.com`. Empfehlung: mit echtem Netzwerkzugriff auf
   exakte Versionen pinnen und Hashes über srihash.org ziehen.
7. **Live-Verifikation (Schritt 5 im Runbook)** — `bash rlstest.sh`, der Edge-Function-curl-Test
   und die MCP-Abfragen ("Tabellen ohne RLS" / "Policies mit anon-Zugriff") brauchen echten
   Supabase-Zugriff. Nach dem Einspielen der Migrationen von einem Menschen oder einer Session
   mit Supabase-MCP-Zugriff ausführen.
8. **os_aufgaben in Lager_index.html** (Zeilen ~1286-1304) — schreibt weiterhin mit dem
   anon-Key des Lager-Projekts. Gleiches Muster wie L1, aber laut `CODE-VORSCHLAEGE-AGENT.md`
   "nicht Teil dieser GHD-Absicherung" — bewusst nicht angefasst, hier nur notiert.
9. **`alert('Fehler: '+e.message)`** — viele Stellen v.a. in team.html, geringes Risiko, nicht
   pauschal umgeschrieben (siehe oben).

## Nicht angefasst (bereits sicher / bewusst unverändert)

- `abw_team` RLS — laut Live-Test bereits HTTP 401, nicht verändert.
- A2 (Client-seitige Rollenprüfung `_istChefin()`) — bleibt für die Oberfläche, echte
  Absicherung ist RLS (siehe Migrationen).
- A3 (PIN-Login-Härtung) — reine Konfigurationsempfehlung (Rate-Limits im Dashboard), kein Code.

## Definition of Done — noch offen

Kann von dieser Session aus nicht abschließend bestätigt werden (kein Supabase-Zugriff). Nach
Erledigung der Punkte oben: `bash rlstest.sh` laufen lassen und gegen die Ziel-Ausgabe in
`FIX-ANLEITUNG-AGENT.md` prüfen.
