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

## NICHT erledigt — noch offen

0. **⚠️ Neu entdeckt: viele weitere, nie geprüfte Edge Functions.** Beim Nachsehen, ob
   `rapid-service` existiert (Antwort: nein, gibt's nicht, war nur eine Vermutung aus dem alten
   Report), fiel auf: Im Hauptprojekt ("Lernquiz") liegen weit mehr Functions als die drei, die
   der Security-Report je kannte (`rapid-function`, `rapid-service`, `swift-worker`). Gesehen
   (Liste ging über den sichtbaren Bereich hinaus, evtl. unvollständig):
   `dynamic-processor`, `mitarbeiter-anziehen`, `process-woerni-aufgabe`, `quick-api`,
   `quick-task`, `rapid-function`, `rechte-gatekeeper`, `smooth-handler`, `tageslage`,
   `team-admin`, `telegram-setup-webhook`, `telegram-tageslage` — und vermutlich mehr weiter
   unten in der Liste (u.a. `swift-worker` selbst war noch nicht sichtbar).
   **Keine davon wurde auf einen Auth-Check (`auth.getUser()`) geprüft.** Besonders
   `rechte-gatekeeper` (Name deutet auf Berechtigungsprüfung) und `team-admin` (setzt
   Passwörter) verdienen als erstes einen Blick. Mirjam wollte das bewusst auf ein andermal
   verschieben — nicht vergessen, das ist potenziell die größte verbliebene unbekannte Fläche.
1. **swift-worker und team-admin verifizieren** — beide existieren bereits (team.html ruft
   `team-admin` auf), lagen aber in keinem der vier Repos und waren nicht einsehbar. Laut
   Anleitung prüft `swift-worker` die Inhaberinnen-Rolle serverseitig — das per Dashboard oder
   `supabase functions download` verifizieren, nicht nur dem Kommentar im Code glauben. (Siehe
   auch Punkt 0 — das ist jetzt Teil eines größeren, noch unbekannten Kreises von Functions.)
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
