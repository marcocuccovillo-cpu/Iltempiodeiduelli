-- =====================================================================
-- TEST DELLA MIGRAZIONE 008 (Black Market Shop)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…008 (black-market-setup.sql … black-market-shop.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- Se un controllo fallisce compare un errore con il nome dello scenario.
-- =====================================================================
begin;
-- PROTEZIONE: il test crea utenti e match di prova e confronta conteggi globali (il primo utente registrato diventa admin).
-- Su un database che contiene già dati veri non può funzionare: si ferma subito, senza toccare nulla.
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-moduli-' || n)::uuid $$;
create function pg_temp.act(u uuid) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_(n text) returns text language sql as $$ select pg_temp.act(pg_temp.uid(n)) $$;
-- esegue una query contando le righe, con il ruolo "authenticated" (come il browser); il ruolo torna normale alla fine
create function pg_temp.rows_as(n text, q text) returns bigint language plpgsql as $$
declare c bigint;
begin
  perform pg_temp.as_(n);
  begin
    execute 'set local role authenticated';
    execute 'select count(*) from (' || q || ') x' into c;
    raise exception 'RISULTATO:%', c;
  exception when others then
    if sqlerrm like 'RISULTATO:%' then return substr(sqlerrm, 11)::bigint; end if;
    raise;
  end;
end $$;
-- esegue una istruzione e restituisce il messaggio d'errore (oppure null se riuscita)
create function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); return pg_temp.err(q); end $$;
create function pg_temp.err_auth(n text, q text) returns text language plpgsql as $$   -- come il browser: ruolo authenticated
begin
  perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end;
end $$;
create function pg_temp.money() returns text language sql as $$
  select md5(coalesce((select string_agg(user_id || ':' || balance, ',' order by user_id) from public.wallets), '')
          || (select count(*)::text || coalesce(sum(amount), 0)::text from public.ledger_entries)
          || (select count(*)::text from public.bounties) || (select count(*)::text from public.bounty_settlements)) $$;
create function pg_temp.ev(nm text) returns uuid language plpgsql as $$
begin perform pg_temp.as_('Org'); return public.create_event(nm || ' ' || gen_random_uuid()::text, current_date); end $$;
create function pg_temp.mm(ev uuid, rnd integer, a text, b text, w text) returns uuid language plpgsql as $$
declare m uuid;
begin
  perform pg_temp.as_('Org');
  m := public.create_match(ev, rnd, pg_temp.uid(a), pg_temp.uid(b));
  if w is not null then perform public.verify_match(m, pg_temp.uid(w)); end if;
  return m;
end $$;
create function pg_temp.mod(m text, on_ boolean) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_module(m, on_, 'attivazione di prova'); end $$;

