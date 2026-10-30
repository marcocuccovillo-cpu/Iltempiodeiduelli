-- =====================================================================
-- TEST DELLA MIGRAZIONE 030 (La guerra degli Eroi: abilità permanenti, gradi dal 5° all'8°)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni della guerra degli Eroi e la 030 (black-market-eroi-abilita-gradi.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
-- =====================================================================
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
create function pg_temp.buy(n text, s text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_buy_skill(s); end $$;
create function pg_temp.bon(n text, st text) returns integer language plpgsql as $$
declare r integer; begin
  execute format('select b_%s from public._game_calc(%L)', st, pg_temp.uid(n)) into r; return r; end $$;
create function pg_temp.gst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
do $$ declare n text; begin
  foreach n in array array['Ann','Bob','Cid'] loop perform public._game_ensure_hero(pg_temp.uid(n)); end loop;
end $$;

-- S1 — catalogo: 40 permanenti, 8 gradi per ognuna delle 5 statistiche, tutto coerente
do $$
declare st text; t integer; prev record; cur record;
begin
  assert (select count(*) from public.game_skills where kind = 'perm') = 40, 'S1: 40 abilità permanenti';
  assert (select count(*) from public.game_skills where kind = 'temp') = 10, 'S1: i 10 potenziamenti temporanei non cambiano';
  foreach st in array array['for','des','vig','spi','frt'] loop
    assert (select count(*) from public.game_skills where kind = 'perm' and stat = st) = 8, 'S1: 8 gradi per ' || st;
    assert (select array_agg(tier order by tier) from public.game_skills where kind = 'perm' and stat = st) = array[1,2,3,4,5,6,7,8]::smallint[], 'S1: gradi 1..8 senza buchi per ' || st;
    for t in 1..8 loop
      select * into cur from public.game_skills where id = 'sk_' || st || '_' || t;
      assert cur.id is not null and cur.tier = t and cur.stat = st and cur.kind = 'perm' and cur.slot is null, 'S1: id e campi di ' || st || t;
      assert (case st when 'for' then cur.p_for when 'des' then cur.p_des when 'vig' then cur.p_vig when 'spi' then cur.p_spi else cur.p_frt end) > 0, 'S1: il bonus è sulla statistica giusta ' || st || t;
      assert cur.p_for + cur.p_des + cur.p_vig + cur.p_spi + cur.p_frt = (case st when 'for' then cur.p_for when 'des' then cur.p_des when 'vig' then cur.p_vig when 'spi' then cur.p_spi else cur.p_frt end), 'S1: un solo bonus per abilità ' || st || t;
      assert cur.descr like '%+' || (cur.p_for + cur.p_des + cur.p_vig + cur.p_spi + cur.p_frt) || '%%', 'S1: il testo riporta il bonus ' || st || t;
      if t > 1 then
        assert cur.price_bc > prev.price_bc and cur.min_level > prev.min_level, 'S1: prezzo e livello crescono ' || st || t;
        assert (cur.p_for + cur.p_des + cur.p_vig + cur.p_spi + cur.p_frt) > (prev.p_for + prev.p_des + prev.p_vig + prev.p_spi + prev.p_frt), 'S1: il bonus cresce ' || st || t;
      end if;
      prev := cur;
    end loop;
  end loop;
  assert (select array_agg(distinct price_bc order by price_bc) from public.game_skills where kind = 'perm' and tier >= 5) = array[25000,60000,150000,400000], 'S1: prezzi dei gradi 5–8';
  assert (select array_agg(distinct min_level order by min_level) from public.game_skills where kind = 'perm' and tier >= 5) = array[100,170,260,400], 'S1: livelli dei gradi 5–8';
  assert (select sum(p_for) from public.game_skills where stat = 'for' and kind = 'perm') = 109, 'S1: bonus totale +109%';
  assert (select count(distinct name) from public.game_skills) = 50, 'S1: nomi tutti diversi';
  assert (select count(*) from public.game_skills where id not in (select id from public.game_skills where id ~ '^(sk_(for|des|vig|spi|frt)_[1-8]|tk_(weapon|armor|helm|amulet|tool)_[12])$')) = 0, 'S1: nessun id anomalo';
  insert into t_log (msg) values ('OK S1 — catalogo: 40 permanenti (8 gradi × 5 statistiche), prezzi, livelli e bonus crescenti');
end $$;

-- S2 — l'ordine e i requisiti
do $$
declare e text; b0 integer;
begin
  perform pg_temp.lvl('Ann', 600); perform pg_temp.gift('Ann', 2000000);
  b0 := pg_temp.bal_('Ann');
  e := pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_5'')');
  assert e like '%Prima ti serve%Forza Primordiale%', 'S2: il grado 5 richiede il 4: ' || coalesce(e, 'nessun errore');
  e := pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_8'')');
  assert e like '%Prima ti serve%Colpo Leggendario%', 'S2: il grado 8 richiede il 7: ' || coalesce(e, 'nessun errore');
  assert pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_9'')') like '%inesistente%', 'S2: il grado 9 non esiste';
  assert pg_temp.bal_('Ann') = b0 and (select count(*) from public.game_hero_skills where user_id = pg_temp.uid('Ann')) = 0, 'S2: nessun BC mosso dagli errori';
  insert into t_log (msg) values ('OK S2 — i gradi alti non si saltano');
