-- =====================================================================
-- TEST DELLA MIGRAZIONE 015 (La guerra degli Eroi, versione 2: energia, punti per livello, skill, lobby)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…015 (black-market-setup.sql … black-market-eroi-v2.sql).
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
-- «passa un giorno»: sposta indietro di 1 giorno tutto ciò che è legato alla data (dal più vecchio, per non creare conflitti)
create function pg_temp.shift() returns void language plpgsql as $$
declare r record;
begin
  for r in select day from public.game_days order by day asc loop update public.game_days set day = day - 1 where day = r.day; end loop;
  for r in select distinct day from public.game_merchant_offers order by day asc loop update public.game_merchant_offers set day = day - 1 where day = r.day; end loop;
  alter table public.game_duels disable trigger user;
  for r in select distinct day from public.game_duels order by day asc loop update public.game_duels set day = day - 1 where day = r.day; end loop;
  alter table public.game_duels enable trigger user;
end $$;
create function pg_temp.boss_hp() returns bigint language sql as $$ select hp from public.game_days where day = public._game_today() $$;


create function pg_temp.exp_hp(p_no integer, p_cycle integer, uids uuid[]) returns bigint language plpgsql as $$
declare s numeric := 0; u uuid; c record;
begin
  foreach u in array uids loop select * into c from public._game_calc(u); s := s + c.s_for * 3; end loop;
  return greatest(50, ceil(s * public._setting('game_daily_actions') * (select coverage from public.game_bosses where no = p_no) * (1 + 0.25 * p_cycle)
                           * public._setting('game_boss_difficulty') / 100.0))::bigint;
