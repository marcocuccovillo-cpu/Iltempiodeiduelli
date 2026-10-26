-- =====================================================================
-- LA GUERRA DEGLI EROI — LA RICARICA DELL'ENERGIA AL LIVELLO VALE SOLO SOTTO IL LIVELLO 100
--   Prima (migrazione 023) ogni salita di livello riportava l'energia al 100% a qualsiasi livello.
--   Ora la ricarica scatta solo se l'eroe, prima di salire, era SOTTO il livello 100. Si spegne da sola:
--   chi parte dal livello 100 in su sale di livello senza ricarica (l'energia resta com'era, dopo il costo del duello).
--   * Dal 99 al 100 la ricarica c'è ancora (si partiva sotto il 100): è l'ultima. Un salto di più livelli che parte sotto il 100
--     (es. dal 98 al 103) ricarica una sola volta. Dal 100 in poi mai più.
--   * Vale per Arena, boss e dungeon (usano tutti la stessa funzione dell'XP). Il costo del duello e la ricarica con il tempo non cambiano.
--   * Il livello soglia sta in una sola funzione, _game_refill_below_level() (oggi 100): per far smettere la ricarica già al 99 basta mettere 99.
-- Da eseguire in Supabase (SQL Editor) DOPO black-market-eroi-limite-livello.sql (e dopo le altre migrazioni della guerra degli Eroi). Si può rieseguire.
-- Non tocca BC, registro, livelli, XP o energia già assegnati. Annullamento: black-market-eroi-ricarica-livello-100-down.sql
-- =====================================================================
begin;

create or replace function public._game_refill_below_level() returns integer language sql immutable security definer set search_path = public as $$ select 100 $$;

-- XP: come prima (limite di livello impostabile) ma la ricarica dell'energia vale solo se il livello di partenza è sotto la soglia
create or replace function public._game_add_xp(p_user uuid, p_xp bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; pct integer; add_ bigint; gained integer := 0; cap integer := public._game_level_cap(); lvl0 integer; refill boolean := false;
begin
  select * into h from public.game_heroes where user_id = p_user for update;
  if not found then raise exception 'Eroe inesistente'; end if;
  lvl0 := h.level;          -- livello di partenza: è questo che decide se la ricarica è ancora attiva
  select xp_pct into pct from public._game_calc(p_user);
  add_ := greatest(0, p_xp) * (100 + coalesce(pct, 0)) / 100;
  if h.level < cap then
    h.xp := h.xp + add_;
    while h.level < cap and h.xp >= public._game_xp_need(h.level) loop
      h.xp := h.xp - public._game_xp_need(h.level); h.level := h.level + 1; gained := gained + 1;
    end loop;
    if h.level >= cap then h.xp := 0; end if;
  else
    h.xp := 0;      -- già al limite (o oltre, se il limite è stato abbassato): il livello non cambia, l'XP in eccesso non si accumula
  end if;
  update public.game_heroes set level = h.level, xp = h.xp, total_xp = total_xp + add_ where user_id = p_user;
  if gained > 0 and lvl0 < public._game_refill_below_level() then      -- salire di livello ricarica la batteria al 100%, ma solo se si partiva sotto il livello 100
    update public.game_heroes set energy = public._game_energy_max(), energy_at = now() where user_id = p_user;
    refill := true;
  end if;
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level, 'energy_full', refill, 'cap', cap);
end $$;

-- Duello in Arena: come nella 023, ma "energia piena" segue la ricarica effettiva e non più la sola salita di livello
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
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1, energy = case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max() else greatest(0, v_en - v_cost) end, energy_at = now() where user_id = v;      -- se la ricarica scatta (sale di livello sotto il livello 100), l'energia torna al 100% (anche dopo il costo del duello)
  insert into public.game_duels (id, day, attacker_id, defender_id, winner_id, atk_level, def_level, xp_awarded, rounds, log)
    values (v_id, d, v, p_target, v_win, a.level, b.level, v_xp, (sim->>'rounds')::integer, sim->'log');
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('id', v_id, 'won', v_win = v, 'xp', v_xp, 'levels', (rw->>'levels')::integer, 'level', (rw->>'level')::integer, 'opponent', pn,
           'opponent_level', b.level, 'rounds', sim->'rounds', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'energy', case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max()::numeric else round(greatest(0, v_en - v_cost), 2) end, 'energy_cost', v_cost, 'energy_full', coalesce((rw->>'energy_full')::boolean, false));
end $$;

revoke all on function public._game_refill_below_level() from public, anon, authenticated;
revoke all on function public._game_add_xp(uuid, bigint) from public, anon, authenticated;
revoke all on function public.game_duel(uuid) from public, anon;
grant execute on function public.game_duel(uuid) to authenticated;
commit;
