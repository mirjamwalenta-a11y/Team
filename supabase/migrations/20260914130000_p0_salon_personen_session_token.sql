-- ════════════════════════════════════════════════════════════
--  P0 (Fortsetzung) — apps.html vertraute beim Wiederherstellen einer
--  gespeicherten Sitzung ausschließlich der in localStorage gespeicherten
--  `id`, ganz ohne erneute PIN-/Passwort-Prüfung. Die Chefin-Zeile in
--  salon_personen hat als id den erratbaren Klartext-Wert "salon-chef"
--  (statt einer zufälligen UUID wie bei den Mitarbeiterinnen-Zeilen).
--
--  Dadurch genügte vor dem RLS-Fix vom 2026-09-14 folgendes in der
--  Browser-Konsole, um vollen Chefin-Zugriff zu bekommen, ganz ohne PIN:
--    localStorage.setItem('ghd_session', JSON.stringify({id:'salon-chef'}))
--  Aktuell ist das nur zufällig blockiert, weil salon_personen seit der
--  vorigen Migration nicht mehr direkt lesbar ist — kein bewusster Fix.
--
--  Fix: zufälliges, nicht erratbares Sitzungs-Token statt der Personen-id.
--  login_mit_pin gibt jetzt zusätzlich ein Token zurück und legt es in
--  salon_sessions ab; session_by_token prüft das Token statt der id;
--  logout_session löscht es beim Abmelden serverseitig. apps.html muss
--  in einem Folge-Commit auf dieses Token umgestellt werden (localStorage
--  speichert ab dann `ghd_session_token` statt der nackten Personen-id).
--
--  Sicher mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.salon_sessions (
  token       text primary key default encode(gen_random_bytes(32), 'hex'),
  person_id   text not null,
  erstellt_am timestamptz not null default now(),
  laeuft_ab   timestamptz not null default (now() + interval '30 days')
);

ALTER TABLE public.salon_sessions ENABLE ROW LEVEL SECURITY;
-- Bewusst KEINE Policy für anon/authenticated — Zugriff nur über die
-- SECURITY DEFINER-Funktionen unten, nie direkt auf die Tabelle.

DROP FUNCTION IF EXISTS public.login_mit_pin(text, text);
CREATE FUNCTION public.login_mit_pin(p_kennung text, p_pin text)
RETURNS TABLE(token text, id text, name text, rolle text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_person record;
  v_token  text;
BEGIN
  SELECT sp.id, sp.name, sp.rolle INTO v_person
  FROM public.salon_personen sp
  WHERE lower(sp.kennung) = lower(p_kennung)
    AND sp.pin_hash = md5(p_pin)
    AND sp.aktiv = true;

  IF v_person.id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.salon_sessions(person_id)
  VALUES (v_person.id)
  RETURNING salon_sessions.token INTO v_token;

  RETURN QUERY SELECT v_token, v_person.id, v_person.name, v_person.rolle;
END;
$$;

REVOKE ALL ON FUNCTION public.login_mit_pin(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.login_mit_pin(text, text) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.session_by_token(text);
CREATE FUNCTION public.session_by_token(p_token text)
RETURNS TABLE(id text, name text, rolle text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT sp.id, sp.name, sp.rolle
    FROM public.salon_sessions ss
    JOIN public.salon_personen sp ON sp.id = ss.person_id
    WHERE ss.token = p_token
      AND ss.laeuft_ab > now()
      AND sp.aktiv = true;
END;
$$;

REVOKE ALL ON FUNCTION public.session_by_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.session_by_token(text) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.logout_session(text);
CREATE FUNCTION public.logout_session(p_token text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.salon_sessions WHERE token = p_token;
$$;

REVOKE ALL ON FUNCTION public.logout_session(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.logout_session(text) TO anon, authenticated;
