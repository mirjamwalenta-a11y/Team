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
möglich). Alle DB-Migrationen wurden deshalb gemeinsam mit Mirjam live im Supabase SQL Editor
durchgeführt (Chat-geführt, Statement für Statement) — Details siehe "Live durchgeführt" unten.
Die Edge Functions liegen als fertiger Code vor, sind aber noch **nicht deployed**.

**Projekt-Namen im Dashboard vs. Code:** Die Anzeigenamen im Supabase-Dashboard weichen von den
technischen Projekt-IDs ab und sind irreführend:
- Hauptprojekt (`wrxlaltgtgkdomklgrlj`) heißt im Dashboard **"Lernquiz"**
- Lager-Projekt (`lpuxvvfrrcnbuzafscyk`) heißt im Dashboard **"Belege"**
- Es gibt daneben kein separates, dritt es Projekt mehr für "Belege"/Belegchecker gefunden —
  falls es das noch gibt, ist es außerhalb der beiden hier bekannten Projekte.

## Live durchgeführt (mit Mirjam, 08.09.2026, im Supabase SQL Editor)

- [x] `teamapp_persons`: RLS aktiviert (nur `authenticated` liest), `pw_hash`-Spalte gelöscht.
- [x] Passwörter zurückgesetzt für: Mirjam, Mazen, Hassan, Alina (Login geprüft — funktioniert).
      **Nicht angefasst:** Testmitarbeiter (`pranz@test.at`, bewusst unverändert laut Mirjam) und
      Woerni (`woerni-telegram@greathairday.internal`, Bot-Konto für Telegram-Anbindung — Passwort
      liegt vermutlich zusätzlich in der Bot-Konfiguration, NICHT ändern ohne das dort zu
      synchronisieren).
- [x] `teamapp_invites`: `laeuft_ab`-Spalte + RLS (anon liest nur nicht abgelaufene Einladungen).
- [x] RLS für `ghd_ereignisse`, `ghd_aufgaben`, `ghd_aufgaben_vorlagen`, `ghd_aufgaben_verlauf`,
      `salon_checks`, `salon_monatszuweisung`, `einkauf_items`, `einkauf_listen`, `einkauf_flex`,
      `lager_bestellliste` — alle existierten, alle Policies erfolgreich angelegt.
- [x] `lager_data`: Tabelle im Hauptprojekt angelegt + RLS. Die alte Tabelle im Lager-Projekt
      (`lpuxvvfrrcnbuzafscyk` / "Belege") war leer (0 Zeilen) — **kein Datenübertrag nötig**.
      Mirjams aktuelle Lagerbestände lagen/liegen lokal im Browser (localStorage) und wurden
      nach dem Login erfolgreich neu hochsynchronisiert (von ihr bestätigt: "alles in Ordnung").
- [x] `abw_team`/`abw_anfragen`/`abw_einstellungen`: RLS + Helper-Funktionen
      (`abw_current_person_id()`, `abw_is_owner()`) aus den vorbereiteten Dateien im
      `abwesenheiten-ghd`-Repo eingespielt.
- [x] `abw_team_scoped`-View (maskiert Urlaubsanspruch/-verbraucht/Eintrittsdatum fremder Zeilen)
      eingespielt — Frontend fragt bereits gezielt diese View ab, kein Client-Fix mehr nötig.

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

## Live durchgeführt, zweiter Teil (mit Mirjam, 08.09.2026, Edge Function + Anthropic)

- [x] `rapid-function` im Supabase-Dashboard deployed (Projekt "Lernquiz" = Hauptprojekt), Code
      per Copy-Paste im Dashboard-Editor (kein CLI). `ANTHROPIC_API_KEY`-Secret war bereits von
      früher hinterlegt, kein neues Secret nötig.
- [x] Getestet per Browser-Console-`fetch` ohne Auth-Token → Antwort
      `{"error":"Nicht angemeldet"}` — Funktion läuft und lehnt unautorisierte Anfragen korrekt ab.
- [x] `rapid-service` bewusst NICHT deployed — laut Mirjam nicht in Verwendung, nur
      `rapid-function` wird gebraucht (von team.html, salon-checklist.html, abwesenheiten.html).
