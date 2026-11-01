-- TEST della migrazione 036 (Arena a classifica). Da eseguire SOLO su un database di prova VUOTO (per esempio un secondo progetto Supabase
-- gratuito), dopo le migrazioni degli Eroi e la 036. Finisce con rollback: non lascia nulla. Mai sul database reale.
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

do $$ begin if to_regprocedure('public.game_arena_state()') is null then raise exception 'Prima esegui la migrazione 036 (black-market-eroi-arena.sql). Non è stato modificato nulla.'; end if; end $$;

-- ---------- supporto dell'Arena ----------
create function pg_temp.ast(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_arena_state(); end $$;
create function pg_temp.alist(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_arena_list(); end $$;
create function pg_temp.dl(a text, b text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(a); return public.game_duel(pg_temp.uid(b)); end $$;
create function pg_temp.pts(n text) returns integer language sql as $$ select (pg_temp.ast(n)->'me'->>'points')::integer $$;
create function pg_temp.setpts(n text, p integer) returns void language sql as $$
  insert into public.game_arena_rating (user_id, season, points, best) values (pg_temp.uid(n), public._game_arena_season(), p, p)
  on conflict (user_id, season) do update set points = excluded.points, best = greatest(game_arena_rating.best, excluded.points) $$;
create function pg_temp.clr() returns void language sql as $$ delete from public.game_arena_log; delete from public.game_arena_rating $$;

do $$ declare n text; begin
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay'] loop perform public._game_ensure_hero(pg_temp.uid(n)); end loop;
  perform pg_temp.hero_('Ann', 100, 80, 70, 70, 50, 30);
  perform pg_temp.hero_('Bob', 1, 5, 5, 5, 3, 2); perform pg_temp.hero_('Cid', 1, 5, 5, 5, 3, 2); perform pg_temp.hero_('Dan', 1, 5, 5, 5, 3, 2);
  perform pg_temp.hero_('Eve', 1, 5, 5, 5, 3, 2); perform pg_temp.hero_('Fay', 100, 100, 100, 100, 100, 100);
  insert into t_log (msg) values ('OK Preparazione: 6 eroi');
end $$;
create temp table t_money (h text);
insert into t_money select pg_temp.money();

-- A1 — scheda iniziale; tabelle e funzioni interne chiuse al browser; permessi
do $$
declare s jsonb; r jsonb;
begin
  s := pg_temp.ast('Ann');
  assert s->>'season' = public._game_arena_season() and s->>'season' ~ '^[0-9]{4}-[0-9]{2}$', 'A1: stagione = mese di oggi';
  assert (s->'me'->>'points')::integer = 1000 and s->'me'->>'league' = 'argento', 'A1: si parte da 1000 punti, lega Argento';
  assert s->'me'->'rank' = 'null'::jsonb and (s->'me'->>'wins')::integer = 0, 'A1: nessuna posizione prima della prima sfida';
  assert (s->'me'->'next_league'->>'name') = 'Oro' and (s->'me'->'next_league'->>'min_points')::integer = 1100 and (s->'me'->>'league_min')::integer = 900, 'A1: prossima lega Oro a 1100';
  assert jsonb_array_length(s->'leagues') = 6 and s->'leagues'->0->>'key' = 'bronzo' and s->'leagues'->5->>'key' = 'leggenda', 'A1: sei leghe in ordine';
  assert (s->>'days_left')::integer = (date_trunc('month', public._game_today()) + interval '1 month')::date - public._game_today() and (s->>'ends_on')::date = (date_trunc('month', public._game_today()) + interval '1 month')::date - 1, 'A1: giorni alla fine della stagione (oggi incluso)';
  assert s->'board' = '[]'::jsonb and s->'last_season' = 'null'::jsonb and s->'recent' = '[]'::jsonb, 'A1: classifica, albo e cronologia vuoti';
  assert (s->>'k')::integer = 32 and (s->>'pair_max')::integer = 3 and (s->>'start')::integer = 1000, 'A1: parametri';
  assert pg_temp.err_auth('Ann', 'select * from public.game_arena_rating') is not null, 'A1: punti chiusi al browser';
  assert pg_temp.err_auth('Ann', 'select * from public.game_arena_log') is not null, 'A1: registro chiuso al browser';
  assert pg_temp.err_auth('Ann', 'select * from public.game_arena_leagues') is not null, 'A1: leghe chiuse al browser';
  assert pg_temp.err_auth('Ann', 'select public._game_arena_record(gen_random_uuid(), ' || quote_literal(pg_temp.uid('Ann')) || '::uuid, ' || quote_literal(pg_temp.uid('Bob')) || '::uuid, true, current_date)') is not null, 'A1: _game_arena_record chiusa';
  assert pg_temp.err_auth('Ann', 'select public._game_arena_touch(' || quote_literal(pg_temp.uid('Ann')) || '::uuid, ''2020-01'')') is not null, 'A1: _game_arena_touch chiusa';
  assert pg_temp.err('set local role anon; select public.game_arena_state()') is not null, 'A1: anonimi fuori (stato)';
  reset role;
  assert pg_temp.err('set local role anon; select public.game_arena_list()') is not null, 'A1: anonimi fuori (elenco)';
  reset role;
  insert into t_log (msg) values ('OK A1 — scheda iniziale, tabelle e funzioni chiuse, anonimi fuori');
end $$;

-- A2 — leghe: soglie
do $$ begin
  assert public._game_arena_league(0) = 'bronzo' and public._game_arena_league(899) = 'bronzo' and public._game_arena_league(900) = 'argento'
     and public._game_arena_league(1099) = 'argento' and public._game_arena_league(1100) = 'oro' and public._game_arena_league(1300) = 'platino'
     and public._game_arena_league(1500) = 'diamante' and public._game_arena_league(1699) = 'diamante' and public._game_arena_league(1700) = 'leggenda'
     and public._game_arena_league(99999) = 'leggenda', 'A2: soglie delle leghe';
  insert into t_log (msg) values ('OK A2 — soglie delle leghe');
end $$;

-- A3 — formula dei punti (Elo): pari, contro più forte, contro più debole, sempre almeno ±1
do $$ begin
  assert public._game_arena_delta(1000, 1000, true) = 16 and public._game_arena_delta(1000, 1000, false) = -16, 'A3: pari = ±16';
  assert public._game_arena_delta(1000, 1400, true) = 29 and public._game_arena_delta(1000, 1400, false) = -3, 'A3: contro uno più forte: +29 / −3';
  assert public._game_arena_delta(1000, 600, true) = 3 and public._game_arena_delta(1000, 600, false) = -29, 'A3: contro uno più debole: +3 / −29';
  assert public._game_arena_delta(2000, 100, true) = 1 and public._game_arena_delta(100, 2000, false) = -1, 'A3: almeno ±1';
  insert into t_log (msg) values ('OK A3 — formula dei punti');
end $$;

-- A4 — una vittoria: +16, l'avversario non cambia, il resto del duello c'è ancora
do $$
declare r jsonb; a jsonb; s jsonb; b0 text;
begin
  perform pg_temp.fill('Ann');
  r := pg_temp.dl('Ann', 'Bob'); a := r->'arena';
  assert (r->>'won')::boolean and (r->>'xp')::bigint >= 0 and r ? 'log' and r ? 'energy' and r ? 'energy_cost' and r ? 'max_a', 'A4: il duello restituisce ancora tutto il resto';
  assert (a->>'before')::integer = 1000 and (a->>'delta')::integer = 16 and (a->>'points')::integer = 1016 and (a->>'counted')::boolean and a->>'season' = public._game_arena_season(), 'A4: +16 → 1016';
  assert a->>'league_before' = 'argento' and a->>'league_after' = 'argento' and not (a->>'league_changed')::boolean and (a->>'opponent_points')::integer = 1000, 'A4: lega e punti dell''avversario';
  assert (a->>'pair_used')::integer = 1 and (a->>'pair_max')::integer = 3, 'A4: 1 sfida valida su 3';
  s := pg_temp.ast('Ann');
  assert (s->'me'->>'points')::integer = 1016 and (s->'me'->>'wins')::integer = 1 and (s->'me'->>'losses')::integer = 0 and (s->'me'->>'best')::integer = 1016, 'A4: scheda aggiornata';
  assert (s->'me'->>'rank')::integer = 1 and (s->'me'->>'ranked')::integer = 1, 'A4: Ann prima su 1';
  assert (pg_temp.ast('Bob')->'me'->>'points')::integer = 1000 and (pg_temp.ast('Bob')->'me'->>'wins')::integer = 0 and pg_temp.ast('Bob')->'me'->'rank' = 'null'::jsonb, 'A4: chi è sfidato non cambia punti né posizione';
  assert (select count(*) from public.game_arena_rating where user_id = pg_temp.uid('Bob') and wins + losses > 0) = 0, 'A4: Bob senza sfide';
  assert (select count(*) from public.game_arena_log) = 1 and (select count(*) from public.game_duels) = 1, 'A4: un duello, una riga di registro';
  insert into t_log (msg) values ('OK A4 — vittoria: +16, avversario invariato, resto del duello presente');
end $$;

-- A5 — una sconfitta: −16
do $$
declare r jsonb; a jsonb;
begin
  perform pg_temp.fill('Bob');
  r := pg_temp.dl('Bob', 'Ann'); a := r->'arena';
  assert not (r->>'won')::boolean and (a->>'delta')::integer = -15 and (a->>'points')::integer = 985, format('A5: sconfitta contro 1016 con 1000 = −15 (è %s)', a->>'delta');
  assert pg_temp.pts('Bob') = 985 and (pg_temp.ast('Bob')->'me'->>'losses')::integer = 1 and (pg_temp.ast('Bob')->'me'->>'rank')::integer = 2, 'A5: Bob 985, secondo';
  assert pg_temp.pts('Ann') = 1016, 'A5: Ann (sfidata) non cambia';
  assert (pg_temp.ast('Bob')->'me'->>'best')::integer = 1000, 'A5: il record resta 1000';
  insert into t_log (msg) values ('OK A5 — sconfitta: −15, lo sfidato non cambia');
end $$;

-- A6 — limite di 3 sfide valide al giorno contro lo stesso avversario
do $$
declare r jsonb; i integer; l jsonb; x jsonb;
begin
  perform pg_temp.clr(); perform pg_temp.fill('Ann');
  for i in 1..3 loop
    r := pg_temp.dl('Ann', 'Cid'); assert (r->'arena'->>'counted')::boolean, format('A6: sfida %s valida', i);
  end loop;
  assert pg_temp.pts('Ann') = 1046, format('A6: tre vittorie contro lo stesso (%s)', pg_temp.pts('Ann'));
  x := (select e from jsonb_array_elements(pg_temp.alist('Ann')) e where e->>'user_id' = pg_temp.uid('Cid')::text);
  assert (x->>'rated_left')::integer = 0 and (x->>'rated_today')::integer = 3 and (x->>'fights_today')::integer = 3, 'A6: elenco: 0 sfide valide rimaste';
  r := pg_temp.dl('Ann', 'Cid');
  assert not (r->'arena'->>'counted')::boolean and (r->'arena'->>'delta')::integer = 0 and r->'arena'->>'reason' = 'pair' and (r->>'won')::boolean, 'A6: la quarta si combatta ma non conta';
  assert (r->>'xp')::bigint >= 0 and r ? 'energy_cost', 'A6: XP/energia come sempre';
  assert (pg_temp.ast('Ann')->'me'->>'wins')::integer = 3, 'A6: vittorie contate = 3';
  r := pg_temp.dl('Ann', 'Dan'); assert (r->'arena'->>'counted')::boolean, 'A6: un altro avversario conta';
  insert into t_log (msg) values ('OK A6 — massimo 3 sfide valide al giorno contro lo stesso avversario');
end $$;

-- A7 — contro un avversario più forte si guadagna di più; contro uno più debole si perde di più
do $$
declare r jsonb;
begin
  perform pg_temp.clr(); perform pg_temp.fill('Ann'); perform pg_temp.fill('Bob');
  perform pg_temp.setpts('Cid', 1400);
  r := pg_temp.dl('Ann', 'Cid');
  assert (r->'arena'->>'delta')::integer = 29 and (r->'arena'->>'opponent_points')::integer = 1400, format('A7: +29 contro 1400 (è %s)', r->'arena'->>'delta');
  perform pg_temp.setpts('Dan', 600);
  r := pg_temp.dl('Ann', 'Dan');
  assert (r->'arena'->>'delta')::integer = public._game_arena_delta((r->'arena'->>'before')::integer, 600, true) and (r->'arena'->>'delta')::integer between 1 and 3, format('A7: pochi punti contro 600 (%s)', r->'arena'->>'delta');
  perform pg_temp.setpts('Bob', 1000); perform pg_temp.setpts('Eve', 600);
  r := pg_temp.dl('Fay', 'Eve');     -- Fay: 1000, vince su 600
  perform pg_temp.fill('Bob');
  assert (r->'arena'->>'delta')::integer = 3, 'A7: Fay +3 contro un 600';
  r := pg_temp.dl('Bob', 'Ann');
  assert not (r->>'won')::boolean and (r->'arena'->>'delta')::integer = least(-1, round(32 * (0 - 1.0 / (1.0 + power(10.0, (pg_temp.pts('Ann') - 1000) / 400.0))))::integer), 'A7: perdere contro un più forte toglie poco';
  insert into t_log (msg) values ('OK A7 — il guadagno dipende dalla differenza di punti');
end $$;

-- A8 — i punti non scendono sotto 0; il passaggio di lega è segnalato
do $$
declare r jsonb;
begin
  perform pg_temp.clr(); perform pg_temp.fill('Bob'); perform pg_temp.fill('Ann');
  perform pg_temp.setpts('Bob', 5); perform pg_temp.setpts('Ann', 100);
  r := pg_temp.dl('Bob', 'Ann');
  assert not (r->>'won')::boolean and (r->'arena'->>'points')::integer >= 0 and pg_temp.pts('Bob') >= 0, format('A8: mai sotto 0 (%s)', r->'arena'->>'points');
  assert r->'arena'->>'league_after' = 'bronzo', 'A8: lega Bronzo';
  perform pg_temp.setpts('Ann', 1090); perform pg_temp.fill('Ann');
  r := pg_temp.dl('Ann', 'Cid');                       -- 1090 vs 1000: +14 → 1104 → Oro
  assert (r->'arena'->>'points')::integer >= 1100 and r->'arena'->>'league_before' = 'argento' and r->'arena'->>'league_after' = 'oro' and (r->'arena'->>'league_changed')::boolean, format('A8: promozione ad Oro (%s)', r->'arena');
  assert pg_temp.ast('Ann')->'me'->>'league' = 'oro' and pg_temp.ast('Ann')->'me'->'next_league'->>'key' = 'platino', 'A8: scheda Oro, prossima Platino';
  perform pg_temp.setpts('Ann', 2500);
  assert pg_temp.ast('Ann')->'me'->'next_league' = 'null'::jsonb and pg_temp.ast('Ann')->'me'->>'league' = 'leggenda', 'A8: in cima non c''è una lega successiva';
  insert into t_log (msg) values ('OK A8 — mai sotto zero, promozione di lega segnalata');
end $$;

-- A9 — stagioni: reset morbido dalla stagione precedente, albo d'oro
do $$
declare cur text := public._game_arena_season(); prv text := to_char(to_date(public._game_arena_season() || '-01', 'YYYY-MM-DD') - interval '1 month', 'YYYY-MM'); s jsonb; r jsonb;
begin
  perform pg_temp.clr();
  insert into public.game_arena_rating (user_id, season, points, wins, losses, best) values
    (pg_temp.uid('Ann'), prv, 1600, 8, 1, 1650), (pg_temp.uid('Bob'), prv, 600, 0, 7, 1000), (pg_temp.uid('Cid'), prv, 1200, 3, 2, 1200),
    (pg_temp.uid('Dan'), prv, 1000, 0, 0, 1000), (pg_temp.uid('Fay'), prv, 1800, 9, 0, 1800);
  assert public._game_arena_points(pg_temp.uid('Ann'), cur) = 1300 and public._game_arena_points(pg_temp.uid('Bob'), cur) = 800 and public._game_arena_points(pg_temp.uid('Eve'), cur) = 1000, 'A9: 1600 → 1300, 600 → 800, nuovo → 1000';
  s := pg_temp.ast('Ann');
  assert (s->'me'->>'points')::integer = 1300 and s->'me'->>'league' = 'platino', 'A9: Ann riparte da 1300 (Platino)';
  assert s->'last_season'->>'season' = prv and s->'last_season'->'top'->0->>'nickname' = 'Fay' and (s->'last_season'->'top'->0->>'points')::integer = 1800
     and jsonb_array_length(s->'last_season'->'top') = 3 and s->'last_season'->'top'->1->>'nickname' = 'Ann', 'A9: albo d''oro: Fay, Ann, Cid';
  assert (s->'last_season'->'me'->>'rank')::integer = 2 and (s->'last_season'->'me'->>'points')::integer = 1600, 'A9: il mio piazzamento nella stagione scorsa';
  assert s->'board' = '[]'::jsonb, 'A9: la classifica nuova parte vuota';
  assert (select count(*) from public.game_arena_rating where season = prv) = 5, 'A9: le stagioni passate restano';
  -- le sfide nella nuova stagione partono dai punti ripartiti
  perform pg_temp.fill('Ann'); perform public._game_ensure_hero(pg_temp.uid('Bob'));
  r := pg_temp.dl('Ann', 'Bob');
  assert (r->'arena'->>'before')::integer = 1300 and (r->'arena'->>'opponent_points')::integer = 800, 'A9: la sfida usa i punti ripartiti';
  insert into t_log (msg) values ('OK A9 — stagioni: reset morbido, albo d''oro, storico conservato');
end $$;

-- A10 — classifica: ordine, solo chi ha sfide valide, sospesi esclusi, massimo 20
do $$
declare s jsonb; n text;
begin
  perform pg_temp.clr();
  insert into public.game_arena_rating (user_id, season, points, wins, losses, best) values
    (pg_temp.uid('Ann'), public._game_arena_season(), 1500, 5, 2, 1500), (pg_temp.uid('Bob'), public._game_arena_season(), 1500, 3, 1, 1500),
    (pg_temp.uid('Cid'), public._game_arena_season(), 1700, 1, 0, 1700), (pg_temp.uid('Dan'), public._game_arena_season(), 1100, 0, 0, 1100),
    (pg_temp.uid('Eve'), public._game_arena_season(), 900, 0, 3, 900);
  s := pg_temp.ast('Fay');
  assert jsonb_array_length(s->'board') = 4, 'A10: 4 in classifica (Dan senza sfide escluso)';
  assert s->'board'->0->>'nickname' = 'Cid' and s->'board'->1->>'nickname' = 'Ann' and s->'board'->2->>'nickname' = 'Bob' and s->'board'->3->>'nickname' = 'Eve', 'A10: ordine per punti, poi vittorie';
  assert (s->'board'->0->>'rank')::integer = 1 and (s->'board'->3->>'rank')::integer = 4 and s->'board'->0->>'league' = 'leggenda', 'A10: posizioni e leghe';
  assert pg_temp.ast('Fay')->'me'->'rank' = 'null'::jsonb, 'A10: chi non ha sfide non ha posizione';
  assert (pg_temp.ast('Ann')->'me'->>'rank')::integer = 2 and (pg_temp.ast('Ann')->'me'->>'ranked')::integer = 4, 'A10: Ann seconda su 4';
  update public.profiles set suspended = true where id = pg_temp.uid('Cid');
  s := pg_temp.ast('Fay');
  assert jsonb_array_length(s->'board') = 3 and s->'board'->0->>'nickname' = 'Ann', 'A10: i sospesi non compaiono';
  update public.profiles set suspended = false where id = pg_temp.uid('Cid');
  insert into t_log (msg) values ('OK A10 — classifica: ordine, esclusioni, posizione propria');
end $$;

-- A11 — elenco avversari: punti, lega, punti in palio, ordine per vicinanza, solo chi accetta sfide
do $$
declare l jsonb; x jsonb;
begin
  perform pg_temp.clr();
  perform pg_temp.setpts('Ann', 1200); perform pg_temp.setpts('Bob', 1210); perform pg_temp.setpts('Cid', 1500); perform pg_temp.setpts('Dan', 900); perform pg_temp.setpts('Eve', 1190);
  update public.game_heroes set arena_open = false where user_id = pg_temp.uid('Fay');
  l := pg_temp.alist('Ann');
  assert jsonb_array_length(l) = 4, 'A11: 4 avversari (Fay non accetta sfide, io escluso)';
  assert l->0->>'nickname' = 'Bob' and l->1->>'nickname' = 'Eve' and l->2->>'nickname' = 'Cid' and l->3->>'nickname' = 'Dan', format('A11: ordine per vicinanza di punti (%s)', (select string_agg(e->>'nickname', ',') from jsonb_array_elements(l) e));
  x := l->2;
  assert (x->>'points')::integer = 1500 and x->>'league' = 'diamante' and (x->>'gain')::integer = public._game_arena_delta(1200, 1500, true) and (x->>'loss')::integer = public._game_arena_delta(1200, 1500, false), 'A11: punti, lega, punti in palio';
  assert (x->>'rated_left')::integer = 3 and (x->>'rated_today')::integer = 0 and x ? 'power' and x ? 'level' and x ? 'bosses_beaten' and x ? 'fights_today' and x ? 'avatar', 'A11: campi di prima presenti';
  assert (l->3->>'gain')::integer < (l->2->>'gain')::integer and (l->3->>'loss')::integer < (l->2->>'loss')::integer, 'A11: contro un più debole guadagno meno e perdo di più';
  update public.game_heroes set arena_open = true where user_id = pg_temp.uid('Fay');
  insert into t_log (msg) values ('OK A11 — elenco: punti, lega, punti in palio, ordine');
end $$;

-- A12 — cronologia delle sfide con i punti; allenamento amichevole e altre attività non toccano i punti
do $$
declare s jsonb; p0 integer; i integer;
begin
  perform pg_temp.clr(); perform pg_temp.fill('Ann');
  perform pg_temp.dl('Ann', 'Bob'); perform pg_temp.dl('Ann', 'Cid');
  s := pg_temp.ast('Ann');
  assert jsonb_array_length(s->'recent') = 2 and (s->'recent'->0->>'won')::boolean and s->'recent'->0->>'opponent' = 'Cid' and (s->'recent'->0->>'delta')::integer = 15 and (s->'recent'->1->>'delta')::integer = 16, 'A12: cronologia, la più recente per prima';
  assert s->'recent'->0 ? 'after' and s->'recent'->0 ? 'counted' and s->'recent'->0 ? 'at', 'A12: campi della cronologia';
  p0 := pg_temp.pts('Ann');
  perform pg_temp.as_('Ann'); perform public.game_train_start('spar'); perform public.game_spar(pg_temp.uid('Bob')); perform public.game_train_stop();
  assert pg_temp.pts('Ann') = p0 and (select count(*) from public.game_arena_log) = 2, 'A12: l''amichevole non tocca i punti';
  for i in 1..12 loop perform pg_temp.fill('Ann'); perform pg_temp.dl('Ann', case when i % 2 = 0 then 'Dan' else 'Eve' end); end loop;
  assert jsonb_array_length(pg_temp.ast('Ann')->'recent') = 10, 'A12: al massimo 10 voci';
  insert into t_log (msg) values ('OK A12 — cronologia, amichevole senza effetti sui punti');
end $$;

-- A13 — controlli del duello invariati
do $$ declare c0 bigint; d0 bigint; begin
  c0 := (select count(*) from public.game_arena_log); d0 := (select count(*) from public.game_duels);
  assert pg_temp.err_as('Ann', 'select public.game_duel(' || quote_literal(pg_temp.uid('Ann')) || '::uuid)') like '%altro eroe%', 'A13: non ci si sfida da soli';
  update public.game_heroes set arena_open = false where user_id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Ann', 'select public.game_duel(' || quote_literal(pg_temp.uid('Bob')) || '::uuid)') like '%non accetta sfide%', 'A13: chi non accetta sfide non si sfida';
  update public.game_heroes set arena_open = true where user_id = pg_temp.uid('Bob');
  update public.game_heroes set energy = 1, energy_at = now() where user_id = pg_temp.uid('Ann');
  assert pg_temp.err_as('Ann', 'select public.game_duel(' || quote_literal(pg_temp.uid('Bob')) || '::uuid)') like 'Energia insufficiente%', 'A13: senza energia non si sfida';
  assert (select count(*) from public.game_arena_log) = c0 and (select count(*) from public.game_duels) = d0, 'A13: i tentativi falliti non lasciano righe';
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_arena_state()') is not null and pg_temp.err_as('Ann', 'select public.game_arena_list()') is not null, 'A13: modulo spento: stato ed elenco bloccati';
  perform pg_temp.mod(true);
  insert into t_log (msg) values ('OK A13 — controlli del duello invariati, modulo spento');
end $$;

-- A14 — impostazioni modificabili
do $$ declare r jsonb; begin
  perform pg_temp.clr(); perform pg_temp.fill('Ann');
  update public.system_settings set value_int = 64 where key = 'game_arena_k';
  r := pg_temp.dl('Ann', 'Bob');
  assert (r->'arena'->>'delta')::integer = 32, 'A14: K = 64 → +32';
  update public.system_settings set value_int = 32 where key = 'game_arena_k';
  update public.system_settings set value_int = 1 where key = 'game_arena_pair_day';
  r := pg_temp.dl('Ann', 'Bob');
  assert not (r->'arena'->>'counted')::boolean, 'A14: una sola sfida valida al giorno';
  update public.system_settings set value_int = 3 where key = 'game_arena_pair_day';
  insert into t_log (msg) values ('OK A14 — K e limite giornaliero modificabili');
end $$;

-- A15 — nessun BC mosso
do $$ begin
  assert pg_temp.money() = (select h from t_money), 'A15: BC e registro invariati';
  insert into t_log (msg) values ('OK A15 — nessun BC mosso');
end $$;

select msg as esito from t_log order by n;
rollback;
