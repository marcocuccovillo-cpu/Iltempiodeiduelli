-- =====================================================================
-- TEST DELLA MIGRAZIONE 013 (La guerra degli Eroi)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…013 (black-market-setup.sql … black-market-eroi.sql).
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

-- G1 — struttura, impostazioni, catalogo, permessi
do $$
begin
  assert (select value_int from public.system_settings where key = 'module_heroes') = 1, 'G1: modulo acceso di default';
  assert (select count(*) from public.game_items where source = 'shop') = 60, 'G1: 60 oggetti in vendita';
  assert (select count(*) from public.game_items where source = 'start') = 5, 'G1: 5 oggetti base';
  assert (select count(*) from public.game_items where source = 'boss') = 10, 'G1: 10 oggetti dei boss';
  assert (select count(distinct slot) from public.game_items where source = 'shop') = 5, 'G1: 5 slot';
  assert (select count(*) from public.game_bosses) = 10, 'G1: 10 boss';
  assert (select bool_and(a.coverage < b.coverage and a.retal < b.retal) from public.game_bosses a join public.game_bosses b on b.no = a.no + 1), 'G1: difficoltà crescente';
  assert not exists (select 1 from public.game_items where source = 'shop' and (price_bc is null or price_bc <= 0)), 'G1: tutto ciò che si vende ha un prezzo';
  assert not exists (select 1 from public.game_items where source <> 'shop' and price_bc is not null), 'G1: gli esclusivi non si comprano';
  assert (select count(*) from public.system_settings where key like 'game\_%') = 8, 'G1: 8 impostazioni del gioco';
  assert has_function_privilege('authenticated', 'public.game_state()', 'execute') and not has_function_privilege('anon', 'public.game_state()', 'execute'), 'G1: RPC solo utenti collegati';
  assert not has_function_privilege('authenticated', 'public._game_finish_boss(date)', 'execute'), 'G1: funzioni interne non esposte';
  assert not has_function_privilege('authenticated', 'public._game_add_xp(uuid,bigint)', 'execute'), 'G1: XP non assegnabile dal browser';
  assert not has_table_privilege('authenticated', 'public.game_heroes', 'update') and not has_table_privilege('authenticated', 'public.game_inventory', 'insert')
     and not has_table_privilege('authenticated', 'public.game_days', 'update') and not has_table_privilege('authenticated', 'public.game_rewards', 'insert'), 'G1: nessuna scrittura diretta';
  insert into t_log (msg) values ('OK G1 — modulo acceso, 75 oggetti (60 in vendita), 10 boss a difficoltà crescente, nessuna scrittura diretta dal browser');
end $$;

-- G2 — l'eroe nasce al primo accesso con l'equipaggiamento base; punti abilità e formula delle statistiche
do $$
declare j jsonb; r jsonb;
begin
  assert (select count(*) from public.game_heroes) = 0, 'G2: nessun eroe prima del primo accesso';
  j := pg_temp.st('Ann');
  assert (j->'me'->>'level')::int = 1 and (j->'me'->>'xp')::int = 0 and not (j->'me'->>'stats_set')::boolean, 'G2: livello 1, punti non ancora assegnati';
  assert (select count(*) from public.game_equipped where user_id = pg_temp.uid('Ann')) = 5 and (select count(*) from public.game_inventory where user_id = pg_temp.uid('Ann')) = 5, 'G2: 5 oggetti base indossati';
  assert (j->'me'->'equipped'->'weapon'->>'id') = 's_weapon', 'G2: spada d''addestramento';
  assert (j->'me'->'alloc'->>'for')::int = 0, 'G2: nessun punto assegnato';
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like '%punti abilità%', 'G2: senza punti non si combatte';
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(11,0,0,0,0)') like '%singola statistica%', 'G2: massimo 10 su una statistica';
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(10,10,1,0,0)') like '%solo 20 punti%', 'G2: massimo 20 punti in tutto';
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(-1,0,0,0,0)') is not null, 'G2: niente punti negativi';
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(null,0,0,0,0)') is not null, 'G2: niente valori nulli';
  r := pg_temp.setst('Ann', 10, 2, 4, 2, 2);
  assert (r->>'stats_set')::boolean and (r->'alloc'->>'for')::int = 10, 'G2: punti salvati';
  -- livello 1: base 5 + punti × 1, poi +bonus % dell'equipaggiamento base (+1% sulla statistica di ogni oggetto)
  assert (r->'stats'->>'for')::int = round(15 * 1.01), 'G2: Forza al livello 1 = 15 (+1%)';
  assert (r->>'max_hp')::int = 50 + 12 * (r->'stats'->>'vig')::int, 'G2: PV = 50 + 12 × Vigore';
  -- crescita col livello: stesse proporzioni, statistiche che salgono
  perform pg_temp.lvl('Ann', 10);
  r := public.game_hero(pg_temp.uid('Ann'));
  assert (r->'stats'->>'for')::int = round((5 + 10 * 10) * 1.01) and (r->'stats'->>'des')::int = round((5 + 2 * 10) * 1.01), 'G2: livello 10 → 5 + punti × 10';
  perform pg_temp.lvl('Ann', 100);
  r := public.game_hero(pg_temp.uid('Ann'));
  assert (r->'stats'->>'for')::int = round((5 + 10 * 100) * 1.01), 'G2: livello 100 → Forza 1015';
  perform pg_temp.lvl('Ann', 1);
  assert (select count(*) from public.game_heroes) = 1, 'G2: un solo eroe creato';
  assert pg_temp.tot() = (select coalesce(sum(amount), 0) from public.ledger_entries), 'G2: saldi = registro';
  insert into t_log (msg) values ('OK G2 — eroe creato al primo accesso con equipaggiamento base; limiti sui punti; statistiche = 5 + punti × livello (+ bonus %)');
