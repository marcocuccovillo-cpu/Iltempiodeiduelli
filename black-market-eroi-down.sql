-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 013 (La guerra degli Eroi)
-- NON distruttivo: spegne il gioco e toglie dal database tutte le funzioni e la classifica, ma LASCIA le tabelle game_* con i loro dati
-- (eroi, inventari, giornate dei boss, ricompense). Così si può rieseguire black-market-eroi.sql in qualunque momento e ritrovare tutto.
-- Nessun saldo né movimento del registro viene toccato: i BC già pagati dai boss o spesi dal mercante restano com'erano, e il vincolo
-- sui tipi di movimento resta quello ampliato (altrimenti i movimenti game_* già scritti non sarebbero più validi).
-- Il browser non vede più nulla: le pagine del gioco mostreranno «modulo non attivo» / un errore finché non si rimette la 013.
-- Per cancellare DAVVERO anche i dati del gioco non c'è uno script: sarebbe irreversibile (le tabelle delle ricompense e del registro
-- sono protette dalla cancellazione apposta). Se serve, va fatto a mano e solo dopo aver esportato i dati.
-- =====================================================================
begin;

-- spegne il gioco (se la riga c'è) e toglie l'interruttore dalla funzione amministrativa
update public.system_settings set value_int = 0, updated_at = now() where key = 'module_heroes';

create or replace function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground','ladder') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui le migrazioni precedenti'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;
revoke all on function public.admin_set_module(text, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_set_module(text, boolean, text) to authenticated;

-- via classifica e funzioni (le tabelle restano)
drop view if exists public.game_leaderboard_v;
drop function if exists public.game_state();
drop function if exists public.game_set_stats(integer, integer, integer, integer, integer);
drop function if exists public.game_set_arena_open(boolean);
drop function if exists public.game_equip(text);
drop function if exists public.game_buy(text);
drop function if exists public.game_boss_act(text, uuid);
drop function if exists public.game_duel(uuid);
drop function if exists public.game_arena_list();
drop function if exists public.game_hero(uuid);
drop function if exists public._game_hero_json(uuid);
drop function if exists public._game_sim(jsonb, jsonb);
drop function if exists public._game_finish_boss(date);
drop function if exists public._game_draw_item(uuid, integer);
drop function if exists public._game_cands(uuid, integer);
drop function if exists public._game_ensure_day();
drop function if exists public._game_ensure_merchant(date);
drop function if exists public._game_ensure_hero(uuid);
drop function if exists public._game_add_xp(uuid, bigint);
drop function if exists public._game_calc(uuid);
drop function if exists public._game_xp_need(integer);
drop function if exists public._game_next_reset();
drop function if exists public._game_today();

commit;