- [x] Anthropic-Kostenbremse geklärt: Konto läuft auf Prepaid-Guthaben (aktuell 19,05 €) mit
      **deaktiviertem** Auto-Aufladen — das ist bereits die sicherste Variante, kein zusätzliches
      Spend-Limit nötig. Bewusst nicht aktiviert (Auto-Aufladen einzuschalten würde die
      natürliche Kostenbremse aufheben).
- [x] Beim Setzen der Anthropic-Secrets fiel auf: `WOERNI_SERVICE_EMAIL` und
      `WOERNI_SERVICE_PASSWORD` liegen bereits als Supabase-Secrets vor — bestätigt, dass Woernis
      Zugangsdaten für die Telegram-Automatisierung dort (nicht in `auth.users`) verwaltet werden.
      Grund, warum wir Woernis Passwort in der DB bewusst nicht angefasst haben (siehe oben).

## Edge-Function-Vollaudit (09.09.2026, mit Mirjam, alle im Hauptprojekt "Lernquiz")

Vollständige Liste der 12 Functions dort (`swift-worker` existiert NICHT (mehr), war nur eine
falsche Annahme im alten Report): `dynamic-processor`, `mitarbeiter-anziehen`,
`process-woerni-aufgabe`, `quick-api`, `quick-task`, `rapid-function`, `rechte-gatekeeper`,
`smooth-handler`, `tageslage`, `team-admin`, `telegram-setup-webhook` (gelöscht, s.u.),
`telegram-tageslage`.

Ergebnisse, Code jeweils gelesen (nicht nur Kommentare geglaubt):

- [x] **`team-admin`** — sauber: echter `auth.getUser()`-Check + serverseitige Rollenprüfung
      (`inhaberin`) vor jeder Aktion (create_user/set_password/deactivate/reactivate).
- [x] **`rechte-gatekeeper`** — sauber, sogar vorbildlich: feste Positivliste erlaubter
      Aktionen (delete_person/create_entry/update_entry/delete_entry) + derselbe
      Auth+Rollen-Check wie team-admin.
- [x] **`telegram-setup-webhook`** — **war komplett ungeschützt** (keinerlei Auth-Check) und
      hat bei jedem Aufruf Teile des Telegram-Bot-Tokens verraten (Länge + erste/letzte 4
      Zeichen) sowie Bot-Status-Infos, öffentlich für jeden im Internet. War laut eigenem
      Code-Kommentar ohnehin nur ein einmaliges Einrichtungs-Werkzeug ("kann danach gelöscht
      werden") — **gelöscht**. Telegram-Bot funktioniert unverändert weiter (Webhook war schon
      gesetzt).
- [x] **`telegram-tageslage`** — sauber: prüft Telegrams eigenes Webhook-Secret
      (`x-telegram-bot-api-secret-token`), reagiert nur auf 3 feste Trigger-Sätze, meldet sich
      für die eigentliche Datenabfrage über ein Service-Konto sauber bei Supabase an (kein
      Sonderweg). "Verify JWT" bleibt hier bewusst AUS (Telegram kann keinen Supabase-Token
      mitschicken) — durch den Secret-Check trotzdem geschützt.
- [x] **`tageslage`** — Code prüft nur, dass ein Authorization-Header *vorhanden* ist, nicht ob
      er *gültig* ist; verlässt sich auf zwei externe Schutzschichten: Plattform-JWT-Verifikation
      (Supabase-Einstellung) + RLS auf `ghd_aufgaben`. Die Plattform-Einstellung **"Verify JWT"
      war ausgeschaltet** (Abweichung vom eigenen Code-Kommentar "nicht ausschalten") — **wieder
      eingeschaltet**. RLS auf `ghd_aufgaben` war ohnehin bereits aktiv (siehe oben), hätte im
      Ernstfall auch ohne die Plattform-Prüfung ungültige Tokens abgelehnt — praktisches Risiko
      war dadurch begrenzt, aber die fehlende erste Schutzschicht war trotzdem ein echter Fund.
