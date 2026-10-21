-- ANNULLA LA MIGRAZIONE 012: toglie solo la funzione admin_user_overview(). Non tocca nessun dato.
-- Senza di essa il pannello amministratore funziona lo stesso, ma non mostra le email.
begin;
drop function if exists public.admin_user_overview();
commit;
