-- =====================================================================
-- TEST DELLA MIGRAZIONE 049 (Torre difficile). SOLO su un database di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-torre-hard-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
do $$
declare s jsonb; r jsonb; e0 jsonb; e1 jsonb; h jsonb; c0 integer; c1 integer; i integer; wins integer := 0; bal0 bigint; bal1 bigint;
begin
  -- H1: la pressione parte da 1 e cresce con il piano
  assert public._game_tower_pressure(1) = 1 and public._game_tower_pressure(10) = 1, 'H1: pressione 1 ai primi piani';
  assert public._game_tower_pressure(100) between 1.55 and 1.65, format('H1: piano 100 (%s)', public._game_tower_pressure(100));
  assert public._game_tower_pressure(1050) between 19 and 22, format('H1: piano 1050 (%s)', public._game_tower_pressure(1050));
  assert public._game_tower_pressure(1500) > public._game_tower_pressure(1050) * 2, 'H1: oltre il 1000 cresce più che in linea retta';
  e1 := public._game_tower_enemy(1051);
  update public.system_settings set value_int = 0 where key in ('game_tower_ramp_floors', 'game_tower_growth_bp');
  assert public._game_tower_pressure(1050) = 1, 'H1: con le impostazioni a 0 la pressione è spenta';
  e0 := public._game_tower_enemy(1051);
  assert (e1->>'s_for')::numeric > (e0->>'s_for')::numeric * 15 and (e1->>'max_hp')::numeric > (e0->>'max_hp')::numeric * 15, 'H1: il nemico del 1051 è molto più forte';
  update public.system_settings set value_int = 150 where key = 'game_tower_ramp_floors';
  update public.system_settings set value_int = 10 where key = 'game_tower_growth_bp';
  assert (public._game_tower_enemy(40000)->>'max_hp')::numeric < 9e18, 'H1: nessun traboccamento ai piani altissimi';
  insert into t_log (msg) values (format('OK H1 — pressione ×%s al 100, ×%s al 1050; nemico del 1051: FOR %s (prima %s)',
    round(public._game_tower_pressure(100), 2), round(public._game_tower_pressure(1050), 1), e1->>'s_for', e0->>'s_for'));

  -- H2: i boss sono più forti
  update public.system_settings set value_int = 115 where key = 'game_tower_boss_pct'; e0 := public._game_tower_enemy(200);
  update public.system_settings set value_int = 140 where key = 'game_tower_boss_pct'; e1 := public._game_tower_enemy(200);
  assert (e1->>'s_for')::numeric > (e0->>'s_for')::numeric * 1.2, 'H2: boss ×1,40';
  insert into t_log (msg) values (format('OK H2 — boss del piano 200: FOR %s (con ×1,15 sarebbe %s)', e1->>'s_for', e0->>'s_for'));

  -- H3: il Miasma riduce le cure, e le stime ne tengono conto
  assert public._game_tower_miasma(5) = 0 and public._game_tower_miasma(300) = 30 and public._game_tower_miasma(1050) = 75, 'H3: miasma 0 / 30 / 75';
  h := jsonb_build_object('level', 100, 's_for', 5000, 's_des', 1000, 's_vig', 3000, 's_spi', 4000, 's_frt', 1000, 'max_hp', 36050);
  assert (public._game_tower_wound(h, 1050)->>'s_spi')::int = 1000 and (public._game_tower_wound(h, 5)->>'s_spi')::int = 4000, 'H3: cure ridotte del 75%';
  assert (public._game_tower_enemy(1050)->>'miasma')::int = 75, 'H3: il nemico mostra il miasma';
  c1 := (public._game_tower_card(h, 300)->>'chance')::int;
  update public.system_settings set value_int = 0 where key = 'game_tower_miasma_max';
  c0 := (public._game_tower_card(h, 300)->>'chance')::int;
  assert c1 <= c0, format('H3: con il miasma la stima non sale (%s → %s)', c0, c1);
  update public.system_settings set value_int = 75 where key = 'game_tower_miasma_max';
  insert into t_log (msg) values (format('OK H3 — miasma −75%% al piano 1050; stima al piano 300: %s%% senza, %s%% con il miasma', c0, c1));

  -- H4: un eroe di livello 600 fermo al piano 1050 non passa più; i dati già scritti restano
  insert into auth.users (id, email, aud, role) values (pg_temp.uid('Ann'), 'ann@test.local', 'authenticated', 'authenticated');
  perform pg_temp.as_('Ann'); perform public.register_profile('Ann'); perform public.game_state();
  update public.game_heroes set level = 600, a_for = 800, a_des = 150, a_vig = 600, a_spi = 150, a_frt = 117, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
  insert into public.game_tower (user_id, best_floor, wins, reached_at) values (pg_temp.uid('Ann'), 1050, 1050, now());
  s := public.game_tower_state();
  assert (s->>'best_floor')::int = 1050 and (s->'enemy'->>'chance')::int <= 5, format('H4: stima al 1051 (%s%%)', s->'enemy'->>'chance');
  select balance into bal0 from public.wallets where user_id = pg_temp.uid('Ann');
  for i in 1..5 loop
    update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
    r := public.game_tower_climb();
    if (r->>'won')::boolean then wins := wins + 1; end if;
  end loop;
  select balance into bal1 from public.wallets where user_id = pg_temp.uid('Ann');
  assert wins = 0, format('H4: %s vittorie su 5', wins);
  assert bal1 = bal0 and (select best_floor from public.game_tower where user_id = pg_temp.uid('Ann')) = 1050, 'H4: piano e BC invariati';
  assert (r->'enemy'->>'miasma')::int = 75, 'H4: il risultato mostra il miasma';
  insert into t_log (msg) values (format('OK H4 — livello 600 al piano 1050: stima %s%%, 0 vittorie su 5, piano raggiunto intatto', s->'enemy'->>'chance'));
end $$;
select msg as risultato from t_log order by n;
rollback;