end $$;

-- S3 — la scala completa su una statistica: prezzi esatti, bonus esatti, livello richiesto
do $$
declare t integer; b0 integer; bon0 integer; k public.game_skills%rowtype; r jsonb; tot integer := 0; e text;
begin
  b0 := pg_temp.bal_('Ann'); bon0 := pg_temp.bon('Ann', 'for');
  for t in 1..4 loop
    select * into k from public.game_skills where id = 'sk_for_' || t;
    r := pg_temp.buy('Ann', k.id); tot := tot + k.price_bc;
    assert (r->>'price')::int = k.price_bc and pg_temp.bal_('Ann') = b0 - tot, 'S3: prezzo grado ' || t;
  end loop;
  assert pg_temp.bon('Ann', 'for') = bon0 + 28, 'S3: i gradi 1–4 danno +28%';
  -- livello: il 5 si apre al livello 100
  perform pg_temp.lvl('Ann', 99);
  e := pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_5'')');
  assert e like '%livello 100%', 'S3: livello 99 non basta per il grado 5: ' || coalesce(e, 'nessun errore');
  perform pg_temp.lvl('Ann', 100);
  for t in 5..8 loop
    select * into k from public.game_skills where id = 'sk_for_' || t;
    if t = 6 then perform pg_temp.lvl('Ann', 169); assert pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_6'')') like '%livello 170%', 'S3: livello 169 non basta per il 6'; perform pg_temp.lvl('Ann', 170); end if;
    if t = 7 then perform pg_temp.lvl('Ann', 259); assert pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_7'')') like '%livello 260%', 'S3: livello 259 non basta per il 7'; perform pg_temp.lvl('Ann', 260); end if;
    if t = 8 then perform pg_temp.lvl('Ann', 399); assert pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_8'')') like '%livello 400%', 'S3: livello 399 non basta per l''8'; perform pg_temp.lvl('Ann', 400); end if;
    r := pg_temp.buy('Ann', k.id); tot := tot + k.price_bc;
    assert pg_temp.bal_('Ann') = b0 - tot, 'S3: saldo dopo il grado ' || t;
    assert pg_temp.bon('Ann', 'for') = bon0 + (select sum(p_for) from public.game_skills where stat = 'for' and kind = 'perm' and tier <= t), 'S3: bonus esatto dopo il grado ' || t;
  end loop;
  assert pg_temp.bon('Ann', 'for') = bon0 + 109, 'S3: +109% con tutti gli 8 gradi';
  assert tot = 250 + 900 + 3000 + 10000 + 25000 + 60000 + 150000 + 400000, 'S3: totale della scala 649.150 BC';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Ann') and kind = 'game_skill') = 8, 'S3: 8 movimenti nel registro';
  assert (select sum(-amount) from public.ledger_entries where user_id = pg_temp.uid('Ann') and kind = 'game_skill') = 649150, 'S3: registro = prezzi';
  assert pg_temp.err_auth('Ann', 'select public.game_buy_skill(''sk_for_8'')') like '%Possiedi già%', 'S3: non si compra due volte';
  assert pg_temp.bal_('Ann') = b0 - 649150, 'S3: il doppio acquisto non costa';
  insert into t_log (msg) values ('OK S3 — scala completa: prezzi, livelli e bonus esatti (+109%), registro BC');
end $$;

-- S4 — la forza reale cresce davvero (le statistiche usano il bonus)
do $$
declare s0 bigint; s1 bigint; a integer;
begin
  update public.game_heroes set a_for = 100, stats_set = true where user_id = pg_temp.uid('Bob');
  perform pg_temp.lvl('Bob', 400); perform pg_temp.gift('Bob', 2000000);
  select s_for into s0 from public._game_calc(pg_temp.uid('Bob'));
  perform pg_temp.buy('Bob', 'sk_for_1'); perform pg_temp.buy('Bob', 'sk_for_2'); perform pg_temp.buy('Bob', 'sk_for_3'); perform pg_temp.buy('Bob', 'sk_for_4');
  select s_for into s1 from public._game_calc(pg_temp.uid('Bob'));
  assert s1 > s0, 'S4: i primi 4 gradi alzano la forza';
  perform pg_temp.buy('Bob', 'sk_for_5');
  select s_for into s0 from public._game_calc(pg_temp.uid('Bob'));
  assert s0 > s1, 'S4: il grado 5 la alza ancora';
  -- 5 + 100*400 = 40005 di base; con +B% di bonus
  assert s0 = round(40005 * (100 + pg_temp.bon('Bob', 'for')) / 100.0), 'S4: forza = base × (100 + bonus)%: ' || s0 || ' vs ' || round(40005 * (100 + pg_temp.bon('Bob', 'for')) / 100.0);
  insert into t_log (msg) values ('OK S4 — le statistiche reali usano il bonus dei nuovi gradi');