-- Preparazione: utenti (il primo registrato diventa amministratore); Org è organizzatore
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Marco','Luca','Paolo','Povero'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  insert into t_log (msg) values ('OK Preparazione: 6 utenti, Admin = primo registrato, Org organizzatore');
end $$;
create function pg_temp.set_(k text, v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting(k, v, 'impostazione di prova'); end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.tot() returns bigint language sql as $$ select coalesce(sum(balance), 0) from public.wallets $$;
create function pg_temp.chal(a text, b text, fmt text default 'Advanced') returns uuid language plpgsql as $$
begin perform pg_temp.as_(a); return public.ladder_challenge(pg_temp.uid(b), fmt, null, gen_random_uuid()::text); end $$;
create function pg_temp.play(a text, b text, result text, score text, reporter text) returns jsonb language plpgsql as $$
declare id uuid; other text; r jsonb;
begin
  id := pg_temp.chal(a, b);
  perform pg_temp.as_(b); perform public.ladder_respond(id, true);
  perform pg_temp.as_(reporter); perform public.ladder_report(id, result, score);
  other := case when reporter = a then b else a end;
  perform pg_temp.as_(other); r := public.ladder_confirm(id);
  return r;
end $$;
-- acquisto come "n" (nuova richiesta ogni volta, salvo rid)
create function pg_temp.buy(n text, item text, rid text default null, exp integer default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.shop_buy(item, coalesce(rid, gen_random_uuid()::text), exp); end $$;
create function pg_temp.sales() returns text language sql as $$
  select md5((select count(*)::text from public.shop_purchases) || (select coalesce(sum(price_paid),0)::text from public.shop_purchases)) $$;
create function pg_temp.save(item text, nm text, ds text, cat text, rar text, pr integer, asset text, act boolean, srt integer, why text) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_shop_save_item(item, nm, ds, cat, rar, pr, asset, act, srt, why); end $$;

-- H1 — Catalogo
do $$
begin
  assert (select count(*) from public.shop_items) >= 30, 'H1: almeno 30 premi';
  assert (select min(price) from public.shop_items) >= 2 and (select max(price) from public.shop_items) = 1000, 'H1: prezzi tra 2 e 1000 BC';
  assert (select count(distinct rarity) from public.shop_items) = 5, 'H1: cinque rarità';
  assert (select count(distinct category) from public.shop_items) = 6, 'H1: sei categorie';
  assert not exists (select 1 from public.shop_items where
     not ((rarity = 'common' and price between 2 and 49) or (rarity = 'rare' and price between 50 and 149) or (rarity = 'epic' and price between 150 and 349)
       or (rarity = 'legendary' and price between 350 and 699) or (rarity = 'mythic' and price between 700 and 1000))), 'H1: ogni prezzo nella fascia della sua rarità';
  assert (select count(*) from public.shop_items where category = 'pet') >= 10, 'H1: almeno 10 pet';
  assert (select price from public.shop_items where id = 'pet_drago_apocalittico') = 1000 and (select rarity from public.shop_items where id = 'pet_drago_apocalittico') = 'mythic', 'H1: il Drago Apocalittico costa 1000 BC ed è Mitico';
  assert (select count(*) from public.shop_items where rarity = 'mythic' and price = 1000) = 1, 'H1: un solo premio finale da 1000 BC';
  assert not exists (select 1 from public.shop_items where char_length(description) < 20), 'H1: ogni premio ha una descrizione propria';
  assert (select count(distinct description) from public.shop_items) = (select count(*) from public.shop_items), 'H1: descrizioni tutte diverse';
  assert public._setting('shop_enabled') = 1, 'H1: shop_enabled = 1';
  assert pg_temp.err('insert into public.shop_items (id,name,description,category,rarity,price,asset) values (''zz_prova'',''Prova'',''Descrizione di prova'',''pet'',''common'',60,''zz_prova'')') like '%shop_items_price_by_rarity%', 'H1: la fascia di prezzo è un vincolo del database';
  insert into t_log (msg) values ('OK H1 — catalogo: 39 premi, 6 categorie, 5 rarità, prezzi 2–1000 nelle fasce giuste (vincolo del database), Drago Apocalittico da 1000 BC');
end $$;

-- H2 — Acquisto: addebito + assegnazione, registro, riconciliazione
do $$
declare r jsonb; t0 bigint; lg0 bigint; w0 integer; pid uuid;
begin
  t0 := pg_temp.tot(); lg0 := (select count(*) from public.ledger_entries); w0 := pg_temp.bal('Marco');
  assert w0 = 1000, 'H2: saldo iniziale 1000';
  r := pg_temp.buy('Marco', 'pet_gelatina', null, 5);
  pid := (r->>'purchase_id')::uuid;
  assert (r->>'price')::int = 5 and (r->>'balance')::int = 995 and (r->>'already')::boolean = false, 'H2: risposta corretta';
  assert pg_temp.bal('Marco') = 995, 'H2: saldo = 995';
  assert pg_temp.tot() = t0 - 5, 'H2: il totale dei BC scende di 5 (nessun credito creato)';
  assert (select count(*) from public.ledger_entries) = lg0 + 1, 'H2: un solo movimento nel registro';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Marco') and kind = 'shop_purchase' and amount = -5 and balance_after = 995 and ref_type = 'shop_purchase' and ref_id = pid) = 1, 'H2: riga di registro corretta';
  assert (select count(*) from public.shop_purchases where id = pid and user_id = pg_temp.uid('Marco') and item_id = 'pet_gelatina' and price_paid = 5 and category = 'pet' and item_name = 'Gelatina Cucciola') = 1, 'H2: acquisto registrato con prezzo e nome';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'H2: saldi = registro';
  assert pg_temp.bal('Luca') = 1000 and pg_temp.bal('Paolo') = 1000, 'H2: i saldi degli altri non cambiano';
  insert into t_log (msg) values ('OK H2 — acquisto: addebito esatto, un solo movimento ''shop_purchase'', acquisto registrato, saldi riconciliati, nessun credito creato');
end $$;

-- H3 — Saldo insufficiente, nessun saldo negativo, atomicità
do $$
declare s0 text; w0 integer; lg0 bigint; r jsonb;
begin
  perform pg_temp.buy('Povero', 'titolo_novizio');
  assert pg_temp.bal('Povero') = 998, 'H3: 998 BC';
  s0 := pg_temp.sales(); w0 := pg_temp.bal('Povero'); lg0 := (select count(*) from public.ledger_entries);
  assert pg_temp.err_as('Povero', format('select public.shop_buy(%L, %L)', 'pet_drago_apocalittico', gen_random_uuid()::text)) like '%Saldo insufficiente%', 'H3: rifiutato per saldo insufficiente';
  assert pg_temp.bal('Povero') = w0 and (select count(*) from public.ledger_entries) = lg0 and pg_temp.sales() = s0, 'H3: nessun addebito, nessun acquisto, nessun movimento (atomicità)';
  assert not exists (select 1 from public.shop_purchases where user_id = pg_temp.uid('Povero') and item_id = 'pet_drago_apocalittico'), 'H3: il premio non è stato assegnato';
  assert not exists (select 1 from public.wallets where balance < 0), 'H3: nessun saldo negativo';
  r := pg_temp.buy('Luca', 'pet_drago_apocalittico', null, 1000);
  assert (r->>'balance')::int = 0 and pg_temp.bal('Luca') = 0, 'H3: con 1000 BC si compra il premio finale e il saldo scende a 0';
  assert pg_temp.err_as('Luca', format('select public.shop_buy(%L, %L)', 'titolo_novizio', gen_random_uuid()::text)) like '%Saldo insufficiente%', 'H3: a saldo 0 non si compra nulla';
  assert not exists (select 1 from public.wallets where balance < 0), 'H3: ancora nessun saldo negativo';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'H3: saldi = registro';
  insert into t_log (msg) values ('OK H3 — saldo insufficiente rifiutato senza effetti, premio da 1000 BC acquistabile a saldo esatto, mai saldi negativi, saldi riconciliati');
end $$;

-- H4 — Doppi acquisti, richieste duplicate, prezzo atteso, negozio chiuso, premio disattivato
do $$
declare r jsonb; rid text := 'richiesta-unica-001'; w integer;
begin
  r := pg_temp.buy('Marco', 'emblema_carta', rid);
  w := pg_temp.bal('Marco');
  assert (r->>'already')::boolean = false and w = 985, 'H4: primo acquisto';
  r := pg_temp.buy('Marco', 'emblema_carta', rid);
  assert (r->>'already')::boolean = true and pg_temp.bal('Marco') = w and (select count(*) from public.shop_purchases where user_id = pg_temp.uid('Marco') and item_id = 'emblema_carta') = 1, 'H4: stessa richiesta = nessun secondo addebito';
  assert pg_temp.err_as('Marco', format('select public.shop_buy(%L, %L)', 'emblema_carta', gen_random_uuid()::text)) like '%Possiedi già%', 'H4: nuova richiesta sullo stesso premio rifiutata';
  assert pg_temp.bal('Marco') = w, 'H4: nessun addebito sul rifiuto';
  assert pg_temp.err_as('Marco', format('select public.shop_buy(%L, %L, %s)', 'cornice_pietra', gen_random_uuid()::text, 99)) like '%prezzo è cambiato%', 'H4: prezzo atteso diverso = rifiuto';
  assert pg_temp.err_as('Marco', format('select public.shop_buy(%L, %L)', 'non_esiste', gen_random_uuid()::text)) like '%inesistente%', 'H4: premio inesistente';
  assert pg_temp.err_as('Marco', format('select public.shop_buy(%L, %L)', 'cornice_pietra', 'corta')) like '%Richiesta non valida%', 'H4: richiesta senza chiave valida rifiutata';
  perform pg_temp.set_('shop_enabled', 0);
  assert pg_temp.err_as('Marco', format('select public.shop_buy(%L, %L)', 'cornice_pietra', gen_random_uuid()::text)) like '%Shop è chiuso%', 'H4: shop_enabled = 0 blocca gli acquisti';
  perform pg_temp.set_('shop_enabled', 1);
  assert (pg_temp.buy('Marco', 'cornice_pietra')->>'price')::int = 12, 'H4: riaperto, si compra';
  perform pg_temp.save('fx_scintille', 'Scintille', 'Minuscole scintille dorate che salgono dal tuo profilo.', 'effect', 'common', 35, 'fx_scintille', false, 350, 'disattivazione di prova');
  assert pg_temp.err_as('Marco', format('select public.shop_buy(%L, %L)', 'fx_scintille', gen_random_uuid()::text)) like '%non è disponibile%', 'H4: premio disattivato non acquistabile';
  perform pg_temp.save('fx_scintille', 'Scintille', 'Minuscole scintille dorate che salgono dal tuo profilo.', 'effect', 'common', 35, 'fx_scintille', true, 350, 'riattivazione di prova');
  assert not exists (select 1 from public.wallets where balance < 0), 'H4: nessun saldo negativo';
  insert into t_log (msg) values ('OK H4 — richiesta duplicata = un solo addebito, premio già posseduto e prezzo cambiato rifiutati, negozio chiuso e premio disattivato bloccano l''acquisto');
end $$;

-- H5 — Il client non può alterare prezzi, acquisti, inventario né saldi
do $$
declare pid uuid;
begin
  pid := (select id from public.shop_purchases where user_id = pg_temp.uid('Marco') and item_id = 'pet_gelatina');
  assert pg_temp.err_auth('Marco', 'update public.shop_items set price = 2') like '%permission denied%', 'H5: nessuna modifica diretta ai prezzi';
  assert pg_temp.err_auth('Marco', 'insert into public.shop_items (id,name,description,category,rarity,price,asset) values (''abc'',''Abc'',''Descrizione di prova'',''pet'',''common'',5,''abc'')') like '%permission denied%', 'H5: nessun premio inserito dal client';
  assert pg_temp.err_auth('Marco', 'delete from public.shop_items') like '%permission denied%', 'H5: nessuna cancellazione del catalogo';
  assert pg_temp.err_auth('Marco', format('insert into public.shop_purchases (user_id,item_id,category,item_name,price_paid,client_request_id) values (%L,''pet_drago_apocalittico'',''pet'',''x'',1,''12345678'')', pg_temp.uid('Marco'))) like '%permission denied%', 'H5: nessun regalo di premi dal client';
  assert pg_temp.err_auth('Marco', format('update public.shop_purchases set price_paid = 1 where id = %L', pid)) like '%permission denied%', 'H5: nessuna modifica degli acquisti dal client';
  assert pg_temp.err_auth('Marco', 'delete from public.shop_purchases') like '%permission denied%', 'H5: nessuna cancellazione di acquisti dal client';
  assert pg_temp.err_auth('Marco', format('insert into public.shop_equipped (user_id,category,item_id) values (%L,''pet'',''pet_drago_apocalittico'')', pg_temp.uid('Marco'))) like '%permission denied%', 'H5: nessun equipaggiamento diretto';
  assert pg_temp.err_auth('Marco', 'update public.wallets set balance = 99999') like '%permission denied%', 'H5: nessuna modifica diretta del wallet';
  assert pg_temp.err_auth('Marco', 'insert into public.ledger_entries (user_id, amount, kind, idempotency_key, balance_after) values (gen_random_uuid(), 500, ''shop_purchase'', ''x1'', 500)') like '%permission denied%', 'H5: nessun movimento scritto dal client';
  assert pg_temp.err(format('update public.shop_purchases set price_paid = 1 where id = %L', pid)) like '%immutabile%', 'H5: acquisti immutabili (update)';
  assert pg_temp.err('delete from public.shop_purchases') like '%immutabile%', 'H5: acquisti immutabili (delete)';
  assert pg_temp.err('truncate public.shop_purchases') is not null and (select count(*) from public.shop_purchases) > 0, 'H5: gli acquisti non si svuotano (truncate rifiutato)';
  assert pg_temp.err('delete from public.shop_items') is not null, 'H5: i premi non si cancellano';
  assert not has_function_privilege('anon', 'public.shop_buy(text,text,integer)', 'execute') and not has_function_privilege('anon', 'public.shop_equip(text)', 'execute')
     and not has_function_privilege('anon', 'public.admin_shop_save_item(text,text,text,text,text,integer,text,boolean,integer,text)', 'execute'), 'H5: anon non può usare lo Shop';
  assert pg_temp.err_auth('Marco', format('select public._ledger_move(%L, 500, ''shop_purchase'', null, null, ''k9'', ''x'')', pg_temp.uid('Marco'))) like '%permission denied%', 'H5: _ledger_move non è esposta';
  perform pg_temp.save('pet_gelatina', 'Gelatina Cucciola', 'Una piccola creatura gelatinosa che saltella accanto al tuo nome.', 'pet', 'common', 9, 'pet_gelatina', true, 20, 'prezzo di prova');
  assert (select price_paid from public.shop_purchases where id = pid) = 5 and (select amount from public.ledger_entries where ref_id = pid and kind = 'shop_purchase') = -5, 'H5: la modifica del prezzo non cambia acquisti e registro già conclusi';
  assert (pg_temp.buy('Povero', 'pet_gelatina')->>'price')::int = 9, 'H5: i nuovi acquisti usano il nuovo prezzo';
  perform pg_temp.save('pet_gelatina', 'Gelatina Cucciola', 'Una piccola creatura gelatinosa che saltella accanto al tuo nome.', 'pet', 'common', 5, 'pet_gelatina', true, 20, 'ripristino prezzo');
  insert into t_log (msg) values ('OK H5 — nessuna scrittura diretta su prezzi, acquisti, inventario, equipaggiamento, wallet e registro; acquisti immutabili; il listino non riscrive il passato');
end $$;

-- H6 — Equipaggiamento: solo posseduti, uno per categoria, persistenza, visibilità pubblica
do $$
begin
  perform pg_temp.buy('Marco', 'aura_bagliore'); perform pg_temp.buy('Marco', 'titolo_notturno');
  assert pg_temp.err_as('Marco', 'select public.shop_equip(''pet_drago_apocalittico'')') like '%Non possiedi%', 'H6: non si equipaggia ciò che non si possiede';
  assert pg_temp.err_as('Marco', 'select public.shop_equip(''non_esiste'')') like '%Non possiedi%', 'H6: né un premio inesistente';
  perform pg_temp.as_('Marco');
  perform public.shop_equip('pet_gelatina'); perform public.shop_equip('aura_bagliore'); perform public.shop_equip('titolo_notturno');
  assert (select count(*) from public.shop_equipped where user_id = pg_temp.uid('Marco')) = 3, 'H6: tre categorie, tre slot';
  perform pg_temp.buy('Paolo', 'pet_gelatina'); perform pg_temp.buy('Paolo', 'pet_fantasmino');
  perform pg_temp.as_('Paolo'); perform public.shop_equip('pet_gelatina'); perform public.shop_equip('pet_fantasmino');
  assert (select item_id from public.shop_equipped where user_id = pg_temp.uid('Paolo') and category = 'pet') = 'pet_fantasmino', 'H6: il nuovo pet sostituisce il precedente';
  assert (select count(*) from public.shop_equipped where user_id = pg_temp.uid('Paolo') and category = 'pet') = 1, 'H6: un solo pet equipaggiato';
  assert (select count(*) from public.shop_purchases where user_id = pg_temp.uid('Paolo') and category = 'pet') = 2, 'H6: entrambi i pet restano posseduti';
  perform public.shop_equip('pet_gelatina');
  assert (select item_id from public.shop_equipped where user_id = pg_temp.uid('Paolo') and category = 'pet') = 'pet_gelatina', 'H6: si può rimettere il pet precedente';
  perform public.shop_unequip('pet');
  assert not exists (select 1 from public.shop_equipped where user_id = pg_temp.uid('Paolo') and category = 'pet'), 'H6: rimosso dal profilo';
  assert (select count(*) from public.shop_purchases where user_id = pg_temp.uid('Paolo') and category = 'pet') = 2, 'H6: rimuovere non fa perdere la proprietà';
  perform public.shop_unequip('pet');
  perform public.shop_equip('pet_fantasmino');
  assert pg_temp.rows_as('Luca', format('select * from public.shop_equipped_v where user_id = %L', pg_temp.uid('Marco'))) = 3, 'H6: gli altri vedono gli oggetti equipaggiati di Marco';
  assert (select count(*) from public.shop_equipped_v where user_id = pg_temp.uid('Paolo') and asset = 'pet_fantasmino') = 1, 'H6: e quello di Paolo';
  assert pg_temp.rows_as('Luca', format('select * from public.shop_purchases where user_id = %L', pg_temp.uid('Marco'))) = 0, 'H6: ma non gli acquisti altrui';
  assert pg_temp.rows_as('Marco', format('select * from public.shop_purchases where user_id = %L', pg_temp.uid('Marco'))) >= 5, 'H6: ognuno vede i propri acquisti';
  assert pg_temp.rows_as('Admin', 'select * from public.shop_purchases') = (select count(*) from public.shop_purchases), 'H6: l''amministratore vede tutti gli acquisti';
  perform pg_temp.save('aura_bagliore', 'Bagliore Tenue', 'Un alone morbido e discreto attorno al tuo profilo.', 'aura', 'common', 30, 'aura_bagliore', false, 100, 'disattivazione di prova');
  assert (select count(*) from public.shop_purchases where user_id = pg_temp.uid('Marco') and item_id = 'aura_bagliore') = 1, 'H6: il premio disattivato resta nell''inventario';
  assert (select count(*) from public.shop_equipped where user_id = pg_temp.uid('Marco') and item_id = 'aura_bagliore') = 1, 'H6: e resta equipaggiato';
  perform pg_temp.as_('Marco'); perform public.shop_unequip('aura'); perform public.shop_equip('aura_bagliore');
  assert (select count(*) from public.shop_equipped where user_id = pg_temp.uid('Marco') and category = 'aura') = 1, 'H6: un premio disattivato si può ancora riequipaggiare';
  perform pg_temp.save('aura_bagliore', 'Bagliore Tenue', 'Un alone morbido e discreto attorno al tuo profilo.', 'aura', 'common', 30, 'aura_bagliore', true, 100, 'riattivazione di prova');
  insert into t_log (msg) values ('OK H6 — equipaggiamento: solo posseduti, uno slot per categoria, sostituire/rimuovere non fa perdere nulla, equipaggiati pubblici (acquisti no), premi disattivati restano posseduti');
end $$;

-- H7 — Amministrazione: permessi, validazioni, audit, storico
do $$
declare a0 bigint; o jsonb; nw jsonb;
begin
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Paolo'), 'moderator', 'moderatore di prova');
  assert pg_temp.err_as('Marco', 'select public.admin_shop_save_item(''pet_gelatina'',''Gelatina'',''Descrizione di prova'',''pet'',''common'',3,''pet_gelatina'',true,1,''tentativo'')') like '%Permessi insufficienti%', 'H7: un duellante non gestisce il catalogo';
  assert pg_temp.err_as('Org', 'select public.admin_shop_save_item(''pet_gelatina'',''Gelatina'',''Descrizione di prova'',''pet'',''common'',3,''pet_gelatina'',true,1,''tentativo'')') like '%Permessi insufficienti%', 'H7: né un organizzatore';
  assert pg_temp.err_as('Paolo', 'select public.admin_shop_save_item(''pet_gelatina'',''Gelatina'',''Descrizione di prova'',''pet'',''common'',3,''pet_gelatina'',true,1,''tentativo'')') like '%Permessi insufficienti%', 'H7: né un moderatore';
  perform pg_temp.as_('Admin');
  assert pg_temp.err('select public.admin_shop_save_item(''pet_gelatina'',''Gelatina'',''Descrizione di prova'',''pet'',''common'',3,''pet_gelatina'',true,1,'''')') like '%Motivazione obbligatoria%', 'H7: motivazione obbligatoria';
  assert pg_temp.err('select public.admin_shop_save_item(''pet_gelatina'',''Gelatina'',''Descrizione di prova'',''pet'',''common'',60,''pet_gelatina'',true,1,''prezzo fuori fascia'')') like '%shop_items_price_by_rarity%', 'H7: prezzo fuori dalla fascia della rarità rifiutato';
  assert pg_temp.err('select public.admin_shop_save_item(''pet_gelatina'',''Gelatina'',''Descrizione di prova'',''aura'',''common'',3,''pet_gelatina'',true,1,''cambio categoria'')') like '%categoria%', 'H7: la categoria non si cambia';
  a0 := (select count(*) from public.audit_logs where entity = 'shop_item');
  perform public.admin_shop_save_item('pet_nuovo_test', 'Cucciolo di Prova', 'Un premio creato dall''amministratore per provare.', 'pet', 'rare', 70, 'pet_gelatina', true, 5, 'creazione di prova');
  assert (select price from public.shop_items where id = 'pet_nuovo_test') = 70 and (select count(*) from public.audit_logs where entity = 'shop_item' and action = 'shop_item_create' and entity_id = 'pet_nuovo_test') = 1, 'H7: premio creato e tracciato';
  perform pg_temp.buy('Marco', 'pet_nuovo_test');
  perform pg_temp.save('pet_nuovo_test', 'Cucciolo Modificato', 'Una nuova descrizione, ora più bella.', 'pet', 'epic', 200, 'pet_fantasmino', true, 5, 'modifica di prova');
  select old_value, new_value into o, nw from public.audit_logs where entity = 'shop_item' and entity_id = 'pet_nuovo_test' and action = 'shop_item_update' order by id desc limit 1;
  assert (o->>'price')::int = 70 and (nw->>'price')::int = 200 and o->>'rarity' = 'rare' and nw->>'rarity' = 'epic' and o->>'asset' = 'pet_gelatina' and nw->>'asset' = 'pet_fantasmino', 'H7: audit con valori prima e dopo';
  assert (select reason from public.audit_logs where entity = 'shop_item' and entity_id = 'pet_nuovo_test' and action = 'shop_item_update') = 'modifica di prova', 'H7: motivazione nell''audit';
  perform pg_temp.save('pet_nuovo_test', 'Cucciolo Modificato', 'Una nuova descrizione, ora più bella.', 'pet', 'epic', 200, 'pet_fantasmino', false, 5, 'disattivazione di prova');
  assert (select count(*) from public.audit_logs where entity = 'shop_item' and entity_id = 'pet_nuovo_test' and action = 'shop_item_deactivate') = 1, 'H7: disattivazione tracciata';
  assert (select price_paid from public.shop_purchases where user_id = pg_temp.uid('Marco') and item_id = 'pet_nuovo_test') = 70 and (select count(*) from public.shop_purchases where item_id = 'pet_nuovo_test') = 1, 'H7: l''acquisto di Marco resta a 70 BC e al suo posto';
  assert (select count(*) from public.audit_logs where entity = 'shop_item') >= a0 + 3, 'H7: storico delle modifiche consultabile';
  assert pg_temp.rows_as('Marco', 'select * from public.audit_logs') = 0, 'H7: l''audit non è leggibile dai duellanti';
  assert pg_temp.err('delete from public.shop_items where id = ''pet_nuovo_test''') is not null, 'H7: nessuna cancellazione di premi, nemmeno disattivati';
  insert into t_log (msg) values ('OK H7 — amministrazione: solo admin, motivazione obbligatoria, fasce di prezzo e categoria protette, audit con valori prima/dopo, acquisti già fatti intatti');
end $$;

-- H8 — Compatibilità con wallet, taglie, Ladder e Most Wanted
do $$
declare ev uuid; m uuid; r jsonb; w0 integer; rw jsonb;
begin
  w0 := pg_temp.bal('Marco');
  perform pg_temp.as_('Marco');
  perform public.create_bounty(pg_temp.uid('Povero'), 100, null, 'shop-compat-1');
  assert pg_temp.bal('Marco') = w0 - 100, 'H8: la taglia usa il saldo rimasto dopo lo Shop';
  ev := pg_temp.ev('Torneo shop'); m := pg_temp.mm(ev, 1, 'Paolo', 'Povero', 'Paolo');
  perform pg_temp.as_('Paolo'); r := public.claim_bounty(m);
  assert (r->>'payout')::int = 100, 'H8: riscossione normale dopo gli acquisti';
  assert (pg_temp.buy('Paolo', 'emblema_stella')->>'balance')::int = pg_temp.bal('Paolo'), 'H8: il pagamento ricevuto si può spendere nello Shop';
  perform pg_temp.mod('ladder', true);
  rw := pg_temp.play('Marco', 'Povero', 'challenger', '2-0', 'Marco');
  assert (rw->>'reward')::int = 20, 'H8: la Ladder premia ancora 20 BC';
  assert pg_temp.bal('Marco') = w0 - 100 + 20, 'H8: il premio Ladder è nel wallet accanto agli acquisti';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'H8: saldi = registro dopo taglie, riscossioni, Ladder e Shop';
  assert not exists (select 1 from public.wallets where balance < 0), 'H8: nessun saldo negativo';
  assert (select coalesce(sum(amount),0) from public.ledger_entries) = (select coalesce(sum(balance),0) from public.wallets), 'H8: somma del registro = somma dei saldi';
  assert (select count(*) from public.ledger_entries where kind = 'shop_purchase' and amount >= 0) = 0, 'H8: gli acquisti sono sempre addebiti';
  assert (select count(*) from public.most_wanted_v) >= 0, 'H8: Most Wanted ancora leggibile';
  insert into t_log (msg) values ('OK H8 — compatibilità: taglie, riscossioni, Ladder e wallet funzionano insieme agli acquisti; somma del registro = somma dei saldi; gli acquisti sono solo addebiti');
end $$;

select n, msg from t_log order by n;
rollback;
