-- =====================================================================
-- TEST DELLA MIGRAZIONE 050 (Torre: chi perde scende). SOLO su un database di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-torre-caduta-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
do $$
declare s jsonb; r jsonb; n text; bal0 bigint; bal1 bigint; xp0 bigint; i integer;
begin
  foreach n in array array['Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state();
  end loop;
  -- Ann: eroe debolissimo al piano 1050 (perde sempre). Bob: eroe fortissimo al piano 5 con record 8 (vince sempre)
  update public.game_heroes set level = 10, a_for = 20, a_des = 5, a_vig = 15, a_spi = 4, a_frt = 3, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
  update public.game_heroes set level = 600, a_for = 800, a_des = 150, a_vig = 600, a_spi = 150, a_frt = 117, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
  update public.system_settings set value_int = 0 where key = 'game_tower_ally_pct';
  insert into public.game_tower (user_id, best_floor, record_floor, wins, reached_at) values (pg_temp.uid('Ann'), 1050, 1050, 1050, now() - interval '1 day'),
    (pg_temp.uid('Bob'), 5, 8, 8, now());

  -- C1: chi perde scende di un piano, il record resta
  perform pg_temp.as_('Ann');
  s := public.game_tower_state();
  assert (s->>'fall_floors')::int = 1 and (s->>'record_floor')::int = 1050, format('C1: stato (%s / %s)', s->>'fall_floors', s->>'record_floor');
  r := public.game_tower_climb();
  assert not (r->>'won')::boolean and (r->>'fell')::int = 1 and (r->>'best_floor')::int = 1049 and (r->>'record_floor')::int = 1050, format('C1: caduta (%s)', r - 'log');
  assert (select best_floor from public.game_tower where user_id = pg_temp.uid('Ann')) = 1049, 'C1: piano 1049 salvato';
  insert into t_log (msg) values ('OK C1 — sconfitta al 1051: si scende al 1049, il record resta 1050');

  -- C2: mai sotto l'ingresso; con 0 la caduta è spenta
  update public.game_tower set best_floor = 0 where user_id = pg_temp.uid('Ann');
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
  update public.game_heroes set a_for = 0, a_des = 0, a_vig = 0, a_spi = 0, a_frt = 0 where user_id = pg_temp.uid('Ann');
  r := public.game_tower_climb();
  if not (r->>'won')::boolean then
    assert (r->>'fell')::int = 0 and (r->>'best_floor')::int = 0, 'C2: all''ingresso non si scende';
  end if;
  update public.game_tower set best_floor = 900 where user_id = pg_temp.uid('Ann');
  update public.system_settings set value_int = 0 where key = 'game_tower_fall_floors';
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
  r := public.game_tower_climb();
  assert not (r->>'won')::boolean and (r->>'fell')::int = 0 and (r->>'best_floor')::int = 900, 'C2: con 0 si resta dove si è';
  update public.system_settings set value_int = 1 where key = 'game_tower_fall_floors';
  insert into t_log (msg) values ('OK C2 — mai sotto l''ingresso; game_tower_fall_floors = 0 spegne la caduta');

  -- C3: risalire sotto il record non paga; oltre il record sì
  perform pg_temp.as_('Bob');
  s := public.game_tower_state();
  assert (s->'enemy'->'reward'->>'claimed')::boolean and (s->'enemy'->'reward'->>'bc')::int = 0, format('C3: piano 6 senza premi (%s)', s->'enemy'->'reward');
  select balance into bal0 from public.wallets where user_id = pg_temp.uid('Bob');
  select total_xp into xp0 from public.game_heroes where user_id = pg_temp.uid('Bob');
  for i in 6..8 loop
    update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
    r := public.game_tower_climb();
    assert (r->>'won')::boolean and (r->>'reclaim')::boolean and (r->>'bc')::int = 0 and (r->>'xp')::int = 0, format('C3: piano %s senza premi (%s)', i, r - 'log');
  end loop;
  select balance into bal1 from public.wallets where user_id = pg_temp.uid('Bob');
  assert bal1 = bal0 and (select total_xp from public.game_heroes where user_id = pg_temp.uid('Bob')) = xp0, 'C3: BC e XP invariati sotto il record';
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
  r := public.game_tower_climb();
  assert (r->>'won')::boolean and not (r->>'reclaim')::boolean and (r->>'bc')::int > 0 and (r->>'record_floor')::int = 9, format('C3: piano 9 pagato (%s)', r - 'log');
  insert into t_log (msg) values (format('OK C3 — piani 6–8 riconquistati senza premi, piano 9 (nuovo record) paga %s BC', r->>'bc'));
end $$;
select msg as risultato from t_log order by n;
rollback;
