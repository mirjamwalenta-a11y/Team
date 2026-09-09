// Telegram-Kanal für Wörni, Phase 1: vier feste Befehle.
//
// WICHTIG ZUR ARCHITEKTUR: Das Betriebssystem bleibt die Wahrheit, Telegram ist
// nur ein Zugangskanal. Diese Function baut KEINE eigene Logik/Datenhaltung —
// sie erkennt nur einen von vier festen Triggern und ruft dafür ausschließlich
// bestehende, bereits produktive Endpunkte/Tabellen auf:
//   - "Tageslage"      → bestehender Endpunkt `tageslage` (unverändert, wie bisher)
//   - "Aufgabe: ..."    → INSERT in die bestehende Tabelle `ghd_aufgaben`
//   - "Notiz: ..."      → INSERT in die bestehende Tabelle `woerni_aufgaben`
//   - "Besprechung: ..." → Rohtext über die bestehende `rapid-function`
//                          (zweck: "besprechung") strukturieren lassen,
//                          Ergebnis als neue Zeile in `woerni_aufgaben` speichern
// Alle vier Befehle LEGEN NUR NEU AN (POST) — keiner ändert oder überschreibt
// eine bestehende Zeile. Damit ist "nichts Bestehendes eigenmächtig verändern"
// durch die Konstruktion selbst erfüllt, ohne zusätzliche Sonderlogik.
// Alles andere als diese vier Trigger: kurze Befehlsübersicht, kein freier Chat.
//
// AUTH: Telegram sendet keinen Supabase-User-Token mit. Diese Function meldet
// sich deshalb selbst mit einem eigenen, fest eingerichteten Service-Account
// bei Supabase an (siehe Anleitung) und bekommt dadurch denselben Typ Token,
// den auch der Browser der Chefin bekommt — sie ruft `tageslage`/`ghd_aufgaben`/
// `woerni_aufgaben`/`rapid-function` also als legitimer, RLS-geprüfter Aufrufer
// auf, nicht über einen Sonderweg.
//
// JWT-Verifikation für DIESE Function bewusst AUS (anders als bei `tageslage`
// selbst): Der Aufrufer ist hier der externe Telegram-Dienst, nicht ein
// eingeloggter Supabase-Client — es gibt keinen Supabase-User-Token, den
// Telegram mitschicken könnte. Die eigentliche Zugriffskontrolle liegt bei
// den aufgerufenen Endpunkten (RLS + JWT dort), nicht hier. Diese Function
// selbst prüft stattdessen Telegrams eigenes Webhook-Secret (siehe
// TELEGRAM_WEBHOOK_SECRET unten), damit nicht irgendwer diese URL beliebig
// aufrufen kann.

const SB_URL = "https://wrxlaltgtgkdomklgrlj.supabase.co";
const SB_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndyeGxhbHRndGdrZG9ta2xncmxqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyNDYwMzYsImV4cCI6MjA5OTgyMjAzNn0.Bw8ch-EJb_cLYTwxHdpjUJWgoCjje3Jc32pB0yiBS8g";

// Secrets — werden in Supabase unter Edge Functions → telegram-tageslage → Secrets gesetzt,
// stehen NICHT im Code:
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const TELEGRAM_WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET")!;
const SERVICE_EMAIL = Deno.env.get("WOERNI_SERVICE_EMAIL")!;
const SERVICE_PASSWORD = Deno.env.get("WOERNI_SERVICE_PASSWORD")!;

// Die vier festen Phase-1-Trigger. Bewusst NUR diese — kein Freitext-Fallback,
// keine natürlichsprachlichen Synonyme mehr (das bisherige "was ist heute
// wichtig"/"was ist kritisch" für Tageslage entfällt damit; siehe Absprache).
const AUFGABE_MUSTER = /^aufgabe:\s*(.+)$/is;
const NOTIZ_MUSTER = /^notiz:\s*(.+)$/is;
const BESPRECHUNG_MUSTER = /^besprechung:\s*(.+)$/is;

