-- ANNULLAMENTO DELLA MIGRAZIONE 023: salire di livello non ricarica più l'energia. Non tocca energia, livelli o XP già assegnati.
begin;

create or replace function public._game_add_xp(p_user uuid, p_xp bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; pct integer; add_ bigint; gained integer := 0;
begin
  select * into h from public.game_heroes where user_id = p_user for update;
  if not found then raise exception 'Eroe inesistente'; end if;
  select xp_pct into pct from public._game_calc(p_user);
  add_ := greatest(0, p_xp) * (100 + coalesce(pct, 0)) / 100;
  if h.level < 9999 then
    h.xp := h.xp + add_;
    while h.level < 9999 and h.xp >= public._game_xp_need(h.level) loop
      h.xp := h.xp - public._game_xp_need(h.level); h.level := h.level + 1; gained := gained + 1;
    end loop;
    if h.level >= 9999 then h.xp := 0; end if;
  end if;
  update public.game_heroes set level = h.level, xp = h.xp, total_xp = total_xp + add_ where user_id = p_user;
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level);
end $$;

create or replace function public.game_duel(p_target uuid) returns jsonb language plpgsql security definer set search_path = public as $$
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
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1, energy = greatest(0, v_en - v_cost), energy_at = now() where user_id = v;
  insert into public.game_duels (id, day, attacker_id, defender_id, winner_id, atk_level, def_level, xp_awarded, rounds, log)
    values (v_id, d, v, p_target, v_win, a.level, b.level, v_xp, (sim->>'rounds')::integer, sim->'log');
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('id', v_id, 'won', v_win = v, 'xp', v_xp, 'levels', (rw->>'levels')::integer, 'level', (rw->>'level')::integer, 'opponent', pn,
           'opponent_level', b.level, 'rounds', sim->'rounds', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'energy', round(greatest(0, v_en - v_cost), 2), 'energy_cost', v_cost);
end $$;

revoke all on function public._game_add_xp(uuid, bigint) from public, anon, authenticated;
revoke all on function public.game_duel(uuid) from public, anon;
grant execute on function public.game_duel(uuid) to authenticated;
commit;
