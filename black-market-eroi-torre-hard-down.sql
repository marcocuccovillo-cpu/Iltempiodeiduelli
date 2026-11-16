-- Annulla la migrazione 049 (Torre difficile): rimette nemici, stime e salita com'erano dopo la 046. Non tocca nessun dato.
begin;
create or replace function public._game_tower_enemy(p_floor integer) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n integer := greatest(1, p_floor); is_boss boolean := n % 10 = 0; k integer := n / 10; fam integer; tier integer := least(3, (n - 1) / 100); cyc integer;
  bs public.game_tower_bosses%rowtype; af jsonb; m numeric; pts numeric := 20 + 3 * (n - 1); w numeric[]; s numeric[]; j integer; lab text;
  dif numeric := greatest(1, public._setting('game_tower_difficulty')) / 100.0; nm text; emo text; spr text; lore text; trait text;
  fams text[] := array['melma','pipistrello','scheletro','goblin','lupo','spettro','ragno','elementale'];
  emos text[] := array['🟢','🦇','💀','👺','🐺','👻','🕷️','🪨'];
  ws numeric[] := array[.20,.05,.45,.15,.15,  .25,.35,.10,.10,.20,  .35,.15,.25,0,.25,  .30,.30,.20,.05,.15,  .35,.30,.20,0,.15,  .20,.25,.15,.25,.15,  .30,.30,.15,.10,.15,  .30,.05,.35,.10,.20];
  nms text[] := array['Melma Verde','Melma Acida','Melma Abissale','Melma Primordiale',
                      'Pipistrello Cieco','Pipistrello d’Ombra','Pipistrello Sanguigno','Pipistrello Spettrale',
                      'Scheletro Errante','Scheletro Guerriero','Scheletro Cavaliere','Scheletro Maledetto',
                      'Goblin Ladro','Goblin Predone','Goblin Sciamano','Goblin Condottiero',
                      'Lupo Grigio','Lupo Nero','Lupo Spettrale','Lupo Ancestrale',
                      'Spettro Pallido','Spettro Lamentoso','Spettro Gelido','Spettro Antico',
                      'Ragno Tessitore','Ragno Velenoso','Ragno Gigante','Ragno dell’Abisso',
                      'Elementale di Pietra','Elementale di Brace','Elementale di Gelo','Elementale di Tempesta'];
  cm text[] := array['', 'Risvegliato', 'Ancestrale', 'Eterno', 'Primordiale', 'Supremo']; cf text[] := array['', 'Risvegliata', 'Ancestrale', 'Eterna', 'Primordiale', 'Suprema'];
begin
  if is_boss then
    select * into bs from public.game_tower_bosses where no = ((k - 1) % 12) + 1;
    cyc := (k - 1) / 12;
    lab := case when cyc < 6 then (case when bs.fem then cf[cyc + 1] else cm[cyc + 1] end) else (case when bs.fem then cf[6] else cm[6] end) || ' ' || (cyc - 6 + 2) end;
    nm := bs.name || case when lab = '' then '' else ' ' || lab end; emo := bs.emoji; spr := bs.sprite; lore := bs.lore; trait := bs.trait;
    w := array[bs.w_for, bs.w_des, bs.w_vig, bs.w_spi, bs.w_frt]; m := 1.15; tier := least(3, cyc);
  else
    fam := ((n * 5 + n / 7) % 8);
    nm := nms[fam * 4 + tier + 1]; emo := emos[fam + 1]; spr := fams[fam + 1]; lore := null; trait := null;
    w := array[ws[fam * 5 + 1], ws[fam * 5 + 2], ws[fam * 5 + 3], ws[fam * 5 + 4], ws[fam * 5 + 5]];
    m := least(1, 0.6 + 0.04 * n); af := public._game_tower_affix(n);
  end if;
  s := array[0, 0, 0, 0, 0];
  for j in 1..5 loop
    s[j] := greatest(1, round((5 + pts * w[j] * n) * m * dif * coalesce((af->>(array['for','des','vig','spi','frt'])[j])::numeric, 1)));
  end loop;
  return jsonb_build_object('floor', n, 'boss', is_boss, 'name', nm, 'emoji', emo, 'sprite', spr, 'tier', tier, 'cycle', case when is_boss then cyc else null end, 'lore', lore, 'trait', trait,
    'affix', case when af is null then null else jsonb_build_object('key', af->>'key', 'name', af->>'name', 'descr', af->>'descr') end,
    'level', n, 's_for', s[1], 's_des', s[2], 's_vig', s[3], 's_spi', s[4], 's_frt', s[5], 'max_hp', 50 + 12 * s[3]);
end $$;


create or replace function public._game_tower_card(p_hero jsonb, p_floor integer) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e jsonb := public._game_tower_enemy(p_floor); r numeric := public._game_tower_ratio(p_hero, e);
begin
  return e || jsonb_build_object('ratio', round(r, 3), 'chance', public._game_tower_chance(r), 'reward', public._game_tower_reward(p_floor));
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


drop function if exists public._game_tower_wound(jsonb, integer);
drop function if exists public._game_tower_miasma(integer);
drop function if exists public._game_tower_pressure(integer);
delete from public.system_settings where key in ('game_tower_ramp_floors','game_tower_growth_bp','game_tower_growth_from','game_tower_boss_pct','game_tower_miasma_max');

revoke all on function public._game_tower_enemy(integer), public._game_tower_card(jsonb, integer) from public, anon, authenticated;
revoke all on function public.game_tower_climb() from public, anon;
grant execute on function public.game_tower_climb() to authenticated;
commit;