end $$;
create function pg_temp.en(n text) returns numeric language sql as $$ select public._game_energy_of(pg_temp.uid(n)) $$;
create function pg_temp.calc(n text) returns jsonb language sql as $$ select to_jsonb(c) from public._game_calc(pg_temp.uid(n)) c $$;
create function pg_temp.join_(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_join(); end $$;
create function pg_temp.buys(n text, k text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_buy_skill(k); end $$;

-- W1 — struttura, impostazioni, catalogo skill, permessi
do $$
declare n text;
begin
  assert (select count(*) from public.game_skills where kind = 'perm') = 20 and (select count(*) from public.game_skills where kind = 'temp') = 10, 'W1: 20 skill permanenti e 10 temporanee';
  assert (select count(distinct stat) from public.game_skills where kind = 'perm') = 5 and (select count(distinct slot) from public.game_skills where kind = 'temp') = 5, 'W1: 5 statistiche, 5 slot';
  assert not exists (select 1 from public.game_skills where price_bc <= 0), 'W1: tutto ha un prezzo';
  assert (select bool_and(a.price_bc < b.price_bc and a.p_for + a.p_des + a.p_vig + a.p_spi + a.p_frt < b.p_for + b.p_des + b.p_vig + b.p_spi + b.p_frt)
          from public.game_skills a join public.game_skills b on b.kind = 'perm' and b.stat = a.stat and b.tier = a.tier + 1 where a.kind = 'perm'), 'W1: i gradi alti costano e danno di più';
  assert (select count(*) from public.system_settings where key like 'game\_%') = 15, 'W1: 15 impostazioni del gioco';
  assert (select value_int from public.system_settings where key = 'game_energy_max') = 100 and (select value_int from public.system_settings where key = 'game_energy_regen_hours') = 8
     and (select value_int from public.system_settings where key = 'game_energy_win') = 5 and (select value_int from public.system_settings where key = 'game_energy_loss') = 8
     and (select value_int from public.system_settings where key = 'game_boss_min_players') = 3 and (select value_int from public.system_settings where key = 'game_points_per_level') = 3, 'W1: valori richiesti (100 / 8 ore / 5 / 8 / 3 giocatori / 3 punti)';
  foreach n in array array['public.game_boss_join()','public.game_boss_leave()','public.game_boss_start()','public.game_buy_skill(text)'] loop
    assert has_function_privilege('authenticated', n, 'execute') and not has_function_privilege('anon', n, 'execute'), 'W1: permessi ' || n;
  end loop;
  assert not has_function_privilege('authenticated', 'public._game_energy_of(uuid)', 'execute') and not has_function_privilege('authenticated', 'public._game_points(integer)', 'execute'), 'W1: funzioni interne chiuse';
  assert not has_table_privilege('authenticated', 'public.game_hero_skills', 'insert') and not has_table_privilege('authenticated', 'public.game_temp_skills', 'update') and not has_table_privilege('authenticated', 'public.game_skills', 'update'), 'W1: nessuna scrittura diretta';
  insert into t_log (msg) values ('OK W1 — 30 skill (20 permanenti + 10 temporanee), 15 impostazioni, permessi');
end $$;

-- eroi pronti
do $$
declare n text;
begin
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay','Org'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.setst('Ann', 10, 2, 4, 2, 2); perform pg_temp.setst('Bob', 4, 4, 4, 4, 4); perform pg_temp.setst('Cid', 8, 2, 6, 2, 2); perform pg_temp.setst('Dan', 2, 2, 2, 10, 4);
  perform pg_temp.setst('Eve', 8, 8, 2, 1, 1); perform pg_temp.setst('Fay', 3, 3, 3, 3, 8); perform pg_temp.setst('Org', 6, 6, 6, 1, 1);
  assert (select count(*) from public.game_heroes where stats_set) = 7, 'W: 7 eroi pronti';
end $$;

-- W2 — 3 punti per livello; aggiungere è gratis, togliere costa
do $$
declare r jsonb; b0 integer; j jsonb;
begin
  j := pg_temp.st('Ann');
  assert (j->'me'->>'points')::int = 20 and (j->'me'->>'points_free')::int = 0, 'W2: al livello 1 i punti sono 20';
  perform pg_temp.lvl('Ann', 5);
  j := pg_temp.st('Ann');
  assert (j->'me'->>'points')::int = 32 and (j->'me'->>'points_free')::int = 12, 'W2: al livello 5: 20 + 4 × 3 = 32, 12 liberi';
  perform pg_temp.lvl('Ann', 100);
  assert (pg_temp.st('Ann')->'me'->>'points')::int = 20 + 99 * 3, 'W2: al livello 100: 317';
  perform pg_temp.lvl('Ann', 9999);
  assert (pg_temp.st('Ann')->'me'->>'points')::int = 20 + 9998 * 3 and (pg_temp.st('Ann')->'me'->'stats'->>'for')::bigint = round((5 + 10::numeric * 9999) * 1.01), 'W2: al livello 9999: 30014 punti, Forza = (5 + 10 × 9999) + 1% dell''arma base';
  perform pg_temp.lvl('Ann', 5);
  update public.game_heroes set fights_total = 3 where user_id = pg_temp.uid('Ann');
  b0 := pg_temp.bal('Ann');
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(10,2,4,2,17)') like '%solo 32 punti%', 'W2: oltre il totale';
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(23,0,0,0,0)') like '%Massimo 22%', 'W2: il tetto per statistica sale coi livelli (10 + 12)';
  r := pg_temp.setst('Ann', 10, 2, 4, 2, 8);
  assert (r->>'paid')::int = 0 and pg_temp.bal('Ann') = b0 and (r->'alloc'->>'frt')::int = 8, 'W2: aggiungere i punti nuovi dopo aver combattuto è gratis';
  r := pg_temp.setst('Ann', 12, 2, 4, 2, 8);
  assert (r->>'paid')::int = 0 and pg_temp.bal('Ann') = b0, 'W2: aggiungere punti liberi alla Forza è gratis';
  r := pg_temp.setst('Ann', 12, 2, 4, 2, 7);
  assert (r->>'paid')::int = 100 and pg_temp.bal('Ann') = b0 - 100, 'W2: togliere un punto già assegnato costa 100 BC dopo aver combattuto';
  r := pg_temp.setst('Ann', 12, 2, 4, 2, 7);
  assert (r->>'paid')::int = 0 and pg_temp.bal('Ann') = b0 - 100, 'W2: nessuna modifica = gratis';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Ann'), -(pg_temp.bal('Ann') - 20), 'saldo basso per la prova');
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(10,2,4,2,7)') = 'Saldo insufficiente', 'W2: senza BC non si ridistribuisce';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Ann'), 500, 'ripristino saldo della prova');
  assert (select a_for from public.game_heroes where user_id = pg_temp.uid('Ann')) = 12, 'W2: niente è cambiato nel fallimento';
  perform pg_temp.setst('Ann', 10, 2, 4, 2, 2); perform pg_temp.lvl('Ann', 1); update public.game_heroes set fights_total = 0 where user_id = pg_temp.uid('Ann');
  insert into t_log (msg) values ('OK W2 — 20 punti + 3 per livello; punti nuovi gratis, togliere punti già dati costa 100 BC; il tetto per statistica sale coi livelli');
