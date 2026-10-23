-- ANNULLAMENTO DELLA MIGRAZIONE 025 (Duel Simulator): cancella SOLO le tabelle, le funzioni e le impostazioni del simulatore
-- (decks, lobby, partite e registri del simulatore vanno persi) e rimette admin_set_module() com'era prima (senza «duel»).
-- Non tocca Ladder, Black Market, wallet, registro contabile, taglie, eroi o notifiche.
begin;
drop function if exists public.sim_state(bigint, bigint), public.sim_deck_save(uuid, text, integer[], integer[], integer[], boolean), public.sim_deck_delete(uuid),
  public.sim_home(), public.sim_lobby_create(text), public.sim_lobby_join(bigint), public.sim_lobby_leave(bigint), public.sim_lobby_kick(bigint),
  public.sim_set_deck(bigint, uuid), public.sim_set_ready(bigint, boolean), public.sim_start(bigint), public.sim_choose_first(bigint, smallint),
  public.sim_concede(bigint), public.sim_confirm_end(bigint), public.sim_dismiss_end(bigint), public.sim_propose(bigint, text, text), public.sim_respond(bigint, boolean),
  public.sim_side(bigint, integer[], integer[], integer[]), public.sim_draw(bigint, integer),
  public.sim_move(bigint, integer, text, integer, text, boolean, boolean, integer, boolean), public.sim_set(bigint, integer, text, boolean),
  public.sim_counter(bigint, integer, integer), public.sim_token(bigint, text, integer, text), public.sim_reveal(bigint, integer, boolean),
  public.sim_shuffle(bigint), public.sim_search(bigint), public.sim_peek(bigint, integer), public.sim_reorder(bigint, integer[], boolean),
  public.sim_top(bigint, integer, text, boolean), public.sim_lp(bigint, smallint, integer, integer), public.sim_phase(bigint, text), public.sim_end_turn(bigint),
  public.sim_coin(bigint, integer), public.sim_dice(bigint, integer), public.sim_say(bigint, text),
  public._sim_user(), public._sim_bump(bigint), public._sim_vis(text, boolean, boolean, smallint, smallint, smallint), public._sim_pub(text, boolean, boolean),
  public._sim_log(bigint, smallint, text, jsonb), public._sim_deck_check(integer[], integer[], integer[]), public._sim_deck_playable(integer[], integer[], integer[]),
  public._sim_enter(bigint, text), public._sim_shuffle_deck(bigint, smallint), public._sim_check_end(bigint), public._sim_state(bigint, uuid),
  public._sim_abandon(bigint, text), public._sim_sweep(), public._sim_new_game(bigint), public._sim_finish_game(bigint, integer, text), public._sim_forfeit(bigint, smallint, text);
drop table if exists public.sim_log, public.sim_cards, public.sim_games, public.sim_players, public.sim_lobbies, public.sim_decks;
delete from public.system_settings where key in ('module_duel', 'sim_max_decks', 'sim_lobby_minutes', 'sim_idle_hours');

create or replace function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground','ladder','heroes') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui le migrazioni precedenti'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;
commit;
