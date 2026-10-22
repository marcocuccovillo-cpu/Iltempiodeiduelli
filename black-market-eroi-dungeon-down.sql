-- ANNULLAMENTO DELLA MIGRAZIONE 017 (La guerra degli Eroi: mini dungeon).
-- Toglie le funzioni dei dungeon e le impostazioni game_dng_*; le lobby ancora aperte vengono annullate.
-- Non cancella nulla di ciò che è stato guadagnato o speso:
--   · BC e registro restano come sono (le righe «game_dungeon_reward» restano, perciò il tipo di movimento resta ammesso);
--   · tabelle dei dungeon, partite concluse, progressi e resoconti restano nel database come storico (nessuno li legge più);
--   · gli oggetti esclusivi dei dungeon già vinti restano negli zaini dei giocatori e continuano a funzionare;
--   · l'energia già spesa non torna indietro.
-- Il resto del gioco (Eroe, Boss, Arena, Mercante) non cambia: nessuna funzione precedente è stata modificata dalla 017.
-- Per rimettere i dungeon basta rieseguire black-market-eroi-dungeon.sql (i progressi e gli oggetti si ritrovano).
begin;

update public.game_runs set status = 'cancelled', finished_at = now() where status = 'lobby';

drop function if exists public.game_dungeon_state();
drop function if exists public.game_dungeon_create(integer, text);
drop function if exists public.game_dungeon_join(uuid, text);
drop function if exists public.game_dungeon_role(uuid, text);
drop function if exists public.game_dungeon_leave(uuid);
drop function if exists public.game_dungeon_start(uuid);
drop function if exists public._game_dng_sim(jsonb, integer);
drop function if exists public._game_dng_check(uuid, integer, text);
drop function if exists public._game_dng_pool_item(uuid, integer);
drop function if exists public._game_dng_run_json(uuid);
drop function if exists public._game_dng_expire();
drop function if exists public._game_dng_open(uuid, integer);
drop function if exists public._game_dng_cost();

delete from public.system_settings where key like 'game\_dng\_%';

commit;