end $$;

-- G3 — a modulo spento tutto è bloccato (anche lato database), gli altri moduli no
do $$
declare f text;
begin
  perform pg_temp.mod(false);
  foreach f in array array['select public.game_state()', 'select public.game_set_stats(5,5,5,5,0)', 'select public.game_equip(''s_weapon'')', 'select public.game_buy(''w01'')',
                           'select public.game_boss_act(''attack'')', 'select public.game_duel(public._game_today() is null)', 'select public.game_arena_list()'] loop
    if f like '%game_duel%' then f := 'select public.game_duel(''' || pg_temp.uid('Bob') || '''::uuid)'; end if;
    assert pg_temp.err_as('Ann', f) = 'Modulo non attivo', 'G3: ' || f || ' deve essere bloccata';
  end loop;
  assert pg_temp.err_as('Ann', 'select public.game_hero(''' || pg_temp.uid('Ann') || '''::uuid)') = 'Modulo non attivo', 'G3: scheda bloccata';
  assert pg_temp.rows_as('Ann', 'select * from public.game_heroes') = 0 and pg_temp.rows_as('Ann', 'select * from public.game_leaderboard_v') = 0
     and pg_temp.rows_as('Ann', 'select * from public.game_items') = 0, 'G3: anche la lettura diretta è chiusa';
  assert public._module_on('ladder'), 'G3: la Ladder non è toccata';
  perform pg_temp.mod(true);
  assert pg_temp.rows_as('Ann', 'select * from public.game_items') = 75, 'G3: riacceso, il catalogo torna visibile';
  insert into t_log (msg) values ('OK G3 — a modulo spento RPC e letture rifiutate; riacceso tutto torna; la Ladder non cambia');
end $$;

-- G4 — i punti abilità degli altri eroi (per i test successivi)
do $$
begin
  perform pg_temp.setst('Bob', 2, 4, 10, 2, 2);
  perform pg_temp.setst('Cid', 4, 4, 4, 4, 4);
  perform pg_temp.setst('Dan', 2, 2, 2, 10, 4);
  perform pg_temp.setst('Eve', 8, 8, 2, 1, 1);
  perform pg_temp.setst('Fay', 3, 3, 3, 3, 8);
  perform pg_temp.setst('Org', 6, 6, 6, 1, 1);
  assert (select count(*) from public.game_heroes where stats_set) = 7, 'G4: 7 eroi pronti';
  assert pg_temp.err_as('Bob', 'select public.game_set_stats(4,4,4,4,4)') is null, 'G4: finché non si combatte si può cambiare gratis';
  perform pg_temp.setst('Bob', 2, 4, 10, 2, 2);
  assert (pg_temp.hero('Bob')).respec_count = 2, 'G4: contati i cambi';
  insert into t_log (msg) values ('OK G4 — 7 eroi con punti assegnati; cambio gratuito prima del primo scontro');
end $$;

-- G5 — equipaggiamento: solo oggetti posseduti, con il livello giusto, uno per slot
do $$
declare r jsonb; s0 bigint; s1 bigint;
begin
  assert pg_temp.err_as('Ann', 'select public.game_equip(''w05'')') = 'Non possiedi questo oggetto', 'G5: non posseduto';
  assert pg_temp.err_as('Ann', 'select public.game_equip(''boh'')') is not null, 'G5: oggetto inesistente';
  insert into public.game_inventory (user_id, item_id, source) values (pg_temp.uid('Ann'), 'w03', 'shop'), (pg_temp.uid('Ann'), 'm01', 'shop');
  assert pg_temp.err_as('Ann', 'select public.game_equip(''w03'')') like '%livello 6%', 'G5: serve il livello';
  perform pg_temp.lvl('Ann', 6);
  s0 := (public.game_hero(pg_temp.uid('Ann'))->'stats'->>'for')::bigint;
  perform pg_temp.as_('Ann'); r := public.game_equip('w03');
  s1 := (r->'stats'->>'for')::bigint;
  assert r->'equipped'->'weapon'->>'id' = 'w03' and s1 > s0, 'G5: la nuova arma sostituisce la vecchia e alza la Forza';
  assert (select count(*) from public.game_equipped where user_id = pg_temp.uid('Ann') and slot = 'weapon') = 1, 'G5: un solo oggetto per slot';
  perform public.game_equip('m01');
  assert (select item_id from public.game_equipped where user_id = pg_temp.uid('Ann') and slot = 'amulet') = 'm01', 'G5: amuleto sostituito';
  -- si torna all'arma base
  r := public.game_equip('s_weapon');
  assert r->'equipped'->'weapon'->>'id' = 's_weapon', 'G5: si può rimettere l''oggetto base';
  assert (select count(*) from public.game_inventory where user_id = pg_temp.uid('Ann')) = 7, 'G5: l''inventario non perde nulla';
  perform pg_temp.lvl('Ann', 1);
  r := public.game_equip('s_weapon');
  insert into t_log (msg) values ('OK G5 — equipaggiare richiede il possesso e il livello; un oggetto per slot; i bonus % salgono');
end $$;

-- G6 — il mercante: 8 offerte al giorno uguali per tutti, solo BC, acquisto una volta sola
do $$
declare ja jsonb; jb jsonb; m0 text; b0 integer; t0 bigint; r jsonb; v_id text; v_pr integer; v_disc integer;
begin
  ja := pg_temp.st('Ann'); jb := pg_temp.st('Bob');
  assert jsonb_array_length(ja->'merchant') = 8, 'G6: 8 offerte';
  assert (select count(distinct x->>'slot') from jsonb_array_elements(ja->'merchant') x) = 5, 'G6: almeno uno per slot';
  assert ja->'merchant' = jb->'merchant' or (select jsonb_agg(x->>'id' order by x->>'id') from jsonb_array_elements(ja->'merchant') x) = (select jsonb_agg(x->>'id' order by x->>'id') from jsonb_array_elements(jb->'merchant') x), 'G6: uguali per tutti';
  assert (select count(*) from jsonb_array_elements(ja->'merchant') x where (x->>'discounted')::boolean) = 1, 'G6: una sola offerta scontata';
  assert (select bool_and((x->>'price')::int <= (x->>'list_price')::int) from jsonb_array_elements(ja->'merchant') x), 'G6: nessun prezzo sopra il listino';
  assert (select count(*) from public.game_merchant_offers where day = public._game_today()) = 8, 'G6: salvate una volta sola';
  assert (select count(*) from public.game_merchant_offers where day = public._game_today()) = 8, 'G6: ripetere la richiesta non le cambia';
  -- acquisto: un oggetto alla portata del livello 1, non scontato
  select x->>'id', (x->>'price')::int into v_id, v_pr from jsonb_array_elements(ja->'merchant') x where (x->>'min_level')::int <= 1 order by (x->>'price')::int limit 1;
  assert v_id is not null, 'G6: c''è almeno un''offerta per il livello 1';
  assert pg_temp.err_as('Ann', 'select public.game_buy(''t12'')') = 'Oggi il mercante non vende questo oggetto', 'G6: solo le offerte di oggi';
  b0 := pg_temp.bal('Ann'); t0 := pg_temp.tot();
  perform pg_temp.as_('Ann'); r := public.game_buy(v_id);
  assert pg_temp.bal('Ann') = b0 - v_pr and (r->>'balance')::int = b0 - v_pr, 'G6: il prezzo è stato addebitato';
  assert pg_temp.tot() = t0 - v_pr, 'G6: i BC spesi escono dal gioco (nessun altro li riceve)';
  assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Ann') and item_id = v_id and source = 'shop'), 'G6: oggetto in inventario';
  assert exists (select 1 from public.ledger_entries where user_id = pg_temp.uid('Ann') and kind = 'game_purchase' and amount = -v_pr), 'G6: movimento nel registro';
  assert pg_temp.err_as('Ann', 'select public.game_buy(''' || v_id || ''')') = 'Possiedi già questo oggetto', 'G6: non si compra due volte';
  assert pg_temp.bal('Ann') = b0 - v_pr, 'G6: nessun doppio addebito';
  -- livello insufficiente e saldo insufficiente
  select x->>'id' into v_id from jsonb_array_elements(ja->'merchant') x where (x->>'min_level')::int > 1 order by (x->>'min_level')::int desc limit 1;
  if v_id is not null then assert pg_temp.err_as('Bob', 'select public.game_buy(''' || v_id || ''')') like '%livello%', 'G6: serve il livello'; end if;
  select x->>'id', (x->>'price')::int into v_id, v_pr from jsonb_array_elements(ja->'merchant') x where (x->>'min_level')::int <= 1 order by (x->>'price')::int desc limit 1;
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Bob'), -(pg_temp.bal('Bob') - 5), 'saldo basso per la prova');
  assert pg_temp.err_as('Bob', 'select public.game_buy(''' || v_id || ''')') = 'Saldo insufficiente', 'G6: saldo insufficiente';
  assert pg_temp.bal('Bob') = 5 and not exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Bob') and item_id = v_id), 'G6: niente acquisto, niente addebito';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Bob'), 500, 'ripristino saldo della prova');
  -- il giorno dopo il mercante cambia (lazily) e quello di ieri resta registrato
  select string_agg(item_id, ',' order by item_id) into m0 from public.game_merchant_offers where day = public._game_today();
  perform pg_temp.shift();
  jb := pg_temp.st('Cid');
  assert (select count(*) from public.game_merchant_offers where day = public._game_today()) = 8, 'G6: nuove 8 offerte il giorno dopo';
  assert (select count(*) from public.game_merchant_offers where day = public._game_today() - 1) = 8, 'G6: quelle di ieri restano';
  perform pg_temp.shift();
  perform pg_temp.shift();     -- (tornati a un giorno «pulito» per le prove successive: spostiamo anche i boss indietro)
  insert into t_log (msg) values ('OK G6 — mercante: 8 offerte uguali per tutti, 1 scontata, BC solo in uscita, niente doppi acquisti né acquisti senza saldo/livello');
end $$;

-- funzione di controllo: PV attesi del boss secondo la formula documentata
create function pg_temp.exp_hp(p_no integer, p_cycle integer) returns bigint language plpgsql as $$
declare s numeric := 0; n integer := 0; r record; c record;
begin
  for r in select h.user_id from public.game_heroes h join public.profiles p on p.id = h.user_id
           where h.stats_set and not p.suspended and h.last_active_at >= now() - interval '7 days' loop
    select * into c from public._game_calc(r.user_id); s := s + c.s_for * 3; n := n + 1;
  end loop;
  if n < 3 then s := s / n * 3; end if;
  return greatest(50, ceil(s * public._setting('game_daily_actions') * (select coverage from public.game_bosses where no = p_no) * (1 + 0.25 * p_cycle)
                           * public._setting('game_boss_difficulty') / 100.0))::bigint;
end $$;

-- G7 — il boss del giorno: azioni, limiti, scudo, KO, cure, debolezze, sconfitta e ricompense
do $$
declare r jsonb; sh0 bigint; hp0 bigint; i integer; dy public.game_days%rowtype; b_tot bigint; b_bal jsonb := '{}'; n text; q integer;
begin
  assert not exists (select 1 from public.game_days where day = public._game_today()), 'G7: oggi il boss non è ancora nato';
  -- primo attacco: nasce il giorno con il boss 1, PV secondo la formula
  r := pg_temp.act('Ann', 'attack');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 1 and dy.cycle = 0 and dy.status = 'open', 'G7: oggi c''è il boss 1';
  assert dy.max_hp = pg_temp.exp_hp(1, 0), 'G7: PV del boss secondo la formula';
  assert (r->>'amount')::bigint > 0 and (r->>'boss_hp')::bigint = dy.max_hp - (r->>'amount')::bigint, 'G7: il colpo toglie PV al boss';
  assert (r->>'actions_left')::int = 2, 'G7: 2 azioni rimaste su 3';
  assert (select dmg from public.game_day_heroes where day = dy.day and user_id = pg_temp.uid('Ann')) = (r->>'amount')::bigint, 'G7: danno registrato';
  update public.game_days set hp = max_hp where day = dy.day;  perform pg_temp.act('Ann', 'attack');
  update public.game_days set hp = max_hp where day = dy.day;  perform pg_temp.act('Ann', 'attack');
  update public.game_days set hp = max_hp where day = dy.day;   -- (il test non deve dipendere dal caso: tengo il boss in vita)
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like '%tutte le azioni%', 'G7: massimo 3 azioni al giorno';
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''boh'')') = 'Azione non valida', 'G7: azione sconosciuta';
  assert (select hp from public.game_day_heroes where day = dy.day and user_id = pg_temp.uid('Ann')) > 0, 'G7: Ann è ancora in piedi';
  -- scudo comune: Bob difende, poi Cid attacca e lo scudo assorbe i colpi di ritorno
  sh0 := (select shield from public.game_days where day = dy.day);
  r := pg_temp.act('Bob', 'guard');
  assert (r->>'amount')::bigint > 0 and (select shield from public.game_days where day = dy.day) = sh0 + (r->>'amount')::bigint, 'G7: la difesa alza lo scudo comune';
  update public.game_days set shield = 1000000 where day = dy.day;
  update public.game_days set hp = max_hp where day = dy.day;
  for i in 1..3 loop                       -- (una schivata non dice nulla sullo scudo: si riprova, al massimo 3 azioni)
    update public.game_days set shield = 1000000 where day = dy.day;
    r := pg_temp.act('Cid', 'attack');
    exit when not (r->>'dodge')::boolean;
  end loop;
  if not (r->>'dodge')::boolean then         -- (se per caso Cid schiva tutti e 3 i colpi non c'è nulla da verificare: probabilità ~1%)
    assert (r->>'taken')::int = 0 and (r->>'absorbed')::int > 0, 'G7: lo scudo assorbe il contraccolpo';
    assert (select shield from public.game_days where day = dy.day) = 1000000 - (r->>'absorbed')::int, 'G7: lo scudo cala della quantità assorbita';
  end if;
  update public.game_days set shield = 0 where day = dy.day;
  -- debolezze: fino a +40%, mai oltre
  r := pg_temp.act('Dan', 'study');
  assert (r->>'amount')::int between 2 and 8 and (r->>'weak')::int = (r->>'amount')::int, 'G7: studio = +2…8%';
  update public.game_days set weak = 39 where day = dy.day;
  r := pg_temp.act('Dan', 'study');
  assert (r->>'weak')::int = 40 and (r->>'amount')::int = 1, 'G7: il tetto è 40%';
  assert pg_temp.err_as('Eve', 'select public.game_boss_act(''study'')') like '%tutte le debolezze%', 'G7: oltre il 40% non si studia più';
  -- KO e cure
  update public.game_days set hp = max_hp where day = dy.day;
  perform pg_temp.act('Fay', 'attack');
  update public.game_day_heroes set hp = 0 where day = dy.day and user_id = pg_temp.uid('Fay');
  assert pg_temp.err_as('Fay', 'select public.game_boss_act(''guard'')') like '%esausto%', 'G7: un eroe a 0 PV non agisce';
  assert pg_temp.err_as('Eve', 'select public.game_boss_act(''heal'', ''' || pg_temp.uid('Org') || '''::uuid)') like '%non è ancora sceso%', 'G7: non si cura chi non è in campo';
  assert pg_temp.err_as('Eve', 'select public.game_boss_act(''heal'', ''' || pg_temp.uid('Ann') || '''::uuid)') like '%bisogno di cure%' or (select hp < max_hp from public.game_day_heroes where day = dy.day and user_id = pg_temp.uid('Ann')),
         'G7: chi è a PV pieni non ha bisogno di cure';
  r := pg_temp.act('Eve', 'heal', 'Fay');
  assert r->>'note' = 'rianimato' and (select hp from public.game_day_heroes where day = dy.day and user_id = pg_temp.uid('Fay')) > 0, 'G7: la cura rianima';
  -- sconfitta: i PV scendono a 1, Eve (seconda azione) dà il colpo finale
  for n in select unnest(array['Admin','Org','Ann','Bob','Cid','Dan','Eve','Fay']) loop
    b_bal := b_bal || jsonb_build_object(n, pg_temp.bal(n));
  end loop;
  b_tot := pg_temp.tot();
  update public.game_days set hp = 1 where day = dy.day;
  r := pg_temp.act('Eve', 'attack');
  assert (r->>'defeated')::boolean and (r->>'boss_hp')::int = 0, 'G7: boss sconfitto';
  assert (r->'reward'->>'bc')::int = 100 and (r->'reward'->>'xp')::int = 84 and r->'reward'->>'item' is not null, 'G7: il colpo finale mostra la ricompensa di Eve';
  -- partecipanti con almeno 2 azioni: Ann (3), Dan (2), Eve (2) e, solo se ha dovuto ritentare per una schivata, Cid. Bob, Fay (1 azione) e Org (nessuna) non ricevono nulla
  assert (select array_agg(user_id order by user_id) from public.game_rewards where day = dy.day) = (select array_agg(user_id order by user_id) from public.game_day_heroes where day = dy.day and actions_used >= 2), 'G7: ricompense esattamente a chi ha ≥2 azioni';
  q := (select count(*) from public.game_rewards where day = dy.day);
  assert q between 3 and 4 and (select count(*) from public.game_rewards where day = dy.day and user_id in (pg_temp.uid('Ann'), pg_temp.uid('Dan'), pg_temp.uid('Eve'))) = 3, 'G7: Ann, Dan ed Eve hanno la ricompensa';
  for n in select unnest(array['Ann','Dan','Eve']) loop
    assert pg_temp.bal(n) = (b_bal->>n)::int + 100, 'G7: ' || n || ' riceve esattamente 100 BC';
    assert (select count(*) from public.game_rewards where day = dy.day and user_id = pg_temp.uid(n) and bc = 100 and xp = 84 and item_id is not null) = 1, 'G7: riga ricompensa di ' || n;
    assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid(n) and source = 'boss'), 'G7: ' || n || ' ha un oggetto del boss';
    assert (select bosses_beaten from public.game_heroes where user_id = pg_temp.uid(n)) = 1, 'G7: ' || n || ' ha un boss battuto';
  end loop;
  for n in select unnest(array['Admin','Org','Bob','Fay']) loop
    assert pg_temp.bal(n) = (b_bal->>n)::int, 'G7: ' || n || ' non riceve BC';
    assert not exists (select 1 from public.game_rewards where day = dy.day and user_id = pg_temp.uid(n)), 'G7: ' || n || ' non ha ricompense';
  end loop;
  assert pg_temp.tot() = b_tot + 100 * q, 'G7: 100 BC per partecipante, non uno di più';
  assert (select count(*) from public.ledger_entries where kind = 'game_boss_reward' and amount = 100) = q, 'G7: un movimento per partecipante';
  assert (select count(*) from public.game_inventory where source = 'boss') = q, 'G7: un oggetto per partecipante';
  -- niente doppi pagamenti
  perform public._game_finish_boss(dy.day); perform public._game_finish_boss(dy.day);
  assert pg_temp.tot() = b_tot + 100 * q and (select count(*) from public.game_rewards) = q and (select count(*) from public.game_inventory where source = 'boss') = q, 'G7: chiamare di nuovo la chiusura non paga due volte';
  assert pg_temp.err_as('Bob', 'select public.game_boss_act(''attack'')') like '%già stato sconfitto%', 'G7: dopo la sconfitta non si attacca più';
  assert (pg_temp.st('Ann')->'boss'->>'status') = 'defeated', 'G7: lo stato lo mostra';
  insert into t_log (msg) values ('OK G7 — boss: limiti, scudo, KO/cure, debolezze al massimo 40%, sconfitta → 100 BC + XP doppia + oggetto solo a chi ha ≥2 azioni, una volta sola');
end $$;

-- G8 — progressione: boss sconfitto → il giorno dopo il successivo; non sconfitto → ritorna lo stesso; dopo l'ultimo si ricomincia più forti
do $$
declare dy public.game_days%rowtype; j jsonb; y public.game_days%rowtype;
begin
  perform pg_temp.shift();
  j := pg_temp.st('Ann');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 2 and dy.cycle = 0 and dy.status = 'open', 'G8: sconfitto il boss 1, oggi c''è il 2';
  assert dy.max_hp = pg_temp.exp_hp(2, 0), 'G8: PV del boss 2 secondo la formula';
  assert (select status from public.game_days where day = dy.day - 1) = 'defeated', 'G8: ieri resta sconfitto';
  assert (j->'boss'->>'no')::int = 2 and j->'boss'->'previous' is not null, 'G8: lo stato mostra il boss 2 e il precedente';
  -- nessuno lo batte: il giorno dopo il boss 2 ritorna, e quello di ieri è scappato
  perform pg_temp.shift();
  perform pg_temp.st('Ann');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 2 and dy.cycle = 0 and dy.status = 'open', 'G8: boss non sconfitto → ritorna lo stesso';
  assert (select status from public.game_days where day = dy.day - 1) = 'escaped', 'G8: quello di ieri è «scappato»';
  -- dopo il boss 10 si ricomincia dal 1, più forti
  update public.game_days set boss_no = 10, status = 'defeated' where day = public._game_today();
  perform pg_temp.shift();
  perform pg_temp.st('Ann');
  select * into dy from public.game_days where day = public._game_today();
  assert dy.boss_no = 1 and dy.cycle = 1, 'G8: dopo il boss 10 si riparte dal 1 con ciclo 1';
  assert dy.max_hp = pg_temp.exp_hp(1, 1), 'G8: PV del ciclo 1 = +25%';
  assert exists (select 1 from public.game_days where cycle = 0 and boss_no = 1 and max_hp < dy.max_hp), 'G8: più forte del primo giro';
  -- i giorni di una stessa data non si duplicano
  perform pg_temp.st('Bob'); perform pg_temp.st('Cid');
  assert (select count(*) from public.game_days where day = public._game_today()) = 1, 'G8: un solo boss al giorno';
  insert into t_log (msg) values ('OK G8 — progressione: sconfitto → il successivo; non sconfitto → riprova; dopo il 10 si riparte più forti (+25%)');
end $$;

-- G9 — Arena: chi vince guadagna solo XP, nessun BC; limiti, eccezioni
do $$
declare r jsonb; b0 bigint; t0 bigint; x0 bigint; lv0 integer; i integer; n text; ha public.game_heroes%rowtype;
begin
  t0 := pg_temp.tot(); b0 := pg_temp.bal('Bob');
  -- vittoria certa: Ann livello 200 contro Bob livello 1
  perform pg_temp.lvl('Ann', 200); perform pg_temp.lvl('Bob', 1);
  select * into ha from public.game_heroes where user_id = pg_temp.uid('Ann');
  r := pg_temp.duel('Ann', 'Bob');
  assert (r->>'won')::boolean, 'G9: l''eroe molto più forte vince';
  assert (r->>'xp')::bigint = round((40 + 2 * 1) * 0.25), 'G9: XP = (40 + 2 × livello avversario) × proporzione (min 0,25)';
  assert (select xp from public.game_heroes where user_id = pg_temp.uid('Ann')) = (r->>'xp')::bigint, 'G9: XP accreditata';
  assert pg_temp.tot() = t0 and pg_temp.bal('Bob') = b0, 'G9: nessun BC si muove in Arena';
  assert (select xp from public.game_heroes where user_id = pg_temp.uid('Bob')) = 0 and (select level from public.game_heroes where user_id = pg_temp.uid('Bob')) = 1, 'G9: lo sfidato non guadagna e non perde nulla';
  assert (select duels_won from public.game_heroes where user_id = pg_temp.uid('Ann')) = 1, 'G9: duelli vinti';
  assert jsonb_array_length(r->'log') > 0 and (r->>'rounds')::int between 1 and 60, 'G9: cronaca del duello presente';
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Bob') || '''::uuid)') like '%già sfidato%', 'G9: una sola sfida al giorno per avversario';
  -- sconfitta certa: nessun XP
  r := pg_temp.duel('Bob', 'Ann');
  assert not (r->>'won')::boolean and (r->>'xp')::int = 0, 'G9: chi perde non prende XP';
  assert (select xp from public.game_heroes where user_id = pg_temp.uid('Bob')) = 0 and (select duels_lost from public.game_heroes where user_id = pg_temp.uid('Bob')) = 1, 'G9: duelli persi';
  -- salita di livello: Dan livello 30 con 395 XP su 400, batte un livello 1 (+11 XP)
  perform pg_temp.lvl('Dan', 30); update public.game_heroes set xp = 395 where user_id = pg_temp.uid('Dan');
  update public.game_heroes set a_for = 10, a_des = 10, a_vig = 0, a_spi = 0, a_frt = 0 where user_id = pg_temp.uid('Dan');
  r := pg_temp.duel('Dan', 'Cid');
  assert (r->>'won')::boolean and (r->>'levels')::int = 1 and (select level from public.game_heroes where user_id = pg_temp.uid('Dan')) = 31
     and (select xp from public.game_heroes where user_id = pg_temp.uid('Dan')) = 395 + 11 - 400, 'G9: salita di livello col resto dell''XP';
  -- limite di 5 duelli al giorno (Ann ne ha fatto 1)
  perform pg_temp.duel('Ann', 'Cid'); perform pg_temp.duel('Ann', 'Dan'); perform pg_temp.duel('Ann', 'Eve'); perform pg_temp.duel('Ann', 'Fay');
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Org') || '''::uuid)') like '%finito i duelli%', 'G9: massimo 5 duelli al giorno';
  -- eccezioni
  assert pg_temp.err_as('Cid', 'select public.game_duel(''' || pg_temp.uid('Cid') || '''::uuid)') like '%altro eroe%', 'G9: niente duello contro se stessi';
  assert pg_temp.err_as('Cid', 'select public.game_duel(null)') is not null, 'G9: avversario obbligatorio';
  assert pg_temp.err_as('Cid', 'select public.game_duel(''' || pg_temp.uid('Admin') || '''::uuid)') like '%non è ancora un eroe%', 'G9: chi non è mai entrato non è sfidabile';
  perform pg_temp.as_('Eve'); perform public.game_set_arena_open(false);
  assert pg_temp.err_as('Cid', 'select public.game_duel(''' || pg_temp.uid('Eve') || '''::uuid)') like '%non accetta sfide%', 'G9: Arena chiusa';
  assert not exists (select 1 from jsonb_array_elements(public.game_arena_list()) x where x->>'nickname' = 'Eve'), 'G9: Eve non compare in lista';
  assert (pg_temp.duel('Eve', 'Cid')->>'rounds') is not null, 'G9: chi chiude l''Arena può comunque sfidare';
  perform pg_temp.as_('Eve'); perform public.game_set_arena_open(true);
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Fay'), true, 'sospeso per la prova');
  assert pg_temp.err_as('Cid', 'select public.game_duel(''' || pg_temp.uid('Fay') || '''::uuid)') = 'Eroe non disponibile', 'G9: sospeso non sfidabile';
  perform pg_temp.as_('Cid');
  assert not exists (select 1 from jsonb_array_elements(public.game_arena_list()) x where x->>'nickname' = 'Fay') and not exists (select 1 from jsonb_array_elements(public.game_arena_list()) x where x->>'nickname' = 'Cid'), 'G9: lista senza sospesi né se stessi';
  assert pg_temp.rows_as('Cid', 'select * from public.game_leaderboard_v where nickname = ''Fay''') = 0, 'G9: i sospesi non sono in classifica';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Fay'), false, 'ripristino');
  assert pg_temp.tot() = t0, 'G9: in tutta l''Arena nessun BC creato o distrutto';
  -- il giorno dopo i duelli tornano disponibili
  perform pg_temp.shift();
  assert pg_temp.duel('Ann', 'Bob') is not null, 'G9: il giorno dopo si può sfidare di nuovo';
  insert into t_log (msg) values ('OK G9 — Arena: vittoria = solo XP (formula), sconfitta = niente, nessun BC, 5 duelli/giorno, una volta per avversario, Arena chiusa/sospesi/se stessi esclusi');
