-- =====================================================================
-- TEST DELLA MIGRAZIONE 021 (Boss: premi a tutta la lobby e una lobby al giorno per ogni giocatore)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…021 (black-market-setup.sql … black-market-eroi-lobby.sql).
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

-- Preparazione: Admin (primo registrato), Org organizzatore e 8 duellanti
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova');
  insert into t_log (msg) values ('OK Preparazione: 10 utenti');
end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.tot() returns bigint language sql as $$ select coalesce(sum(balance), 0) from public.wallets $$;
create function pg_temp.st(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
create function pg_temp.setst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_set_stats(8, 4, 4, 2, 2); end $$;
create function pg_temp.act(n text, a text, t text default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_boss_act(a, case when t is null then null else pg_temp.uid(t) end); end $$;
create function pg_temp.join_(n text, p_lobby bigint default null) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_join(p_lobby); end $$;
create function pg_temp.leave_(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_leave(); end $$;
create function pg_temp.start_(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_start(); end $$;
create function pg_temp.lob(n text) returns bigint language sql as $$ select lobby_id from public.game_day_heroes where user_id = pg_temp.uid(n) and day = public._game_today() $$;
create function pg_temp.mod(on_ boolean) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', on_, 'prova del modulo'); end $$;
-- «passa un giorno»: sposta indietro di 1 giorno tutto ciò che è legato alla data
create function pg_temp.shift() returns void language plpgsql as $$
declare r record;
begin
  for r in select day from public.game_days order by day asc loop update public.game_days set day = day - 1 where day = r.day; end loop;
  for r in select distinct day from public.game_merchant_offers order by day asc loop update public.game_merchant_offers set day = day - 1 where day = r.day; end loop;
  alter table public.game_rewards disable trigger user;
  update public.game_rewards set day = day - 1;
  alter table public.game_rewards enable trigger user;
  -- anche le chiavi di idempotenza dei premi seguono la data (in produzione i giorni non si ripetono: qui sì)
  alter table public.ledger_entries disable trigger ledger_immutable;
  for r in select distinct split_part(idempotency_key, ':', 2)::date as dd from public.ledger_entries where idempotency_key like 'gameboss:%' order by 1 asc loop
    update public.ledger_entries set idempotency_key = 'gameboss:' || (r.dd - 1)::text || ':' || split_part(idempotency_key, ':', 3)
      where idempotency_key like 'gameboss:' || r.dd::text || ':%';
  end loop;
  alter table public.ledger_entries enable trigger ledger_immutable;
end $$;
create function pg_temp.exp_hp(p_no integer, p_cycle integer, uids uuid[]) returns bigint language plpgsql as $$
declare s numeric := 0; u uuid; c record;
begin
  foreach u in array uids loop select * into c from public._game_calc(u); s := s + c.s_for * 3; end loop;
  return greatest(50, ceil(s * public._setting('game_daily_actions') * (select coverage from public.game_bosses where no = p_no) * (1 + 0.25 * p_cycle)
                           * public._setting('game_boss_difficulty') / 100.0))::bigint;
end $$;

-- L1 — struttura, impostazioni, permessi
do $$
begin
  assert to_regclass('public.game_lobbies') is not null, 'L1: tabella delle lobby';
  assert (select count(*) from public.system_settings where key = 'game_boss_min_actions') = 0, 'L1: il minimo di azioni non esiste più';
  assert (select value_int from public.system_settings where key = 'game_boss_min_players') = 1, 'L1: lobby da 1 giocatore (modificabile)';
  assert (select is_nullable from information_schema.columns where table_name = 'game_day_heroes' and column_name = 'lobby_id') = 'NO', 'L1: ogni eroe in campo ha una lobby';
  assert (select is_nullable from information_schema.columns where table_name = 'game_day_log' and column_name = 'lobby_id') = 'NO', 'L1: ogni azione ha una lobby';
  assert has_function_privilege('authenticated', 'public.game_boss_join(bigint)', 'execute') and not has_function_privilege('anon', 'public.game_boss_join(bigint)', 'execute'), 'L1: join solo da autenticati';
  assert not has_function_privilege('authenticated', 'public._game_finish_lobby(bigint)', 'execute'), 'L1: la chiusura è interna';
  assert to_regprocedure('public._game_finish_boss(date)') is null and to_regprocedure('public.game_boss_join()') is null, 'L1: le vecchie funzioni non ci sono più';
  assert (select relrowsecurity from pg_class where oid = 'public.game_lobbies'::regclass), 'L1: RLS attiva sulle lobby';
  assert not has_table_privilege('authenticated', 'public.game_lobbies', 'insert') and not has_table_privilege('authenticated', 'public.game_lobbies', 'update')
     and not has_table_privilege('authenticated', 'public.game_lobbies', 'delete') and not has_table_privilege('anon', 'public.game_lobbies', 'select'), 'L1: lobby in sola lettura';
  insert into t_log (msg) values ('OK L1 — tabella lobby protetta, min giocatori 1, minimo azioni tolto, vecchie funzioni tolte');
end $$;

-- L2 — i premi vanno a TUTTI quelli della lobby
do $$
declare r jsonb; n text; l bigint; b0 jsonb := '{}'; t0 bigint; inv0 bigint; xp0 jsonb := '{}';
begin
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop perform pg_temp.st(n); perform pg_temp.setst(n); end loop;
  r := pg_temp.join_('Ann'); l := (r->>'lobby')::bigint;
  assert (r->>'players')::int = 1 and l is not null, 'L2: Ann crea la sua lobby';
  perform pg_temp.join_('Bob', l); perform pg_temp.join_('Cid', l); perform pg_temp.join_('Dan', l); r := pg_temp.join_('Eve', l);
  assert (r->>'players')::int = 5, 'L2: cinque nella lobby';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), true, 'sospesa per la prova');
  r := pg_temp.start_('Bob');
  assert (r->>'players')::int = 4 and (select status from public.game_lobbies where id = l) = 'open', 'L2: parte con 4 (la sospesa è fuori)';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), false, 'ripristino');
  -- solo Ann agisce davvero; Bob non fa nulla; Cid fa 1 azione; Dan va KO senza agire
  update public.game_day_heroes set hp = 0 where user_id = pg_temp.uid('Dan') and day = public._game_today();
  perform pg_temp.act('Cid', 'study');
  assert (select actions_used from public.game_day_heroes where user_id = pg_temp.uid('Bob') and day = public._game_today()) = 0, 'L2: Bob non ha fatto azioni';
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop
    b0 := b0 || jsonb_build_object(n, pg_temp.bal(n));
    xp0 := xp0 || jsonb_build_object(n, (select xp + level * 100000 from public.game_heroes where user_id = pg_temp.uid(n)));
  end loop;
  t0 := pg_temp.tot(); select count(*) into inv0 from public.game_inventory where source = 'boss';
  update public.game_lobbies set hp = 1 where id = l;
  r := pg_temp.act('Ann', 'attack');
  assert (r->>'defeated')::boolean and (r->'reward'->>'bc')::int = 100, 'L2: boss sconfitto, Ann riceve 100 BC';
  foreach n in array array['Ann','Bob','Cid','Dan'] loop
    assert pg_temp.bal(n) = (b0->>n)::int + 100, 'L2: ' || n || ' riceve 100 BC anche con poche o zero azioni (o KO)';
    assert exists (select 1 from public.game_rewards where day = public._game_today() and user_id = pg_temp.uid(n) and bc = 100 and xp > 0 and item_id is not null), 'L2: ' || n || ' ha la ricompensa con XP e oggetto';
    assert (select xp + level * 100000 from public.game_heroes where user_id = pg_temp.uid(n)) > (xp0->>n)::bigint, 'L2: ' || n || ' guadagna XP';
    assert (select bosses_beaten from public.game_heroes where user_id = pg_temp.uid(n)) = 1, 'L2: ' || n || ' ha un boss battuto';
  end loop;
  foreach n in array array['Eve','Fay','Gus','Hal','Org','Admin'] loop assert pg_temp.bal(n) = (b0->>n)::int, 'L2: ' || n || ' non era nella lobby: niente premio'; end loop;
  assert pg_temp.tot() = t0 + 400 and (select count(*) from public.game_rewards where day = public._game_today()) = 4, 'L2: 400 BC in tutto, 4 ricompense';
  assert (select count(*) from public.game_inventory where source = 'boss') = inv0 + 4, 'L2: 4 oggetti consegnati';
  assert (select count(*) from public.ledger_entries where kind = 'game_boss_reward') = 4, 'L2: 4 movimenti nel registro';
  perform public._game_finish_lobby(l); perform public._game_finish_lobby(l);
  assert pg_temp.tot() = t0 + 400 and (select count(*) from public.game_rewards where day = public._game_today()) = 4, 'L2: richiamare la chiusura non paga due volte';
  assert (select status from public.game_days where day = public._game_today()) = 'defeated', 'L2: il boss del giorno risulta battuto';
  -- uno sospeso DOPO la partenza non viene pagato
  r := pg_temp.join_('Fay'); l := (r->>'lobby')::bigint; perform pg_temp.join_('Gus', l); perform pg_temp.join_('Hal', l); perform pg_temp.start_('Fay');
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Hal'), true, 'sospeso a metà');
  update public.game_lobbies set hp = 1 where id = l;
  r := pg_temp.act('Fay', 'attack');
  assert (r->>'defeated')::boolean and pg_temp.bal('Fay') = (b0->>'Fay')::int + 100 and pg_temp.bal('Gus') = (b0->>'Gus')::int + 100, 'L2: Fay e Gus pagati';
  assert pg_temp.bal('Hal') = (b0->>'Hal')::int and not exists (select 1 from public.game_rewards where user_id = pg_temp.uid('Hal')), 'L2: chi è sospeso non incassa';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Hal'), false, 'ripristino');
  insert into t_log (msg) values ('OK L2 — premi (BC, XP, oggetto) a tutta la lobby anche con 0 azioni o KO; fuori lobby e sospesi no; mai doppi');