end $$;

-- W3 — energia a batteria
do $$
declare r jsonb; t0 bigint; i integer; n text;
begin
  t0 := pg_temp.tot();
  update public.game_heroes set energy = 100, energy_at = now() where true;
  perform pg_temp.lvl('Ann', 200); update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
  assert (pg_temp.st('Ann')->'energy'->>'value')::numeric = 100 and (pg_temp.st('Ann')->'energy'->>'max')::int = 100, 'W3: batteria piena a 100';
  i := 0;
  foreach n in array array['Bob','Cid','Dan','Eve','Fay','Org'] loop
    r := pg_temp.duel('Ann', n); i := i + 1;
    assert (r->>'won')::boolean and (r->>'energy_cost')::int = 5 and (r->>'energy')::numeric = 100 - 5 * i, 'W3: duello vinto contro ' || n || ' costa 5';
  end loop;
  assert pg_temp.en('Ann') = 70, 'W3: dopo 6 vittorie restano 70';
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Bob') || '''::uuid)') like '%già sfidato%', 'W3: resta «una sfida al giorno per avversario»';
  r := pg_temp.duel('Bob', 'Ann');
  assert not (r->>'won')::boolean and (r->>'energy_cost')::int = 8 and pg_temp.en('Bob') = 92, 'W3: duello perso costa 8';
  update public.game_heroes set energy = 7.9, energy_at = now() where user_id = pg_temp.uid('Cid');
  assert pg_temp.err_as('Cid', 'select public.game_duel(''' || pg_temp.uid('Fay') || '''::uuid)') like 'Energia insufficiente%', 'W3: con meno di 8 non si sfida';
  update public.game_heroes set energy = 8, energy_at = now() where user_id = pg_temp.uid('Cid');
  r := pg_temp.duel('Cid', 'Fay');
  assert pg_temp.en('Cid') = case when (r->>'won')::boolean then 3 else 0 end, 'W3: con 8 si può sfidare; non scende sotto 0';
  update public.game_heroes set energy = 0, energy_at = now() - interval '4 hours' where user_id = pg_temp.uid('Dan');
  assert abs(pg_temp.en('Dan') - 50) < 0.01, 'W3: dopo 4 ore 50';
  update public.game_heroes set energy = 0, energy_at = now() - interval '1 hour' where user_id = pg_temp.uid('Dan');
  assert abs(pg_temp.en('Dan') - 12.5) < 0.01, 'W3: dopo 1 ora 12,5';
  update public.game_heroes set energy = 0, energy_at = now() - interval '8 hours' where user_id = pg_temp.uid('Dan');
  assert pg_temp.en('Dan') = 100, 'W3: dopo 8 ore piena';
  update public.game_heroes set energy = 40, energy_at = now() - interval '48 hours' where user_id = pg_temp.uid('Dan');
  assert pg_temp.en('Dan') = 100, 'W3: mai oltre 100';
  update public.game_heroes set energy = 0, energy_at = now() - interval '4 hours' where user_id = pg_temp.uid('Dan');
  r := pg_temp.st('Dan')->'energy';
  assert (r->>'value')::numeric = 50 and (r->>'full_in_s')::int = 14400 and (r->>'per_hour')::numeric = 12.5, 'W3: lo stato dice 50, piena tra 4 ore, 12,5 all''ora';
  update public.game_items set extra_fights = 2 where id = 's_tool';
  assert abs(public._game_energy_rate(pg_temp.uid('Dan')) - 12.5 * 1.5) < 0.001, 'W3: +2 duelli = ricarica +50%';
  update public.game_items set extra_fights = 0 where id = 's_tool';
  assert pg_temp.tot() = t0, 'W3: l''energia non muove BC';
  assert (pg_temp.st('Bob')->'duels') ? 'recent' and not ((pg_temp.st('Bob')->'duels') ? 'limit'), 'W3: niente più limite giornaliero di duelli';
  insert into t_log (msg) values ('OK W3 — energia: 100 max, 5 per vittoria e 8 per sconfitta, minimo 8 per sfidare, +12,5 all''ora, mai oltre 100, niente più limite di 5 duelli');
end $$;

-- W4 — skill permanenti
do $$
declare c0 jsonb; c1 jsonb; r jsonb; b0 integer; t0 bigint;
begin
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Cid'), 2000, 'BC per comprare le skill della prova');
  perform pg_temp.lvl('Cid', 3); b0 := pg_temp.bal('Cid'); t0 := pg_temp.tot();
  c0 := pg_temp.calc('Cid');
  perform pg_temp.lvl('Cid', 12);
  assert pg_temp.err_as('Cid', 'select public.game_buy_skill(''sk_for_2'')') like 'Prima ti serve%Pugno Temprato%', 'W4: il grado 2 richiede il grado 1';
  assert pg_temp.err_as('Cid', 'select public.game_buy_skill(''boh'')') = 'Abilità inesistente', 'W4: skill inesistente';
  perform pg_temp.lvl('Cid', 2);
  assert pg_temp.err_as('Cid', 'select public.game_buy_skill(''sk_for_1'')') like '%livello 3%', 'W4: serve il livello';
  perform pg_temp.lvl('Cid', 3);
  r := pg_temp.buys('Cid', 'sk_for_1');
  assert (r->>'price')::int = 250 and pg_temp.bal('Cid') = b0 - 250 and (r->>'balance')::int = b0 - 250, 'W4: 250 BC addebitati';
  c1 := pg_temp.calc('Cid');
  assert (c1->>'b_for')::bigint = (c0->>'b_for')::bigint + 3 and (c1->>'b_des')::bigint = (c0->>'b_des')::bigint, 'W4: +3% solo alla Forza';
  assert pg_temp.err_as('Cid', 'select public.game_buy_skill(''sk_for_1'')') = 'Possiedi già questa abilità' and pg_temp.bal('Cid') = b0 - 250, 'W4: non si compra due volte';
  assert exists (select 1 from public.ledger_entries where user_id = pg_temp.uid('Cid') and kind = 'game_skill' and amount = -250), 'W4: movimento nel registro';
  assert pg_temp.tot() = t0 - 250, 'W4: i BC spesi escono dal gioco';
  perform pg_temp.lvl('Cid', 12); perform pg_temp.buys('Cid', 'sk_for_2');
  assert (pg_temp.calc('Cid')->>'b_for')::bigint = (c0->>'b_for')::bigint + 8, 'W4: i gradi si sommano (3% + 5%)';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Cid'), -(pg_temp.bal('Cid') - 10), 'saldo basso per la prova');
  perform pg_temp.lvl('Cid', 30);
  assert pg_temp.err_as('Cid', 'select public.game_buy_skill(''sk_for_3'')') = 'Saldo insufficiente', 'W4: senza BC non si compra';
  assert not exists (select 1 from public.game_hero_skills where user_id = pg_temp.uid('Cid') and skill_id = 'sk_for_3'), 'W4: niente acquisto senza saldo';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Cid'), 600, 'ripristino saldo della prova');
  assert (select count(*) from jsonb_array_elements(pg_temp.st('Cid')->'skills') x where (x->>'owned')::boolean) = 2, 'W4: lo stato dice quali sono tue';
  perform pg_temp.lvl('Cid', 3);
  insert into t_log (msg) values ('OK W4 — skill permanenti: prezzo, livello, ordine dei gradi, bonus % solo alla statistica giusta, una volta sola');
end $$;

-- W5 — skill temporanee (un solo potenziamento per equipaggiamento, 24 ore)
do $$
declare c0 jsonb; c1 jsonb; r jsonb; b0 integer;
begin
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Dan'), 1000, 'BC per comprare le skill della prova');
  perform pg_temp.lvl('Dan', 1); c0 := pg_temp.calc('Dan'); b0 := pg_temp.bal('Dan');
  r := pg_temp.buys('Dan', 'tk_weapon_1');
  assert (r->>'price')::int = 80 and pg_temp.bal('Dan') = b0 - 80, 'W5: 80 BC';
  assert (select expires_at from public.game_temp_skills where user_id = pg_temp.uid('Dan') and skill_id = 'tk_weapon_1') = now() + interval '24 hours', 'W5: dura 24 ore';
  c1 := pg_temp.calc('Dan');
  assert (c1->>'b_for')::bigint = (c0->>'b_for')::bigint + 6 and (c1->>'b_des')::bigint = (c0->>'b_des')::bigint + 3 and (c1->>'b_vig')::bigint = (c0->>'b_vig')::bigint, 'W5: arma: Forza +6% e Destrezza +3%';
  assert exists (select 1 from jsonb_array_elements(pg_temp.st('Dan')->'skills') x where x->>'id' = 'tk_weapon_1' and x->>'active_until' is not null), 'W5: lo stato mostra la scadenza';
  assert pg_temp.err_as('Dan', 'select public.game_buy_skill(''tk_weapon_2'')') like '%livello 15%', 'W5: il grado 2 richiede il livello 15';
  perform pg_temp.lvl('Dan', 15);
  perform pg_temp.buys('Dan', 'tk_weapon_2');
  c1 := pg_temp.calc('Dan');
  assert (c1->>'b_for')::bigint = (c0->>'b_for')::bigint + 12 and (c1->>'b_des')::bigint = (c0->>'b_des')::bigint + 6, 'W5: il grado 2 sostituisce il grado 1 (non si somma)';
  assert (select count(*) from public.game_temp_skills t join public.game_skills s on s.id = t.skill_id where t.user_id = pg_temp.uid('Dan') and s.slot = 'weapon' and t.expires_at > now()) = 1, 'W5: uno solo attivo per slot';
  assert pg_temp.err_as('Dan', 'select public.game_buy_skill(''tk_weapon_1'')') like 'Hai già un potenziamento migliore%', 'W5: non si scende di grado';
  perform pg_temp.buys('Dan', 'tk_armor_1');
  c1 := pg_temp.calc('Dan');
  assert (c1->>'b_vig')::bigint = (c0->>'b_vig')::bigint + 6 and (c1->>'b_frt')::bigint = (c0->>'b_frt')::bigint + 3 and (c1->>'b_for')::bigint = (c0->>'b_for')::bigint + 12, 'W5: slot diversi si sommano';
  update public.game_temp_skills set expires_at = now() + interval '1 hour' where user_id = pg_temp.uid('Dan') and expires_at > now();
  b0 := pg_temp.bal('Dan'); r := pg_temp.buys('Dan', 'tk_armor_1');
  assert pg_temp.bal('Dan') = b0 - 80 and (select count(*) from public.game_temp_skills t join public.game_skills s on s.id = t.skill_id where t.user_id = pg_temp.uid('Dan') and s.slot = 'armor' and t.expires_at > now()) = 1
     and (select expires_at from public.game_temp_skills where user_id = pg_temp.uid('Dan') and skill_id = 'tk_armor_1' and expires_at > now()) = now() + interval '24 hours', 'W5: il rinnovo riporta a 24 ore e resta uno solo attivo';
  update public.game_temp_skills set expires_at = now() - interval '1 second' where user_id = pg_temp.uid('Dan');
  c1 := pg_temp.calc('Dan');
  assert (c1->>'b_for')::bigint = (c0->>'b_for')::bigint and (c1->>'b_vig')::bigint = (c0->>'b_vig')::bigint, 'W5: scaduta la skill, il bonus sparisce da solo';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Dan') and kind = 'game_skill') = 4, 'W5: 4 acquisti nel registro';
  insert into t_log (msg) values ('OK W5 — skill temporanee: 24 ore, un solo potenziamento per equipaggiamento, rinnovo, scadenza automatica, bonus corretti');
end $$;

-- W6 — lobby del boss
do $$
declare dy public.game_days%rowtype; r jsonb; n text; b_bal jsonb := '{}'; b_tot bigint; mem uuid[];
begin
  perform pg_temp.mod(true);
  perform pg_temp.lvl('Ann', 1); perform pg_temp.lvl('Bob', 1); perform pg_temp.lvl('Cid', 1); perform pg_temp.lvl('Dan', 1);
  r := pg_temp.st('Org');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.status = 'lobby' and dy.boss_no = 1 and dy.hp = 0 and dy.max_hp = 0, 'W6: oggi c''è il boss 1, in lobby, senza ancora PV';
  assert (r->'boss'->>'status') = 'lobby' and (r->'boss'->>'min_players')::int = 3 and not (r->'boss'->>'joined')::boolean, 'W6: lo stato dice «lobby», 3 giocatori minimi';
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like 'Il boss non è ancora partito%', 'W6: senza lobby non si combatte';
  assert pg_temp.err_as('Ann', 'select public.game_boss_start()') = 'Entra prima nella lobby', 'W6: per avviare bisogna essere nella lobby';
  assert pg_temp.err_as('Admin', 'select public.game_boss_join()') like '%punti abilità%', 'W6: serve aver assegnato i punti';
  r := pg_temp.join_('Ann'); assert (r->>'players')::int = 1, 'W6: Ann entra';
  r := pg_temp.join_('Ann'); assert (r->>'players')::int = 1, 'W6: entrare due volte non raddoppia';
  r := pg_temp.join_('Bob'); assert (r->>'players')::int = 2, 'W6: Bob entra';
  assert pg_temp.err_as('Ann', 'select public.game_boss_start()') like 'Servono almeno 3 giocatori%(ora 2)', 'W6: con 2 giocatori non parte';
  r := pg_temp.join_('Cid'); r := pg_temp.join_('Dan'); r := pg_temp.join_('Eve'); assert (r->>'players')::int = 5, 'W6: 5 nella lobby';
  perform pg_temp.as_('Eve'); r := public.game_boss_leave(); assert (r->>'players')::int = 4, 'W6: Eve esce';
  assert not exists (select 1 from public.game_day_heroes where user_id = pg_temp.uid('Eve') and day = public._game_today()), 'W6: la sua riga è sparita';
  r := pg_temp.join_('Eve');
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), true, 'sospesa per la prova');
  assert pg_temp.err_as('Fay', 'select public.game_boss_start()') = 'Entra prima nella lobby', 'W6: chi non è nella lobby non avvia';
  mem := array[pg_temp.uid('Ann'), pg_temp.uid('Bob'), pg_temp.uid('Cid'), pg_temp.uid('Dan')];
  perform pg_temp.as_('Bob'); r := public.game_boss_start();
  select * into dy from public.game_days where day = public._game_today();
  assert dy.status = 'open' and (r->>'players')::int = 4 and dy.started_at is not null, 'W6: partito con 4 giocatori (la sospesa è fuori)';
  assert dy.max_hp = pg_temp.exp_hp(1, 0, mem) and dy.hp = dy.max_hp and dy.max_hp = (r->>'boss_hp')::bigint, 'W6: PV = somma dei danni dei presenti × azioni × copertura';
  assert (select count(*) from public.game_day_heroes where day = dy.day) = 4, 'W6: 4 righe in lobby';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), false, 'ripristino');
  assert pg_temp.err_as('Ann', 'select public.game_boss_start()') = 'Il boss è già partito', 'W6: non si riavvia';
  assert pg_temp.err_as('Fay', 'select public.game_boss_join()') like 'Il boss è già partito%', 'W6: dopo la partenza non si entra';
  assert pg_temp.err_as('Ann', 'select public.game_boss_leave()') like 'Il boss è già partito%', 'W6: né si esce';
  assert pg_temp.err_as('Fay', 'select public.game_boss_act(''attack'')') like 'Non sei nella lobby%', 'W6: chi non c''era non combatte';
  assert pg_temp.err_as('Eve', 'select public.game_boss_act(''attack'')') like 'Non sei nella lobby%', 'W6: nemmeno la sospesa tolta dalla lobby';
  update public.game_days set hp = max_hp where day = dy.day; perform pg_temp.act('Ann', 'attack');
  update public.game_days set hp = max_hp where day = dy.day; perform pg_temp.act('Ann', 'attack');
  update public.game_days set hp = max_hp where day = dy.day; perform pg_temp.act('Bob', 'guard'); perform pg_temp.act('Bob', 'guard');
  update public.game_days set hp = max_hp where day = dy.day; perform pg_temp.act('Cid', 'study'); perform pg_temp.act('Dan', 'attack');
  assert (select count(*) from public.game_day_heroes where day = dy.day and actions_used >= 2) = 2, 'W6: solo Ann e Bob hanno 2 azioni';
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Eve','Fay'] loop b_bal := b_bal || jsonb_build_object(n, pg_temp.bal(n)); end loop;
  b_tot := pg_temp.tot();
  update public.game_days set hp = 1 where day = dy.day;
  r := pg_temp.act('Ann', 'attack');
  assert (r->>'defeated')::boolean and (r->'reward'->>'bc')::int = 100, 'W6: boss sconfitto, 100 BC';
  assert pg_temp.bal('Ann') = (b_bal->>'Ann')::int + 100 and pg_temp.bal('Bob') = (b_bal->>'Bob')::int + 100, 'W6: Ann e Bob ricevono 100 BC';
  foreach n in array array['Cid','Dan','Eve','Fay','Org'] loop assert pg_temp.bal(n) = (b_bal->>n)::int, 'W6: ' || n || ' non riceve BC'; end loop;
  assert pg_temp.tot() = b_tot + 200 and (select count(*) from public.game_rewards where day = dy.day) = 2, 'W6: 200 BC in tutto, 2 ricompense';
  perform public._game_finish_boss(dy.day);
  assert pg_temp.tot() = b_tot + 200, 'W6: nessun doppio pagamento';
  assert pg_temp.err_as('Bob', 'select public.game_boss_join()') like 'Il boss di oggi è già stato sconfitto%', 'W6: a boss sconfitto non si entra';
  insert into t_log (msg) values ('OK W6 — lobby: servono 3, entrare/uscire, avvio solo dai presenti, PV al via sui presenti, ricompense (≥2 azioni) una volta sola');
end $$;

-- W7 — progressione dei giorni con la lobby
do $$
declare dy public.game_days%rowtype; j jsonb;
begin
  perform pg_temp.shift();
  j := pg_temp.st('Ann');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 2 and dy.status = 'lobby' and dy.cycle = 0, 'W7: sconfitto il boss 1, oggi il 2 in lobby';
  assert (j->'boss'->'previous'->>'status') = 'defeated', 'W7: ieri sconfitto';
  perform pg_temp.join_('Ann');
  perform pg_temp.shift();
  perform pg_temp.st('Ann');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 2 and dy.status = 'lobby' and not exists (select 1 from public.game_day_heroes where day = dy.day), 'W7: boss 2 di nuovo, lobby nuova e vuota';
  assert (select status from public.game_days where day = dy.day - 1) = 'escaped', 'W7: la lobby mai partita è «scappata»';
  perform pg_temp.join_('Ann'); perform pg_temp.join_('Bob'); perform pg_temp.join_('Cid'); perform pg_temp.as_('Ann'); perform public.game_boss_start();
  perform pg_temp.shift(); perform pg_temp.st('Ann');
  assert (select boss_no from public.game_days where day = public._game_today()) = 2 and (select status from public.game_days where day = public._game_today() - 1) = 'escaped', 'W7: boss iniziato ma non sconfitto: ritorna, ieri «scappato»';
  update public.game_days set boss_no = 10, status = 'defeated' where day = public._game_today();
  perform pg_temp.shift(); perform pg_temp.st('Ann');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 1 and dy.cycle = 1 and dy.status = 'lobby', 'W7: dopo il 10 si riparte dal 1, giro 1';
  perform pg_temp.join_('Ann'); perform pg_temp.join_('Bob'); perform pg_temp.join_('Cid'); perform pg_temp.as_('Cid'); perform public.game_boss_start();
  assert (select max_hp from public.game_days where day = dy.day) = pg_temp.exp_hp(1, 1, array[pg_temp.uid('Ann'), pg_temp.uid('Bob'), pg_temp.uid('Cid')]), 'W7: PV del giro 1 = +25%';
  assert (select count(*) from public.game_days where day = dy.day) = 1, 'W7: un solo boss al giorno';
  insert into t_log (msg) values ('OK W7 — progressione: sconfitto → il successivo; lobby mai partita o boss non battuto → riprova; dopo il 10 si ricomincia più forti');
end $$;

-- W8 — permessi, modulo spento, contabilità
do $$
declare q text;
begin
  foreach q in array array['update public.game_heroes set energy = 100', 'update public.game_heroes set a_for = 99999', 'insert into public.game_hero_skills (user_id, skill_id) values (auth.uid(), ''sk_for_4'')',
    'insert into public.game_temp_skills (user_id, skill_id, expires_at) values (auth.uid(), ''tk_weapon_2'', now() + interval ''9 days'')', 'update public.game_skills set price_bc = 1', 'update public.game_day_heroes set hp = 99999',
    'delete from public.game_temp_skills', 'update public.game_days set hp = 1'] loop
    assert pg_temp.err_auth('Ann', q) is not null, 'W8: scrittura diretta non permessa: ' || q;
  end loop;
  assert pg_temp.err_auth('Ann', 'select public._game_energy_of(auth.uid())') is not null and pg_temp.err_auth('Ann', 'select public._game_points(100)') is not null, 'W8: funzioni interne chiuse';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  assert pg_temp.err('select public.game_boss_join()') is not null and pg_temp.err('select public.game_buy_skill(''sk_for_1'')') is not null, 'W8: serve il login';
  assert pg_temp.rows_as('Bob', 'select * from public.game_hero_skills') = (select count(*) from public.game_hero_skills where user_id = pg_temp.uid('Bob')), 'W8: ognuno vede solo le proprie skill';
  assert pg_temp.rows_as('Bob', 'select * from public.game_skills') = 30, 'W8: il catalogo è leggibile';
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_boss_join()') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_boss_start()') = 'Modulo non attivo'
     and pg_temp.err_as('Ann', 'select public.game_boss_leave()') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_buy_skill(''sk_for_1'')') = 'Modulo non attivo', 'W8: a modulo spento tutto è bloccato';
  assert pg_temp.rows_as('Ann', 'select * from public.game_skills') = 0, 'W8: e il catalogo è chiuso';
  perform pg_temp.mod(true);
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'W8: saldi = registro';
  assert not exists (select 1 from public.wallets where balance < 0), 'W8: nessun saldo negativo';
  assert not exists (select 1 from public.ledger_entries where kind = 'game_skill' and amount >= 0), 'W8: le skill sono solo uscite di BC';
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind = 'game_boss_reward') = 100 * (select count(*) from public.game_rewards where bc > 0), 'W8: BC creati solo dai boss, 100 per ricompensa';
  insert into t_log (msg) values ('OK W8 — nessuna scrittura diretta, anon e modulo spento fuori, saldi = registro, BC creati solo dai boss');
end $$;

select n, msg from t_log order by n;
rollback;
