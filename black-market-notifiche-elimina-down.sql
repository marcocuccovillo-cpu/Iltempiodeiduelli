-- =====================================================================
-- ANNULLAMENTO della migrazione 010 (black-market-notifiche-elimina.sql).
-- Toglie solo la funzione notif_delete: nessuna notifica viene toccata e quelle già cancellate non tornano.
-- L'app, senza la funzione, mostra le notifiche senza il pulsante «Elimina».
-- =====================================================================
begin;
drop function if exists public.notif_delete(uuid);
commit;
