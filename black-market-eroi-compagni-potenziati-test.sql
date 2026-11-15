-- =====================================================================
-- TEST DELLA MIGRAZIONE 047 (compagni potenziati). SOLO su un database di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-potenziati-' || n)::uuid $$;
do $$
declare s jsonb; p jsonb; v100 integer; v200 integer; old100 integer; b record; mx integer;
begin
  -- P1: catalogo
  assert (select value_int from public.system_settings where key = 'game_pet_max_level') = 200, 'P1: livello massimo 200';
  assert (select bool_and(max_value = base_max * 2) from public.game_pet_lines where effect in ('for','des','vig','spi','frt','xp')), 'P1: statistiche e XP raddoppiate';
  assert (select bool_and(max_value = base_max + 1) from public.game_pet_lines where effect = 'actions'), 'P1: azioni boss +1';
  assert (select bool_and(max_value = base_max) from public.game_pet_lines where effect = 'fights'), 'P1: ricarica energia invariata';
  insert into t_log (msg) values (format('OK P1 — livello massimo 200; bonus raddoppiati (il più alto: %s%%); ricarica energia invariata', (select max(max_value) from public.game_pet_lines where effect <> 'fights')));

  -- P2: a parità di livello nessun bonus scende, a 200 vale il doppio di prima a 100
  for b in select * from public.game_pet_lines loop
    for mx in select generate_series(1, 100) loop
      assert public._game_pet_line_value(b.max_value, b.base_max, b.effect, b.unlock_level, mx) >= public._game_pet_value(b.base_max, b.unlock_level, mx, 100), format('P2: %s pos %s liv %s scende', b.pet_id, b.pos, mx);
    end loop;
    assert public._game_pet_line_value(b.max_value, b.base_max, b.effect, b.unlock_level, 200) = b.max_value, 'P2: valore pieno a 200';
    if b.effect = 'fights' then assert public._game_pet_line_value(b.max_value, b.base_max, b.effect, b.unlock_level, 100) = b.base_max, 'P2: ricarica energia piena già a 100, come prima'; end if;
  end loop;
  insert into t_log (msg) values ('OK P2 — a ogni livello i bonus sono uguali o più alti di prima; pieni al livello 200');

  -- P3: un compagno a 100 riprende a crescere fino a 200 (ma non oltre l'eroe)
  insert into auth.users (id, email, aud, role) values (pg_temp.uid('Ann'), 'ann@test.local', 'authenticated', 'authenticated');
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid('Ann'), 'role', 'authenticated')::text, true);
  perform public.register_profile('Ann'); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
  perform public.game_pet_choose((select id from public.game_pets where starter order by no limit 1));
  update public.game_heroes set level = 150 where user_id = pg_temp.uid('Ann');
  update public.game_hero_pets set level = 100, xp = 0 where user_id = pg_temp.uid('Ann');
  perform public._game_pet_gain(pg_temp.uid('Ann'), 2000000000);
  assert (select level from public.game_hero_pets where user_id = pg_temp.uid('Ann')) = 150, format('P3: sale fino al livello dell''eroe (%s)', (select level from public.game_hero_pets where user_id = pg_temp.uid('Ann')));
  update public.game_heroes set level = 400 where user_id = pg_temp.uid('Ann');
  perform public._game_pet_gain(pg_temp.uid('Ann'), 2000000000); perform public._game_pet_gain(pg_temp.uid('Ann'), 2000000000);
  assert (select level from public.game_hero_pets where user_id = pg_temp.uid('Ann')) = 200, 'P3: si ferma a 200';
  s := public.game_pet_state();
  assert (s->>'max_level')::int = 200, 'P3: lo stato dice 200';
  select x into p from jsonb_array_elements(s->'pets') x where (x->>'active')::boolean;
  assert (select bool_and((l->>'value')::int = (l->>'max')::int) from jsonb_array_elements(p->'lines') l), format('P3: bonus pieni a 200 (%s)', p->'lines');
  assert (select pq from public._game_pet_bonus(pg_temp.uid('Ann'))) is not null, 'P3: bonus calcolati';
  insert into t_log (msg) values ('OK P3 — un compagno fermo a 100 riprende a salire: fino al livello dell''eroe, al massimo 200, con i bonus pieni');
end $$;
select msg as risultato from t_log order by n;
rollback;
