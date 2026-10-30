-- =====================================================================
-- TEST DELLA MIGRAZIONE 034 (La guerra degli Eroi: l'Allenamento)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni della guerra degli Eroi, Lo stagno (031) e la 034 (black-market-eroi-allenamento.sql).
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
create function pg_temp.gst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
create function pg_temp.addxp(n text, x bigint) returns jsonb language sql as $$ select public._game_add_xp(pg_temp.uid(n), x) $$;

-- ---------- supporto dell'allenamento ----------
create function pg_temp.tst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_train_state(); end $$;
create function pg_temp.tstart(n text, k text, s text default null) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_train_start(k, s); end $$;
create function pg_temp.tstop(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_train_stop(); end $$;
create function pg_temp.spar(n text, t text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_spar(pg_temp.uid(t)); end $$;
create function pg_temp.tdc(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_dungeon_create(1, 'dps'); end $$;
create function pg_temp.bon(n text, st text) returns integer language plpgsql as $$
declare r integer; begin execute format('select b_%s from public._game_calc(%L)', st, pg_temp.uid(n)) into r; return r; end $$;
create temp table t_base (n text, st text, v integer);
create function pg_temp.bd(n text, st text) returns integer language sql as $$ select pg_temp.bon(n, st) - coalesce((select v from t_base where t_base.n = bd.n and t_base.st = bd.st), 0) $$;
create function pg_temp.endnow(n text) returns void language sql as $$ update public.game_training set started_at = now() - interval '100 hours', ends_at = now() - interval '1 second' where user_id = pg_temp.uid(n) $$;
create function pg_temp.sw(n text) returns integer language sql as $$ select coalesce((select spar_wins from public.game_train_hero where user_id = pg_temp.uid(n)), 0) $$;
create function pg_temp.hsnap(n text) returns text language sql as $$
  select h.level || ':' || h.xp || ':' || h.total_xp || ':' || h.duels_won || ':' || h.duels_lost || ':' || h.bosses_beaten || ':' || h.fights_total || ':' || round(h.energy::numeric, 1) from public.game_heroes h where h.user_id = pg_temp.uid(n) $$;

-- 7 eroi: Ann (forte, livello 100), Bob/Cid/Dan/Eve (deboli, livello 1), Fay (forte, per perdere contro di lei si usa Gus debole)
do $$ declare n text; begin
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay'] loop perform public._game_ensure_hero(pg_temp.uid(n)); end loop;
  perform pg_temp.hero_('Ann', 100, 80, 70, 70, 50, public._game_points(100) - 3 - 270);   -- 3 punti ancora da distribuire
  perform pg_temp.hero_('Bob', 1, 5, 5, 5, 3, 2); perform pg_temp.hero_('Cid', 1, 5, 5, 5, 3, 2); perform pg_temp.hero_('Dan', 1, 5, 5, 5, 3, 2); perform pg_temp.hero_('Eve', 1, 5, 5, 5, 3, 2);
  perform pg_temp.hero_('Fay', 100, 100, 100, 100, 100, 100);
  insert into t_log (msg) values ('OK Preparazione: 6 eroi');
end $$;
insert into t_base select n, st, pg_temp.bon(n, st) from unnest(array['Ann','Bob','Cid','Dan']) n, unnest(array['for','des','vig','spi','frt']) st;
create temp table t_money (h text);
insert into t_money select pg_temp.money();

-- T1 — scheda dell'eroe: nulla cambia per chi non si allena; funzioni pubbliche chiuse agli anonimi
do $$
declare s jsonb; h jsonb;
begin
  s := pg_temp.tst('Bob');
  assert s->'active' = 'null'::jsonb and (s->>'train_points')::int = 0 and (s->>'max_level')::int = 10 and jsonb_array_length(s->'stats') = 5 and jsonb_array_length(s->'levels') = 10, 'T1: stato iniziale: nessun allenamento, 5 statistiche, 10 livelli';
  assert (select (x->'next'->>'hours')::int from jsonb_array_elements(s->'stats') x where x->>'stat' = 'for') = 6, 'T1: il primo livello dura 6 ore';
  h := (pg_temp.gst('Ann'))->'me';
  assert (h->>'train_points')::int = 0 and h->'training' = 'null'::jsonb and (h->>'points')::int = public._game_points(100) and (h->>'points_free')::int = 3, 'T1: punti dell''eroe invariati';
  assert pg_temp.bd('Ann', 'for') = 0, 'T1: nessun bonus di allenamento';
  assert pg_temp.err_auth('Bob', 'select count(*) from public.game_training') like '%permission denied%' and pg_temp.err_auth('Bob', 'select count(*) from public.game_spar_log') like '%permission denied%'
     and pg_temp.err_auth('Bob', 'select count(*) from public.game_train_hero') like '%permission denied%' and pg_temp.err_auth('Bob', 'select count(*) from public.game_train_stats') like '%permission denied%'
     and pg_temp.err_auth('Bob', 'select count(*) from public.game_train_levels') like '%permission denied%', 'T1: tabelle chiuse al browser';
  assert pg_temp.err_auth('Bob', 'select public._game_train_points(null::uuid)') like '%permission denied%' and pg_temp.err_auth('Bob', 'select public._game_train_busy(null::uuid)') like '%permission denied%' and pg_temp.err_auth('Bob', 'select public._game_train_settle(null::uuid)') like '%permission denied%'
     and pg_temp.err_auth('Bob', 'select public._game_train_bonus(null::uuid)') like '%permission denied%', 'T1: funzioni interne chiuse';
  insert into t_log (msg) values ('OK T1 — stato iniziale, tabelle e funzioni interne chiuse');
end $$;

-- T2 — allenamento a tempo: avvio, un solo allenamento alla volta, nessun bonus prima della fine, fermarsi lo annulla
do $$
declare s jsonb; r jsonb; t public.game_training%rowtype;
begin
  assert pg_temp.err_as('Bob', 'select public.game_train_start(''xx'', null)') like '%Scegli un tipo%', 'T2: tipo non valido';
  assert pg_temp.err_as('Bob', 'select public.game_train_start(''stat'', null)') like '%Scegli una statistica%', 'T2: statistica obbligatoria';
  assert pg_temp.err_as('Bob', 'select public.game_train_start(''stat'', ''xxx'')') like '%Scegli una statistica%', 'T2: statistica non valida';
  assert pg_temp.err_as('Bob', 'select public.game_train_stop()') like '%Nessun allenamento%', 'T2: niente da fermare';
  s := pg_temp.tstart('Bob', 'stat', 'for');
  select * into t from public.game_training where user_id = pg_temp.uid('Bob');
  assert t.kind = 'stat' and t.stat = 'for' and t.target_level = 1 and t.ends_at between now() + interval '5 hours 59 minutes' and now() + interval '6 hours 1 minute', 'T2: dura 6 ore, livello 1';
  assert s->'active'->>'kind' = 'stat' and (s->'active'->>'seconds_left')::int between 21500 and 21600 and (s->'active'->>'target_level')::int = 1, 'T2: stato mostra il conto alla rovescia';
  assert pg_temp.bd('Bob', 'for') = 0, 'T2: nessun bonus prima della fine';
  assert (public._game_hero_json(pg_temp.uid('Bob')))->'training'->>'kind' = 'stat', 'T2: la scheda dell''eroe mostra l''allenamento';
  assert pg_temp.err_as('Bob', 'select public.game_train_start(''stat'', ''des'')') like '%già un allenamento%' and pg_temp.err_as('Bob', 'select public.game_train_start(''spar'')') like '%già un allenamento%', 'T2: uno alla volta';
  r := pg_temp.tstop('Bob');
  assert r->>'stopped' = 'stat' and (r->>'lost')::boolean and r->'active' = 'null'::jsonb and pg_temp.bd('Bob', 'for') = 0 and not exists (select 1 from public.game_train_stats where user_id = pg_temp.uid('Bob')), 'T2: fermato: progresso perso, nessun bonus';
  insert into t_log (msg) values ('OK T2 — avvio, un allenamento alla volta, niente bonus prima della fine, stop');
end $$;

-- T3 — fine dell'allenamento: il bonus si applica da solo, i livelli salgono fino al 10, poi basta; ogni statistica per conto suo
do $$
declare s jsonb; r jsonb; b0 bigint; b1 bigint; i integer; ex integer[] := array[6, 8, 12, 16, 24, 32, 40, 48, 60, 72]; h integer;
begin
  select s_for into b0 from public._game_calc(pg_temp.uid('Ann'));
  perform pg_temp.tstart('Ann', 'stat', 'for'); perform pg_temp.endnow('Ann');
  assert pg_temp.bd('Ann', 'for') = 1, 'T3: finito il tempo il bonus c''è già, senza riaprire la pagina';
  select s_for into b1 from public._game_calc(pg_temp.uid('Ann'));
  assert b0 = round((5 + 80::numeric * 100) * (100 + (select v from t_base where n = 'Ann' and st = 'for')) / 100) and b1 = round((5 + 80::numeric * 100) * (101 + (select v from t_base where n = 'Ann' and st = 'for')) / 100) and b1 > b0, 'T3: la Forza reale cresce dell''1%: formula delle statistiche';
  assert public._game_train_busy(pg_temp.uid('Ann')) = false and (public._game_hero_json(pg_temp.uid('Ann')))->'training' = 'null'::jsonb, 'T3: finito = libero, anche prima di riaprire';
  s := pg_temp.tst('Ann');
  assert s->'finished'->>'stat' = 'for' and (s->'finished'->>'level')::int = 1 and (s->'finished'->>'bonus_pct')::int = 1 and s->'active' = 'null'::jsonb, 'T3: lo stato dichiara il livello completato';
  assert (select level from public.game_train_stats where user_id = pg_temp.uid('Ann') and stat = 'for') = 1 and not exists (select 1 from public.game_training where user_id = pg_temp.uid('Ann')), 'T3: livello registrato, allenamento chiuso';
  assert pg_temp.tst('Ann')->'finished' = 'null'::jsonb, 'T3: il completamento si segnala una volta sola';
  assert pg_temp.bd('Ann', 'des') = 0 and pg_temp.bd('Ann', 'for') = 1, 'T3: le altre statistiche non cambiano';
  for i in 2..10 loop
    s := pg_temp.tstart('Ann', 'stat', 'for');
    h := extract(epoch from ((s->'active'->>'ends_at')::timestamptz - (s->'active'->>'started_at')::timestamptz)) / 3600;
    assert h = ex[i] and (s->'active'->>'target_level')::int = i, format('T3: il livello %s dura %s ore', i, ex[i]);
    perform pg_temp.endnow('Ann'); perform pg_temp.tst('Ann');
    assert pg_temp.bd('Ann', 'for') = i, format('T3: al livello %s il bonus è +%s%%', i, i);
  end loop;
  assert pg_temp.err_as('Ann', 'select public.game_train_start(''stat'', ''for'')') like '%livello massimo%', 'T3: al 10 non si va oltre';
  r := pg_temp.tstart('Ann', 'stat', 'vig');
  assert (r->'active'->>'target_level')::int = 1 and (select (x->>'level')::int from jsonb_array_elements(r->'stats') x where x->>'stat' = 'for') = 10, 'T3: un''altra statistica parte dal suo livello 1';
  -- fermare un allenamento già scaduto non lo perde: il livello si applica
  perform pg_temp.endnow('Ann'); r := pg_temp.tstop('Ann');
  assert r->>'stopped' is null and not (r->>'lost')::boolean and pg_temp.bd('Ann', 'vig') = 1, 'T3: stop dopo la fine: il livello resta';
  insert into t_log (msg) values ('OK T3 — bonus alla fine (anche senza riaprire), 10 livelli con le durate previste, massimo, statistiche separate');
end $$;

-- T4 — chi si allena non entra nei dungeon; chi è in un dungeon non si allena
do $$
declare r jsonb; run uuid; s jsonb;
begin
  perform pg_temp.hero_('Cid', 20, 20, 20, 20, 20, 20); perform pg_temp.hero_('Dan', 20, 20, 20, 20, 20, 20); perform pg_temp.fill('Cid'); perform pg_temp.fill('Dan');
  perform pg_temp.tstart('Cid', 'stat', 'spi');
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_create(1, ''dps'')') like '%Sei in allenamento%', 'T4: allenamento a tempo: niente dungeon';
  perform pg_temp.tstop('Cid'); perform pg_temp.tstart('Cid', 'spar');
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_create(1, ''dps'')') like '%Sei in allenamento%', 'T4: amichevole acceso: niente dungeon';
  -- creare è impossibile, ma anche unirsi a una lobby altrui
  perform pg_temp.as_('Dan'); r := public.game_dungeon_create(1, 'tank'); run := (r->>'run_id')::uuid;
  assert run is not null, 'T4: Dan apre una lobby (non si allena)';
  assert pg_temp.err_as('Cid', format('select public.game_dungeon_join(%L, ''dps'')', run)) like '%Sei in allenamento%', 'T4: Cid non può unirsi alla lobby di Dan';
  assert pg_temp.err('insert into public.game_run_members (run_id, user_id, role) values (' || quote_literal(run) || ', ' || quote_literal(pg_temp.uid('Cid')) || ', ''support'')') like '%Sei in allenamento%', 'T4: nemmeno con un inserimento diretto (lo vieta il database)';
  -- Dan è in una lobby: non può iniziare un allenamento
  assert pg_temp.err_as('Dan', 'select public.game_train_start(''spar'')') like '%lobby%' and pg_temp.err_as('Dan', 'select public.game_train_start(''stat'', ''for'')') like '%lobby%', 'T4: chi è in una lobby non si allena';
  perform pg_temp.as_('Dan'); perform public.game_dungeon_leave(run);
  s := pg_temp.tstart('Dan', 'stat', 'for');
  assert s->'active'->>'kind' = 'stat' and not (s->>'in_dungeon')::boolean, 'T4: uscito dalla lobby, Dan può allenarsi';
  -- allenamento a tempo scaduto (non ancora registrato): i dungeon si aprono
  perform pg_temp.endnow('Dan');
  r := (select pg_temp.tdc('Dan'));
  assert r->>'run_id' is not null, 'T4: scaduto il tempo si entra nei dungeon';
  -- fermato l'amichevole, Cid entra
  perform pg_temp.tstop('Cid');
  r := (select pg_temp.tdc('Cid'));
  assert r->>'run_id' is not null, 'T4: fermato l''amichevole, Cid apre un dungeon';
  assert (pg_temp.tst('Cid')->>'in_dungeon')::boolean, 'T4: lo stato dice che sei in un dungeon';
  assert pg_temp.err_as('Cid', 'select public.game_train_start(''spar'')') like '%lobby%', 'T4: in lobby: niente allenamento';
  insert into t_log (msg) values ('OK T4 — dungeon bloccati durante l''allenamento (anche con inserimento diretto); lobby e allenamento si escludono');
end $$;

-- T5 — amichevole: serve l'allenamento amichevole; niente energia, XP, BC, duelli; l'avversario non cambia; controlli sull'avversario
do $$
declare r jsonb; a0 text; b0 text; en0 numeric; nd integer; m0 text := (select h from t_money);
begin
  perform pg_temp.fill('Ann'); perform pg_temp.fill('Bob');
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%iniziare l''allenamento amichevole%', 'T5: senza allenamento amichevole non si combatte';
  perform pg_temp.tstart('Ann', 'spar');
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Ann'))) like '%un altro eroe%' and pg_temp.err_as('Ann', 'select public.game_spar(null)') like '%un altro eroe%', 'T5: non contro se stessi';
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', gen_random_uuid())) like '%non disponibile%', 'T5: avversario inesistente';
  update public.game_heroes set arena_open = false where user_id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%non accetta sfide in Arena%', 'T5: chi non accetta sfide in Arena non si sfida';
  update public.game_heroes set arena_open = true where user_id = pg_temp.uid('Bob');
  update public.profiles set suspended = true where id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%non disponibile%', 'T5: un sospeso non si sfida';
  update public.profiles set suspended = false where id = pg_temp.uid('Bob');
  update public.game_heroes set stats_set = false where user_id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%non ha ancora assegnato%', 'T5: chi non ha assegnato i punti non si sfida';
  update public.game_heroes set stats_set = true where user_id = pg_temp.uid('Bob');
  a0 := pg_temp.hsnap('Ann'); b0 := pg_temp.hsnap('Bob'); select energy into en0 from public.game_heroes where user_id = pg_temp.uid('Ann'); select count(*) into nd from public.game_duels;
  r := pg_temp.spar('Ann', 'Bob');
  assert (r->>'friendly')::boolean and (r->>'won')::boolean and (r->>'counted')::boolean and r->>'opponent' = 'Bob' and jsonb_array_length(r->'log') > 0 and (r->>'spar_wins')::int = 1 and (r->>'to_next')::int = 49 and not (r->>'point_gained')::boolean, 'T5: vittoria amichevole che conta';
  assert pg_temp.hsnap('Ann') = a0 and pg_temp.hsnap('Bob') = b0, 'T5: nessuna XP, energia, vittoria/sconfitta, combattimento registrato (né per lui né per l''avversario)';
  assert (select count(*) from public.game_duels) = nd and pg_temp.money() = m0, 'T5: nessun duello registrato, nessun movimento di BC';
  assert pg_temp.sw('Ann') = 1 and (select count(*) from public.game_spar_log where user_id = pg_temp.uid('Ann') and counted and won) = 1, 'T5: una vittoria contata, registrata';
  -- una sconfitta non conta; i combattimenti si contano comunque
  perform pg_temp.tstop('Ann'); perform pg_temp.tstart('Bob', 'spar');
  r := pg_temp.spar('Bob', 'Ann');
  assert not (r->>'won')::boolean and not (r->>'counted')::boolean and pg_temp.sw('Bob') = 0 and (select spar_fights from public.game_train_hero where user_id = pg_temp.uid('Bob')) = 1, 'T5: una sconfitta non conta, il combattimento sì';
  assert pg_temp.hsnap('Ann') = a0, 'T5: l''avversario che vince non ottiene nulla';
  perform pg_temp.tstop('Bob'); perform pg_temp.tstart('Ann', 'spar');
  insert into t_log (msg) values ('OK T5 — amichevole: serve l''allenamento, controlli sull''avversario, niente XP/energia/BC/duelli, sconfitta non conta');
end $$;

-- T6 — ogni 50 vittorie che contano, 1 punto abilità da distribuire (e non uno di più)
do $$
declare r jsonb; h jsonb; free0 integer; res jsonb;
begin
  update public.game_train_hero set spar_wins = 48 where user_id = pg_temp.uid('Ann');
  r := pg_temp.spar('Ann', 'Bob');
  assert pg_temp.sw('Ann') = 49 and not (r->>'point_gained')::boolean and (r->>'to_next')::int = 1 and pg_temp.err_as('Ann', 'select 1') is null, 'T6: 49 vittorie: ancora nessun punto, ne manca 1';
  h := (pg_temp.gst('Ann'))->'me'; free0 := (h->>'points_free')::int;
  assert (h->>'train_points')::int = 0 and (h->>'points')::int = public._game_points(100), 'T6: a 49 nessun punto in più';
  r := pg_temp.spar('Ann', 'Cid');
  assert pg_temp.sw('Ann') = 50 and (r->>'point_gained')::boolean and (r->>'to_next')::int = 50, 'T6: alla 50ª vittoria arriva il punto';
  h := (pg_temp.gst('Ann'))->'me';
  assert (h->>'train_points')::int = 1 and (h->>'points')::int = public._game_points(100) + 1 and (h->>'points_free')::int = free0 + 1, 'T6: +1 punto in totale e da distribuire';
  assert free0 = 3 and (h->>'points_free')::int = 4, 'T6: da 3 a 4 punti liberi';
  assert (public._game_hero_json(pg_temp.uid('Ann'))->>'train_points')::int = 1, 'T6: anche la scheda pubblica';
  -- si può distribuire il punto in più, non due
  res := pg_temp.setst('Ann', 84, 70, 70, 50, public._game_points(100) - 3 - 270);
  assert (res->>'points_free')::int = 0 and (res->'alloc'->>'for')::int = 84, 'T6: il punto guadagnato si può mettere in una statistica';
  assert pg_temp.err_as('Ann', 'select public.game_set_stats(85, 70, 70, 50, ' || (public._game_points(100) - 3 - 270) || ')') like '%Hai solo%punti da distribuire%', 'T6: ma non uno di più';
  -- il costo della nuova distribuzione non è cambiato (fights_total non è toccato dalle amichevoli)
  assert (select fights_total from public.game_heroes where user_id = pg_temp.uid('Ann')) = 0 and (pg_temp.setst('Ann', 84, 71, 69, 50, public._game_points(100) - 3 - 270)->>'paid')::int = 0, 'T6: l''amichevole non fa pagare le redistribuzioni';
  -- 100 vittorie: 2 punti
  update public.game_train_hero set spar_wins = 99 where user_id = pg_temp.uid('Ann');
  r := pg_temp.spar('Ann', 'Dan');
  assert (r->>'point_gained')::boolean and (pg_temp.gst('Ann')->'me'->>'train_points')::int = 2, 'T6: alla 100ª il secondo punto';
  insert into t_log (msg) values ('OK T6 — 1 punto abilità ogni 50 vittorie che contano; si distribuisce come gli altri; nessun costo di redistribuzione');
end $$;

-- T7 — limiti giornalieri: 10 vittorie al giorno, 3 contro lo stesso avversario, 30 combattimenti; il giorno dopo si riparte
do $$
declare r jsonb; i integer; w0 integer; opp text[] := array['Bob','Cid','Dan','Eve']; n integer;
begin
  delete from public.game_spar_log; update public.game_train_hero set spar_wins = 0;
  -- 3 contro lo stesso avversario, la 4ª non conta (motivo: avversario)
  for i in 1..3 loop r := pg_temp.spar('Ann', 'Bob'); assert (r->>'counted')::boolean, 'T7: le prime 3 contro Bob contano'; end loop;
  r := pg_temp.spar('Ann', 'Bob');
  assert (r->>'won')::boolean and not (r->>'counted')::boolean and r->>'reason' = 'pair' and pg_temp.sw('Ann') = 3, 'T7: la 4ª contro lo stesso avversario non conta';
  -- altri avversari fino a 10 in tutto
  for i in 1..3 loop perform pg_temp.spar('Ann', 'Cid'); end loop;
  for i in 1..3 loop perform pg_temp.spar('Ann', 'Dan'); end loop;
  r := pg_temp.spar('Ann', 'Eve');
  assert (r->>'counted')::boolean and pg_temp.sw('Ann') = 10 and (r->>'today_counted')::int = 10, 'T7: la 10ª vittoria del giorno conta';
  r := pg_temp.spar('Ann', 'Eve');
  assert (r->>'won')::boolean and not (r->>'counted')::boolean and r->>'reason' = 'day' and pg_temp.sw('Ann') = 10, 'T7: l''11ª non conta (limite giornaliero)';
  assert (pg_temp.tst('Ann')->'spar'->'today'->>'counted')::int = 10 and (pg_temp.tst('Ann')->'spar'->'pair'->>(pg_temp.uid('Bob')::text))::int = 3, 'T7: lo stato mostra i conteggi di oggi e per avversario';
  -- tetto ai combattimenti totali
  update public.system_settings set value_int = 14 where key = 'game_train_spar_day_fights';
  select count(*) into n from public.game_spar_log where user_id = pg_temp.uid('Ann') and day = public._game_today();
  while n < 14 loop perform pg_temp.spar('Ann', 'Bob'); n := n + 1; end loop;
  assert pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%abbastanza amichevoli per oggi%', 'T7: tetto ai combattimenti del giorno';
  -- il giorno dopo si riparte
  update public.game_spar_log set day = day - 1;
  r := pg_temp.spar('Ann', 'Bob');
  assert (r->>'counted')::boolean and pg_temp.sw('Ann') = 11, 'T7: il giorno dopo i limiti ripartono';
  -- le impostazioni dell'admin comandano
  update public.system_settings set value_int = 1 where key = 'game_train_spar_day_wins';
  r := pg_temp.spar('Ann', 'Cid');
  assert not (r->>'counted')::boolean and r->>'reason' = 'day', 'T7: impostazione game_train_spar_day_wins';
  update public.system_settings set value_int = 10 where key = 'game_train_spar_day_wins'; update public.system_settings set value_int = 30 where key = 'game_train_spar_day_fights';
  update public.system_settings set value_int = 2 where key = 'game_train_wins_per_point';
  update public.game_train_hero set spar_wins = 3 where user_id = pg_temp.uid('Ann');
  assert (pg_temp.tst('Ann')->>'train_points')::int = 1 and (pg_temp.tst('Ann')->'spar'->>'to_next')::int = 1, 'T7: impostazione game_train_wins_per_point';
  update public.system_settings set value_int = 50 where key = 'game_train_wins_per_point';
  insert into t_log (msg) values ('OK T7 — limiti: 10 vittorie/giorno, 3 per avversario, tetto ai combattimenti; ripartono il giorno dopo; impostazioni');
end $$;

-- T8 — durante l'allenamento restano possibili duelli, Torre e boss (si bloccano solo i dungeon); un solo tipo di allenamento
do $$
declare r jsonb; e0 numeric; m0 text;
begin
  perform pg_temp.fill('Ann'); perform pg_temp.fill('Eve');
  assert public._game_train_busy(pg_temp.uid('Ann')), 'T8: premessa: Ann è in allenamento amichevole';
  r := pg_temp.duel('Ann', 'Eve');
  assert (r->>'won')::boolean and (r->>'xp')::bigint > 0, 'T8: un duello vero funziona e dà XP anche in allenamento';
  assert pg_temp.err_as('Ann', 'select public.game_tower_state()') is null, 'T8: la Torre non è bloccata';
  assert pg_temp.err_as('Ann', 'select public.game_arena_list()') is null, 'T8: l''elenco dell''Arena funziona';
  assert (select count(*) from public.game_duels where attacker_id = pg_temp.uid('Ann')) = 1 and (select count(*) from public.game_spar_log where user_id = pg_temp.uid('Ann') and day = public._game_today()) >= 1, 'T8: duelli e amichevoli sono registri separati';
  insert into t_log (msg) values ('OK T8 — duelli, Torre e Arena non sono bloccati dall''allenamento');
end $$;

-- T9 — permessi: sospesi, modulo spento, anonimi
do $$
declare s text;
begin
  update public.profiles set suspended = true where id = pg_temp.uid('Fay');
  assert pg_temp.err_as('Fay', 'select public.game_train_state()') like '%sospeso%' and pg_temp.err_as('Fay', 'select public.game_train_start(''spar'')') like '%sospeso%' and pg_temp.err_as('Fay', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%sospeso%', 'T9: un sospeso non si allena';
  update public.profiles set suspended = false where id = pg_temp.uid('Fay');
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_train_state()') like '%Modulo non attivo%' and pg_temp.err_as('Ann', 'select public.game_train_start(''spar'')') like '%Modulo non attivo%' and pg_temp.err_as('Ann', format('select public.game_spar(%L)', pg_temp.uid('Bob'))) like '%Modulo non attivo%', 'T9: modulo spento';
  perform pg_temp.mod(true);
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.game_train_state()') like '%Accesso richiesto%', 'T9: senza accesso nulla';
  assert pg_temp.err_auth('Bob', 'select 1 from public.game_train_hero') like '%permission denied%', 'T9: tabella dei contatori chiusa';
  perform pg_temp.as_('Bob'); set local role anon;
  begin perform public.game_train_state(); s := null; exception when others then s := sqlerrm; end;
  reset role;
  assert s like '%permission denied%', 'T9: gli anonimi non possono chiamare le funzioni';
  insert into t_log (msg) values ('OK T9 — permessi: sospesi, modulo spento, anonimi');
end $$;

-- T10 — nessun movimento di BC in tutta la prova (a parte i regali di prova e il duello, che dà solo XP)
do $$
begin
  assert pg_temp.money() = (select h from t_money), 'T10: BC e registro invariati';
  insert into t_log (msg) values ('OK T10 — nessun BC mosso');
end $$;

select msg as esito from t_log order by n;
rollback;
