-- =====================================================================
-- ANNULLA la migrazione 036 (Arena a classifica): rimette game_duel e game_arena_list com'erano e toglie tabelle, funzioni e impostazioni.
-- I PUNTI ARENA, le leghe e le stagioni spariscono. I duelli già fatti (XP, vittorie, sconfitte) restano. Si può rieseguire senza danni.
-- =====================================================================
begin;

CREATE OR REPLACE FUNCTION public.game_duel(p_target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date := public._game_today(); a public.game_heroes%rowtype; b public.game_heroes%rowtype; ca jsonb; cb jsonb; sim jsonb; v_en numeric; v_need integer; v_cost integer;
  v_win uuid; v_xp bigint := 0; v_id uuid := gen_random_uuid(); rw jsonb; v_first uuid; v_second uuid; pn text;
begin
  perform public._require_module('heroes');
  if p_target is null or p_target = v then raise exception 'Scegli un altro eroe da sfidare'; end if;
  perform public._game_ensure_hero(v);
  if not exists (select 1 from public.profiles where id = p_target and not suspended) then raise exception 'Eroe non disponibile'; end if;
  if not exists (select 1 from public.game_heroes where user_id = p_target) then raise exception 'Questo duellante non è ancora un eroe'; end if;
  v_first := least(v, p_target); v_second := greatest(v, p_target);                  -- blocco in ordine fisso
  perform 1 from public.game_heroes where user_id = v_first for update;
  perform 1 from public.game_heroes where user_id = v_second for update;
  select * into a from public.game_heroes where user_id = v;
  select * into b from public.game_heroes where user_id = p_target;
  if not a.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  if not b.stats_set then raise exception 'Questo eroe non ha ancora assegnato i suoi punti abilità'; end if;
  if not b.arena_open then raise exception 'Questo eroe non accetta sfide in Arena'; end if;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  select to_jsonb(x) into cb from public._game_calc(p_target) x;
  v_need := greatest(public._setting('game_energy_win'), public._setting('game_energy_loss'));
  v_en := public._game_energy_of(v);
  if v_en < v_need then raise exception 'Energia insufficiente: per sfidare ne servono almeno % (ora %)', v_need, floor(v_en); end if;
  sim := public._game_sim(ca, cb);
  v_win := case when sim->>'winner' = 'a' then v else p_target end;
  if v_win = v then
    v_xp := greatest(1, round((40 + 2 * b.level) * least(2::numeric, greatest(0.25, b.level::numeric / a.level)))::bigint);
    rw := public._game_add_xp(v, v_xp);
    v_xp := (rw->>'xp')::bigint;
    update public.game_heroes set duels_won = duels_won + 1 where user_id = v;
  else
    rw := jsonb_build_object('xp', 0, 'levels', 0, 'level', a.level);
    update public.game_heroes set duels_lost = duels_lost + 1 where user_id = v;
  end if;
  v_cost := case when v_win = v then public._setting('game_energy_win') else public._setting('game_energy_loss') end;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1, energy = case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max() else greatest(0, v_en - v_cost) end, energy_at = now() where user_id = v;      -- se la ricarica scatta (sale di livello sotto il livello 100), l'energia torna al 100% (anche dopo il costo del duello)
  insert into public.game_duels (id, day, attacker_id, defender_id, winner_id, atk_level, def_level, xp_awarded, rounds, log)
    values (v_id, d, v, p_target, v_win, a.level, b.level, v_xp, (sim->>'rounds')::integer, sim->'log');
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('id', v_id, 'won', v_win = v, 'xp', v_xp, 'levels', (rw->>'levels')::integer, 'level', (rw->>'level')::integer, 'opponent', pn,
           'opponent_level', b.level, 'rounds', sim->'rounds', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'energy', case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max()::numeric else round(greatest(0, v_en - v_cost), 2) end, 'energy_cost', v_cost, 'energy_full', coalesce((rw->>'energy_full')::boolean, false));
end $function$;

CREATE OR REPLACE FUNCTION public.game_arena_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := public._game_today(); v_lvl integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select level into v_lvl from public.game_heroes where user_id = v;
  return coalesce((select jsonb_agg(x order by (x->>'gap')::integer, (x->>'level')::integer desc, x->>'nickname') from (
    select jsonb_build_object('user_id', h.user_id, 'nickname', p.nickname, 'avatar', p.avatar, 'level', h.level, 'bosses_beaten', h.bosses_beaten, 'duels_won', h.duels_won,
             'power', c.s_for + c.s_des + c.s_vig + c.s_spi + c.s_frt, 'gap', abs(h.level - v_lvl),
             'fought_today', exists (select 1 from public.game_duels q where q.day = d and q.attacker_id = v and q.defender_id = h.user_id),
             'fights_today', (select count(*) from public.game_duels q where q.day = d and q.attacker_id = v and q.defender_id = h.user_id)) as x
    from public.game_heroes h join public.profiles p on p.id = h.user_id cross join lateral public._game_calc(h.user_id) c
    where h.user_id <> v and h.stats_set and h.arena_open and not p.suspended order by abs(h.level - v_lvl), h.level desc limit 60) t), '[]'::jsonb);
end $function$;

revoke all on function public.game_duel(uuid), public.game_arena_list() from public, anon;
grant execute on function public.game_duel(uuid), public.game_arena_list() to authenticated;

drop function if exists public.game_arena_state();
drop function if exists public._game_arena_record(uuid, uuid, uuid, boolean, date);
drop function if exists public._game_arena_delta(integer, integer, boolean);
drop function if exists public._game_arena_touch(uuid, text);
drop function if exists public._game_arena_points(uuid, text);
drop function if exists public._game_arena_league(integer);
drop function if exists public._game_arena_season(date);
drop table if exists public.game_arena_log;
drop table if exists public.game_arena_rating;
drop table if exists public.game_arena_leagues;
delete from public.system_settings where key in ('game_arena_start', 'game_arena_k', 'game_arena_pair_day', 'game_arena_soft_pct');
commit;