end $$;

-- G10 — livelli fino a 9999
do $$
declare r jsonb;
begin
  update public.game_heroes set level = 1, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Fay');
  r := public._game_add_xp(pg_temp.uid('Fay'), 1000);
  assert (r->>'levels')::int = 7 and (select level from public.game_heroes where user_id = pg_temp.uid('Fay')) = 8 and (select xp from public.game_heroes where user_id = pg_temp.uid('Fay')) = 20, 'G10: 1000 XP dal livello 1 = livello 8 con 20 XP';
  assert public._game_xp_need(1) = 110 and public._game_xp_need(9998) = 100080, 'G10: XP necessaria = 100 + 10 × livello';
  update public.game_heroes set level = 9998, xp = public._game_xp_need(9998) - 5 where user_id = pg_temp.uid('Fay');
  r := public._game_add_xp(pg_temp.uid('Fay'), 100000000);
  assert (select level from public.game_heroes where user_id = pg_temp.uid('Fay')) = 9999 and (select xp from public.game_heroes where user_id = pg_temp.uid('Fay')) = 0 and (r->>'levels')::int = 1, 'G10: tetto a 9999, niente XP residua';
  r := public._game_add_xp(pg_temp.uid('Fay'), 100000000);
  assert (select level from public.game_heroes where user_id = pg_temp.uid('Fay')) = 9999 and (r->>'levels')::int = 0, 'G10: oltre il tetto non succede nulla';
  assert not exists (select 1 from public.game_heroes where level > 9999 or level < 1), 'G10: vincolo di livello';
  assert pg_temp.err('update public.game_heroes set level = 10000 where user_id = ''' || pg_temp.uid('Fay') || '''') is not null, 'G10: 10000 è rifiutato dal database';
  -- un eroe a 9999 ha statistiche enormi ma finite, e le sa usare
  assert (pg_temp.st('Fay')->'me'->'stats'->>'for')::bigint > 10000, 'G10: statistiche coerenti a livello alto';
  update public.game_heroes set level = 1, xp = 0 where user_id = pg_temp.uid('Fay');
  insert into t_log (msg) values ('OK G10 — livelli da 1 a 9999: XP necessaria, salite multiple, tetto, vincolo del database');
end $$;

-- G11 — permessi: il browser legge soltanto, non scrive; ognuno vede solo il proprio inventario
do $$
declare t text; q text;
begin
  foreach q in array array[
    'update public.game_heroes set level = 9999', 'insert into public.game_inventory (user_id, item_id, source) values (auth.uid(), ''t12'', ''shop'')',
    'update public.game_days set hp = 0', 'insert into public.game_rewards (day, user_id, boss_no, bc, xp) values (current_date, auth.uid(), 1, 1000, 1)',
    'delete from public.game_duels', 'update public.game_merchant_offers set price = 1', 'update public.game_items set price_bc = 1',
    'delete from public.game_inventory', 'update public.game_equipped set item_id = ''t12''', 'update public.wallets set balance = 999999'] loop
    assert pg_temp.err_auth('Ann', q) is not null, 'G11: scrittura diretta non permessa: ' || q;
  end loop;
  foreach q in array array['select public._game_finish_boss(current_date)', 'select public._game_add_xp(auth.uid(), 1000)', 'select public._game_calc(auth.uid())', 'select public._game_ensure_day()', 'select public._ledger_move(auth.uid(), 1000, ''game_boss_reward'', null, null, ''x'', ''x'')'] loop
    assert pg_temp.err_auth('Ann', q) is not null, 'G11: funzione interna non chiamabile: ' || q;
  end loop;
  -- utente non collegato (anon)
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  assert pg_temp.err('select public.game_state()') is not null, 'G11: serve il login';
  -- sospeso: non gioca
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Cid'), true, 'sospeso per la prova');
  assert pg_temp.err_as('Cid', 'select public.game_state()') is not null and pg_temp.err_as('Cid', 'select public.game_boss_act(''attack'')') is not null, 'G11: un sospeso non gioca';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Cid'), false, 'ripristino');
  -- privacy dell'inventario e delle ricompense (RLS)
  assert pg_temp.rows_as('Ann', 'select * from public.game_inventory') = (select count(*) from public.game_inventory where user_id = pg_temp.uid('Ann')), 'G11: Ann vede solo il suo inventario';
  assert pg_temp.rows_as('Bob', 'select * from public.game_rewards') = 0, 'G11: Bob non ha ricompense e non vede quelle degli altri';
  assert pg_temp.rows_as('Admin', 'select * from public.game_rewards') = (select count(*) from public.game_rewards), 'G11: l''admin vede tutte le ricompense';
  assert pg_temp.rows_as('Bob', 'select * from public.game_heroes') = (select count(*) from public.game_heroes), 'G11: gli eroi sono pubblici (come in classifica)';
  assert pg_temp.rows_as('Bob', 'select * from public.game_equipped') > 0 and pg_temp.rows_as('Bob', 'select * from public.game_bosses') = 10, 'G11: equipaggiamento e boss leggibili';
  insert into t_log (msg) values ('OK G11 — nessuna scrittura diretta, funzioni interne chiuse, anon e sospesi fuori, inventario e ricompense privati');
