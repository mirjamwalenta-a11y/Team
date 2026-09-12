# Zugriffskonzept: Team, Handbuch, Checkliste

Stand: 2026-09-12. Prüft konkret die drei Apps `Team` (dieses Repo),
`Mitarbeiterhandbuch` und `salon-checklist` ("Checkliste") gegen das Ziel:
**ein Login pro Person, danach automatisch nur die freigegebenen Apps und
Daten — Sicherheit serverseitig, nicht nur in der Oberfläche.**

Geprüft wurde der tatsächliche Code in allen drei Repos (nicht nur dieses
Repo). Für den *Live*-Zustand der Datenbank (welche RLS-Policies gerade
wirklich aktiv sind) gilt dieselbe Einschränkung wie in `FORTSCHRITT.md`:
kein Supabase-Dashboard-/CLI-Zugriff in dieser Session. Alle Aussagen unten
sind aus dem Anwendungscode und den vorliegenden `.sql`-Migrationen
abgeleitet und müssen vor dem Einspielen der neuen Migration
(`20260912120000_rls_rollenbasiert_team_handbuch_checkliste.sql`) mit
`select * from pg_policies where tablename in (...)` gegengeprüft werden.

## Kurzfassung

Die gute Nachricht zuerst: **Es muss keine neue Login-Struktur gebaut
werden.** Team, Handbuch und Checkliste nutzen bereits heute exakt
denselben Mechanismus:

- dasselbe Supabase-Projekt (`wrxlaltgtgkdomklgrlj`),
- denselben echten Login (`supabase.auth.signInWithPassword`, kein Fake-PIN),
- dieselbe Tabelle `teamapp_persons` mit den Feldern `email`, `rolle`
  (`inhaberin` / `mitarbeiter`), `aktiv`.

Das heißt: Eine Person, die sich einmal in Team einloggt, hat technisch
bereits alles, was sie braucht, um sich mit denselben Zugangsdaten auch in
Handbuch und Checkliste einzuloggen — und weil alle drei Apps unter
derselben Herkunft `mirjamwalenta-a11y.github.io/...` laufen, teilen sie
sich sogar automatisch die angemeldete Sitzung im Browser (siehe
"Was 'leicht offen' konkret bedeutet" unten). Es gibt keine Parallel-Logins
zu entfernen — die Frage ist nicht "wie bauen wir SSO", sondern "warum
funktioniert es im Alltag noch nicht für alle außer dich".

Zwei echte Probleme habe ich gefunden:

1. **Ein Rollout-Problem** (nicht Code): Mitarbeiter:innen können sich nur
   einloggen, wenn sie ein aktives Konto mit funktionierendem Passwort
   haben. Am 8.9. wurden die alten `pw_hash`-Werte als kompromittiert
   eingestuft; laut `FORTSCHRITT.md` steht der Passwort-Reset für alle
   Personen aber noch aus. Bis das gemacht ist, kann praktisch nur die
   Person mit einem funktionierenden Passwort — also aktuell du — sich
   einloggen. Das betrifft **alle drei Apps gleich**, weil sie dieselbe
   Nutzer-Datenbank teilen.
2. **Ein echtes Sicherheitsproblem** (Code/Datenbank): Die serverseitigen
   Regeln (RLS) prüfen bisher nur "angemeldet oder nicht", nicht die
   Rolle. Die `_me.rolle === 'inhaberin'`-Prüfungen in allen drei Apps sind
   bisher **nur Oberfläche**. Details und Fix unten bei Punkt 4.

## 1. Wie ist der Zugang aktuell an dein Login gebunden?

**Team (`team.html`)** — nicht hart an dich gebunden. Login läuft über
`sbAuth.auth.signInWithPassword({email, password})`, danach wird die
passende Zeile aus `teamapp_persons` geladen. Jede Person mit aktivem
Konto + `aktiv:true` kommt rein. Ein Einladungs-Mechanismus
(`teamapp_invites`, Link mit 7 Tage Ablauf) zum Onboarding neuer Personen
existiert bereits im Code.

**Handbuch (`Mitarbeiterhandbuch_App.html`)** — identischer Mechanismus,
sogar mit demselben Kommentar im Code: *"gleicher Supabase-Account wie
team.html / lernquiz.html"*. Login prüft `teamapp_persons`, `_me.rolle`
schaltet den Review-Bereich frei. Auch hier: keine Bindung an dich im
Code.

**Checkliste (`salon-checklist.html`)** — Login ebenfalls über denselben
Supabase-Account, jede Person mit Konto kommt in die App hinein. **Aber:**
zwei Stellen weichen von Team/Handbuch ab und bilden genau die
Parallelstruktur, die du vermeiden willst:

