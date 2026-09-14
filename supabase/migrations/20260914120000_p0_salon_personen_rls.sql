-- ════════════════════════════════════════════════════════════
--  P0 — salon_personen (Supabase-Projekt wrxlaltgtgkdomklgrlj) hatte
--  keinerlei RLS und war damit für jeden mit dem öffentlichen anon-Key
--  vollständig lesbar: Name, Kennung, PIN-Hash (MD5) und Rolle aller
--  Mitarbeiterinnen und der Chefin. Live bestätigt am 2026-09-14 per
--  Direktabfrage über den anon-Key, der offen in apps.html
--  (Repo index.greathairday, öffentlich auf GitHub) liegt.
--
--  Einziger Nutzer der Tabelle ist der PIN-Login in apps.html, der
--  bisher direkt per REST mit dem anon-Key filtert:
--    .../salon_personen?kennung=eq.X&pin_hash=eq.<md5(pin)>&aktiv=eq.true
--  Das setzt voraus, dass die Tabelle für anon lesbar ist — genau das
--  ist die Lücke: jede Zeile (inkl. aller PIN-Hashes) ist damit ohne
--  gültigen PIN abrufbar, MD5 macht kurze PINs zusätzlich in Sekunden
--  brute-forcebar.
--
--  Fix: RLS an, kein direkter anon/authenticated-Zugriff mehr auf die
--  Tabelle (RLS ohne Policy verweigert per Default). Stattdessen eine
--  SECURITY DEFINER-Funktion, die Kennung+PIN serverseitig prüft und
--  nur id/name/rolle zurückgibt — nie pin_hash.
--
--  Notwendiger Folge-Schritt (separates Repo, hier kein Schreibzugriff):
--  apps.html muss von der direkten REST-Abfrage auf
--    supabase.rpc('login_mit_pin', { p_kennung: kennung, p_pin: pin })
--  umgestellt werden. Bis dahin ist der Team-Login in apps.html
--  absichtlich funktionsunfähig — sicher ausgesperrt ist besser als
--  weiterhin offen lesbar.
--
--  WICHTIG, unabhängig von dieser Migration: alle PINs in
--  salon_personen zurücksetzen. Die aktuellen Werte gelten als
--  kompromittiert, weil sie nachweislich öffentlich lesbar waren.
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.salon_personen ENABLE ROW LEVEL SECURITY;

-- Bewusst KEINE Policy für anon/authenticated auf der Tabelle selbst.
-- Zugriff läuft ab jetzt ausschließlich über die Funktion unten
-- (SECURITY DEFINER umgeht RLS kontrolliert, nur für diese eine Prüfung).

DROP FUNCTION IF EXISTS public.login_mit_pin(text, text);
CREATE FUNCTION public.login_mit_pin(p_kennung text, p_pin text)
RETURNS TABLE(id text, name text, rolle text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT sp.id::text, sp.name, sp.rolle
    FROM public.salon_personen sp
    WHERE lower(sp.kennung) = lower(p_kennung)
      AND sp.pin_hash = md5(p_pin)
      AND sp.aktiv = true;
END;
$$;

REVOKE ALL ON FUNCTION public.login_mit_pin(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.login_mit_pin(text, text) TO anon, authenticated;