async function holeServiceToken(): Promise<string> {
  // Meldet den technischen Wörni-Telegram-Nutzer bei Supabase Auth an — genau
  // derselbe Mechanismus wie SZ_AUTH.auth.signInWithPassword() im Web-Frontend,
  // nur mit einem eigenen Account statt der Chefin-Session.
  const res = await fetch(`${SB_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: SB_ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: SERVICE_EMAIL, password: SERVICE_PASSWORD }),
  });
  if (!res.ok) throw new Error("Service-Login fehlgeschlagen: " + (await res.text()));
  const data = await res.json();
  return data.access_token as string;
}

async function holeTageslage(): Promise<any> {
  const token = await holeServiceToken();
  const res = await fetch(`${SB_URL}/functions/v1/tageslage`, {
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error("tageslage-Aufruf fehlgeschlagen: " + (await res.text()));
  return res.json();
}

function formatiereAntwort({ engpass, fokusAufgabe, fokusGrund, handlungsempfehlung }: any): string {
  const zeilen: string[] = [];
  if (engpass?.label) zeilen.push(`Engpass: ${engpass.label}`);
  if (fokusAufgabe?.titel) zeilen.push(`Fokus heute: ${fokusAufgabe.titel}`);
  if (fokusGrund?.text) zeilen.push(`Warum: ${fokusGrund.text}`);
  if (handlungsempfehlung) zeilen.push(`Nächster Zug: ${handlungsempfehlung}`);
  return zeilen.length > 0 ? zeilen.join("\n") : "Aktuell keine offenen Aufgaben.";
}

// ── Aufgabe: … → bestehende Tabelle ghd_aufgaben (dieselbe, die tageslage liest) ──
async function legeAufgabeAn(titel: string): Promise<void> {
  const token = await holeServiceToken();
  const res = await fetch(`${SB_URL}/rest/v1/ghd_aufgaben`, {
    method: "POST",
    headers: {
      apikey: SB_ANON_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({
      titel,
      typ: "betrieb",
      prioritaet: "diese-woche",
      status: "offen",
      app_kontext: "telegram",
      erstellt_von: "woerni-telegram",
    }),
  });
  if (!res.ok) throw new Error("Aufgabe anlegen fehlgeschlagen: " + (await res.text()));
}

// ── Notiz: … / Besprechung: … → bestehende Tabelle woerni_aufgaben (schon heute
// für freie Notizen in apps.html im Einsatz, dort auch angezeigt) ──
async function legeNotizAn(typ: string, notizText: string): Promise<void> {
  const token = await holeServiceToken();
  const res = await fetch(`${SB_URL}/rest/v1/woerni_aufgaben`, {
    method: "POST",
    headers: {
      apikey: SB_ANON_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({
      app: "allgemein",
      typ,
      anlass: `telegram_${typ}`,
      notiz: notizText,
      status: "offen",
    }),
  });
  if (!res.ok) throw new Error("Notiz speichern fehlgeschlagen: " + (await res.text()));
}

// "Titel | Inhalt" unterstützen, sonst automatisch einen kurzen Titel ableiten —
// reine Textverarbeitung, kein KI-Aufruf nötig.
function parseNotizEingabe(rohtext: string): { titel: string; inhalt: string } {
  if (rohtext.includes("|")) {
    const [erster, ...rest] = rohtext.split("|");
    const titel = erster.trim();
    const inhalt = rest.join("|").trim() || titel;
    return { titel, inhalt };
  }
  const inhalt = rohtext.trim();
  const titel = inhalt.length > 40 ? inhalt.slice(0, 40).trim() + "…" : inhalt;
  return { titel, inhalt };
}

// ── Besprechung: … → Rohtext über die bestehende, abgesicherte rapid-function
// strukturieren lassen (zweck "besprechung"), Ergebnis als Notiz speichern ──
async function struktueriereBesprechung(rohtext: string): Promise<string> {
  const token = await holeServiceToken();
  const res = await fetch(`${SB_URL}/functions/v1/rapid-function`, {
    method: "POST",
    headers: {
      apikey: SB_ANON_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ zweck: "besprechung", text: rohtext }),
  });
  if (!res.ok) throw new Error("Strukturierung fehlgeschlagen: " + (await res.text()));
  const data = await res.json();
  const text = data?.content?.[0]?.text;
  if (!text) throw new Error("Keine Antwort von rapid-function erhalten.");
  return text.trim();
}

async function sendeTelegramNachricht(chatId: number, text: string) {
  await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text }),
  });
}

const BEFEHLSUEBERSICHT =
  "Verfügbare Befehle:\n" +
  "Tageslage — aktuelle Lage abrufen\n" +
  "Aufgabe: <Text> — neue Aufgabe anlegen\n" +
  "Notiz: <Titel> | <Text> — neue Notiz anlegen\n" +
  "Besprechung: <Rohtext> — Besprechungsvorbereitung erstellen";

Deno.serve(async (req: Request) => {
  // Telegrams eigenes Webhook-Secret prüfen — verhindert, dass fremde Aufrufer
  // diese URL direkt ansprechen (Ersatz für die hier fehlende JWT-Prüfung).
  const secretHeader = req.headers.get("x-telegram-bot-api-secret-token");
  if (secretHeader !== TELEGRAM_WEBHOOK_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  try {
    const update = await req.json();
    const message = update?.message;
    const text: string | undefined = message?.text;
    const chatId: number | undefined = message?.chat?.id;

    if (!text || !chatId) {
      // Kein verwertbarer Text (z. B. Foto, Sticker, Systemmeldung) — ignorieren.
      return new Response("ok");
    }

    const eingabe = text.trim();

    try {
      if (/^tageslage\b/i.test(eingabe)) {
        const daten = await holeTageslage();
        await sendeTelegramNachricht(chatId, formatiereAntwort(daten));
      } else if (AUFGABE_MUSTER.test(eingabe)) {
        const inhalt = eingabe.match(AUFGABE_MUSTER)![1].trim();
        if (inhalt.length < 3) {
          await sendeTelegramNachricht(chatId, "Was genau soll die Aufgabe sein? Bitte kurz präzisieren, z. B. \"Aufgabe: Farbe bei Lieferant X nachbestellen\".");
        } else {
          await legeAufgabeAn(inhalt);
          await sendeTelegramNachricht(chatId, `✅ Aufgabe angelegt: ${inhalt}`);
        }
      } else if (NOTIZ_MUSTER.test(eingabe)) {
        const roh = eingabe.match(NOTIZ_MUSTER)![1];
        const { titel, inhalt } = parseNotizEingabe(roh);
        await legeNotizAn("notiz", `${titel}\n\n${inhalt}`);
        await sendeTelegramNachricht(chatId, `✅ Notiz gespeichert: ${titel}`);
      } else if (BESPRECHUNG_MUSTER.test(eingabe)) {
        const roh = eingabe.match(BESPRECHUNG_MUSTER)![1].trim();
        if (roh.length < 3) {
          await sendeTelegramNachricht(chatId, "Bitte den Besprechungsinhalt mitschicken, z. B. \"Besprechung: Team X hat Y vorgeschlagen, offen ist Z\".");
        } else {
          const strukturiert = await struktueriereBesprechung(roh);
          await legeNotizAn("besprechung", strukturiert);
          await sendeTelegramNachricht(chatId, `✅ Besprechungsvorbereitung gespeichert:\n\n${strukturiert}`);
        }
      } else {
        // Kein bekannter Befehl — kurze Übersicht statt freiem Chat.
        await sendeTelegramNachricht(chatId, BEFEHLSUEBERSICHT);
      }
    } catch (err) {
      // Kein lokaler Ersatz, keine Notlösung — nur ehrlich melden.
      console.error("telegram-tageslage Befehlsfehler:", err);
      await sendeTelegramNachricht(chatId, "Gerade nicht möglich, bitte später erneut versuchen.");
    }

    return new Response("ok");
  } catch (err) {
    return new Response("ok"); // Telegram erwartet immer 200, sonst wiederholt es die Zustellung
  }
});
