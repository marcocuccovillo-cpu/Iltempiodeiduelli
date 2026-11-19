-- =====================================================================
-- TEST DELLA MIGRAZIONE 052 (Torre: ritocchi e riconquista). SOLO su un database di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-torre-ritocchi-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
do $$
declare s jsonb; r jsonb; full_ jsonb; bal0 bigint; bal1 bigint; i integer;
begin
  -- R1: impostazioni
  assert public._setting('game_tower_difficulty') = 85 and public._setting('game_tower_xp_pct') = 75 and public._setting('game_tower_reclaim_pct') = 25, 'R1: impostazioni';
  full_ := public._game_tower_reward(20); r := public._game_tower_reclaim_reward(20);
  assert (r->>'bc')::numeric = round((full_->>'bc')::numeric * 0.25) and (r->>'xp')::numeric = round((full_->>'xp')::numeric * 0.25), 'R1: 25% del premio';
  assert r->'item' = 'null'::jsonb and (r->>'claimed')::boolean, 'R1: niente reliquia';
  insert into t_log (msg) values (format('OK R1 — difficoltà 85, XP 75%%, riconquista del piano 20: %s BC / %s XP (pieno %s / %s)', r->>'bc', r->>'xp', full_->>'bc', full_->>'xp'));

  -- R2: riconquista pagata due volte (chiavi diverse nel registro), senza reliquia; oltre il record premio pieno
  insert into auth.users (id, email, aud, role) values (pg_temp.uid('Bob'), 'bob@test.local', 'authenticated', 'authenticated');
  perform pg_temp.as_('Bob'); perform public.register_profile('Bob'); perform public.game_state();
  update public.game_heroes set level = 600, a_for = 800, a_des = 150, a_vig = 600, a_spi = 150, a_frt = 117, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
  update public.system_settings set value_int = 0 where key = 'game_tower_ally_pct';
  insert into public.game_tower (user_id, best_floor, record_floor, wins, reached_at) values (pg_temp.uid('Bob'), 9, 10, 10, now());
  s := public.game_tower_state();
  assert (s->'enemy'->'reward'->>'claimed')::boolean and (s->'enemy'->'reward'->>'bc')::int > 0, format('R2: carta del piano 10 (%s)', s->'enemy'->'reward');
  select balance into bal0 from public.wallets where user_id = pg_temp.uid('Bob');
  for i in 1..2 loop
    update public.game_tower set best_floor = 9 where user_id = pg_temp.uid('Bob');
    update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
    r := public.game_tower_climb();
    assert (r->>'won')::boolean and (r->>'reclaim')::boolean and (r->>'bc')::int = (public._game_tower_reclaim_reward(10)->>'bc')::int and r->'item' = 'null'::jsonb, format('R2: riconquista %s (%s)', i, r - 'log');
  end loop;
  select balance into bal1 from public.wallets where user_id = pg_temp.uid('Bob');
  assert bal1 - bal0 = 2 * (public._game_tower_reclaim_reward(10)->>'bc')::int, 'R2: pagata due volte';
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
  r := public.game_tower_climb();
  assert (r->>'won')::boolean and not (r->>'reclaim')::boolean and (r->>'bc')::int = (public._game_tower_reward(11)->>'bc')::int, 'R2: oltre il record premio pieno';
  -- con 0 la riconquista non paga
  update public.system_settings set value_int = 0 where key = 'game_tower_reclaim_pct';
  assert (public._game_tower_reclaim_reward(10)->>'bc')::int = 0 and (public._game_tower_reclaim_reward(10)->>'xp')::int = 0, 'R2: 0 = niente';
  insert into t_log (msg) values ('OK R2 — piano 10 riconquistato due volte con premio ridotto e senza reliquia; piano 11 premio pieno');
end $$;
select msg as risultato from t_log order by n;
rollback;
