-- ANNULLAMENTO DELLA MIGRAZIONE 024: toglie la funzione di ricarica dell'energia per l'amministratore. Non tocca energia, audit o altro.
begin;
drop function if exists public.game_admin_refill_energy();
commit;
