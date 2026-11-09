-- =====================================================================
-- TEST DELLA MIGRAZIONE 041 (Mappa dei terreni e Locanda)
-- Da eseguire SOLO su un progetto Supabase di PROVA ancora vuoto, con tutte le migrazioni applicate fino a black-market-eroi-mappa.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-mappa-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.plot(rg integer, k integer) returns integer language sql as $$ select id from public.game_land where region_no = rg order by id offset k limit 1 $$;

do $$
declare n text;
begin
  foreach n in array array['Admin','Ann','Bob','Cid'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
    perform public._ledger_move(pg_temp.uid(n), 2000000, 'admin_adjustment', 'test', null, 'test:soldi:' || n, 'soldi di prova');
  end loop;
  update public.game_heroes set level = 120 where user_id = pg_temp.uid('Ann');
  insert into t_log (msg) values ('OK Preparazione');
end $$;

-- M1 — Mappa e acquisto
do $$
declare s jsonb; r jsonb; b0 integer; p integer := pg_temp.plot(1, 0);
begin
  perform pg_temp.as_('Ann'); s := public.game_map_state();
  assert (s->>'enabled')::boolean and jsonb_array_length(s->'plots') = 316 and jsonb_array_length(s->'regions') = 8, 'M1: 316 terreni in 8 regioni';
  b0 := pg_temp.bal('Ann'); r := public.game_land_buy(p);
  assert (r->>'price')::int = 2000 and pg_temp.bal('Ann') = b0 - 2000, 'M1: primo terreno a prezzo pieno';
  assert (select owner_id from public.game_land where id = p) = pg_temp.uid('Ann'), 'M1: il terreno è di Ann';
  assert pg_temp.err_as('Bob', format('select public.game_land_buy(%s)', p)) like '%già un proprietario%', 'M1: nessuno può portarlo via';
  r := public.game_land_buy(pg_temp.plot(1, 1));
  assert (r->>'price')::int = 2060, 'M1: il secondo costa il 3% in più';
  assert pg_temp.err_as('Bob', format('select public.game_land_buy(%s)', pg_temp.plot(4, 0))) like '%livello 100%', 'M1: le regioni si sbloccano col livello';
  r := public.game_land_buy(pg_temp.plot(4, 0)); assert (r->>'ok')::boolean, 'M1: Ann (liv. 120) compra nel Deserto';
  insert into t_log (msg) values ('OK M1 — 316 terreni, acquisto, prezzo crescente del 3%, regioni a livello, proprietà definitiva');
end $$;

-- M2 — Miglioramenti e rendita
do $$
declare r jsonb; p integer := pg_temp.plot(1, 0); b0 integer; d0 bigint; got integer;
begin
  perform pg_temp.as_('Ann');
  d0 := public._land_daily(pg_temp.uid('Ann'));
  assert d0 = 100 + 100 + 1100, 'M2: rendita base 1.300/giorno';
  r := public.game_land_upgrade(p); assert (r->>'cost')::int = 1200 and (r->>'level')::int = 1, 'M2: Accampamento al 60% del prezzo';
  perform public.game_land_upgrade(p); perform public.game_land_upgrade(p); perform public.game_land_upgrade(p); perform public.game_land_upgrade(p);
  assert (select level from public.game_land where id = p) = 5, 'M2: Castello';
  assert pg_temp.err_as('Ann', format('select public.game_land_upgrade(%s)', p)) like '%già un Castello%', 'M2: oltre il Castello no';
  assert pg_temp.err_as('Bob', format('select public.game_land_upgrade(%s)', p)) like '%solo i tuoi%', 'M2: solo il proprietario migliora';
  assert public._land_daily(pg_temp.uid('Ann')) = 600 + 100 + 1100, 'M2: Castello = rendita ×6';
  -- 12 ore dopo: metà della rendita giornaliera
  update public.game_land_owners set last_claim_at = now() - interval '12 hours' where user_id = pg_temp.uid('Ann');
  b0 := pg_temp.bal('Ann'); r := public.game_land_collect();
  assert (r->>'collected')::int = 900 and pg_temp.bal('Ann') = b0 + 900, format('M2: 12 ore = 900 BC (%s)', r->>'collected');
  -- 5 giorni dopo: si incassano al massimo 48 ore
  update public.game_land_owners set last_claim_at = now() - interval '5 days' where user_id = pg_temp.uid('Ann');
  r := public.game_land_collect(); assert (r->>'collected')::int = 3600, 'M2: massimo 48 ore di rendita';
  r := public.game_land_collect(); assert (r->>'collected')::int = 0, 'M2: niente doppio incasso';
  insert into t_log (msg) values ('OK M2 — 5 miglioramenti fino al Castello (×6), rendita oraria, massimo 48 ore, nessun doppio incasso');
end $$;

-- M3 — Classifica
do $$
declare s jsonb;
begin
  perform pg_temp.as_('Bob'); perform public.game_land_buy(pg_temp.plot(1, 5));
  s := public.game_map_state();
  assert s->'top'->0->>'nickname' = 'Ann' and (s->'top'->0->>'plots')::int = 3, 'M3: Ann prima con 3 terreni';
  assert (s->>'my_rank')::int = 2, 'M3: Bob secondo';
  insert into t_log (msg) values ('OK M3 — classifica dei proprietari');
end $$;

-- M4 — Locanda: presenti, riposo, giro offerto
do $$
declare s jsonb; r jsonb; b0 integer;
begin
  update public.game_heroes set energy = 10, energy_at = now() where true;
  perform pg_temp.as_('Ann'); s := public.game_tavern_state();
  perform pg_temp.as_('Bob'); s := public.game_tavern_state();
  assert jsonb_array_length(s->'present') = 2, 'M4: due eroi in locanda';
  r := public.game_tavern_rest(); assert (r->>'energy')::int = 25, 'M4: riposo +25 energia';
  assert pg_temp.err_as('Bob', 'select public.game_tavern_rest()') like '%già riposato%', 'M4: riposo una volta al giorno';
  b0 := pg_temp.bal('Ann'); perform pg_temp.as_('Ann'); r := public.game_tavern_round();
  assert (r->>'recipients')::int = 2 and pg_temp.bal('Ann') = b0 - 1000, 'M4: il giro costa 1.000 BC e arriva ai 2 presenti';
  assert floor(public._game_energy_of(pg_temp.uid('Bob'))) = 45, format('M4: Bob 10 + 25 + 10 = 45 (%s)', floor(public._game_energy_of(pg_temp.uid('Bob'))));
  assert floor(public._game_energy_of(pg_temp.uid('Cid'))) = 10, 'M4: chi non è in locanda non riceve niente';
  assert pg_temp.err_as('Ann', 'select public.game_tavern_round()') like '%una volta all''ora%', 'M4: un giro all''ora';
  update public.game_heroes set energy = 99, energy_at = now() where user_id = pg_temp.uid('Cid');
  perform pg_temp.as_('Cid'); r := public.game_tavern_rest(); assert (r->>'energy')::int = 1, 'M4: l''energia non supera il massimo';
  insert into t_log (msg) values ('OK M4 — presenti, riposo giornaliero, giro offerto ai presenti, tetto di energia');
end $$;

-- M5 — Dadi: posta, partita, piatto meno il 5%, tavolo chiuso
do $$
declare r jsonb; t bigint; a0 integer; b0 integer; t0 bigint; tot0 bigint;
begin
  tot0 := (select sum(balance) from public.wallets);
  perform pg_temp.as_('Ann'); a0 := pg_temp.bal('Ann'); b0 := pg_temp.bal('Bob');
  assert pg_temp.err_as('Ann', 'select public.game_dice_open(50)') like '%da 100%', 'M5: posta minima';
  assert pg_temp.err_as('Bob', 'select public.game_dice_open(5000)') like '%da 100 a 200%', 'M5: posta massima legata al livello (Bob liv. 1)';
  t := (public.game_dice_open(1000)->>'id')::bigint;
  assert pg_temp.bal('Ann') = a0 - 1000, 'M5: posta trattenuta';
  assert pg_temp.err_as('Ann', format('select public.game_dice_join(%s)', t)) like '%contro te stesso%', 'M5: non contro se stessi';
  perform pg_temp.as_('Bob'); r := public.game_dice_join(t);
  if (r->>'draw')::boolean then
    assert pg_temp.bal('Ann') = a0 and pg_temp.bal('Bob') = b0, 'M5: pareggio, poste restituite';
  else
    assert (r->>'pot')::int = 1900, 'M5: piatto 2.000 meno il 5%';
    assert pg_temp.bal('Ann') + pg_temp.bal('Bob') = a0 + b0 - 100, 'M5: la casa trattiene 100 BC';
  end if;
  assert pg_temp.err_as('Cid', format('select public.game_dice_join(%s)', t)) like '%non è più disponibile%', 'M5: tavolo già giocato';
  perform pg_temp.as_('Ann'); a0 := pg_temp.bal('Ann'); t := (public.game_dice_open(500)->>'id')::bigint; perform public.game_dice_cancel(t);
  assert pg_temp.bal('Ann') = a0, 'M5: tavolo chiuso, posta restituita';
  t := (public.game_dice_open(700)->>'id')::bigint; update public.game_dice set created_at = now() - interval '25 hours' where id = t;
  a0 := pg_temp.bal('Ann'); perform public.game_tavern_state();
  assert pg_temp.bal('Ann') = a0 + 700 and (select status from public.game_dice where id = t) = 'expired', 'M5: dopo 24 ore il tavolo scade e la posta torna';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'M5: ogni saldo coincide con il registro';
  insert into t_log (msg) values ('OK M5 — dadi: limiti di posta, partita, 5% alla casa, tavolo chiuso e scaduto, saldi = registro');
end $$;

-- M6 — Permessi e interruttore
do $$
begin
  begin execute 'set local role authenticated'; perform pg_temp.as_('Bob'); update public.game_land set owner_id = pg_temp.uid('Bob'); raise exception 'SCRITTO';
  exception when others then assert sqlerrm <> 'SCRITTO', 'M6: il browser non scrive sulla mappa'; end;
  execute 'reset role';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('game_map_enabled', 0, 'prova');
  perform pg_temp.as_('Ann'); assert (public.game_map_state()->>'enabled')::boolean = false, 'M6: mappa spenta';
  assert pg_temp.err_as('Ann', 'select public.game_land_collect()') like '%chiusa%', 'M6: niente azioni a mappa spenta';
  insert into t_log (msg) values ('OK M6 — permessi e interruttore game_map_enabled');
end $$;

select msg as risultato from t_log order by n;
rollback;
