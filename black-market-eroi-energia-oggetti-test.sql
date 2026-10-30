-- TEST della migrazione 035. Da eseguire SOLO su un database di prova vuoto, dopo le migrazioni degli Eroi e la 035. Finisce con rollback.
begin;
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto, mai su quello reale. Non è stato modificato nulla.';
  end if;
  if to_regprocedure('public._game_energy_checkpoint(uuid)') is null then raise exception 'Prima esegui la migrazione 035.'; end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-moduli-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.en(n text) returns numeric language sql as $$ select public._game_energy_of(pg_temp.uid(n)) $$;
create function pg_temp.eq(n text, it text) returns void language plpgsql as $$ begin perform pg_temp.as_(n); perform public.game_equip(it); end $$;
-- fa passare h ore (sposta l'ultimo salvataggio indietro)
create function pg_temp.hours(n text, h numeric) returns void language sql as $$ update public.game_heroes set energy_at = energy_at - make_interval(secs => h * 3600) where user_id = pg_temp.uid(n) $$;
create function pg_temp.near(a numeric, b numeric) returns boolean language sql as $$ select abs(a - b) < 0.05 $$;
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;

do $$ declare n text; begin
  foreach n in array array['Admin','Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Ann'); perform public.game_state(); perform pg_temp.as_('Bob'); perform public.game_state();
  update public.game_heroes set level = 20, stats_set = true where user_id in (pg_temp.uid('Ann'), pg_temp.uid('Bob'));
  insert into public.game_inventory (user_id, item_id, source) values (pg_temp.uid('Ann'), 't04', 'shop'), (pg_temp.uid('Bob'), 't04', 'shop');
  assert (select extra_fights from public.game_items where id = 't04') = 1, 'oggetto di prova t04 con +1 duelli';
  assert (select slot from public.game_items where id = 't04') = 'tool', 't04 è uno strumento';
  insert into t_log (msg) values ('OK Preparazione');
end $$;

create temp table t_led as select (select count(*) from public.ledger_entries) as n, (select coalesce(sum(balance),0) from public.wallets) as b;

-- T0 — senza la correzione il bug esiste (controllo del test)
do $$ declare s text; begin
  s := (select id from public.game_items where source = 'start' and slot = 'tool');
  update public.game_heroes set energy = 0, energy_at = now() where user_id = pg_temp.uid('Ann');
  alter table public.game_equipped disable trigger game_equipped_energy;
  perform pg_temp.eq('Ann', 't04'); perform pg_temp.hours('Ann', 4);
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), 'T0: con lo strumento veloce 4 ore = 62,5';
  perform pg_temp.eq('Ann', s);
  assert pg_temp.near(pg_temp.en('Ann'), 50), format('T0: senza correzione, togliendo lo strumento l''energia scende a 50 (è %s)', pg_temp.en('Ann'));
  alter table public.game_equipped enable trigger game_equipped_energy;
  insert into t_log (msg) values ('OK T0 — senza la correzione il bug si riproduce (62,5 → 50)');
end $$;

-- T1 — con la correzione: togliere e rimettere lo strumento non fa perdere nulla
do $$ declare s text; begin
  s := (select id from public.game_items where source = 'start' and slot = 'tool');
  update public.game_heroes set energy = 0, energy_at = now() where user_id = pg_temp.uid('Ann');
  perform pg_temp.eq('Ann', s); perform pg_temp.eq('Ann', 't04');
  perform pg_temp.hours('Ann', 4);
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), 'T1: 4 ore con lo strumento veloce = 62,5';
  perform pg_temp.eq('Ann', s);
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), format('T1: togliere lo strumento NON toglie energia (è %s)', pg_temp.en('Ann'));
  assert pg_temp.near((select energy from public.game_heroes where user_id = pg_temp.uid('Ann')), 62.5), 'T1: il valore è stato salvato';
  perform pg_temp.eq('Ann', 't04');
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), 'T1: rimettere lo strumento non cambia l''energia';
  perform pg_temp.hours('Ann', 2);
  assert pg_temp.near(pg_temp.en('Ann'), 93.75), format('T1: poi 2 ore col veloce = 93,75 (è %s)', pg_temp.en('Ann'));
  insert into t_log (msg) values ('OK T1 — togliere e rimettere lo strumento non perde energia');
end $$;

-- T2 — la nuova velocità vale solo per il tempo futuro (né regali né perdite)
do $$ declare s text; begin
  s := (select id from public.game_items where source = 'start' and slot = 'tool');
  update public.game_heroes set energy = 20, energy_at = now() where user_id = pg_temp.uid('Ann');
  perform pg_temp.eq('Ann', s); perform pg_temp.hours('Ann', 2);
  assert pg_temp.near(pg_temp.en('Ann'), 45), format('T2: 2 ore senza strumento veloce = 20 + 25 (è %s)', pg_temp.en('Ann'));
  perform pg_temp.eq('Ann', 't04'); perform pg_temp.hours('Ann', 2);
  assert pg_temp.near(pg_temp.en('Ann'), 76.25), format('T2: poi 2 ore col veloce = 45 + 31,25 (è %s)', pg_temp.en('Ann'));
  -- indossare lo strumento veloce non regala energia per il passato
  update public.game_heroes set energy = 0, energy_at = now() - interval '4 hours' where user_id = pg_temp.uid('Ann');
  perform pg_temp.eq('Ann', s);
  update public.game_heroes set energy = 0, energy_at = now() - interval '4 hours' where user_id = pg_temp.uid('Ann');
  perform pg_temp.eq('Ann', 't04');
  assert pg_temp.near(pg_temp.en('Ann'), 50), format('T2: indossare lo strumento veloce non regala energia per il passato (50, è %s)', pg_temp.en('Ann'));
  insert into t_log (msg) values ('OK T2 — la velocità nuova vale solo dal cambio in poi');