end $$;

-- G12 — contabilità: saldi = registro, nessun BC creato oltre le regole
do $$
begin
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'G12: ogni saldo coincide con il suo registro';
  assert not exists (select 1 from public.wallets where balance < 0), 'G12: nessun saldo negativo';
  assert (select count(*) from public.ledger_entries where kind = 'game_boss_reward') = (select count(*) from public.game_rewards where bc > 0), 'G12: un movimento per ricompensa';
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind = 'game_boss_reward') = 100 * (select count(*) from public.game_rewards), 'G12: i BC emessi dai boss sono 100 per ricompensa';
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind = 'game_purchase') < 0, 'G12: gli acquisti sono solo uscite';
  assert not exists (select 1 from public.ledger_entries where kind in ('game_boss_reward','game_purchase','game_respec') and idempotency_key is null), 'G12: chiavi di idempotenza sempre presenti';
  insert into t_log (msg) values ('OK G12 — saldi = registro, nessun saldo negativo, BC creati solo dai boss (100 per partecipante) e solo spesi dal mercante');
end $$;

-- G13 — classifica
do $$
declare p integer;
begin
  perform pg_temp.as_('Bob');
  assert (select count(*) from public.game_leaderboard_v) = 7, 'G13: 7 eroi in classifica (con punti assegnati)';
  assert (select nickname from public.game_leaderboard_v order by rank limit 1) = 'Ann', 'G13: Ann (livello 200) prima';
  assert (select max(rank) from public.game_leaderboard_v) <= 7 and (select min(rank) from public.game_leaderboard_v) = 1, 'G13: posizioni';
  insert into t_log (msg) values ('OK G13 — classifica per livello e XP');
