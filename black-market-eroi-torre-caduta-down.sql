-- Annulla la migrazione 050 (chi perde scende): rimette stato e salita della 049. Il piano attuale di ognuno torna al suo record.
begin;
update public.game_tower set best_floor = record_floor where record_floor > best_floor;
create or replace function public.game_tower_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  t public.game_tower%rowtype; ca jsonb; best integer; fl integer; en numeric; cost integer := greatest(1, public._setting('game_tower_energy')); hs public.game_heroes%rowtype;
  al jsonb; nb integer; prev jsonb := '[]'::jsonb; j integer; rank_ integer; lvl integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into hs from public.game_heroes where user_id = v;
  select * into t from public.game_tower where user_id = v;
  best := coalesce(t.best_floor, 0); fl := best + 1;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  al := public._game_tower_allies(v, best);
  ca := public._game_tower_party(ca, al);                    -- le stime tengono conto dei compagni di piano
  en := public._game_energy_of(v);
  for j in fl + 1..fl + 4 loop
    prev := prev || jsonb_build_array(public._game_tower_card(ca, j) - 'reward' - 'lore' - 'trait');
  end loop;
  nb := ((best / 10) + 1) * 10;
  select count(*) + 1 into rank_ from public.game_tower o join public.profiles p on p.id = o.user_id
   where not p.suspended and (o.best_floor > best or (o.best_floor = best and o.reached_at < t.reached_at)) and o.best_floor > 0 and best > 0;
  return jsonb_build_object(
    'best_floor', best, 'next_floor', fl, 'wins', coalesce(t.wins, 0), 'losses', coalesce(t.losses, 0), 'rank', case when best > 0 then rank_ else null end,
    'stats_set', hs.stats_set, 'cost', cost, 'energy', round(en, 2), 'energy_max', public._game_energy_max(),
    'enemy', public._game_tower_card(ca, fl), 'boss_floor', nb, 'boss_in', nb - best,
    'boss', case when nb = fl then null else public._game_tower_card(ca, nb) - 'lore' - 'trait' end,
    'upcoming', prev,
    'allies', coalesce((select jsonb_agg(x - 's_for' - 'max_hp') from jsonb_array_elements(al) x), '[]'::jsonb), 'ally_pct', greatest(0, coalesce(public._setting('game_tower_ally_pct'), 0)),
    'climbers', coalesce((select jsonb_agg(jsonb_build_object('user_id', q.user_id, 'nickname', q.nickname, 'level', q.level, 'best_floor', q.best_floor) order by q.best_floor desc, q.reached_at asc)
                       from (select o.user_id, p.nickname, h.level, o.best_floor, o.reached_at
                               from public.game_tower o join public.profiles p on p.id = o.user_id join public.game_heroes h on h.user_id = o.user_id
                              where o.best_floor > 0 and not p.suspended order by (o.user_id = v) desc, (o.best_floor = best) desc, o.best_floor desc, o.reached_at asc limit 60) q), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('floor', x.floor, 'won', x.won, 'rounds', x.rounds, 'at', x.created_at) order by x.created_at desc)
                          from (select * from public.game_tower_fights where user_id = v order by created_at desc limit 8) x), '[]'::jsonb),
    'top', coalesce((select jsonb_agg(jsonb_build_object('rank', q.rk, 'user_id', q.user_id, 'nickname', q.nickname, 'avatar', q.avatar, 'level', q.level, 'best_floor', q.best_floor, 'reached_at', q.reached_at) order by q.rk, q.nickname)
                       from (select o.user_id, p.nickname, p.avatar, h.level, o.best_floor, o.reached_at,
                                    rank() over (order by o.best_floor desc, o.reached_at asc) rk
                               from public.game_tower o join public.profiles p on p.id = o.user_id join public.game_heroes h on h.user_id = o.user_id
                              where o.best_floor > 0 and not p.suspended) q where q.rk <= 15), '[]'::jsonb),
    'hall', coalesce((select jsonb_agg(jsonb_build_object('floor', x.floor, 'nickname', x.nickname, 'avatar', x.avatar, 'boss', x.bname, 'at', x.created_at) order by x.created_at desc)
                        from (select f.floor, p.nickname, p.avatar, f.created_at, public._game_tower_enemy(f.floor)->>'name' as bname
                                from public.game_tower_firsts f join public.profiles p on p.id = f.user_id order by f.created_at desc limit 8) x), '[]'::jsonb));
end $$;

