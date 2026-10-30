-- =====================================================================
-- TEST DELLA MIGRAZIONE 031 (La guerra degli Eroi: Lo stagno, pet companion)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni della guerra degli Eroi e la 031 (black-market-eroi-stagno.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
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


-- Preparazione: Admin (primo registrato), Org organizzatore, e 6 duellanti
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Eve','Fay'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova');
  insert into t_log (msg) values ('OK Preparazione: 8 utenti');
end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.tot() returns bigint language sql as $$ select coalesce(sum(balance), 0) from public.wallets $$;
create function pg_temp.st(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
create function pg_temp.setst(n text, f integer, d integer, v integer, s integer, r integer) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_set_stats(f, d, v, s, r); end $$;
create function pg_temp.lvl(n text, l integer) returns void language sql as $$ update public.game_heroes set level = l, xp = 0 where user_id = pg_temp.uid(n) $$;
create function pg_temp.hero(n text) returns public.game_heroes language sql as $$ select * from public.game_heroes where user_id = pg_temp.uid(n) $$;
create function pg_temp.act(n text, a text, t text default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_boss_act(a, case when t is null then null else pg_temp.uid(t) end); end $$;
create function pg_temp.duel(a text, b text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(a); return public.game_duel(pg_temp.uid(b)); end $$;
create function pg_temp.mod(on_ boolean) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', on_, 'prova del modulo'); end $$;
-- ---------- supporto ----------
create function pg_temp.bal_(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.gift(n text, amt integer) returns void language sql as $$
  select public._ledger_move(pg_temp.uid(n), amt, 'admin_adjustment', 'test', gen_random_uuid(), 'gift:' || gen_random_uuid()::text, 'regalo di prova') $$;
create function pg_temp.hero_(n text, l integer, f integer, d integer, v integer, s integer, r integer) returns void language sql as $$
  update public.game_heroes set level = l, xp = 0, a_for = f, a_des = d, a_vig = v, a_spi = s, a_frt = r, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid(n) $$;
create function pg_temp.fill(n text) returns void language sql as $$ update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid(n) $$;
create function pg_temp.pst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_pet_state(); end $$;
create function pg_temp.choose(n text, p text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_pet_choose(p); end $$;
create function pg_temp.buy(n text, p text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_pet_buy(p); end $$;
create function pg_temp.activate(n text, p text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_pet_activate(p); end $$;
create function pg_temp.gst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
create function pg_temp.petlv(n text, p text, l integer) returns void language sql as $$ update public.game_hero_pets set level = l, xp = 0 where user_id = pg_temp.uid(n) and pet_id = p $$;
create function pg_temp.pet(n text, p text) returns public.game_hero_pets language sql as $$ select * from public.game_hero_pets where user_id = pg_temp.uid(n) and pet_id = p $$;
create function pg_temp.climb(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_tower_climb(); end $$;
create function pg_temp.sure_win() returns void language sql as $$ update public.system_settings set value_int = 1 where key = 'game_tower_difficulty' $$;
create function pg_temp.normal() returns void language sql as $$ update public.system_settings set value_int = 100 where key = 'game_tower_difficulty' $$;
create function pg_temp.addxp(n text, x bigint) returns jsonb language sql as $$ select public._game_add_xp(pg_temp.uid(n), x) $$;
create function pg_temp.pb(n text) returns jsonb language sql as $$ select to_jsonb(x) from public._game_pet_bonus(pg_temp.uid(n)) x $$;
create function pg_temp.bon(n text, st text) returns integer language plpgsql as $$
declare r integer; begin execute format('select b_%s from public._game_calc(%L)', st, pg_temp.uid(n)) into r; return r; end $$;
do $$ declare n text; begin
  foreach n in array array['Ann','Bob','Cid','Dan'] loop perform public._game_ensure_hero(pg_temp.uid(n)); end loop;
end $$;

-- P1 — catalogo: 30 compagni (3 base gratuiti + 9 gradi da 3), prezzi crescenti, bonus 3/4/5 con sblocchi
do $$
declare t integer; prev integer := -1; r record;
begin
  assert (select count(*) from public.game_pets) = 30 and (select count(*) from public.game_pets where starter) = 3, 'P1: 30 pet, 3 di base';
  assert (select count(distinct sprite) from public.game_pets) = 30 and (select count(distinct name) from public.game_pets) = 30 and (select count(distinct no) from public.game_pets) = 30, 'P1: sprite, nomi e numeri tutti diversi';
  assert not exists (select 1 from public.game_pets where starter and (tier <> 0 or price_bc <> 0)), 'P1: i tre base sono di grado 0 e gratuiti';
  for t in 1..9 loop
    assert (select count(*) from public.game_pets where tier = t) = 3 and (select array_agg(variant order by variant) from public.game_pets where tier = t) = array['a','b','c'], 'P1: grado ' || t || ': tre pet, uno per stile';
    assert (select count(distinct price_bc) from public.game_pets where tier = t) = 1 and (select min(price_bc) from public.game_pets where tier = t) > prev, 'P1: il prezzo sale con il grado (' || t || ')';
    prev := (select min(price_bc) from public.game_pets where tier = t);
  end loop;
  assert (select array_agg(min_level order by tier) from (select tier, min(min_level) min_level from public.game_pets where tier > 0 group by tier) x) = array[5,15,30,50,80,120,180,260,380], 'P1: livelli richiesti per grado';
  assert (select array_agg(price_bc order by tier) from (select tier, min(price_bc) price_bc from public.game_pets where tier > 0 group by tier) x) = array[1500,4000,9000,20000,45000,90000,180000,350000,700000], 'P1: prezzi per grado';
  for r in select id, tier, (select count(*) from public.game_pet_lines l where l.pet_id = g.id) c, (select min(unlock_level) from public.game_pet_lines l where l.pet_id = g.id) u0 from public.game_pets g loop
    assert r.c = case when r.tier <= 2 then 3 when r.tier <= 6 then 4 else 5 end, 'P1: numero di bonus di ' || r.id;
    assert r.u0 = 1, 'P1: il primo bonus c''è già al livello 1 (' || r.id || ')';
  end loop;
  assert not exists (select 1 from public.game_pet_lines where unlock_level not in (1,10,25,45,70)), 'P1: sblocchi solo ai livelli 1/10/25/45/70';
  -- un grado alto è davvero migliore: somma dei massimi dei bonus statistici crescente con il grado (per stile)
  assert (select bool_and(s2 > s1) from (select a.variant, a.tier, (select sum(max_value) from public.game_pet_lines where pet_id = a.id) s2, (select sum(max_value) from public.game_pet_lines where pet_id = b.id) s1
          from public.game_pets a join public.game_pets b on b.variant = a.variant and b.tier = a.tier - 1) x), 'P1: ogni grado ha bonus complessivi più alti del precedente';
  insert into t_log (msg) values ('OK P1 — catalogo 30 pet, prezzi, livelli richiesti, bonus 3/4/5');
end $$;

-- P2 — tabelle chiuse al browser, funzioni interne non chiamabili, anon escluso
do $$
begin
  assert pg_temp.err_auth('Ann', 'select * from public.game_pets') like '%permission denied%', 'P2: game_pets chiusa';
  assert pg_temp.err_auth('Ann', 'select * from public.game_pet_lines') like '%permission denied%', 'P2: game_pet_lines chiusa';
  assert pg_temp.err_auth('Ann', 'select * from public.game_hero_pets') like '%permission denied%', 'P2: game_hero_pets chiusa';
  assert pg_temp.err_auth('Ann', 'update public.game_hero_pets set level = 100') like '%permission denied%', 'P2: nessun UPDATE diretto';
  assert pg_temp.err_auth('Ann', format('select public._game_pet_gain(%L, 1000)', pg_temp.uid('Ann'))) like '%permission denied for function _game_pet_gain%', 'P2: _game_pet_gain non chiamabile';
  assert pg_temp.err_auth('Ann', format('select * from public._game_pet_bonus(%L)', pg_temp.uid('Ann'))) like '%permission denied for function _game_pet_bonus%', 'P2: _game_pet_bonus non chiamabile';
  assert pg_temp.err_auth('Ann', format('select public._game_pet_card(%L)', pg_temp.uid('Ann'))) like '%permission denied for function _game_pet_card%', 'P2: _game_pet_card non chiamabile';
  assert pg_temp.err_auth('Ann', format('select public._game_add_xp(%L, 1000)', pg_temp.uid('Ann'))) like '%permission denied for function _game_add_xp%', 'P2: _game_add_xp resta interna';
  assert pg_temp.err_auth('Ann', format('select public._game_calc(%L)', pg_temp.uid('Ann'))) like '%permission denied for function _game_calc%', 'P2: _game_calc resta interna';
  assert not has_function_privilege('anon', 'public.game_pet_state()', 'execute') and not has_function_privilege('anon', 'public.game_pet_buy(text)', 'execute')
     and not has_function_privilege('anon', 'public.game_pet_choose(text)', 'execute') and not has_function_privilege('anon', 'public.game_pet_activate(text)', 'execute'), 'P2: anon escluso';
  assert has_function_privilege('authenticated', 'public.game_pet_state()', 'execute') and has_function_privilege('authenticated', 'public.game_pet_buy(text)', 'execute'), 'P2: authenticated può chiamare gli RPC';
  assert pg_temp.err_auth('Ann', 'select public.game_pet_state()') is null, 'P2: lo stato si legge anche col ruolo del browser';
  insert into t_log (msg) values ('OK P2 — accessi: tabelle chiuse, interne non chiamabili');
end $$;

-- P3 — la scelta del pet base: una volta sola, solo tra i tre
do $$
declare s jsonb; c jsonb;
begin
  s := pg_temp.pst('Ann');
  assert (s->>'chosen')::boolean = false and s->'active' = 'null'::jsonb and jsonb_array_length(s->'pets') = 30 and (s->>'xp_pct')::int = 20, 'P3: prima della scelta: nessun pet, 30 in catalogo, XP 20%';
  assert pg_temp.gst('Ann')->'me'->'pet' = 'null'::jsonb, 'P3: senza pet la scheda eroe ha pet = null';
  assert pg_temp.err_as('Ann', 'select pg_temp.buy(''Ann'', ''pet_gatto'')') like '%scegli il tuo compagno base%', 'P3: non si compra prima di aver scelto il base';
  assert pg_temp.err_as('Ann', 'select pg_temp.choose(''Ann'', ''pet_gatto'')') like '%non è tra i tre di base%', 'P3: non si sceglie un pet in vendita';
  assert pg_temp.err_as('Ann', 'select pg_temp.choose(''Ann'', ''pet_inesistente'')') like '%inesistente%', 'P3: pet inesistente';
  c := pg_temp.choose('Ann', 'pet_ranocchio');
  assert c->>'pet' = 'Ranocchio Scintilla' and c->'card'->>'id' = 'pet_ranocchio' and (c->'card'->>'level')::int = 1, 'P3: scelta riuscita, livello 1';
  assert pg_temp.err_as('Ann', 'select pg_temp.choose(''Ann'', ''pet_tartaruga'')') like '%Hai già scelto%', 'P3: la scelta è una sola';
  s := pg_temp.pst('Ann');
  assert (s->>'chosen')::boolean and s->'active'->>'id' = 'pet_ranocchio', 'P3: stato dopo la scelta';
  assert pg_temp.gst('Ann')->'me'->'pet'->>'id' = 'pet_ranocchio' and jsonb_array_length(pg_temp.gst('Ann')->'me'->'pet'->'lines') = 3, 'P3: il pet è nella scheda eroe (cruscotto)';
  assert (select count(*) from public.game_hero_pets where user_id = pg_temp.uid('Ann')) = 1 and (select active from public.game_hero_pets where user_id = pg_temp.uid('Ann')), 'P3: una riga, attiva';
  assert pg_temp.pst('Bob')->>'chosen' = 'false', 'P3: un altro giocatore non ne è toccato';
  insert into t_log (msg) values ('OK P3 — scelta del pet base una sola volta');
end $$;

-- P4 — i bonus: livello 1 = un quarto del massimo solo sulle righe sbloccate; crescono con il livello; si sbloccano a 10 e 25; arrivano in _game_calc
do $$
declare b0 integer; b1 integer; ln record; pbn jsonb;
begin
  -- valori della formula
  assert public._game_pet_value(12, 1, 1, 100) = 3 and public._game_pet_value(12, 1, 100, 100) = 12 and public._game_pet_value(12, 10, 9, 100) = 0 and public._game_pet_value(12, 10, 10, 100) = 3, 'P4: formula: 1/4 allo sblocco, pieno al livello massimo, zero prima';
  assert public._game_pet_value(1, 1, 1, 100) = 1 and public._game_pet_value(5, 70, 70, 100) = 1, 'P4: mai meno di 1 una volta sbloccato';
  assert public._game_pet_value(12, 1, 500, 100) = 12, 'P4: oltre il livello massimo non cresce';
  assert (select bool_and(v2 >= v1) from (select public._game_pet_value(40, 1, l, 100) v1, public._game_pet_value(40, 1, l + 1, 100) v2 from generate_series(1, 99) l) q), 'P4: mai in calo al crescere del livello';
  -- Ann: ranocchio (for 12 / des 9 / vig 6) — senza e con pet
  pbn := pg_temp.pb('Ann');
  assert (pbn->>'pf')::int = 2 and (pbn->>'pd')::int = 0 and (pbn->>'pv')::int = 0, 'P4: livello 1: solo il primo bonus (for 8 → 2)';
  perform pg_temp.petlv('Ann', 'pet_ranocchio', 10); pbn := pg_temp.pb('Ann');
  assert (pbn->>'pd')::int >= 1 and (pbn->>'pv')::int = 0 and (pbn->>'pf')::int >= 2, 'P4: al livello 10 si sblocca il secondo bonus';
  perform pg_temp.petlv('Ann', 'pet_ranocchio', 25); pbn := pg_temp.pb('Ann');
  assert (pbn->>'pv')::int >= 1, 'P4: al livello 25 si sblocca il terzo';
  perform pg_temp.petlv('Ann', 'pet_ranocchio', 100); pbn := pg_temp.pb('Ann');
  assert (pbn->>'pf')::int = 8 and (pbn->>'pd')::int = 6 and (pbn->>'pv')::int = 4, 'P4: al livello 100 i bonus sono al massimo';
  -- integrazione in _game_calc: la differenza con/senza pet è esattamente il bonus
  b1 := pg_temp.bon('Ann', 'for');
  update public.game_hero_pets set active = false where user_id = pg_temp.uid('Ann'); b0 := pg_temp.bon('Ann', 'for');
  update public.game_hero_pets set active = true where user_id = pg_temp.uid('Ann');
  assert b1 - b0 = 8 and pg_temp.bon('Ann', 'des') - (select b_des from public._game_calc(pg_temp.uid('Bob'))) = 6 and pg_temp.bon('Ann', 'vig') - (select b_vig from public._game_calc(pg_temp.uid('Bob'))) = 4, 'P4: i bonus del pet entrano nelle statistiche dell''eroe';
  -- le statistiche reali crescono con il bonus
  assert (select s_for from public._game_calc(pg_temp.uid('Ann'))) >= (select s_for from public._game_calc(pg_temp.uid('Bob'))), 'P4: statistica di forza non inferiore a chi non ha pet';
  -- somma con altri bonus (abilità permanenti): si accumulano
  assert exists (select 1 from public.game_skills where id = 'sk_for_1'), 'P4: abilità disponibili';
  perform pg_temp.gift('Ann', 100000); perform pg_temp.lvl('Ann', 20);
  perform pg_temp.as_('Ann'); perform public.game_buy_skill('sk_for_1');
  assert pg_temp.bon('Ann', 'for') = b1 + (select p_for from public.game_skills where id = 'sk_for_1'), 'P4: il bonus del pet si somma a quello delle abilità';
  -- bonus XP / azioni / ricariche: un pet di alto grado li porta in extra_actions e extra_fights
  perform pg_temp.gift('Bob', 5000000); perform pg_temp.lvl('Bob', 400);
  perform pg_temp.choose('Bob', 'pet_tartaruga');
  assert (select extra_actions from public._game_calc(pg_temp.uid('Bob'))) = 0, 'P4: nessuna azione extra col pet base';
  perform pg_temp.buy('Bob', 'pet_drago_celeste'); perform pg_temp.petlv('Bob', 'pet_drago_celeste', 100); perform pg_temp.activate('Bob', 'pet_drago_celeste');
  select * into ln from public.game_pet_lines where pet_id = 'pet_drago_celeste' and effect = 'actions';
  assert (select extra_actions from public._game_calc(pg_temp.uid('Bob'))) = (case when ln.max_value is null then 0 else ln.max_value end), 'P4: il bonus azioni boss arriva in extra_actions';
  assert (select xp_pct from public._game_calc(pg_temp.uid('Bob'))) = (select max_value from public.game_pet_lines where pet_id = 'pet_drago_celeste' and effect = 'xp'), 'P4: il bonus XP arriva in xp_pct';
  insert into t_log (msg) values ('OK P4 — bonus: formula, sblocchi a 10/25, somma con le abilità, XP e azioni');
end $$;

-- P5 — esperienza del pet: 20% dell'XP effettiva dell'eroe, solo il pet attivo, tetto = livello eroe e 100
do $$
declare r jsonb; p public.game_hero_pets; h public.game_heroes; before_xp bigint;
begin
  -- Cid: pet base, eroe di livello 50
  perform pg_temp.lvl('Cid', 50); perform pg_temp.choose('Cid', 'pet_libellula');
  r := pg_temp.addxp('Cid', 1000);
  p := pg_temp.pet('Cid', 'pet_libellula');
  assert (r->>'xp')::bigint >= 1000 and p.total_xp = floor((r->>'xp')::bigint * 0.2) and p.level >= 1, 'P5: il pet prende il 20% dell''XP effettiva dell''eroe (' || p.total_xp || ' su ' || (r->>'xp') || ')';
  -- il 20% usa l'XP finale (con bonus XP): un eroe con xp_pct maggiore dà più XP al pet
  perform pg_temp.lvl('Cid', 50);
  update public.game_hero_pets set level = 1, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Cid');
  perform pg_temp.addxp('Cid', 50); perform pg_temp.addxp('Cid', 50); perform pg_temp.addxp('Cid', 50);
  p := pg_temp.pet('Cid', 'pet_libellula');
  assert p.total_xp = 3 * floor(50 * 0.2 * (100 + (select xp_pct from public._game_calc(pg_temp.uid('Cid')))) / 100.0) or p.total_xp between 27 and 33, 'P5: più accrediti, quota coerente';
  -- sale di livello: pet a livello 1 con tanto XP
  update public.game_hero_pets set level = 1, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Cid');
  perform pg_temp.addxp('Cid', 5000);   -- eroe prende ~5000 → pet ~1000 → sale di livello (110 per il 1°, 120 per il 2°...)
  p := pg_temp.pet('Cid', 'pet_libellula');
  assert p.level >= 4 and p.level <= 20 and p.xp < public._game_xp_need(p.level), 'P5: il pet sale di livello più livelli in un colpo (livello ' || p.level || ')';
  -- tetto: non supera il livello dell'eroe
  perform pg_temp.lvl('Cid', 6);
  update public.game_hero_pets set level = 5, xp = 0 where user_id = pg_temp.uid('Cid');
  perform public._game_pet_gain(pg_temp.uid('Cid'), 1000000);
  select * into p from public.game_hero_pets where user_id = pg_temp.uid('Cid');
  select * into h from public.game_heroes where user_id = pg_temp.uid('Cid');
  assert p.level <= h.level and p.level = least(h.level, 100), 'P5: il pet non supera il livello dell''eroe (pet ' || p.level || ', eroe ' || h.level || ')';
  assert p.xp = 0, 'P5: al tetto l''XP non si accumula';
  -- tetto assoluto 100
  perform pg_temp.lvl('Cid', 300); update public.game_hero_pets set level = 99, xp = 0 where user_id = pg_temp.uid('Cid');
  perform pg_temp.addxp('Cid', 10000000);
  assert (pg_temp.pet('Cid', 'pet_libellula')).level = 100 and (pg_temp.pet('Cid', 'pet_libellula')).xp = 0, 'P5: il pet si ferma al livello 100';
  perform pg_temp.addxp('Cid', 100000);
  assert (pg_temp.pet('Cid', 'pet_libellula')).level = 100, 'P5: oltre il 100 non cresce';
  -- percentuale impostabile
  update public.game_hero_pets set level = 1, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Cid');
  update public.system_settings set value_int = 0 where key = 'game_pet_xp_pct';
  perform pg_temp.addxp('Cid', 1000);
  assert (pg_temp.pet('Cid', 'pet_libellula')).total_xp = 0, 'P5: con la percentuale a 0 il pet non guadagna';
  update public.system_settings set value_int = 100 where key = 'game_pet_xp_pct';
  r := pg_temp.addxp('Cid', 1000);
  assert (pg_temp.pet('Cid', 'pet_libellula')).total_xp = (r->>'xp')::bigint, 'P5: con la percentuale a 100 il pet prende tutta l''XP';
  update public.system_settings set value_int = 20 where key = 'game_pet_xp_pct';
  -- chi non ha un pet non ha problemi
  assert (pg_temp.addxp('Dan', 500)->>'xp')::bigint >= 500, 'P5: chi non ha pet guadagna XP normalmente';
  assert (select count(*) from public.game_hero_pets where user_id = pg_temp.uid('Dan')) = 0, 'P5: nessun pet creato per caso';
  insert into t_log (msg) values ('OK P5 — XP al pet: 20%, solo attivo, tetto eroe e 100, percentuale impostabile');
end $$;

-- P6 — acquisto, requisiti, registro, attivazione, un solo attivo, livelli conservati
do $$
declare b0 integer; t0 bigint; r jsonb; e text;
begin
  perform pg_temp.lvl('Dan', 400); perform pg_temp.choose('Dan', 'pet_ranocchio');
  b0 := pg_temp.bal_('Dan'); t0 := pg_temp.tot();
  assert pg_temp.err_as('Dan', 'select pg_temp.buy(''Dan'', ''pet_gatto'')') like '%Saldo insufficiente%', 'P6: senza BC non si compra';
  assert pg_temp.bal_('Dan') = b0 and (select count(*) from public.game_hero_pets where user_id = pg_temp.uid('Dan')) = 1, 'P6: acquisto fallito = nulla è cambiato';
  perform pg_temp.gift('Dan', 2000000); b0 := pg_temp.bal_('Dan'); t0 := pg_temp.tot();
  perform pg_temp.lvl('Dan', 4);
  assert pg_temp.err_as('Dan', 'select pg_temp.buy(''Dan'', ''pet_gatto'')') like '%livello 5%', 'P6: livello eroe insufficiente';
  perform pg_temp.lvl('Dan', 5);
  r := pg_temp.buy('Dan', 'pet_gatto');
  assert (r->>'price')::int = 1500 and (r->>'balance')::int = b0 - 1500 and pg_temp.bal_('Dan') = b0 - 1500, 'P6: acquisto: BC scalati';
  assert pg_temp.tot() = t0 - 1500, 'P6: i BC escono dal sistema (nulla si crea)';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Dan') and kind = 'game_pet' and amount = -1500 and idempotency_key like 'gamepet:' || pg_temp.uid('Dan')::text || ':pet_gatto:%') = 1, 'P6: movimento nel registro, tipo game_pet';
  assert (select active from public.game_hero_pets where user_id = pg_temp.uid('Dan') and pet_id = 'pet_gatto') = false, 'P6: il pet comprato non diventa attivo da solo';
  assert pg_temp.err_as('Dan', 'select pg_temp.buy(''Dan'', ''pet_gatto'')') like '%Possiedi già%', 'P6: non si compra due volte';
  assert pg_temp.bal_('Dan') = b0 - 1500, 'P6: il secondo tentativo non costa nulla';
  assert pg_temp.err_as('Dan', 'select pg_temp.buy(''Dan'', ''pet_ranocchio'')') like '%non si comprano%', 'P6: i pet base non si comprano';
  assert pg_temp.err_as('Dan', 'select pg_temp.buy(''Dan'', ''pet_lupo'')') like '%livello 30%', 'P6: il grado 3 chiede il livello 30';
  -- attivazione
  perform pg_temp.addxp('Dan', 3000);                         -- il ranocchio (attivo) guadagna
  assert (pg_temp.pet('Dan', 'pet_ranocchio')).total_xp > 0 and (pg_temp.pet('Dan', 'pet_gatto')).total_xp = 0, 'P6: l''XP va solo al pet attivo';
  perform pg_temp.petlv('Dan', 'pet_ranocchio', 3);
  r := pg_temp.activate('Dan', 'pet_gatto');
  assert r->'card'->>'id' = 'pet_gatto' and (select count(*) from public.game_hero_pets where user_id = pg_temp.uid('Dan') and active) = 1, 'P6: ora il gatto è l''unico attivo';
  assert (pg_temp.pet('Dan', 'pet_ranocchio')).level = 3 and not (pg_temp.pet('Dan', 'pet_ranocchio')).active, 'P6: il ranocchio resta con il suo livello';
  perform pg_temp.addxp('Dan', 3000);
  assert (pg_temp.pet('Dan', 'pet_gatto')).total_xp > 0 and (pg_temp.pet('Dan', 'pet_ranocchio')).level = 3 and (pg_temp.pet('Dan', 'pet_ranocchio')).xp = 0, 'P6: ora l''XP va al gatto, il ranocchio resta fermo';
  assert pg_temp.err_as('Dan', 'select pg_temp.activate(''Dan'', ''pet_lupo'')') like '%Non possiedi%', 'P6: non si attiva ciò che non si possiede';
  assert pg_temp.err_as('Ann', 'select pg_temp.activate(''Ann'', ''pet_gatto'')') like '%Non possiedi%', 'P6: il pet di un altro non è tuo';
  assert pg_temp.pst('Dan')->'active'->>'id' = 'pet_gatto' and (select count(*) from jsonb_array_elements(pg_temp.pst('Dan')->'pets') x where (x->>'owned')::boolean) = 2, 'P6: stato: 2 posseduti, gatto attivo';
  -- il pet di un utente non si vede ad altri: la scheda di Ann non mostra il gatto
  assert pg_temp.gst('Ann')->'me'->'pet'->>'id' = 'pet_ranocchio', 'P6: ognuno vede il proprio pet';
  assert not exists (select 1 from public.game_hero_pets group by user_id having count(*) filter (where active) > 1), 'P6: mai due pet attivi';
  -- indice univoco: un secondo attivo diretto viene respinto anche da chi scavalcasse le funzioni
  e := pg_temp.err('update public.game_hero_pets set active = true where user_id = ''' || pg_temp.uid('Dan')::text || ''' and pet_id = ''pet_ranocchio''');
  assert e like '%duplicate key%' or e like '%game_hero_pets_one_active%', 'P6: il vincolo del database impedisce due attivi';
  insert into t_log (msg) values ('OK P6 — acquisto, requisiti, registro, attivazione, un solo attivo');
end $$;

-- P7 — integrazione: il duello assegna l'XP al pet, e i bonus del pet pesano nello scontro; boss e Torre usano la stessa strada
do $$
declare r jsonb; p0 bigint; p1 bigint;
begin
  perform pg_temp.hero_('Ann', 20, 3, 3, 3, 3, 3); perform pg_temp.hero_('Bob', 20, 3, 3, 3, 3, 3);
  update public.game_heroes set arena_open = true where true;
  update public.game_hero_pets set level = 1, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Ann');
  -- Ann vince sicuramente: Bob senza forza
  update public.game_heroes set a_for = 0, a_des = 0, a_vig = 0, a_spi = 0, a_frt = 0 where user_id = pg_temp.uid('Bob');
  r := pg_temp.duel('Ann', 'Bob');
  assert (r->>'won')::boolean, 'P7: Ann vince il duello';
  p1 := (pg_temp.pet('Ann', 'pet_ranocchio')).total_xp;
  assert p1 = floor((r->>'xp')::bigint * 0.2), 'P7: il pet prende il 20% dell''XP del duello (' || p1 || ' su ' || (r->>'xp') || ')';
  -- una sconfitta non dà XP al pet
  update public.game_heroes set a_for = 0, a_des = 0, a_vig = 0, a_spi = 0, a_frt = 0 where user_id = pg_temp.uid('Ann');
  update public.game_heroes set a_for = 20, a_des = 20, a_vig = 20, a_spi = 20, a_frt = 20 where user_id = pg_temp.uid('Bob');
  perform pg_temp.fill('Ann');
  r := pg_temp.duel('Ann', 'Bob');
  assert not (r->>'won')::boolean and (pg_temp.pet('Ann', 'pet_ranocchio')).total_xp = p1, 'P7: sconfitta = nessuna XP al pet';
  assert (select count(*) from public.ledger_entries where kind = 'game_pet') = 2, 'P7: nel registro solo gli acquisti di Bob e Dan';
  -- la Torre passa dalla stessa funzione dell'XP
  perform pg_temp.sure_win(); perform pg_temp.hero_('Ann', 20, 3, 3, 3, 3, 3); perform pg_temp.fill('Ann');
  update public.game_hero_pets set level = 1, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Ann');
  r := pg_temp.climb('Ann');
  assert (r->>'won')::boolean and (pg_temp.pet('Ann', 'pet_ranocchio')).total_xp = floor((r->>'xp')::bigint * 0.2) and (r->>'xp')::bigint > 0, 'P7: la Torre nutre il pet (20% dell''XP)';
  perform pg_temp.normal();
  insert into t_log (msg) values ('OK P7 — il duello nutre il pet; la sconfitta no');
end $$;

-- P8 — modulo spento, sospesi, soldi
do $$
begin
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_pet_state()') like '%Modulo non attivo%' and pg_temp.err_as('Dan', 'select public.game_pet_buy(''pet_fatina'')') like '%Modulo non attivo%'
     and pg_temp.err_as('Ann', 'select public.game_pet_activate(''pet_ranocchio'')') like '%Modulo non attivo%' and pg_temp.err_as('Bob', 'select public.game_pet_choose(''pet_ranocchio'')') like '%Modulo non attivo%', 'P8: a modulo spento tutto è chiuso';
  perform pg_temp.mod(true);
  assert pg_temp.pst('Dan')->'active'->>'id' = 'pet_gatto', 'P8: riacceso, i pet ci sono';
  assert not exists (select 1 from public.wallets where balance < 0), 'P8: nessun saldo negativo';
  assert (select count(*) from public.ledger_entries where kind = 'game_pet') = (select count(distinct idempotency_key) from public.ledger_entries where kind = 'game_pet'), 'P8: chiavi del registro uniche';
  assert (select coalesce(sum(-amount), 0) from public.ledger_entries where kind = 'game_pet') = (select coalesce(sum(g.price_bc), 0) from public.game_hero_pets hp join public.game_pets g on g.id = hp.pet_id where not g.starter), 'P8: BC spesi nel registro = prezzi dei pet posseduti';
  assert not exists (select 1 from public.game_hero_pets hp join public.game_pets g on g.id = hp.pet_id join public.game_heroes h on h.user_id = hp.user_id where hp.level > least(100, greatest(h.level, hp.level)) ), 'P8: coerenza';
  insert into t_log (msg) values ('OK P8 — modulo spento, saldi, registro coerente');
end $$;

select msg as esito from t_log order by n;
rollback;
