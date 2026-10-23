-- =====================================================================
-- TEST DELLA MIGRAZIONE 023 (salire di livello ricarica l'energia al 100%)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…023 (black-market-setup.sql … black-market-eroi-livello-energia.sql).
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


create function pg_temp.en(n text) returns numeric language sql as $$ select public._game_energy_of(pg_temp.uid(n)) $$;
create function pg_temp.setup(n text, lvl integer, xp_left integer, en numeric) returns void language plpgsql as $$
begin   -- livello, XP mancanti al prossimo livello, energia attuale
  update public.game_heroes set level = lvl, xp = public._game_xp_need(lvl) - xp_left, energy = en, energy_at = now() where user_id = pg_temp.uid(n);
end $$;
create function pg_temp.duel(a text, b text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(a); return public.game_duel(pg_temp.uid(b)); end $$;

-- E1 — la funzione dell'XP: livello su → batteria piena; nessun livello → energia com'era
do $$
declare r jsonb; n text;
begin
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan'] loop perform pg_temp.st(n); perform pg_temp.setst(n); end loop;
  assert not has_function_privilege('authenticated', 'public._game_add_xp(uuid,bigint)', 'execute'), 'E1: la funzione dell''XP è interna';
  perform pg_temp.setup('Ann', 5, 50, 10);
  r := public._game_add_xp(pg_temp.uid('Ann'), 10);
  assert (r->>'levels')::int = 0 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Ann') - 10) < 0.5, 'E1: senza livello l''energia non cambia';
  r := public._game_add_xp(pg_temp.uid('Ann'), 60);
  assert (r->>'levels')::int = 1 and (r->>'energy_full')::boolean and pg_temp.en('Ann') = public._game_energy_max(), 'E1: salito di livello: energia al massimo';
  assert (select level from public.game_heroes where user_id = pg_temp.uid('Ann')) = 6, 'E1: livello 6';
  perform pg_temp.setup('Bob', 5, 50, 0);
  r := public._game_add_xp(pg_temp.uid('Bob'), 5000);
  assert (r->>'levels')::int > 1 and pg_temp.en('Bob') = public._game_energy_max(), 'E1: più livelli di colpo: una sola ricarica, al massimo';
  perform pg_temp.setup('Cid', 5, 50, 100);
  r := public._game_add_xp(pg_temp.uid('Cid'), 60);
  assert pg_temp.en('Cid') = public._game_energy_max(), 'E1: già piena: resta piena';
  update public.game_heroes set level = 9999, xp = 0, energy = 20, energy_at = now() where user_id = pg_temp.uid('Dan');
  r := public._game_add_xp(pg_temp.uid('Dan'), 1000);
  assert (r->>'levels')::int = 0 and abs(pg_temp.en('Dan') - 20) < 0.5, 'E1: al livello massimo non si ricarica nulla';
  insert into t_log (msg) values ('OK E1 — livello su → energia al 100%; senza livello, al livello massimo o già piena nessun cambiamento anomalo');
end $$;

-- E2 — duello in Arena: il costo si paga, ma se si sale di livello l'energia finisce a 100%
do $$
declare r jsonb; e0 numeric;
begin
  -- Ann diventa fortissima, Eve è debole: la vittoria è praticamente certa
  update public.game_heroes set level = 60, a_for = 200, a_des = 100, a_vig = 100, a_spi = 50, a_frt = 100, stats_set = true where user_id = pg_temp.uid('Ann');
  perform pg_temp.setup('Ann', 60, 1, 40);
  perform pg_temp.st('Eve'); perform pg_temp.setst('Eve');
  r := pg_temp.duel('Ann', 'Eve');
  assert (r->>'won')::boolean and (r->>'levels')::int > 0, 'E2: premessa: vinto e salito di livello';
  assert (r->>'energy_full')::boolean and (r->>'energy')::numeric = public._game_energy_max() and pg_temp.en('Ann') = public._game_energy_max(), 'E2: energia al 100% dopo il duello del livello';
  -- senza salire di livello: costo normale
  perform pg_temp.setup('Ann', 60, 600, 60);
  r := pg_temp.duel('Ann', 'Eve');
  assert (r->>'won')::boolean and (r->>'levels')::int = 0 and not (r->>'energy_full')::boolean, 'E2: premessa: vinto senza salire';
  assert abs(pg_temp.en('Ann') - (60 - (r->>'energy_cost')::numeric)) < 0.5 and abs((r->>'energy')::numeric - pg_temp.en('Ann')) < 0.5, 'E2: senza livello, si paga il costo del duello';
  insert into t_log (msg) values ('OK E2 — duello: con il livello energia 100% (risposta e database), senza livello il costo normale');
end $$;

-- E3 — boss sconfitto: chi sale di livello con il premio ha la batteria piena
do $$
declare r jsonb; l bigint;
begin
  perform pg_temp.setup('Cid', 3, 5, 15);
  perform pg_temp.setup('Dan', 3, 120, 15);
  r := pg_temp.join_('Cid'); l := (r->>'lobby')::bigint; perform pg_temp.join_('Dan', l); perform pg_temp.start_('Cid');
  update public.game_lobbies set hp = 1 where id = l;
  r := pg_temp.act('Cid', 'attack');
  assert (r->>'defeated')::boolean and (r->'reward'->>'levels')::int > 0, 'E3: premessa: boss battuto, Cid sale di livello';
  assert pg_temp.en('Cid') = public._game_energy_max(), 'E3: Cid ha l''energia al 100%';
  assert abs(pg_temp.en('Dan') - 15) < 0.5, 'E3: Dan, che non sale di livello, resta com''era';
  insert into t_log (msg) values ('OK E3 — boss: la ricarica vale per chi sale di livello, non per gli altri della lobby');
end $$;

-- E4 — coerenza: nessun BC creato, saldi = registro
do $$
begin
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'E4: saldi = registro';
  assert (select max(energy) from public.game_heroes) <= public._game_energy_max(), 'E4: energia mai oltre il massimo';
  insert into t_log (msg) values ('OK E4 — saldi = registro, energia entro il massimo');
end $$;

select msg from t_log order by n;
rollback;