end $$;

-- G14 — estrazione dell'oggetto del boss: mai doppioni, mai troppo avanti, dal boss giusto
do $$
declare i integer; x text; u uuid := pg_temp.uid('Fay'); seen text[] := '{}'; lv integer := (select min_level from public.game_items where source = 'boss' and boss_no = 3);
begin
  update public.game_heroes set level = lv, xp = 0 where user_id = u;
  for i in 1..300 loop
    x := public._game_draw_item(u, 3);
    assert x is not null, 'G14: c''è sempre qualcosa da estrarre';
    assert not exists (select 1 from public.game_inventory where user_id = u and item_id = x), 'G14: mai un oggetto già posseduto';
    assert (select min_level from public.game_items where id = x) <= lv + 8, 'G14: al massimo 8 livelli più avanti';
    assert (select source from public.game_items where id = x) = 'shop' or (select boss_no from public.game_items where id = x) = 3, 'G14: gli esclusivi sono quelli del boss giusto';
    seen := seen || x;
  end loop;
  assert (select count(distinct s) from unnest(seen) s) > 10, 'G14: l''estrazione varia';
  assert exists (select 1 from unnest(seen) s join public.game_items i on i.id = s where i.source = 'boss'), 'G14: l''oggetto esclusivo del boss esce (peso ×4)';
  -- possedendo tutto ciò che è estraibile non esce più nulla
  insert into public.game_inventory (user_id, item_id, source) select u, id, 'shop' from public._game_cands(u, 3) on conflict do nothing;
  assert public._game_draw_item(u, 3) is null, 'G14: se hai già tutto non esce nulla';
  delete from public.game_inventory where user_id = u and source = 'shop' and item_id not in (select id from public.game_items where source = 'start');
  update public.game_heroes set level = 1, xp = 0 where user_id = u;
  insert into t_log (msg) values ('OK G14 — estrazione: nessun doppione, limite di livello, esclusivi del boss giusto, nulla se si ha già tutto');
end $$;

select n, msg from t_log order by n;
rollback;