end $$;

-- S5 — saldo insufficiente e catalogo nello stato per la pagina
do $$
declare s jsonb; e text; b0 integer;
begin
  perform pg_temp.lvl('Cid', 600); perform pg_temp.gift('Cid', 14200);
  for e in select 'sk_' || x || '_' || t from unnest(array['for']) x, generate_series(1,4) t order by 1 loop perform pg_temp.buy('Cid', e); end loop;
  b0 := pg_temp.bal_('Cid');
  assert pg_temp.err_auth('Cid', 'select public.game_buy_skill(''sk_for_5'')') like '%Saldo insufficiente%', 'S5: saldo insufficiente per il grado 5';
  assert pg_temp.bal_('Cid') = b0 and not exists (select 1 from public.game_hero_skills where user_id = pg_temp.uid('Cid') and skill_id = 'sk_for_5'), 'S5: niente è stato comprato';
  s := pg_temp.gst('Cid');
  assert (select count(*) from jsonb_array_elements(s->'skills') x where x->>'kind' = 'perm') = 40, 'S5: lo stato porta le 40 abilità permanenti';
  assert (select (x->>'owned')::boolean from jsonb_array_elements(s->'skills') x where x->>'id' = 'sk_for_4') and not (select (x->>'owned')::boolean from jsonb_array_elements(s->'skills') x where x->>'id' = 'sk_for_5'), 'S5: possedute e no';
  assert (select (x->>'prev_owned')::boolean from jsonb_array_elements(s->'skills') x where x->>'id' = 'sk_for_5'), 'S5: il grado 5 è acquistabile (prev_owned)';
  assert not (select (x->>'prev_owned')::boolean from jsonb_array_elements(s->'skills') x where x->>'id' = 'sk_for_6'), 'S5: il grado 6 no';
  assert (select x->>'prev' from jsonb_array_elements(s->'skills') x where x->>'id' = 'sk_for_6') = 'Braccio del Colosso', 'S5: «prima serve» indica il grado 5';
  assert (select x->>'prev' from jsonb_array_elements(s->'skills') x where x->>'id' = 'sk_des_5') = 'Precisione Assoluta', 'S5: il 5 di Destrezza punta al 4';
  insert into t_log (msg) values ('OK S5 — saldo insufficiente e dati per la pagina');
end $$;

-- S6 — le altre 4 statistiche: ogni scala arriva a +109% e ciascuna tocca solo la propria
do $$
declare st text; t integer; b0 integer; bon_before jsonb := '{}'::jsonb; k integer;
begin
  perform pg_temp.lvl('Ann', 600); perform pg_temp.gift('Ann', 3000000);
  foreach st in array array['des','vig','spi','frt'] loop
    bon_before := bon_before || jsonb_build_object(st, pg_temp.bon('Ann', st));
  end loop;
  foreach st in array array['des','vig','spi','frt'] loop
    for t in 1..8 loop perform pg_temp.buy('Ann', 'sk_' || st || '_' || t); end loop;
    assert pg_temp.bon('Ann', st) = (bon_before->>st)::int + 109, 'S6: +109% su ' || st;
  end loop;
  assert (select count(*) from public.game_hero_skills where user_id = pg_temp.uid('Ann')) = 40, 'S6: Ann possiede tutte e 40';
  insert into t_log (msg) values ('OK S6 — ogni statistica arriva a +109%');
end $$;

-- S7 — il catalogo è leggibile dal browser e chiuso in scrittura
do $$
begin
  assert pg_temp.rows_as('Bob', 'select * from public.game_skills') = 50, 'S7: catalogo leggibile (50 righe)';
  assert pg_temp.err_auth('Bob', 'update public.game_skills set price_bc = 1') is not null, 'S7: catalogo non modificabile dal browser';
  assert pg_temp.err_auth('Bob', 'insert into public.game_hero_skills (user_id, skill_id) values (auth.uid(), ''sk_des_8'')') is not null, 'S7: niente acquisti diretti';
  insert into t_log (msg) values ('OK S7 — catalogo in sola lettura per il browser');
end $$;

-- S8 — annullamento: si ferma se ci sono acquisti dei nuovi gradi
do $$
declare e text;
begin
  e := pg_temp.err($d$ do $x$ declare n integer; begin select count(*) into n from public.game_hero_skills s join public.game_skills k on k.id = s.skill_id where k.kind = 'perm' and k.tier >= 5;
    if n > 0 then raise exception 'ANNULLAMENTO FERMATO: % acquisti', n; end if; delete from public.game_skills where kind = 'perm' and tier >= 5; end $x$ $d$);
  assert e like 'ANNULLAMENTO FERMATO%', 'S8: l''annullamento si ferma: ' || coalesce(e, 'nessun errore');
  assert (select count(*) from public.game_skills where kind = 'perm') = 40, 'S8: catalogo intatto';
  insert into t_log (msg) values ('OK S8 — l''annullamento rifiuta se ci sono acquisti');
end $$;

select msg as esito from t_log order by n;
rollback;