end $$;

-- L3 — lobby multiple: una al giorno per giocatore, ciascuna con il suo boss
do $$
declare r jsonb; l1 bigint; l2 bigint; l3 bigint; j jsonb; hp1 bigint; mem uuid[];
begin
  perform pg_temp.shift();
  perform pg_temp.st('Ann');
  assert (select boss_no from public.game_days where day = public._game_today()) = 2 and (select status from public.game_days where day = public._game_today()) = 'lobby', 'L3: ieri battuto, oggi il boss 2';
  assert (select count(*) from public.game_lobbies where day = public._game_today()) = 0, 'L3: oggi nessuna lobby';
  j := pg_temp.st('Ann');
  assert (j->'boss'->>'status') = 'lobby' and not (j->'boss'->>'joined')::boolean and jsonb_array_length(j->'boss'->'lobbies') = 0 and (j->'boss'->>'wins_today')::int = 0, 'L3: stato vuoto, nessuna lobby aperta';
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like 'Non sei in nessuna lobby%', 'L3: senza lobby non si combatte';
  assert pg_temp.err_as('Ann', 'select public.game_boss_start()') = 'Entra prima in una lobby', 'L3: senza lobby non si avvia';
  assert pg_temp.err_as('Ann', 'select public.game_boss_leave()') = 'Non sei in nessuna lobby', 'L3: senza lobby non si esce';
  assert pg_temp.err_as('Ann', 'select public.game_boss_join(999999)') = 'Lobby non trovata', 'L3: lobby inesistente';
  r := pg_temp.join_('Ann'); l1 := (r->>'lobby')::bigint;
  r := pg_temp.join_('Bob'); l2 := (r->>'lobby')::bigint;
  assert l1 <> l2 and (select count(*) from public.game_lobbies where day = public._game_today() and status = 'lobby') = 2, 'L3: ognuno ha creato la sua';
  j := pg_temp.st('Cid');
  assert jsonb_array_length(j->'boss'->'lobbies') = 2 and (j->'boss'->'lobbies'->0->>'players')::int = 1 and (j->'boss'->'lobbies'->0->>'host') = 'Ann', 'L3: Cid vede le due lobby aperte con il capo';
  r := pg_temp.join_('Cid', l1); assert (r->>'players')::int = 2, 'L3: Cid entra nella lobby di Ann';
  r := pg_temp.join_('Cid', l1); assert (r->>'players')::int = 2, 'L3: entrare di nuovo nella stessa non fa nulla';
  assert pg_temp.err_as('Cid', format('select public.game_boss_join(%s)', l2)) like 'Sei già in una lobby%', 'L3: una sola lobby alla volta';
  assert pg_temp.err_as('Cid', 'select public.game_boss_join()') is null, 'L3: join senza argomenti con lobby già mia: resta nella stessa';
  j := pg_temp.st('Cid');
  assert (j->'boss'->>'joined')::boolean and (j->'boss'->>'lobby_id')::bigint = l1 and jsonb_array_length(j->'boss'->'party') = 2 and jsonb_array_length(j->'boss'->'lobbies') = 0, 'L3: Cid vede solo il suo gruppo';
  r := pg_temp.join_('Dan', l2); assert (r->>'players')::int = 2, 'L3: Dan entra nella lobby di Bob';
  r := pg_temp.leave_('Dan'); assert (r->>'players')::int = 1, 'L3: Dan esce';
  r := pg_temp.join_('Dan'); l3 := (r->>'lobby')::bigint;
  assert l3 not in (l1, l2), 'L3: e crea la sua';
  r := pg_temp.leave_('Dan'); assert (r->>'players')::int = 0 and not exists (select 1 from public.game_lobbies where id = l3), 'L3: la lobby vuota sparisce';
  r := pg_temp.join_('Dan', l1); assert (r->>'players')::int = 3, 'L3: Dan entra con Ann e Cid';
  mem := array[pg_temp.uid('Ann'), pg_temp.uid('Cid'), pg_temp.uid('Dan')];
  r := pg_temp.start_('Ann');
  assert (r->>'players')::int = 3 and (r->>'boss_hp')::bigint = pg_temp.exp_hp(2, 0, mem) and (select hp from public.game_lobbies where id = l1) = (r->>'boss_hp')::bigint, 'L3: PV della lobby 1 sui suoi 3 eroi';
  assert (select status from public.game_lobbies where id = l2) = 'lobby', 'L3: la lobby di Bob è ancora in attesa';
  assert pg_temp.err_as('Ann', 'select public.game_boss_start()') = 'Il boss è già partito', 'L3: non si riavvia';
  assert pg_temp.err_as('Eve', format('select public.game_boss_join(%s)', l1)) like 'Questa lobby è già partita%', 'L3: una lobby partita è chiusa agli altri';
  assert pg_temp.err_as('Cid', 'select public.game_boss_leave()') like 'Il boss è già partito%', 'L3: da partita non si esce';
  assert pg_temp.err_as('Bob', 'select public.game_boss_act(''attack'')') like 'Il boss non è ancora partito%', 'L3: Bob non può agire finché non parte la sua';
  mem := array[pg_temp.uid('Bob')];
  r := pg_temp.start_('Bob');
  assert (r->>'players')::int = 1 and (r->>'boss_hp')::bigint = pg_temp.exp_hp(2, 0, mem), 'L3: Bob parte da solo, PV sul solo Bob';
  update public.game_lobbies set max_hp = max_hp * 1000, hp = hp * 1000 where id in (l1, l2);      -- così nessun colpo di prova chiude per caso la lobby
  select hp into hp1 from public.game_lobbies where id = l2;
  perform pg_temp.act('Ann', 'attack'); perform pg_temp.act('Ann', 'guard'); perform pg_temp.act('Cid', 'study');
  assert (select hp from public.game_lobbies where id = l2) = hp1 and (select shield from public.game_lobbies where id = l2) = 0 and (select weak from public.game_lobbies where id = l2) = 0, 'L3: la lobby di Bob non è toccata';
  assert (select hp from public.game_lobbies where id = l1) < (select max_hp from public.game_lobbies where id = l1) and (select shield from public.game_lobbies where id = l1) > 0 and (select weak from public.game_lobbies where id = l1) > 0, 'L3: la lobby 1 sì';
  perform pg_temp.act('Bob', 'attack');
  assert (select hp from public.game_lobbies where id = l2) < hp1, 'L3: e quella di Bob ha il suo colpo';
  assert (select count(*) from public.game_day_log where lobby_id = l1) = 3 and (select count(*) from public.game_day_log where lobby_id = l2) = 1, 'L3: cronache separate';
  update public.game_day_heroes set hp = hp - 1 where user_id = pg_temp.uid('Ann') and day = public._game_today();
  assert pg_temp.err_as('Bob', format('select public.game_boss_act(%L, %L)', 'heal', pg_temp.uid('Ann'))) = 'Questo eroe non è nella tua lobby', 'L3: non si cura chi sta in un''altra lobby';
  j := pg_temp.st('Cid');
  assert jsonb_array_length(j->'boss'->'party') = 3 and jsonb_array_length(j->'boss'->'log') = 3, 'L3: stato: gruppo e cronaca della sua lobby';
  j := pg_temp.st('Bob');
  assert jsonb_array_length(j->'boss'->'party') = 1 and jsonb_array_length(j->'boss'->'log') = 1 and (j->'boss'->>'max_hp')::bigint = (select max_hp from public.game_lobbies where id = l2), 'L3: stato di Bob: solo il suo';
  insert into t_log (msg) values ('OK L3 — più lobby al giorno, una per giocatore, ognuna con PV, scudo, debolezza e cronaca propri');
