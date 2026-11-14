-- =====================================================================
-- TEST DELLA MIGRAZIONE 046 (Torre: compagni di piano). SOLO su un database di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-squadra-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
do $$
declare s jsonb; r jsonb; n text; c0 integer; c1 integer; f0 numeric; i integer; w integer := 0;
begin
  foreach n in array array['Ann','Bob','Cal','Dan'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state();
    update public.game_heroes set level = 30, a_for = 40, a_des = 20, a_vig = 40, a_spi = 10, a_frt = 20, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid(n);
  end loop;
  -- Ann e Bob sono fermi al piano 40, Cal al 12, Dan (sospeso) al 40
  insert into public.game_tower (user_id, best_floor, wins, reached_at) values (pg_temp.uid('Ann'), 40, 40, now() - interval '2 hours'), (pg_temp.uid('Bob'), 40, 40, now() - interval '1 hour'),
    (pg_temp.uid('Cal'), 12, 12, now()), (pg_temp.uid('Dan'), 40, 40, now());
  update public.profiles set suspended = true where id = pg_temp.uid('Dan');

  -- Q1: Ann vede Bob come compagno (non Cal, non il sospeso); da sola la stima è più bassa
  perform pg_temp.as_('Ann'); s := public.game_tower_state();
  assert jsonb_array_length(s->'allies') = 1 and s->'allies'->0->>'nickname' = 'Bob', format('Q1: compagno Bob (%s)', s->'allies');
  assert not (s->'allies'->0 ? 's_for'), 'Q1: le statistiche del compagno non escono';
  assert (s->>'ally_pct')::int = 50, 'Q1: percentuale';
  c1 := (s->'enemy'->>'chance')::int; f0 := (s->'enemy'->>'ratio')::numeric;
  update public.system_settings set value_int = 0 where key = 'game_tower_ally_pct';
  s := public.game_tower_state(); c0 := (s->'enemy'->>'chance')::int;
  assert jsonb_array_length(s->'allies') = 0 and (s->'enemy'->>'ratio')::numeric < f0 and c0 <= c1, format('Q1: da soli si è più deboli (%s → %s)', c0, c1);
  update public.system_settings set value_int = 50 where key = 'game_tower_ally_pct';
  insert into t_log (msg) values (format('OK Q1 — stesso piano = squadra: stima %s%% da soli, %s%% con un compagno; sospesi e altri piani esclusi', c0, c1));

  -- Q2: scalatori per piano (senza sospesi), io compreso
  s := public.game_tower_state();
  assert (select count(*) from jsonb_array_elements(s->'climbers')) = 3, format('Q2: 3 scalatori (%s)', s->'climbers');
  assert (select count(*) from jsonb_array_elements(s->'climbers') x where (x->>'best_floor')::int = 40) = 2, 'Q2: due al piano 40';
  assert position('Dan' in (s->'climbers')::text) = 0, 'Q2: sospeso escluso';
  insert into t_log (msg) values ('OK Q2 — «climbers» elenca gli scalatori con il loro piano');

  -- Q3: la salita usa la squadra; il compagno non riceve né perde nulla; salendo la squadra si scioglie
  select balance into c0 from public.wallets where user_id = pg_temp.uid('Bob');
  r := public.game_tower_climb();
  assert jsonb_array_length(r->'allies') = 1 and r->'allies'->0->>'nickname' = 'Bob', format('Q3: Bob in battaglia (%s)', r->'allies');
  assert (r->>'max_a')::numeric > (select max_hp from public._game_calc(pg_temp.uid('Ann'))), 'Q3: i PV della squadra superano quelli del solo eroe';
  assert (select balance from public.wallets where user_id = pg_temp.uid('Bob')) = c0 and (select best_floor from public.game_tower where user_id = pg_temp.uid('Bob')) = 40, 'Q3: Bob non cambia';
  if (r->>'won')::boolean then
    s := public.game_tower_state();
    assert jsonb_array_length(s->'allies') = 0, 'Q3: al piano 41 Ann è sola';
  end if;
  -- all'ingresso non ci sono compagni
  assert jsonb_array_length(public._game_tower_allies(pg_temp.uid('Ann'), 0)) = 0, 'Q3: ingresso senza compagni';
  -- il massimo è rispettato
  update public.system_settings set value_int = 0 where key = 'game_tower_allies_max';
  assert jsonb_array_length(public._game_tower_allies(pg_temp.uid('Cal'), 40)) = 0, 'Q3: massimo 0';
  insert into t_log (msg) values (format('OK Q3 — la salita è di squadra (%s), il compagno non guadagna e non perde nulla', case when (r->>'won')::boolean then 'vinta' else 'persa' end));
end $$;
select msg as risultato from t_log order by n;
rollback;
