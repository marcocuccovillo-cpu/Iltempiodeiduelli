-- ANNULLAMENTO DELLA MIGRAZIONE 015 (La guerra degli Eroi, versione 2).
-- Toglie le funzioni nuove (lobby, acquisto skill, energia) e la versione 2 delle funzioni del gioco; poi, SUBITO DOPO, vanno rieseguiti
-- black-market-eroi.sql (013) e black-market-eroi-avatar.sql (014), che rimettono le funzioni della versione 1 (duelli al giorno, boss senza lobby).
-- Non cancella nulla di ciò che è stato guadagnato o speso: BC, registro, eroi, livelli e oggetti restano come sono.
--   · le skill acquistate restano salvate nelle loro tabelle ma smettono di avere effetto (la versione 1 non le conosce) e i BC spesi non tornano indietro;
--   · i punti già assegnati restano; con la versione 1 si possono avere al massimo 20 punti totali, quindi chi li ha superati va oltre il massimo
--     finché non li ridistribuisce (la versione 1 non li ricontrolla se non si modificano);
--   · un boss rimasto «in lobby» oggi viene segnato come «scappato»: domani la versione 1 ne prepara uno nuovo;
--   · energia, colonne e tabelle nuove restano (non danno fastidio).
begin;

update public.game_days set status = 'escaped' where status = 'lobby';

drop function if exists public.game_boss_join();
drop function if exists public.game_boss_leave();
drop function if exists public.game_boss_start();
drop function if exists public.game_buy_skill(text);
drop function if exists public._game_energy_of(uuid);
drop function if exists public._game_energy_rate(uuid);
drop function if exists public._game_energy_max();
drop function if exists public._game_points(integer);
-- la versione 2 restituisce più colonne: va tolta prima che la 013 la ricrei
drop function if exists public._game_calc(uuid);

delete from public.system_settings where key in ('game_points_per_level','game_boss_min_players','game_energy_max','game_energy_regen_hours','game_energy_win','game_energy_loss','game_temp_hours');
update public.system_settings set description = 'Eroi: duelli al giorno in Arena' where key = 'game_daily_fights' and description like 'Eroi: (non più usato%';

commit;
-- ORA riesegui, in ordine: black-market-eroi.sql (013) e black-market-eroi-avatar.sql (014).