end $$;

-- L4 — chi ha già fatto la sua lobby non ne fa un'altra; ognuno può batterlo
do $$
declare r jsonb; l1 bigint := pg_temp.lob('Ann'); l2 bigint := pg_temp.lob('Bob'); l4 bigint; b0 integer; t0 bigint; j jsonb;
begin
  assert pg_temp.err_as('Ann', 'select public.game_boss_join()') like 'Hai già fatto la tua lobby di oggi%', 'L4: una lobby al giorno (Ann è in una partita)';
  assert pg_temp.err_as('Ann', format('select public.game_boss_join(%s)', l2)) like 'Hai già fatto la tua lobby di oggi%', 'L4: nemmeno entrando in un''altra';
  t0 := pg_temp.tot(); b0 := pg_temp.bal('Dan');
  update public.game_lobbies set hp = 1 where id = l1;
  r := pg_temp.act('Cid', 'attack');
  assert (r->>'defeated')::boolean, 'L4: la lobby 1 sconfigge il boss';
  assert pg_temp.tot() = t0 + 300 and pg_temp.bal('Dan') = b0 + 100, 'L4: premio ai 3 della lobby 1';
  assert (select status from public.game_lobbies where id = l2) = 'open' and (select hp from public.game_lobbies where id = l2) > 1, 'L4: la lobby di Bob combatte ancora';
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like 'Hai già sconfitto il boss di oggi con la tua lobby%', 'L4: Ann ha finito';
  assert pg_temp.err_as('Ann', 'select public.game_boss_join()') like 'Hai già fatto la tua lobby di oggi%', 'L4: e non ne rifà un''altra oggi';
  r := pg_temp.join_('Eve'); l4 := (r->>'lobby')::bigint;
  assert (select status from public.game_days where day = public._game_today()) = 'defeated' and l4 is not null, 'L4: il giorno risulta battuto ma Eve può aprire la sua lobby';
  j := pg_temp.st('Fay');
  assert (j->'boss'->>'wins_today')::int = 1 and jsonb_array_length(j->'boss'->'lobbies') = 1, 'L4: Fay vede 1 vittoria e la lobby di Eve';
  perform pg_temp.join_('Fay', l4); perform pg_temp.start_('Eve');
  t0 := pg_temp.tot();
  update public.game_lobbies set hp = 1 where id = l4;
  r := pg_temp.act('Fay', 'attack');
  assert (r->>'defeated')::boolean and pg_temp.tot() = t0 + 200, 'L4: la lobby di Eve batte il boss: 100 BC a Eve e a Fay';
  t0 := pg_temp.tot(); update public.game_lobbies set hp = 1 where id = l2;
  r := pg_temp.act('Bob', 'attack');
  assert (r->>'defeated')::boolean and pg_temp.tot() = t0 + 100 and (select count(*) from public.game_rewards where day = public._game_today()) = 6, 'L4: Bob lo batte da solo: 6 giocatori premiati oggi, nessuno due volte';
  assert (select count(*) from public.game_lobbies where day = public._game_today() and status = 'defeated') = 3, 'L4: tre lobby vittoriose';
  assert (select count(*) from (select user_id from public.game_rewards where day = public._game_today() group by user_id having count(*) > 1) x) = 0, 'L4: un solo premio per giocatore al giorno';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('game_boss_min_players', 2, 'prova');
  r := pg_temp.join_('Gus');
  assert pg_temp.err_as('Gus', 'select public.game_boss_start()') like 'Servono almeno 2 giocatori%(ora 1)', 'L4: con il minimo a 2 non si parte da soli';
  perform pg_temp.join_('Hal', (r->>'lobby')::bigint);
  assert (pg_temp.start_('Gus')->>'players')::int = 2, 'L4: in due si parte';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('game_boss_min_players', 1, 'ripristino');
  insert into t_log (msg) values ('OK L4 — una lobby al giorno, tre lobby che battono lo stesso boss, minimo giocatori regolabile');