create or replace function public.game_tower_climb() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  hs public.game_heroes%rowtype; t public.game_tower%rowtype; ca jsonb; en jsonb; sim jsonb; fl integer; v_en numeric; cost integer := greatest(1, public._setting('game_tower_energy'));
  won boolean; rw jsonb := jsonb_build_object('xp', 0, 'levels', 0, 'energy_full', false); price jsonb; v_bc bigint := 0; v_xp bigint := 0; v_id uuid := gen_random_uuid(); item jsonb := null;
  v_first boolean := false; v_new public.game_tower%rowtype; v_item text; v_lvl integer; r numeric; al jsonb;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into hs from public.game_heroes where user_id = v for update;                 -- un tentativo alla volta per eroe
  if not hs.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  insert into public.game_tower (user_id) values (v) on conflict (user_id) do nothing;
  select * into t from public.game_tower where user_id = v for update;
  fl := t.best_floor + 1;
  v_en := public._game_energy_of(v);
  if v_en < cost then raise exception 'Energia insufficiente: per salire ne servono % (ora %)', cost, floor(v_en); end if;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  al := public._game_tower_allies(v, t.best_floor);          -- chi è fermo sul tuo stesso piano combatte con te
  ca := public._game_tower_party(ca, al);
  ca := public._game_tower_wound(ca, fl);                   -- il Miasma della Torre riduce le cure dell'eroe (e della squadra)
  en := public._game_tower_enemy(fl);
  r := public._game_tower_ratio(ca, en);
  sim := public._game_sim(ca, en);
  won := sim->>'winner' = 'a';
  if won then
    price := public._game_tower_reward(fl);
    v_bc := (price->>'bc')::bigint;
    if v_bc > 0 then
      perform public._ledger_move(v, v_bc::integer, 'game_dungeon_reward', 'game_tower', v_id, 'gametower:' || v::text || ':' || fl::text, 'La guerra degli Eroi: Torre Infinita, piano ' || fl);
    end if;
    rw := public._game_add_xp(v, (price->>'xp')::bigint);
    v_xp := (rw->>'xp')::bigint;
    if price->'item' is not null and price->'item' <> 'null'::jsonb then
      v_item := price->'item'->>'id';
      insert into public.game_inventory (user_id, item_id, source) values (v, v_item, 'tower') on conflict do nothing;
      item := price->'item';
    end if;
    if fl % 10 = 0 then
      insert into public.game_tower_firsts (floor, user_id) values (fl, v) on conflict (floor) do nothing;
      v_first := exists (select 1 from public.game_tower_firsts where floor = fl and user_id = v);
    end if;
    update public.game_tower set best_floor = fl, wins = wins + 1, reached_at = clock_timestamp(), updated_at = clock_timestamp() where user_id = v;
  else
    update public.game_tower set losses = losses + 1, updated_at = clock_timestamp() where user_id = v;
  end if;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1,
         energy = case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max() else greatest(0, v_en - cost) end, energy_at = now() where user_id = v;
  insert into public.game_tower_fights (id, user_id, floor, won, rounds, hero_hp, enemy_hp) values (v_id, v, fl, won, (sim->>'rounds')::integer, (sim->>'hp_a')::bigint, (sim->>'hp_b')::bigint);
  select level into v_lvl from public.game_heroes where user_id = v;
  select * into v_new from public.game_tower where user_id = v;
  return jsonb_build_object('won', won, 'floor', fl, 'enemy', en - 's_for' - 's_des' - 's_vig' - 's_spi' - 's_frt' || jsonb_build_object('ratio', round(r, 3), 'chance', public._game_tower_chance(r)),
    'rounds', sim->'rounds', 'log', sim->'log', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b',
    'bc', v_bc, 'xp', v_xp, 'levels', coalesce((rw->>'levels')::integer, 0), 'level', v_lvl, 'energy_full', coalesce((rw->>'energy_full')::boolean, false), 'energy_cost', cost,
    'item', item, 'first_global', v_first, 'allies', coalesce((select jsonb_agg(x - 's_for' - 'max_hp') from jsonb_array_elements(al) x), '[]'::jsonb), 'best_floor', v_new.best_floor, 'next_floor', v_new.best_floor + 1);
end $$;

alter table public.game_tower drop column if exists record_floor;
delete from public.system_settings where key = 'game_tower_fall_floors';
revoke all on function public.game_tower_state(), public.game_tower_climb() from public, anon;
grant execute on function public.game_tower_state(), public.game_tower_climb() to authenticated;
commit;