end $$;

-- T3 — il tetto resta il massimo; energia già al massimo resta al massimo
do $$ declare s text; begin
  s := (select id from public.game_items where source = 'start' and slot = 'tool');
  update public.game_heroes set energy = 90, energy_at = now() - interval '10 hours' where user_id = pg_temp.uid('Ann');
  perform pg_temp.eq('Ann', s);
  assert pg_temp.near(pg_temp.en('Ann'), 100), 'T3: energia al massimo resta al massimo';
  perform pg_temp.eq('Ann', 't04');
  assert pg_temp.near(pg_temp.en('Ann'), 100), 'T3: e dopo averlo rimesso';
  insert into t_log (msg) values ('OK T3 — tetto al massimo rispettato');
end $$;

-- T4 — cancellazione diretta dell'oggetto equipaggiato (un amministratore, una funzione futura): stessa protezione
do $$ declare s text; begin
  update public.game_heroes set energy = 0, energy_at = now() where user_id = pg_temp.uid('Ann');
  perform pg_temp.eq('Ann', 't04'); perform pg_temp.hours('Ann', 4);
  delete from public.game_equipped where user_id = pg_temp.uid('Ann') and slot = 'tool';
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), format('T4: delete diretto non perde energia (è %s)', pg_temp.en('Ann'));
  insert into public.game_equipped (user_id, slot, item_id) values (pg_temp.uid('Ann'), 'tool', 't04');
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), 'T4: insert diretto non cambia l''energia';
  insert into t_log (msg) values ('OK T4 — vale anche per insert/delete diretti');
end $$;

-- T5 — un amministratore cambia il «+duelli» di un oggetto del catalogo
do $$ begin
  update public.game_heroes set energy = 0, energy_at = now() - interval '4 hours' where user_id = pg_temp.uid('Ann');
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), 'T5: prima 62,5';
  update public.game_items set extra_fights = 3 where id = 't04';
  assert pg_temp.near(pg_temp.en('Ann'), 62.5), format('T5: cambiare il +duelli non cambia il passato (è %s)', pg_temp.en('Ann'));
  perform pg_temp.hours('Ann', 1);
  assert pg_temp.near(pg_temp.en('Ann'), 62.5 + 12.5 * 1.75), 'T5: da ora vale il nuovo valore';
  update public.game_items set extra_fights = 1 where id = 't04';
  update public.game_items set name = name where id = 't04';   -- altre modifiche: nessun effetto
  insert into t_log (msg) values ('OK T5 — modifica del catalogo: stessa protezione');
end $$;

-- T6 — un giocatore non è toccato dai cambi di un altro; permessi chiusi al browser
do $$ begin
  update public.game_heroes set energy = 30, energy_at = now() - interval '2 hours' where user_id = pg_temp.uid('Bob');
  perform pg_temp.eq('Bob', 't04');
  assert pg_temp.near(pg_temp.en('Bob'), 30 + 25), format('T6: Bob con il suo strumento: 30 + 2 ore di recupero normale = 55 (è %s)', pg_temp.en('Bob'));
  assert pg_temp.near((select energy from public.game_heroes where user_id = pg_temp.uid('Bob')), 55), 'T6: salvati i 55 di Bob';
  assert not exists (select 1 from public.game_heroes where user_id = pg_temp.uid('Admin') and energy_at > now() - interval '1 minute' and energy <> 100), 'T6: l''amministratore non è toccato';
  assert pg_temp.err('set local role authenticated; select public._game_energy_checkpoint(' || quote_literal(pg_temp.uid('Ann')) || '::uuid)') is not null, 'T6: la funzione interna è chiusa al browser';
  reset role;
  assert pg_temp.err('set local role anon; select public.game_equip(''t04'')') is not null, 'T6: anonimi fuori';
  reset role;
  insert into t_log (msg) values ('OK T6 — altri giocatori non toccati, permessi chiusi');
end $$;

-- T7 — nessun BC mosso
do $$ begin
  assert (select count(*) from public.ledger_entries) = (select n from t_led), 'T7: registro BC invariato';
  assert (select coalesce(sum(balance),0) from public.wallets) = (select b from t_led), 'T7: saldi invariati';
  insert into t_log (msg) values ('OK T7 — nessun BC mosso');
end $$;

select msg as esito from t_log order by n;
rollback;