- [x] **`process-woerni-aufgabe`** — 🔴 **schwerwiegendster Fund**: überhaupt keine Absicherung,
      kompletter Anfrage-Body wurde 1:1 unverändert an die Anthropic-API durchgereicht. Jeder im
      Internet hätte auf Mirjams Anthropic-Guthaben beliebige, auch teure Modelle/Anfragen
      auslösen können (Modell, Textlänge, alles frei wählbar von außen) — praktisch ein offener
      Zugang zu ihrem API-Guthaben, nur durch das ohnehin fehlende Auto-Aufladen (19€ Deckel)
      begrenzt. Wird laut Mirjam noch gebraucht (genauer Aufrufer nicht bekannt, Logs leer) —
      **gefixt**: derselbe `auth.getUser()`-Check wie bei team-admin/rechte-gatekeeper/
      rapid-function ergänzt, Rest der Funktion (Body wird weiterhin 1:1 durchgereicht)
      unverändert gelassen, um nichts Bestehendes zu brechen. **Falls in den nächsten Tagen
      irgendein automatischer Wörni-Ablauf nicht mehr funktioniert, hier zuerst nachschauen** —
      dann braucht der eigentliche Aufrufer vermutlich noch einen echten Supabase-Token, den er
      bisher nicht mitgeschickt hat.

**Noch zu prüfen (nächstes Mal):** `dynamic-processor`, `mitarbeiter-anziehen`, `quick-api`,
`quick-task`, `smooth-handler` — Code jeweils noch nicht gelesen. Die vier generisch benannten
(`dynamic-processor`, `quick-api`, `quick-task`, `smooth-handler`) sehen nach automatisch von
Supabase vergebenen Platzhalternamen aus (könnten alte/verwaiste Test-Deployments von
`rapid-function` sein) — trotzdem prüfen, nicht nur vermuten.

## NICHT erledigt — noch offen

1. **Restliche Edge Functions prüfen** — siehe Liste direkt oberhalb.
2. **CDN-Pinning + SRI (I1)** — bewusst NICHT gemacht, siehe Begründung im Commit-Verlauf:
   ohne Netzwerkzugriff keine echten SRI-Hashes berechenbar, ein falscher Hash hätte die Seiten
   lahmgelegt. Betroffen: `cdn.jsdelivr.net`, `cdnjs.cloudflare.com`, `unpkg.com`,
   `cdn.tailwindcss.com`. Niedrige Priorität, kann später mit echtem Netzwerkzugriff nachgeholt
   werden.
3. **os_aufgaben in Lager_index.html** (Zeilen ~1286-1304) — schreibt weiterhin mit dem
   anon-Key des Lager-Projekts ("Belege"). Gleiches Muster wie L1, aber laut
   `CODE-VORSCHLAEGE-AGENT.md` "nicht Teil dieser GHD-Absicherung" — bewusst nicht angefasst.
4. **`alert('Fehler: '+e.message)`** — viele Stellen v.a. in team.html, geringes Risiko (natives
   Dialogfeld, kein HTML-Kontext), nicht pauschal umgeschrieben.
5. **Live-Verifikation (Schritt 5 im Runbook, `rlstest.sh`)** — konnte in dieser Session nicht
   ausgeführt werden (kein Terminal/curl-Zugriff bei Mirjam, kein Supabase-MCP hier). Alle
   Kern-Migrationen sind eingespielt und live getestet (Login, Lager-Sync, Edge Function) — ein
   formeller Abschluss-Scan mit dem Skript steht aber noch aus.

## Nicht angefasst (bereits sicher / bewusst unverändert)

- `abw_team` RLS — laut Live-Test bereits HTTP 401, nicht verändert.
- A2 (Client-seitige Rollenprüfung `_istChefin()`) — bleibt für die Oberfläche, echte
  Absicherung ist RLS (siehe Migrationen).
- A3 (PIN-Login-Härtung) — reine Konfigurationsempfehlung (Rate-Limits im Dashboard), kein Code.

## Definition of Done — noch offen

Kann von dieser Session aus nicht abschließend bestätigt werden (kein Supabase-Zugriff). Nach
Erledigung der Punkte oben: `bash rlstest.sh` laufen lassen und gegen die Ziel-Ausgabe in
`FIX-ANLEITUNG-AGENT.md` prüfen.
