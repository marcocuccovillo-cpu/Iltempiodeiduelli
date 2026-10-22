-- =====================================================================
-- TEST DELLA MIGRAZIONE 016 (La guerra degli Eroi: duelli liberi, solo l'energia come freno)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…016 (black-market-setup.sql … black-market-eroi-duelli-liberi.sql).
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
create function pg_temp.calc(n text) returns jsonb language sql as $$ select to_jsonb(c) from public._game_calc(pg_temp.uid(n)) c $$;
create function pg_temp.join_(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_join(); end $$;
create function pg_temp.buys(n text, k text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_buy_skill(k); end $$;



create function pg_temp.en(n text) returns numeric language sql as $$ select public._game_energy_of(pg_temp.uid(n)) $$;
-- eroi pronti
do $$
declare n text;
begin
  foreach n in array array['Ann','Bob','Cid','Eve'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.setst('Ann', 10, 4, 4, 2, 0); perform pg_temp.setst('Bob', 4, 4, 4, 4, 4); perform pg_temp.setst('Cid', 6, 6, 4, 2, 2); perform pg_temp.setst('Eve', 8, 8, 2, 1, 1);
  perform pg_temp.mod(true);
  assert (select count(*) from public.game_heroes where stats_set) = 4, 'X: 4 eroi pronti';
end $$;

-- X1 — si può sfidare lo stesso eroe quante volte si vuole
do $$
declare r jsonb; i integer; t0 bigint; b0 integer; x0 bigint; lst jsonb;
begin
  assert not exists (select 1 from pg_constraint where conrelid = 'public.game_duels'::regclass and contype = 'u'), 'X1: niente più vincolo di unicità sui duelli';
  perform pg_temp.lvl('Ann', 300);
  update public.game_heroes set energy = 100, energy_at = now() where true;
  t0 := pg_temp.tot(); b0 := pg_temp.bal('Ann'); x0 := (pg_temp.hero('Ann')).total_xp;
  for i in 1..4 loop
    r := pg_temp.duel('Ann', 'Bob');
    assert (r->>'won')::boolean and (r->>'energy_cost')::int = 5 and (r->>'energy')::numeric = 100 - 5 * i, 'X1: duello ' || i || ' contro Bob: vinto, costa 5';
    assert (r->>'xp')::int > 0, 'X1: ogni vittoria dà XP';
  end loop;
  assert (select count(*) from public.game_duels where attacker_id = pg_temp.uid('Ann') and defender_id = pg_temp.uid('Bob') and day = public._game_today()) = 4, 'X1: 4 duelli registrati contro lo stesso eroe, nello stesso giorno';
  assert pg_temp.en('Ann') = 80, 'X1: energia 80';
  assert pg_temp.tot() = t0 and pg_temp.bal('Ann') = b0, 'X1: nessun BC mosso';
  assert (pg_temp.hero('Ann')).total_xp > x0, 'X1: l''XP è cresciuta';
  perform pg_temp.as_('Ann'); lst := public.game_arena_list();
  assert (select (x->>'fights_today')::int from jsonb_array_elements(lst) x where x->>'nickname' = 'Bob') = 4, 'X1: l''elenco dell''Arena dice 4 duelli oggi contro Bob';
  assert (select (x->>'fights_today')::int from jsonb_array_elements(lst) x where x->>'nickname' = 'Cid') = 0 and (select (x->>'fought_today')::boolean from jsonb_array_elements(lst) x where x->>'nickname' = 'Bob'), 'X1: 0 contro Cid; «già sfidato» resta vero per Bob';
  r := pg_temp.duel('Bob', 'Ann');
  r := pg_temp.duel('Bob', 'Ann');
  assert (select count(*) from public.game_duels where attacker_id = pg_temp.uid('Bob') and defender_id = pg_temp.uid('Ann')) = 2, 'X1: anche nell''altro verso, più volte';
  insert into t_log (msg) values ('OK X1 — stesso avversario più volte al giorno: ogni duello costa energia, dà XP, non muove BC');
end $$;

-- X2 — l'unico freno è l'energia
do $$
declare r jsonb; i integer := 0; e text; n numeric;
begin
  update public.game_heroes set energy = 17, energy_at = now() where user_id = pg_temp.uid('Ann');
  loop
    i := i + 1; assert i < 10, 'X2: dovrebbe fermarsi per energia';
    e := pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Cid') || '''::uuid)');
    exit when e is not null;
  end loop;
  assert e like 'Energia insufficiente%', 'X2: si ferma con «Energia insufficiente»: ' || e;
  n := pg_temp.en('Ann');
  assert n < 8 and i between 2 and 4, 'X2: da 17 di energia si fa 2–3 duelli e poi si resta sotto 8 (' || n || ', ' || i || ')';
  update public.game_heroes set energy = 0, energy_at = now() - interval '2 hours' where user_id = pg_temp.uid('Ann');
  assert abs(pg_temp.en('Ann') - 25) < 0.01, 'X2: dopo 2 ore di ricarica 25';
  r := pg_temp.duel('Ann', 'Cid');
  assert (r->>'won')::boolean and (r->>'energy')::numeric = 20, 'X2: ricaricato, si sfida di nuovo lo stesso eroe (25 − 5)';
  insert into t_log (msg) values ('OK X2 — con energia sotto 8 il duello è rifiutato; ricaricando si riprende anche contro lo stesso eroe');
end $$;

-- X3 — il resto delle regole non è cambiato
do $$
begin
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Ann') || '''::uuid)') = 'Scegli un altro eroe da sfidare', 'X3: non si sfida se stessi';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), true, 'prova');
  update public.game_heroes set energy = 100, energy_at = now() where true;
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Eve') || '''::uuid)') = 'Eroe non disponibile', 'X3: un sospeso non si sfida';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), false, 'ripristino');
  update public.game_heroes set arena_open = false where user_id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Bob') || '''::uuid)') = 'Questo eroe non accetta sfide in Arena', 'X3: Arena chiusa rispettata';
  update public.game_heroes set arena_open = true where user_id = pg_temp.uid('Bob');
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  assert pg_temp.err('select public.game_duel(null)') is not null, 'X3: serve il login';
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_duel(''' || pg_temp.uid('Bob') || '''::uuid)') = 'Modulo non attivo', 'X3: a modulo spento tutto è bloccato';
  perform pg_temp.mod(true);
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'X3: saldi = registro';
  assert not exists (select 1 from public.ledger_entries where kind like 'game\_%' and kind <> 'game_boss_reward' and amount > 0) , 'X3: i duelli non creano BC';
  insert into t_log (msg) values ('OK X3 — sé stessi, sospesi, Arena chiusa, login, modulo spento, saldi = registro');
end $$;

select n, msg from t_log order by n;
rollback;
