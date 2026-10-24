-- =====================================================================
-- TEST DEI 60 NUOVI PREMI DELLO SHOP (black-market-shop-extra.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-shop.sql e black-market-shop-extra.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) or exists (select 1 from public.shop_purchases) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create temp table t_new (id text);
insert into t_new select unnest(array['xe_guardiano', 'xf_rovi', 'xx_scintille', 'xe_mago', 'xt_cacciatore', 'xp_pipistrello', 'xa_braci', 'xp_golem', 'xe_spada', 'xt_custode', 'xf_rune', 'xx_piume', 'xa_druidica', 'xt_stregone', 'xp_volpe', 'xe_occhio', 'xf_ghiaccio', 'xp_cavaliere', 'xa_gelida', 'xp_lupo', 'xe_stella', 'xt_signore', 'xa_tempesta', 'xf_drago', 'xx_fulmini', 'xp_grifone', 'xe_corona', 'xt_eroe', 'xp_sfinge', 'xf_fulmini', 'xx_neve', 'xa_sacra', 'xp_idra', 'xe_ali', 'xa_infernale', 'xt_caos', 'xf_millennio', 'xp_drago_cremisi', 'xe_teschio', 'xp_cerbero', 'xx_meteore', 'xf_infernale', 'xt_re', 'xp_leviatano', 'xa_astrale', 'xe_drago', 'xa_caos', 'xt_imperatore', 'xp_arcidemone', 'xf_siderale', 'xe_infinito', 'xx_anime', 'xp_drago_cosmico', 'xt_dio', 'xf_vuoto', 'xa_galattica', 'xf_eclissi', 'xa_singolarita', 'xp_ouroboros', 'xt_sovrano']);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-shop-extra-' || n)::uuid $$;
create function pg_temp.act(u uuid) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_(n text) returns text language sql as $$ select pg_temp.act(pg_temp.uid(n)) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return null; exception when others then return sqlerrm; end $$;
-- esegue una query come utente autenticato e restituisce il messaggio d'errore (null se riesce); il ruolo viene sempre ripristinato
create function pg_temp.err_auth(n text, q text) returns text language plpgsql as $$
begin
  perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end;