end $$;

-- L5 — nuovo giorno: avanza il boss, le lobby non finite scappano, il modulo spento blocca tutto
do $$
declare r jsonb; l bigint;
begin
  assert (select count(*) from public.game_lobbies where status = 'open') = 1, 'L5: una lobby ancora aperta (Gus e Hal)';
  perform pg_temp.shift();
  perform pg_temp.st('Ann');
  assert (select boss_no from public.game_days where day = public._game_today()) = 3, 'L5: battuto il 2 → oggi il 3';
  assert (select count(*) from public.game_lobbies where status = 'open') = 0 and (select count(*) from public.game_lobbies where status = 'escaped') = 1, 'L5: la lobby di ieri non finita è «scappata»';
  assert not (pg_temp.st('Gus')->'boss'->>'joined')::boolean, 'L5: oggi si riparte da zero';
  assert (pg_temp.st('Gus')->'boss'->'previous'->>'status') = 'defeated', 'L5: ieri risulta battuto (da altre lobby)';
  r := pg_temp.join_('Gus'); l := (r->>'lobby')::bigint; perform pg_temp.start_('Gus');
  perform pg_temp.shift();
  perform pg_temp.st('Gus');
  assert (select boss_no from public.game_days where day = public._game_today()) = 3 and (select status from public.game_lobbies where id = l) = 'escaped', 'L5: nessuna vittoria → il boss 3 ritorna';
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_boss_join()') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_boss_start()') = 'Modulo non attivo'
     and pg_temp.err_as('Ann', 'select public.game_boss_leave()') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') = 'Modulo non attivo', 'L5: modulo spento';
  perform pg_temp.mod(true);
  assert pg_temp.err('select public.game_boss_join()') is not null, 'L5: serve il login';
  assert pg_temp.err_auth('Ann', 'insert into public.game_lobbies (day) values (current_date)') is not null and pg_temp.err_auth('Ann', 'update public.game_lobbies set hp = 0') is not null
     and pg_temp.err_auth('Ann', 'update public.game_day_heroes set hp = 0') is not null, 'L5: nessuna scrittura diretta';
  assert pg_temp.rows_as('Ann', 'select * from public.game_lobbies') >= 1, 'L5: le lobby si leggono';
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind = 'game_boss_reward') = 100 * (select count(*) from public.game_rewards where bc > 0), 'L5: BC creati solo dai boss, uno per ricompensa';
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'L5: saldi = registro';
  insert into t_log (msg) values ('OK L5 — progressione tra giorni, lobby non finite chiuse, modulo spento e permessi');
end $$;

select msg from t_log order by n;
rollback;
