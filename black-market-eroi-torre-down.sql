-- =====================================================================
-- ANNULLA la migrazione 029 (la Torre Infinita): toglie le funzioni, le tabelle, le reliquie (anche da zaini ed equipaggiamento) e le impostazioni.
-- I BC già incassati restano (le righe del registro «game_dungeon_reward» con riferimento «game_tower» non si toccano). Livelli e XP non cambiano.
-- Si ferma solo se qualcosa dopo la 029 usa ancora l'origine «tower» (non succede con i file di questo pacchetto).
-- =====================================================================
begin;
drop function if exists public.game_tower_climb();
drop function if exists public.game_tower_state();
drop function if exists public._game_tower_card(jsonb, integer);
drop function if exists public._game_tower_reward(integer);
drop function if exists public._game_tower_chance(numeric);
drop function if exists public._game_tower_ratio(jsonb, jsonb);
drop function if exists public._game_tower_enemy(integer);
drop function if exists public._game_tower_affix(integer);

delete from public.game_equipped where item_id in (select id from public.game_items where source = 'tower');
delete from public.game_inventory where source = 'tower' or item_id in (select id from public.game_items where source = 'tower');
drop table if exists public.game_tower_items;
delete from public.game_items where source = 'tower';
drop table if exists public.game_tower_firsts;
drop table if exists public.game_tower_fights;
drop table if exists public.game_tower;
drop table if exists public.game_tower_bosses;

delete from public.system_settings where key in ('game_tower_energy', 'game_tower_bc_pct', 'game_tower_xp_pct', 'game_tower_difficulty');
alter table public.game_items drop constraint if exists game_items_source_chk;
alter table public.game_items add constraint game_items_source_chk check (source in ('start','shop','boss','dungeon'));
alter table public.game_inventory drop constraint if exists game_inventory_source_chk;
alter table public.game_inventory add constraint game_inventory_source_chk check (source in ('start','shop','boss','dungeon'));
commit;
