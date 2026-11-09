-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 042 (Villaggi)
-- Spegne i Villaggi togliendo le funzioni. Gli eserciti in marcia restano fermi dove sono.
-- Le tabelle (villaggi, edifici, soldati, rapporti) NON vengono cancellate: riapplicando la 042 tutto torna com'era.
-- Per cancellare anche i dati, dopo questo file: drop table public.game_village_marches, public.game_villages;
-- =====================================================================
begin;
drop function if exists public.game_village_state(integer);
drop function if exists public.game_village_found(integer, text);
drop function if exists public.game_village_rename(integer, text);
drop function if exists public.game_village_build(integer, text);
drop function if exists public.game_village_train(integer, integer, integer, integer);
drop function if exists public.game_village_defense(integer, integer, integer, integer);
drop function if exists public.game_village_attack(integer, integer, integer, integer, integer);
drop function if exists public.game_village_collect(integer);
drop function if exists public._vil_found_cost(uuid);
drop function if exists public._vil_mine(uuid, integer);
drop function if exists public._vil_tick();
drop function if exists public._vil_power(integer[], integer[], boolean);
drop function if exists public._vil_check(uuid);
drop function if exists public._vil_sync(integer);
drop function if exists public._vil_upkeep(integer);
drop function if exists public._vil_away(integer);
drop function if exists public._vil_minutes(integer, integer, boolean);
drop function if exists public._vil_pos(integer);
drop function if exists public._vil_unit(text);
drop function if exists public._vil_cost(text, integer);
drop function if exists public._vil_army_cap(integer);
drop function if exists public._vil_bc_day(integer);
drop function if exists public._vil_cap(integer);
drop function if exists public._vil_prod(integer);
drop function if exists public._vil_max_level();
-- funzioni della prima versione (un villaggio a testa), se c'erano ancora
drop function if exists public.game_village_state();
drop function if exists public.game_village_rename(text);
drop function if exists public.game_village_build(text);
drop function if exists public.game_village_train(integer, integer, integer);
drop function if exists public.game_village_defense(integer, integer, integer);
drop function if exists public.game_village_attack(uuid, integer, integer, integer);
drop function if exists public.game_village_collect();
drop function if exists public._vil_sync(uuid);
drop function if exists public._vil_upkeep(uuid);
drop function if exists public._vil_away(uuid);
delete from public.system_settings where key = 'game_village_enabled';
commit;