- Zeile 464: `let TEAM = ['Mirjam','Alina','Mazen','Hassan','Ronya']` — eine
  von Hand gepflegte Namensliste, unabhängig von `teamapp_persons`.
- Zeile 714: `const CHEFIN_EMAIL = 'mirjam.walenta@gmail.com'` — der
  Admin-Bereich (Monatszuweisung) wird per hart codiertem
  E-Mail-Vergleich freigeschaltet statt über `rolle === 'inhaberin'`.

Das ist der einzige Ort, an dem tatsächlich **deine** E-Mail-Adresse
namentlich im Code steht und Zugriff regelt — nicht der Login selbst,
sondern nur dieser eine Admin-Schalter.

**Fazit Frage 1:** Der Login selbst ist in allen drei Apps bereits
personen- und nicht chefin-gebunden. Das "nur mit meinem Login"-Erlebnis
kommt aus (a) fehlenden/nicht zurückgesetzten Mitarbeiter-Passwörtern und
(b) in der Checkliste zusätzlich aus der hart codierten `TEAM`/`CHEFIN_EMAIL`-Logik.

## 2. Wie wird das sauber auf den Team-Login umgestellt?

Kein Umbau, sondern vier konkrete, kleine Schritte:

1. **Für jede Mitarbeiterin/jeden Mitarbeiter** eine aktive Zeile in
   `teamapp_persons` sicherstellen (`rolle:'mitarbeiter'`, `aktiv:true`,
   korrekte E-Mail). Der Mechanismus dafür existiert bereits in
   `team.html` (Person anlegen → Einladungslink).
2. **Passwort-Reset abschließen** (offener Punkt aus `FORTSCHRITT.md`,
   Punkt 2): Für jede Person über `team.html` → Team-Tab → "Passwort
   setzen" (ruft die `team-admin`-Funktion auf) ein neues, echtes Passwort
   vergeben. Sobald das steht, funktionieren Team **und** Handbuch für
   diese Person automatisch — ohne jede Codeänderung, weil beide dieselbe
   Prüfung nutzen.
3. **Checkliste von der Parallelstruktur lösen:** `TEAM`-Array beim Start
   aus `teamapp_persons` ableiten statt hart zu codieren, und den
   `CHEFIN_EMAIL`-Vergleich durch denselben `rolle === 'inhaberin'`-Check
   ersetzen, den Team und Handbuch schon verwenden. Konkret (Ersatz für
   Zeile 464 und den Block ab Zeile 714):

   ```js
   // ersetzt: let TEAM = ['Mirjam','Alina','Mazen','Hassan','Ronya'];
   let TEAM = [];
   let _me = null; // eigene teamapp_persons-Zeile, wie in team.html

   async function ladeTeamUndRolle() {
     const { data: { session } } = await AUTH_CLIENT.auth.getSession();
     const email = session?.user?.email;
     const persons = await sbFetch(`teamapp_persons?aktiv=eq.true&select=name,email,rolle`);
     TEAM = persons.map(p => p.name);
     _me = persons.find(p => p.email?.toLowerCase() === email?.toLowerCase()) || null;
   }
   // in starteApp() vor dem ersten Rendern aufrufen: await ladeTeamUndRolle();

   // ersetzt: const CHEFIN_EMAIL = ...; und den eingeloggteEmail-Vergleich in toggleAdmin()
   function toggleAdmin() {
     const s = document.getElementById('admin-screen');
     if (s.classList.contains('open')) { s.classList.remove('open'); return; }
     if (_me?.rolle === 'inhaberin') { s.classList.add('open'); renderAdmin(); }
     else { showToast('❌ Nur die Inhaberin hat Zugriff auf diesen Bereich'); }
   }
   ```

   Damit gibt es nur noch **eine** Wahrheit darüber, wer im Team ist und
   wer Inhaberin ist: `teamapp_persons`. Das ist im `salon-checklist`-Repo
   umzusetzen, auf das ich aktuell nur Lesezugriff habe — sag Bescheid,
   wenn ich das direkt umsetzen und pushen soll.
4. **Serverseitig nachziehen** (siehe Punkt 4 unten) — sonst bleibt die
   Rollenprüfung aus Schritt 3 wieder nur Oberfläche.

## 3. Welche Rollenprüfung braucht jede der drei Apps?