end $$;
-- esegue una query come utente autenticato e CONSERVA gli effetti (se fallisce, il test si ferma con l'errore vero)
create function pg_temp.do_auth(n text, q text) returns void language plpgsql as $$
begin perform pg_temp.as_(n); execute 'set local role authenticated'; execute q; execute 'reset role'; end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;

do $$
declare n text;
begin
  foreach n in array array['Admin','Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin');
  perform public.admin_adjust_balance(pg_temp.uid('Ann'), 6000, 'Fondi di prova per i test dello Shop');
  insert into t_log (msg) values ('OK Preparazione: 3 utenti (Admin = primo registrato), Ann con 6.300 BC, Bob con il solo bonus iniziale');
end $$;

-- ===== X1 catalogo =====
do $$
declare bad bigint;
begin
  assert (select count(*) from public.shop_items) = 99, 'X1: 39 premi di prima + 60 nuovi = 99';
  assert (select count(*) from public.shop_items i join t_new using (id)) = 60, 'X1: tutti i 60 premi nuovi sono nel catalogo';
  assert (select count(*) from public.shop_items where id in ('pet_gelatina','titolo_novizio','cornice_eclissi','pet_drago_apocalittico') and active) = 4, 'X1: i premi di prima ci sono ancora e sono in vendita';
  assert (select price from public.shop_items where id = 'titolo_novizio') = 2 and (select price from public.shop_items where id = 'pet_drago_apocalittico') = 1000
     and (select rarity from public.shop_items where id = 'pet_drago_apocalittico') = 'mythic', 'X1: prezzi e rarità dei premi di prima invariati';
  assert (select count(*) from public.shop_items i join t_new using (id) where category = 'pet') = 14
     and (select count(*) from public.shop_items i join t_new using (id) where category = 'frame') = 10
     and (select count(*) from public.shop_items i join t_new using (id) where category = 'aura') = 10
     and (select count(*) from public.shop_items i join t_new using (id) where category = 'emblem') = 10
     and (select count(*) from public.shop_items i join t_new using (id) where category = 'title') = 10
     and (select count(*) from public.shop_items i join t_new using (id) where category = 'effect') = 6, 'X1: 14 pet, 10 cornici, 10 aure, 10 emblemi, 10 titoli, 6 effetti';
  assert (select count(*) from public.shop_items i join t_new using (id) where rarity = 'divine') = 4
     and (select min(price) from public.shop_items where rarity = 'divine') >= 1001 and (select max(price) from public.shop_items where rarity = 'divine') <= 5000, 'X1: 4 premi Divini tra 1.001 e 5.000 BC';
  assert (select count(*) from public.shop_items i join t_new using (id) where rarity = 'common') = 8
     and (select count(*) from public.shop_items i join t_new using (id) where rarity = 'rare') = 12
     and (select count(*) from public.shop_items i join t_new using (id) where rarity = 'epic') = 13
     and (select count(*) from public.shop_items i join t_new using (id) where rarity = 'legendary') = 12
     and (select count(*) from public.shop_items i join t_new using (id) where rarity = 'mythic') = 11, 'X1: distribuzione per rarità';
  select count(*) into bad from public.shop_items n join t_new using (id) join public.shop_items o on o.price = n.price and o.id <> n.id and o.id not in (select id from t_new);
  assert bad = 0, 'X1: nessun prezzo nuovo uguale a un prezzo già presente';
  select count(*) into bad from public.shop_items n join t_new using (id) join public.shop_items o on lower(o.name) = lower(n.name) and o.id <> n.id;
  assert bad = 0, 'X1: nessun nome uguale a un altro premio';
  assert (select count(distinct price) from public.shop_items i join t_new using (id)) = 60, 'X1: i 60 prezzi nuovi sono tutti diversi';
  assert (select count(*) from public.shop_items i join t_new using (id) where active and asset = id and sort >= 400) = 60, 'X1: attivi, asset = codice, ordine dopo i premi di prima';
  assert (select count(distinct sort) from public.shop_items) = 99, 'X1: ordine univoco';
  insert into t_log (msg) values ('OK X1: 99 premi, 60 nuovi per categoria/rarità/prezzo, nessun doppione di nome o prezzo, quelli di prima intatti');
end $$;

-- ===== X2 fasce di prezzo e rarità =====
do $$
declare s text;
begin
  s := pg_temp.err($q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_div_lo', 'Divino basso', 'Prova prezzo troppo basso', 'pet', 'divine', 1000, 't_div_lo') $q$);
  assert s like '%shop_items_price_by_rarity%', 'X2: Divino a 1.000 BC rifiutato: ' || coalesce(s, 'riuscito');
  s := pg_temp.err($q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_div_hi', 'Divino alto', 'Prova prezzo troppo alto', 'pet', 'divine', 5001, 't_div_hi') $q$);
  assert s like '%shop_items_price_by_rarity%', 'X2: Divino a 5.001 BC rifiutato';
  s := pg_temp.err($q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_myt_hi', 'Mitico alto', 'Il Mitico non supera 1000', 'pet', 'mythic', 1001, 't_myt_hi') $q$);
  assert s like '%shop_items_price_by_rarity%', 'X2: Mitico a 1.001 BC rifiutato (le fasce di prima non cambiano)';
  s := pg_temp.err($q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_com_hi', 'Comune caro', 'Il Comune non supera 49', 'pet', 'common', 50, 't_com_hi') $q$);
  assert s like '%shop_items_price_by_rarity%', 'X2: Comune a 50 BC rifiutato';
  s := pg_temp.err($q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_god', 'Rarità inventata', 'Una rarità che non esiste', 'pet', 'god', 2000, 't_god') $q$);
  assert s like '%shop_items_rarity_check%' or s like '%shop_items_price_by_rarity%', 'X2: rarità inventata rifiutata';
  s := pg_temp.err($q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_div_ok1', 'Divino minimo', 'Estremo basso della fascia', 'pet', 'divine', 1001, 't_div_ok1'), ('t_div_ok2', 'Divino massimo', 'Estremo alto della fascia', 'pet', 'divine', 5000, 't_div_ok2') $q$);
  assert s is null, 'X2: Divino a 1.001 e 5.000 BC accettato: ' || coalesce(s, '');
  delete from public.shop_items where false;
  assert (select count(*) from pg_constraint where conrelid = 'public.shop_items'::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ 'rarity') = 2, 'X2: due soli vincoli sulla rarità';
  insert into t_log (msg) values ('OK X2: Divino 1.001–5.000 (estremi inclusi), fuori fascia rifiutato, fasce di prima intatte, rarità inventate rifiutate');
end $$;

-- ===== X3 acquisti dei premi nuovi =====
do $$
declare r jsonb; b0 integer; l0 bigint; s text;
begin
  perform pg_temp.as_('Ann'); b0 := pg_temp.bal('Ann');
  execute 'set local role authenticated';
  r := public.shop_buy('xt_cacciatore', 'req-ann-0001', 36);
  execute 'reset role';
  assert (r->>'already')::boolean = false and (r->>'price')::int = 36 and (r->>'balance')::int = b0 - 36, 'X3: acquisto titolo comune a 36 BC';
  assert pg_temp.bal('Ann') = b0 - 36, 'X3: saldo di Ann scalato di 36';
  assert (select amount from public.ledger_entries where kind = 'shop_purchase' and user_id = pg_temp.uid('Ann') order by id desc limit 1) = -36, 'X3: movimento -36 nel registro';
  -- Divino
  perform pg_temp.as_('Ann'); b0 := pg_temp.bal('Ann');
  execute 'set local role authenticated';
  r := public.shop_buy('xp_ouroboros', 'req-ann-0002', 2500);
  execute 'reset role';
  assert (r->>'price')::int = 2500 and pg_temp.bal('Ann') = b0 - 2500, 'X3: acquisto del pet Divino a 2.500 BC';
  assert (select price_paid from public.shop_purchases where user_id = pg_temp.uid('Ann') and item_id = 'xp_ouroboros') = 2500, 'X3: prezzo pagato registrato';
  -- richiesta ripetuta: nessun secondo addebito
  perform pg_temp.as_('Ann'); b0 := pg_temp.bal('Ann');
  execute 'set local role authenticated';
  r := public.shop_buy('xp_ouroboros', 'req-ann-0002', 2500);
  execute 'reset role';
  assert (r->>'already')::boolean and pg_temp.bal('Ann') = b0, 'X3: richiesta ripetuta = nessun secondo addebito';
  s := pg_temp.err_auth('Ann', $q$ select public.shop_buy('xp_ouroboros', 'req-ann-0003', 2500) $q$);
  assert s like '%Possiedi già%', 'X3: lo stesso premio non si compra due volte: ' || coalesce(s, 'riuscito');
  s := pg_temp.err_auth('Ann', $q$ select public.shop_buy('xp_idra', 'req-ann-0004', 100) $q$);
  assert s like '%prezzo è cambiato%', 'X3: prezzo atteso diverso = rifiutato';
  assert not exists (select 1 from public.shop_purchases where item_id = 'xp_idra'), 'X3: nulla comprato col prezzo sbagliato';
  -- saldo insufficiente (Bob ha solo il bonus iniziale)
  b0 := pg_temp.bal('Bob');
  select count(*) into l0 from public.ledger_entries where user_id = pg_temp.uid('Bob');
  s := pg_temp.err_auth('Bob', $q$ select public.shop_buy('xa_singolarita', 'req-bob-0001', 2200) $q$);
  assert s like '%Saldo insufficiente%', 'X3: Bob non può pagare un premio Divino: ' || coalesce(s, 'riuscito');
  assert pg_temp.bal('Bob') = b0 and (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Bob')) = l0
     and not exists (select 1 from public.shop_purchases where user_id = pg_temp.uid('Bob')), 'X3: rifiuto = nessun addebito, nessun premio, nessun movimento';
  -- Bob compra un premio alla sua portata
  perform pg_temp.as_('Bob'); execute 'set local role authenticated';
  r := public.shop_buy('xe_guardiano', 'req-bob-0002', 19);
  execute 'reset role';
  assert pg_temp.bal('Bob') = b0 - 19, 'X3: Bob compra l''emblema da 19 BC';
  -- conservazione
  assert (select coalesce(sum(-amount), 0) from public.ledger_entries where kind = 'shop_purchase') = (select sum(price_paid) from public.shop_purchases), 'X3: i movimenti dello Shop coincidono con i prezzi pagati';
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'X3: somma dei saldi = somma dei movimenti';
  insert into t_log (msg) values ('OK X3: acquisti (anche Divino), richiesta ripetuta, doppio acquisto, prezzo cambiato, saldo insufficiente, conservazione dei BC');
end $$;

-- ===== X4 equipaggiamento =====
do $$
declare s text;
begin
  perform pg_temp.as_('Ann'); execute 'set local role authenticated';
  perform public.shop_equip('xp_ouroboros'); perform public.shop_equip('xt_cacciatore');
  execute 'reset role';
  assert (select rarity from public.shop_equipped_v where user_id = pg_temp.uid('Ann') and category = 'pet') = 'divine'
     and (select asset from public.shop_equipped_v where user_id = pg_temp.uid('Ann') and category = 'pet') = 'xp_ouroboros', 'X4: la vista pubblica mostra il pet Divino equipaggiato';
  assert (select count(*) from public.shop_equipped where user_id = pg_temp.uid('Ann')) = 2, 'X4: due slot occupati';
  s := pg_temp.err_auth('Bob', $q$ select public.shop_equip('xp_idra') $q$);
  assert s like '%Non possiedi%', 'X4: non si equipaggia ciò che non si possiede';
  perform pg_temp.as_('Ann'); execute 'set local role authenticated';
  perform public.shop_unequip('pet');
  execute 'reset role';
  assert not exists (select 1 from public.shop_equipped where user_id = pg_temp.uid('Ann') and category = 'pet')
     and exists (select 1 from public.shop_purchases where user_id = pg_temp.uid('Ann') and item_id = 'xp_ouroboros'), 'X4: togliere dal profilo non fa perdere il premio';
  -- un altro utente vede gli oggetti equipaggiati di Ann (sono pubblici)
  perform pg_temp.as_('Bob'); execute 'set local role authenticated';
  assert (select count(*) from public.shop_equipped_v where user_id = pg_temp.uid('Ann')) = 1, 'X4: Bob vede il titolo equipaggiato di Ann';
  assert (select count(*) from public.shop_purchases where user_id = pg_temp.uid('Ann')) = 0, 'X4: Bob non vede gli acquisti di Ann';
  execute 'reset role';
  insert into t_log (msg) values ('OK X4: equipaggia/rimuovi, vista pubblica con rarità Divino, solo ciò che si possiede, acquisti privati');
end $$;

-- ===== X5 gestione del catalogo (solo admin) =====
do $$
declare s text;
begin
  s := pg_temp.err_auth('Ann', $q$ select public.admin_shop_save_item('t_nuovo', 'Premio di prova', 'Descrizione di prova', 'pet', 'divine', 1500, 't_nuovo', true, 500, 'Prova dei permessi') $q$);
  assert s is not null and s not like '%RIUSCITA%', 'X5: un utente comune non può creare premi: ' || coalesce(s, 'riuscito');
  s := pg_temp.err_auth('Admin', $q$ select public.admin_shop_save_item('t_nuovo', 'Premio di prova', 'Descrizione di prova', 'pet', 'divine', 1500, 't_nuovo', true, 500, 'ok') $q$);
  assert s like '%Motivazione%', 'X5: serve la motivazione';
  perform pg_temp.do_auth('Admin', $q$ select public.admin_shop_save_item('t_nuovo', 'Premio di prova', 'Descrizione di prova', 'pet', 'divine', 1500, 't_nuovo', true, 500, 'Creo un premio Divino di prova') $q$);
  assert (select rarity from public.shop_items where id = 't_nuovo') = 'divine', 'X5: l''admin crea un premio Divino';
  s := pg_temp.err_auth('Admin', $q$ select public.admin_shop_save_item('t_nuovo', 'Premio di prova', 'Descrizione di prova', 'pet', 'divine', 900, 't_nuovo', true, 500, 'Prezzo fuori fascia') $q$);
  assert s like '%shop_items_price_by_rarity%', 'X5: prezzo Divino sotto la fascia rifiutato anche dall''admin';
  perform pg_temp.do_auth('Admin', $q$ select public.admin_shop_save_item('t_nuovo', 'Premio di prova', 'Descrizione di prova', 'pet', 'mythic', 900, 't_nuovo', true, 500, 'Passa a Mitico') $q$);
  assert (select rarity from public.shop_items where id = 't_nuovo') = 'mythic' and (select price from public.shop_items where id = 't_nuovo') = 900, 'X5: cambio rarità + prezzo coerenti';
  s := pg_temp.err_auth('Admin', $q$ select public.admin_shop_save_item('t_nuovo', 'Premio di prova', 'Descrizione di prova', 'title', 'mythic', 900, 't_nuovo', true, 500, 'Cambio categoria vietato') $q$);
  assert s like '%categoria%', 'X5: la categoria non si cambia: ' || coalesce(s, 'riuscito');
  -- cambio prezzo di un premio già comprato: vale solo per i nuovi acquisti
  perform pg_temp.as_('Admin');
  perform public.admin_shop_save_item('xp_ouroboros', 'Ouroboros Cosmico', (select description from public.shop_items where id = 'xp_ouroboros'), 'pet', 'divine', 2600, 'xp_ouroboros', true, (select sort from public.shop_items where id = 'xp_ouroboros'), 'Ritocco prezzo di prova');
  assert (select price_paid from public.shop_purchases where user_id = pg_temp.uid('Ann') and item_id = 'xp_ouroboros') = 2500, 'X5: il prezzo già pagato non cambia';
  assert (select count(*) from public.audit_logs where entity = 'shop_item' and entity_id in ('t_nuovo', 'xp_ouroboros')) = 3, 'X5: ogni modifica riuscita è nel registro di audit (2 su t_nuovo + 1 su xp_ouroboros)';
  -- disattivazione
  perform public.admin_shop_save_item('xp_idra', 'Idra a Tre Teste', (select description from public.shop_items where id = 'xp_idra'), 'pet', 'epic', (select price from public.shop_items where id = 'xp_idra'), 'xp_idra', false, (select sort from public.shop_items where id = 'xp_idra'), 'Tolgo dalla vendita');
  s := pg_temp.err_auth('Ann', $q$ select public.shop_buy('xp_idra', 'req-ann-0005', null) $q$);
  assert s like '%non è disponibile%', 'X5: un premio disattivato non si compra';
  -- Shop chiuso
  update public.system_settings set value_int = 0 where key = 'shop_enabled';
  s := pg_temp.err_auth('Ann', $q$ select public.shop_buy('xp_golem', 'req-ann-0006', 47) $q$);
  assert s like '%chiuso%', 'X5: con lo Shop chiuso non si compra';
  update public.system_settings set value_int = 1 where key = 'shop_enabled';
  insert into t_log (msg) values ('OK X5: solo admin, motivazione, fasce rispettate, categoria bloccata, prezzo pagato invariato, audit, disattivazione, Shop chiuso');
end $$;

-- ===== X6 integrità =====
do $$
declare s text;
begin
  s := pg_temp.err($q$ delete from public.shop_items where id = 'xp_golem' $q$);
  assert s is not null, 'X6: i premi non si cancellano';
  s := pg_temp.err($q$ update public.shop_purchases set price_paid = 1 $q$);
  assert s is not null, 'X6: gli acquisti non si modificano';
  s := pg_temp.err_auth('Ann', $q$ insert into public.shop_items (id, name, description, category, rarity, price, asset) values ('t_hack', 'Hack', 'Inserimento diretto', 'pet', 'common', 5, 't_hack') $q$);
  assert s like '%permission denied%', 'X6: un utente non scrive nel catalogo: ' || coalesce(s, 'riuscito');
  s := pg_temp.err_auth('Ann', $q$ update public.shop_items set price = 2 where id = 'xp_golem' $q$);
  assert s like '%permission denied%', 'X6: un utente non cambia i prezzi';
  assert (select count(*) from public.shop_items) = 99 + 2 + 1, 'X6: nel catalogo solo i premi attesi (99 + 2 di prova in X2 + 1 creato in X5)';
  insert into t_log (msg) values ('OK X6: nessuna cancellazione, acquisti immutabili, catalogo scrivibile solo dalle funzioni');
end $$;

select msg from t_log order by n;
rollback;
