-- =====================================================================
-- TEST DELLA MIGRAZIONE 042 (Villaggi)
-- Da eseguire SOLO su un progetto Supabase di PROVA ancora vuoto, con tutte le migrazioni applicate fino a black-market-eroi-villaggi.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-villaggi-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.plot(rg integer, k integer) returns integer language sql as $$ select id from public.game_land where region_no = rg order by id offset k limit 1 $$;
create function pg_temp.vil(n text) returns public.game_villages language sql as $$ select * from public.game_villages where user_id = pg_temp.uid(n) order by founded_at, plot_id limit 1 $$;
create function pg_temp.vp(n text) returns integer language sql as $$ select plot_id from public.game_villages where user_id = pg_temp.uid(n) order by founded_at, plot_id limit 1 $$;

do $$
declare n text; k integer := 0;
begin
  foreach n in array array['Admin','Ann','Bob','Cid'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
    perform public._ledger_move(pg_temp.uid(n), 2000000, 'admin_adjustment', 'test', null, 'test:soldi:' || n, 'soldi di prova');
    if n <> 'Admin' then perform public.game_land_buy(pg_temp.plot(1, k)); k := k + 10; end if;
    if n = 'Ann' then perform public.game_land_buy(pg_temp.plot(1, 3)); perform public.game_land_buy(pg_temp.plot(1, 4)); end if;
  end loop;
  insert into t_log (msg) values ('OK Preparazione: Bob e Cid hanno un terreno, Ann tre');
end $$;

-- V1 — Fondazione
do $$
declare r jsonb; b0 integer; s jsonb;
begin
  perform pg_temp.as_('Ann'); s := public.game_village_state();
  assert (s->>'enabled')::boolean and s->'me' = 'null'::jsonb and jsonb_array_length(s->'my_plots') = 3, 'V1: niente villaggio, tre terreni disponibili';
  assert pg_temp.err_as('Ann', format('select public.game_village_found(%s, %L)', pg_temp.plot(1, 10), 'Rocca')) like '%solo su un tuo terreno%', 'V1: solo sui propri terreni';
  assert pg_temp.err_as('Ann', format('select public.game_village_found(%s, %L)', pg_temp.plot(1, 0), 'X')) like '%da 3 a 24%', 'V1: nome troppo corto';
  b0 := pg_temp.bal('Ann'); r := public.game_village_found(pg_temp.plot(1, 0), 'Rocca Ann');
  assert pg_temp.bal('Ann') = b0 - 10000, 'V1: la fondazione costa 10.000 BC';
  assert pg_temp.err_as('Ann', format('select public.game_village_found(%s, %L)', pg_temp.plot(1, 0), 'Altro')) like '%già un villaggio%', 'V1: un villaggio per terreno';
  assert pg_temp.err_as('Bob', format('select public.game_village_found(%s, %L)', pg_temp.plot(1, 10), 'rocca ann')) like '%questo nome%', 'V1: nomi unici';
  perform pg_temp.as_('Bob'); perform public.game_village_found(pg_temp.plot(1, 10), 'Borgo Bob');
  perform pg_temp.as_('Cid'); perform public.game_village_found(pg_temp.plot(1, 20), 'Castel Cid');
  perform pg_temp.as_('Ann'); s := public.game_village_state();
  assert s->'me'->>'name' = 'Rocca Ann' and (s->'me'->>'shield_until') is not null and jsonb_array_length(s->'villages') = 3, 'V1: villaggio con tregua, 3 villaggi in mappa';
  assert (s->'rules'->>'found_cost')::int = 20000, 'V1: il secondo villaggio costa 20.000';
  b0 := pg_temp.bal('Ann'); r := public.game_village_found(pg_temp.plot(1, 3), 'Ann Due');
  assert pg_temp.bal('Ann') = b0 - 20000 and (r->>'next_cost')::int = 30000, 'V1: secondo villaggio a 20.000, il terzo costerà 30.000';
  s := public.game_village_state(pg_temp.plot(1, 3));
  assert s->'me'->>'name' = 'Ann Due' and jsonb_array_length(s->'mine') = 2 and jsonb_array_length(s->'my_plots') = 1, 'V1: Ann ha due villaggi e un terreno libero';
  s := public.game_village_state(pg_temp.plot(1, 10));
  assert s->'me'->>'name' = 'Rocca Ann', 'V1: un villaggio altrui non si apre: torna il primo';
  assert (s->'villages'->0->>'user_id')::uuid = pg_temp.uid('Ann') or (s->'villages'->1->>'min')::int >= 5, 'V1: tempi di marcia calcolati';
  insert into t_log (msg) values ('OK V1 — ogni terreno può diventare un villaggio (10.000, 20.000, 30.000…), uno per terreno, nomi unici, tregua iniziale');
end $$;

-- V2 — Produzione, magazzino, cassa
do $$
declare v public.game_villages%rowtype; s jsonb; b0 integer; r jsonb;
begin
  update public.game_villages set res_at = now() - interval '10 hours' where plot_id = pg_temp.vp('Ann');
  perform pg_temp.as_('Ann'); s := public.game_village_state(); v := pg_temp.vil('Ann');
  assert floor(v.wood) = 900 and floor(v.stone) = 900 and floor(v.food) = 900, format('V2: 10 ore = +300 di ogni risorsa (%s)', floor(v.wood));
  assert floor(v.vault) = 83, format('V2: cassa 200 BC/giorno → 83 in 10 ore (%s)', floor(v.vault));
  update public.game_villages set res_at = now() - interval '10 days' where plot_id = pg_temp.vp('Ann');
  s := public.game_village_state(); v := pg_temp.vil('Ann');
  assert v.wood = 1500 and v.vault = 400, format('V2: magazzino pieno a 1.500, cassa ferma a 48 ore (%s, %s)', v.wood, v.vault);
  b0 := pg_temp.bal('Ann'); r := public.game_village_collect(pg_temp.vp('Ann'));
  assert (r->>'collected')::int = 400 and pg_temp.bal('Ann') = b0 + 400, 'V2: riscossi 400 BC';
  assert pg_temp.err_as('Ann', format('select public.game_village_collect(%s)', pg_temp.vp('Ann'))) like '%vuota%', 'V2: niente doppio incasso';
  update public.game_villages set vault = 50 where user_id = pg_temp.uid('Ann');
  r := public.game_village_collect(null); assert (r->>'collected')::int = 100 and (r->>'villages')::int = 2, 'V2: riscuoti tutti i villaggi insieme';
  assert pg_temp.err_as('Bob', format('select public.game_village_collect(%s)', pg_temp.vp('Ann'))) like '%vuota%', 'V2: la cassa altrui non si tocca';
  insert into t_log (msg) values ('OK V2 — produzione oraria, capienza del magazzino, cassa con limite di 48 ore e riscossione');
end $$;

-- V3 — Edifici
do $$
declare r jsonb; b0 integer; v public.game_villages%rowtype;
begin
  perform pg_temp.as_('Ann');
  assert pg_temp.err_as('Ann', format('select public.game_village_build(%s, %L)', pg_temp.vp('Ann'), 'lumber')) like '%Municipio al livello 2%', 'V3: niente supera il Municipio';
  b0 := pg_temp.bal('Ann'); r := public.game_village_build(pg_temp.vp('Ann'), 'hall');
  assert (r->>'level')::int = 2 and pg_temp.bal('Ann') = b0 - 4950, format('V3: Municipio 2 = 495 legno, 495 pietra, 4.950 BC (%s)', b0 - pg_temp.bal('Ann'));
  v := pg_temp.vil('Ann'); assert v.wood = 1005 and v.stone = 1005, 'V3: risorse scalate';
  perform public.game_village_build(pg_temp.vp('Ann'), 'lumber');
  assert pg_temp.err_as('Ann', format('select public.game_village_build(%s, %L)', pg_temp.vp('Ann'), 'lumber')) like '%Municipio al livello 3%', 'V3: Segheria ferma al Municipio';
  assert pg_temp.err_as('Ann', format('select public.game_village_build(%s, %L)', pg_temp.vp('Ann'), 'torre')) like '%sconosciuto%', 'V3: edificio sconosciuto';
  update public.game_villages set wood = 0 where user_id = pg_temp.uid('Ann');
  assert pg_temp.err_as('Ann', format('select public.game_village_build(%s, %L)', pg_temp.vp('Ann'), 'wall')) like '%Servono%legno%', 'V3: servono le risorse';
  insert into t_log (msg) values ('OK V3 — costruzioni con legno, pietra e BC; limite del Municipio; risorse insufficienti');
end $$;

-- V4 — Soldati
do $$
declare r jsonb; b0 integer; v public.game_villages%rowtype;
begin
  update public.game_villages set food = 1500, wood = 1500, stone = 1500 where true;
  perform pg_temp.as_('Ann');
  assert pg_temp.err_as('Ann', format('select public.game_village_train(%s, 0, 5, 0)', pg_temp.vp('Ann'))) like '%Caserma al livello 3%', 'V4: arcieri dalla Caserma 3';
  assert pg_temp.err_as('Ann', format('select public.game_village_train(%s, 26, 0, 0)', pg_temp.vp('Ann'))) like '%al massimo 25%', 'V4: Caserma 1 = 25 soldati';
  b0 := pg_temp.bal('Ann'); r := public.game_village_train(pg_temp.vp('Ann'), 20, 0, 0);
  v := pg_temp.vil('Ann');
  assert pg_temp.bal('Ann') = b0 - 1200 and v.inf = 20 and floor(v.food) = 900, format('V4: 20 fanti = 1.200 BC + 600 cibo (%s)', v.food);
  assert public._vil_upkeep(pg_temp.vp('Ann')) = 20, 'V4: mantenimento 1 cibo/ora a fante';
  update public.game_villages set food = 10 where user_id = pg_temp.uid('Ann');
  assert pg_temp.err_as('Ann', format('select public.game_village_train(%s, 5, 0, 0)', pg_temp.vp('Ann'))) like '%cibo%', 'V4: serve cibo';
  update public.game_villages set food = 1500 where user_id = pg_temp.uid('Ann');
  insert into t_log (msg) values ('OK V4 — addestramento in BC + cibo, sblocchi della Caserma, limite dell''esercito, mantenimento');
end $$;

-- V5 — Guarnigione, tregua, invasione vinta, bottino e ritorno
do $$
declare r jsonb; s jsonb; v public.game_villages%rowtype; m public.game_village_marches%rowtype; n0 integer;
begin
  perform pg_temp.as_('Ann');
  perform public.game_village_defense(pg_temp.vp('Ann'), 5, 0, 0);
  assert pg_temp.err_as('Ann', format('select public.game_village_defense(%s, 30, 0, 0)', pg_temp.vp('Ann'))) like '%abbastanza soldati%', 'V5: guarnigione solo con chi c''è';
  assert pg_temp.err_as('Ann', format('select public.game_village_attack(%s, %s, 5, 0, 0)', pg_temp.vp('Ann'), pg_temp.vp('Bob'))) like '%in tregua%', 'V5: tregua iniziale';
  update public.game_villages set shield_until = null where user_id in (pg_temp.uid('Bob'), pg_temp.uid('Cid'));
  assert pg_temp.err_as('Ann', format('select public.game_village_attack(%s, %s, 16, 0, 0)', pg_temp.vp('Ann'), pg_temp.vp('Bob'))) like '%di guardia%', 'V5: chi difende non parte';
  update public.game_villages set vault = 1000, wood = 1500, stone = 1500, food = 1500 where user_id = pg_temp.uid('Bob');
  n0 := (select count(*) from public.notifications where user_id = pg_temp.uid('Bob'));
  r := public.game_village_attack(pg_temp.vp('Ann'), pg_temp.vp('Bob'), 15, 0, 0);
  assert (r->>'minutes')::int >= 5 and (select count(*) from public.notifications where user_id = pg_temp.uid('Bob')) = n0 + 1, 'V5: marcia partita, Bob avvisato';
  v := pg_temp.vil('Ann'); assert v.inf = 5 and v.shield_until is null, 'V5: 15 fanti in marcia, tregua di Ann tolta';
  assert public._vil_upkeep(pg_temp.vp('Ann')) = 20, 'V5: chi marcia mangia lo stesso';
  s := public.game_village_state(); assert jsonb_array_length(s->'marches') = 1, 'V5: marcia visibile';
  perform pg_temp.as_('Bob'); s := public.game_village_state();
  assert jsonb_array_length(s->'marches') = 1 and s->'marches'->0->'army' = 'null'::jsonb, 'V5: Bob vede l''attacco in arrivo ma non quanti sono';
  -- arrivo: Bob ha solo la milizia (5 fanti): Ann vince
  update public.game_village_marches set arrive_at = now() - interval '1 minute', depart_at = now() - interval '11 minutes' where attacker_id = pg_temp.uid('Ann');
  s := public.game_village_state();
  select * into m from public.game_village_marches where attacker_id = pg_temp.uid('Ann');
  assert m.status = 'returning' and m.won, format('V5: Ann vince (%s)', m.report);
  assert m.back_inf between 9 and 15, format('V5: perdite contenute (%s)', m.back_inf);
  assert m.loot_bc between 1 and 250 and m.loot_wood + m.loot_stone + m.loot_food + m.loot_bc <= m.back_inf * 25, format('V5: bottino entro il trasporto, 25%% della cassa (%s)', m.report);
  v := pg_temp.vil('Bob'); assert v.shield_until > now() + interval '7 hours' and v.def_lost = 1, 'V5: Bob in tregua 8 ore';
  assert floor(v.wood) >= 300, 'V5: il 20% nascosto resta';
  assert pg_temp.err_as('Cid', format('select public.game_village_attack(%s, %s, 1, 0, 0)', pg_temp.vp('Cid'), pg_temp.vp('Bob'))) is not null, 'V5: villaggio saccheggiato protetto';
  -- ritorno
  update public.game_village_marches set return_at = now() - interval '1 second' where id = m.id;
  update public.game_villages set wood = 100 where user_id = pg_temp.uid('Ann');
  perform pg_temp.as_('Ann'); s := public.game_village_state(); v := pg_temp.vil('Ann');
  assert v.inf = 5 + m.back_inf and v.loot_bc = m.loot_bc and floor(v.wood) >= 100 + m.loot_wood, 'V5: soldati e bottino tornati a casa';
  assert (select status from public.game_village_marches where id = m.id) = 'done', 'V5: marcia conclusa';
  assert jsonb_array_length(s->'reports') = 1, 'V5: rapporto della battaglia';
  assert pg_temp.err_as('Ann', format('select public.game_village_attack(%s, %s, 1, 0, 0)', pg_temp.vp('Ann'), pg_temp.plot(1, 3))) like '%un tuo villaggio%', 'V5: i propri villaggi non si attaccano';
  assert pg_temp.err_as('Ann', format('select public.game_village_attack(%s, %s, 1, 0, 0)', pg_temp.vp('Bob'), pg_temp.vp('Cid'))) like '%non è un tuo villaggio%', 'V5: si parte solo dai propri villaggi';
  insert into t_log (msg) values ('OK V5 — guarnigione, tregua, marcia con avviso, vittoria, bottino (risorse + 25% cassa) entro il trasporto, 8 ore di tregua, ritorno');
end $$;

-- V6 — Difesa che regge, sasso-carta-forbice, limiti
do $$
declare s jsonb; m public.game_village_marches%rowtype;
begin
  update public.game_villages set barracks = 5, hall = 5, food = 50000 where user_id = pg_temp.uid('Cid');
  perform pg_temp.as_('Cid'); perform public.game_village_train(pg_temp.vp('Cid'), 40, 0, 0); perform public.game_village_defense(pg_temp.vp('Cid'), 40, 0, 0);
  update public.game_villages set barracks = 5, hall = 5, food = 50000 where user_id = pg_temp.uid('Ann');
  perform pg_temp.as_('Ann'); perform public.game_village_train(pg_temp.vp('Ann'), 0, 0, 20);
  assert public._vil_power(array[10,0,0], array[0,0,10], true) = 150 and public._vil_power(array[0,0,10], array[10,0,0], true) = 165 and public._vil_power(array[0,10,0], array[10,0,0], true) = 210, 'V6: vantaggi ×1,5 e svantaggi ×0,75';
  perform public.game_village_defense(pg_temp.vp('Ann'), 0, 0, 0);
  perform public.game_village_attack(pg_temp.vp('Ann'), pg_temp.vp('Cid'), 0, 0, 20);
  assert (select arrive_at - depart_at from public.game_village_marches where attacker_id = pg_temp.uid('Ann') and status = 'going') <=
         make_interval(mins => public._vil_minutes(pg_temp.vp('Ann'), pg_temp.vp('Cid'), true)), 'V6: i cavalieri vanno veloci';
  update public.game_village_marches set arrive_at = now() - interval '1 minute' where attacker_id = pg_temp.uid('Ann') and status = 'going';
  perform public.game_village_state();
  select * into m from public.game_village_marches where attacker_id = pg_temp.uid('Ann') order by id desc limit 1;
  assert not m.won and m.back_cav = 6 and m.loot_bc = 0, format('V6: 20 cavalieri contro 40 fanti + mura: respinti, ne tornano 6 (%s)', m.report);
  assert (select def_won from public.game_villages where user_id = pg_temp.uid('Cid')) = 1, 'V6: difesa vinta';
  -- villaggio troppo piccolo
  update public.game_villages set hall = 1, shield_until = null where user_id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Ann', format('select public.game_village_attack(%s, %s, 0, 0, 1)', pg_temp.vp('Ann'), pg_temp.vp('Bob'))) like '%troppo piccolo%', 'V6: protezione dei villaggi piccoli';
  -- limite giornaliero
  update public.game_villages set hall = 5 where user_id = pg_temp.uid('Bob');
  insert into public.game_village_marches (attacker_id, defender_id, attacker_plot, defender_plot, inf, status, arrive_at, return_at, back_inf, won)
  select pg_temp.uid('Ann'), pg_temp.uid('Bob'), pg_temp.vp('Ann'), pg_temp.vp('Bob'), 0, 'done', now(), now(), 0, false from generate_series(1, 3);
  assert pg_temp.err_as('Ann', format('select public.game_village_attack(%s, %s, 0, 0, 1)', pg_temp.vp('Ann'), pg_temp.vp('Bob'))) like '%5 volte oggi%', 'V6: massimo 5 attacchi al giorno';
  perform pg_temp.as_('Ann'); perform public.game_village_train(pg_temp.plot(1, 3), 0, 0, 1);
  assert (public.game_village_attack(pg_temp.plot(1, 3), pg_temp.vp('Bob'), 0, 0, 1)->>'ok')::boolean, 'V6: il limite è per villaggio: Ann parte dal secondo';
  insert into t_log (msg) values ('OK V6 — difesa con mura respinge, sasso-carta-forbice, cavalieri veloci, protezione dei piccoli, 5 attacchi al giorno per villaggio');
end $$;

-- V7 — Fame, saldi e permessi
do $$
begin
  update public.game_villages set food = 0, farm = 1, res_at = now() - interval '2 hours' where user_id = pg_temp.uid('Cid');
  perform pg_temp.as_('Cid'); perform public.game_village_state();
  assert (select food from public.game_villages where user_id = pg_temp.uid('Cid')) = 0, 'V7: il cibo non va sotto zero';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'V7: ogni saldo coincide con il registro';
  begin execute 'set local role authenticated'; perform pg_temp.as_('Bob'); update public.game_villages set inf = 9999; raise exception 'SCRITTO';
  exception when others then assert sqlerrm <> 'SCRITTO', 'V7: il browser non scrive sui villaggi'; end;
  execute 'reset role';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('game_village_enabled', 0, 'prova');
  perform pg_temp.as_('Ann'); assert (public.game_village_state()->>'enabled')::boolean = false, 'V7: villaggi spenti';
  assert pg_temp.err_as('Ann', 'select public.game_village_collect(null)') like '%chiusi%', 'V7: niente azioni a villaggi spenti';
  insert into t_log (msg) values ('OK V7 — fame, saldi = registro, permessi, interruttore game_village_enabled');
end $$;

select msg as risultato from t_log order by n;
rollback;