| App | Mitarbeiter:in darf | nur Inhaberin darf |
|---|---|---|
| **Team** | Feed lesen, eigene Beiträge/Reaktionen, Team-Liste ansehen, eigenes Profil | Beiträge erstellen (FAB), Personen anlegen/deaktivieren/reaktivieren/löschen, Protokoll |
| **Handbuch** | alle 20 Handbuch-Kapitel lesen, freigegebene Wissensbank-Artikel lesen, eigene Vorschläge einreichen/lesen/löschen | Vorschläge freigeben/ablehnen (Review), fremde Artikel löschen, Artikel direkt (ohne Review) veröffentlichen |
| **Checkliste** | Tages-Checklisten aller Bereiche lesen/abhaken, Einkaufslisten lesen/bearbeiten — **gleichberechtigt für alle 5 Personen**, das ist hier gewollt | Monatszuweisung (wer ist wofür zuständig) ändern |

Team und Handbuch prüfen das bereits korrekt im Code
(`_me.rolle === 'inhaberin'`). Checkliste braucht die Umstellung aus
Punkt 2.3.

## 4. Wo müssen Inhaberinnen-Rechte, Schreibrechte oder sensible Daten noch serverseitig abgesichert werden?

Das ist der wichtigste Befund, und er betrifft **alle drei Apps
gemeinsam**, weil sie dieselbe Datenbank teilen: Die bisherigen
RLS-Policies (Migrationen vom 8.9.) unterscheiden nur zwischen
`authenticated` und `anon` — nicht zwischen Rollen. Die `rolle`-Prüfungen
im Code sind also aktuell **nur die Oberfläche**; genau die Lücke, die du
ausdrücklich ausschließen wolltest ("es reicht nicht, Buttons zu
verstecken").

Konkret, mit Belegen aus dem Code:

- **`teamapp_persons` (Team-Verwaltung):** Die Migration vom 8.9. hat nur
  eine `SELECT`-Policy für `authenticated` angelegt. Für `INSERT`/`UPDATE`/
  `DELETE` — genau die Aktionen, die `team.html` beim Anlegen/Deaktivieren/
  Löschen einer Person direkt per REST-Aufruf ausführt (nicht über die
  `team-admin`-Funktion, die nur das Login-Passwort betrifft) — ist der
  aktuelle Stand aus den Migrationsdateien nicht ersichtlich. Falls dort
  noch eine ältere, weite Policy aktiv ist (wahrscheinlich, sonst würde
  dein eigenes Personen-Anlegen auch nicht funktionieren), könnte
  **jede angemeldete Mitarbeiterin sich selbst per direktem REST-Aufruf
  `rolle:'inhaberin'` setzen** oder andere Personen löschen. Das ist der
  kritischste Punkt für "Wörni, System, sensible Übersichten bleiben nur
  für mich zugänglich" — die Rolle selbst ist aktuell möglicherweise nicht
  geschützt.
- **`wissensbank_artikel` (Handbuch-Vorschläge):** Diese Tabelle war in
  keiner der bisherigen Migrationen enthalten — ihr RLS-Zustand ist
  unbekannt. Der Client lädt zudem per `select=*` **immer alle Artikel**,
  auch fremde, noch nicht freigegebene Vorschläge, und filtert nur beim
  Anzeigen nach Status. D.h. selbst wenn RLS aktiv wäre, aber nicht
  rollen-/besitzbasiert: fremde unfertige Vorschläge sind für jede
  angemeldete Person in der Netzwerk-Antwort sichtbar. Ohne RLS-Fix könnte
  außerdem jede Person per direktem REST-Aufruf einen Artikel direkt mit
  `status:'freigegeben'` anlegen und damit die Freigabe durch dich
  umgehen.
- **`salon_monatszuweisung` (Checkliste-Admin):** Laut Migration vom 8.9.
  darf jede angemeldete Person `INSERT`/`UPDATE` — der `CHEFIN_EMAIL`-Schutz
  existiert nur im Frontend. Jede Mitarbeiterin könnte die
  Monatszuweisung per direktem REST-Aufruf ändern, ganz unabhängig vom
  geplanten Fix aus Punkt 2.3.
- **`salon_checks`, `einkauf_*`, `lager_bestellliste`, `ghd_*`:** bewusst
  **nicht** eingeschränkt — das sind die gemeinsam genutzten
  Arbeits-Tabellen der 6 Mitarbeiter-Apps, alle Mitarbeiter:innen sollen
  hier gleichberechtigt lesen/schreiben dürfen.
- **`teamAdminCall` / Edge Function `team-admin`:** Wird von `team.html`
  für Konto-Aktionen (Passwort setzen, Konto anlegen, sperren) aufgerufen.
  Laut `supabase/functions/README.md` liegt der Code dieser Funktion nicht
  in diesem Repo und war für die vorige Session nicht einsehbar — ob sie
  serverseitig wirklich prüft, dass nur die Inhaberin sie aufrufen darf,
  ist **nicht verifiziert**, nur laut Kommentar im aufrufenden Code
  behauptet. Das bitte mit jemandem mit Supabase-Dashboard-Zugriff
  (`supabase functions download team-admin`) gegenprüfen, bevor die App
  produktiv für alle Mitarbeiter:innen freigegeben wird — sonst hilft die
  beste RLS auf `teamapp_persons` nichts, wenn der Nebenweg über die
  Edge Function offensteht.

**Was ich dazu jetzt schon vorbereitet habe:** eine neue Migration
`supabase/migrations/20260912120000_rls_rollenbasiert_team_handbuch_checkliste.sql`
in diesem Repo. Sie legt eine serverseitige Rollen-Funktion
(`teamapp_ist_inhaberin()`, geprüft über die eigene Sitzungs-E-Mail, nicht
über einen vom Client mitgeschickten Wert) an und macht `teamapp_persons`,
`wissensbank_artikel` und `salon_monatszuweisung` für Schreibzugriffe
rollenabhängig statt nur login-abhängig. Wie in den vorherigen Migrationen
dieses Repos ist sie **nicht automatisch eingespielt** (kein Live-DB-Zugriff
in dieser Session) — ein Mensch mit Supabase-Zugriff muss sie prüfen und
ausführen, inklusive des Hinweises im Dateikopf, vorher nach alten,
gleichlautenden Policies mit anderem Namen zu suchen (RLS-Policies werden
mit ODER verknüpft — eine neue enge Policy schützt nichts, wenn daneben
eine alte weite Policy stehen bleibt).

## Was „leicht offen" für Mitarbeiter:innen konkret heißt

Damit daraus kein halber Komfort-Fix wird, hier die genaue Definition:

- **Genau ein Login-Bildschirm**, technisch einmal umgesetzt (Supabase
  Auth), der in Team, Handbuch und Checkliste gleich aussieht/funktioniert.
- Weil alle drei Apps unter derselben Herkunft
  `mirjamwalenta-a11y.github.io/...` laufen, teilt der Browser die
  angemeldete Sitzung automatisch zwischen ihnen (Supabase-JS speichert
  die Sitzung in `localStorage`, das ist pro Herkunft, nicht pro Ordner,
  gültig). Wer sich in Team einloggt und danach Handbuch öffnet, ist dort
  **automatisch schon angemeldet** — kein zweiter Login-Bildschirm, kein
  PIN, kein neues Passwort.
- Ein Klick auf eine erlaubte App öffnet sie direkt. Die Rollenprüfung
  läuft im Hintergrund als Datenbank-Abfrage (Millisekunden), nicht als
  weitere Eingabe für die Person.
- Die Sitzung bleibt über Tage/Wochen gültig (Standard-Verhalten von
  Supabase-JS: `persistSession` + `autoRefreshToken`). Ein neuer Login ist
  nur nach explizitem Abmelden, abgelaufenem Refresh-Token oder
  Passwort-Änderung nötig — nicht täglich, nicht pro App.
- Eine zusätzliche PIN-Abfrage ist ausschließlich für einzelne, wirklich
  heikle Einzelaktionen akzeptabel (z. B. eine Löschbestätigung) —
  **niemals** als Ersatz-Login pro App.
- **Nicht erfüllt** ist "leicht offen" durch: einen gemeinsamen Account für
  alle Mitarbeiter:innen, versteckte statt wirklich geschützte Buttons/URLs,
  eine zweite parallele Nutzerliste pro App (wie aktuell `TEAM` in der
  Checkliste), oder Berechtigungsprüfungen, die nur im Browser und nicht
  in der Datenbank stattfinden.

## Nächste Schritte (Vorschlag)

1. Migration in diesem Repo von jemandem mit Supabase-Zugriff prüfen und
   einspielen (inkl. Policy-Check laut Dateikopf).
2. Passwort-Reset für alle Mitarbeiter:innen abschließen (offener Punkt
   aus `FORTSCHRITT.md`).
3. `team-admin`-Funktion serverseitig verifizieren (siehe oben).
4. Checkliste von `TEAM`/`CHEFIN_EMAIL` auf `teamapp_persons`/`rolle`
   umstellen — ich kann das direkt im `salon-checklist`-Repo umsetzen und
   pushen, sobald du grünes Licht gibst (aktuell habe ich dort nur
   Lesezugriff).
