# RLS-Sicherheitscheck — automatisch & manuell

Hintergrund: Am 2026-09-14 war die Tabelle `salon_personen` (Supabase-Projekt
`wrxlaltgtgkdomklgrlj`, genutzt von `apps.html`/`schaltzentrale.html` im Repo
`index.greathairday`) ohne Row Level Security (RLS) und dadurch über den
öffentlichen anon-Key komplett lesbar — inklusive aller PIN-Hashes. Fix siehe
`supabase/migrations/20260914120000_p0_salon_personen_rls.sql`.

Damit sowas nicht wieder unbemerkt bleibt, gibt es jetzt zwei Absicherungen:

## 1. Automatisch (empfohlen, einmaliges Setup)

`.github/workflows/rls-audit.yml` prüft jeden Montag automatisch alle
Tabellen im `public`-Schema und legt ein GitHub-Issue an, falls eine Tabelle
ohne RLS gefunden wird.

**Einmaliges Setup (nur du, nicht Claude):**
1. Supabase-Dashboard → Project Settings → Database → Connection string → URI
2. GitHub → dieses Repo → Settings → Secrets and variables → Actions →
   „New repository secret"
3. Name: `SUPABASE_DB_URL`, Wert: die kopierte Connection-String
4. Fertig — ab jetzt läuft der Check automatisch, jede Woche, ohne dass du
   dich darum kümmern musst. Bei einem Fund bekommst du ein GitHub-Issue.

Der Connection-String enthält dein DB-Passwort — er bleibt ausschließlich in
den GitHub-Secrets, niemand (auch keine Claude-Session) kann ihn danach im
Klartext auslesen.

## 2. Manuell (jederzeit möglich, z. B. wenn eine neue App dazukommt)

Im Supabase SQL-Editor ausführen:

```sql
select relname as tabelle, relrowsecurity as rls_aktiv
from pg_class
join pg_namespace n on n.oid = pg_class.relnamespace
where n.nspname = 'public' and relkind = 'r'
order by relrowsecurity, relname;
```

Jede Zeile mit `rls_aktiv = false` ist eine Tabelle ohne Schutz — genau das,
was `salon_personen` war. Das Ergebnis kannst du auch einfach in eine
Claude-Code-Session einfügen, wie bisher.

## Faustregel für neue Apps/Tabellen

Jede neue Tabelle bekommt RLS **bevor** sie mit einer Live-App verbunden
wird — nicht danach. Das gehört zum "neue Tabelle anlegen"-Schritt dazu,
nicht zu einem späteren Security-Review.
