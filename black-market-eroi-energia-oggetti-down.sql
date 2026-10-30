-- ANNULLAMENTO della migrazione 035 (black-market-eroi-energia-oggetti.sql): toglie i due controlli e la funzione.
-- Riporta il comportamento di prima (con il bug: cambiando oggetto la velocità nuova vale anche per il passato). Non tocca l'energia dei giocatori.
begin;
drop trigger if exists game_equipped_energy on public.game_equipped;
drop trigger if exists game_items_energy on public.game_items;
drop function if exists public._trg_equipped_energy();
drop function if exists public._trg_items_energy();
drop function if exists public._game_energy_checkpoint(uuid);
commit;
