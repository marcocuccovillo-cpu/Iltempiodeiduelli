-- =====================================================================
-- TEST DELLA RICARICA DELL'ENERGIA AL LIVELLO, SOLO SOTTO IL LIVELLO 100 (black-market-eroi-ricarica-livello-100.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO tutte le migrazioni della guerra degli Eroi (… black-market-eroi-boss-attacco.sql) e DOPO black-market-eroi-ricarica-livello-100.sql.
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


create function pg_temp.mx() returns numeric language sql as $$ select public._game_energy_max()::numeric $$;
create function pg_temp.prep(n text) returns void language plpgsql as $$ begin perform pg_temp.st(n); perform pg_temp.setst(n); end $$;
create function pg_temp.lv(n text) returns integer language sql as $$ select level from public.game_heroes where user_id = pg_temp.uid(n) $$;
create function pg_temp.xp(n text, x bigint) returns jsonb language sql as $$ select public._game_add_xp(pg_temp.uid(n), x) $$;

-- R1 — la funzione dell'XP: la ricarica dipende dal livello di PARTENZA (sotto il 100 sì, dal 100 in poi no)
do $$
declare r jsonb; n text; m0 text := pg_temp.money();
begin
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop perform pg_temp.prep(n); end loop;
  assert public._game_refill_below_level() = 100, 'R1: la soglia è 100';
  assert not has_function_privilege('authenticated', 'public._game_refill_below_level()', 'execute') and not has_function_privilege('anon', 'public._game_refill_below_level()', 'execute'), 'R1: la funzione soglia è interna';
  assert not has_function_privilege('authenticated', 'public._game_add_xp(uuid,bigint)', 'execute'), 'R1: la funzione dell''XP è interna';
  -- livello 50 → 51: ricarica
  perform pg_temp.setup('Ann', 50, 50, 10); update public.game_heroes set energy_at = now() - interval '2 days' where user_id = pg_temp.uid('Ann'); r := pg_temp.xp('Ann', 60);
  assert (r->>'levels')::int = 1 and (r->>'energy_full')::boolean and pg_temp.en('Ann') = pg_temp.mx(), 'R1: al livello 50 la ricarica scatta';
  assert (select energy = public._game_energy_max() and energy_at >= now() from public.game_heroes where user_id = pg_temp.uid('Ann')), 'R1: la ricarica riparte da adesso (energia e orario)';
  -- 98 → 99: ricarica
  perform pg_temp.setup('Bob', 98, 50, 10); r := pg_temp.xp('Bob', 60);
  assert pg_temp.lv('Bob') = 99 and (r->>'energy_full')::boolean and pg_temp.en('Bob') = pg_temp.mx(), 'R1: 98 → 99 ricarica';
  -- 99 → 100: ricarica (si partiva sotto il 100) = l''ultima
  perform pg_temp.setup('Cid', 99, 50, 10); r := pg_temp.xp('Cid', 60);
  assert pg_temp.lv('Cid') = 100 and (r->>'energy_full')::boolean and pg_temp.en('Cid') = pg_temp.mx(), 'R1: 99 → 100 ricarica (l''ultima)';
  -- 100 → 101: nessuna ricarica, l''energia resta com''era
  perform pg_temp.setup('Dan', 100, 50, 20); r := pg_temp.xp('Dan', 60);
  assert pg_temp.lv('Dan') = 101 and (r->>'levels')::int = 1 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Dan') - 20) < 0.5, 'R1: 100 → 101 nessuna ricarica';
  -- livello 150: nessuna ricarica
  perform pg_temp.setup('Eve', 150, 50, 5); r := pg_temp.xp('Eve', 60);
  assert pg_temp.lv('Eve') = 151 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Eve') - 5) < 0.5, 'R1: livello 150 nessuna ricarica';
  -- salto di più livelli a cavallo del 100 (parte da 98): una ricarica sola, al massimo
  perform pg_temp.setup('Fay', 98, 5, 0); r := pg_temp.xp('Fay', 5000000);
  assert (r->>'levels')::int >= 3 and pg_temp.lv('Fay') > 100 and (r->>'energy_full')::boolean and pg_temp.en('Fay') = pg_temp.mx(), 'R1: dal 98 oltre il 100 con un colpo solo: ricarica (partiva sotto)';
  -- salto di più livelli partendo dal 100: nessuna ricarica
  perform pg_temp.setup('Gus', 100, 5, 7); r := pg_temp.xp('Gus', 5000000);
  assert (r->>'levels')::int >= 3 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Gus') - 7) < 0.5, 'R1: dal 100 con più livelli: nessuna ricarica';
  -- senza salire di livello: nessun cambiamento, sotto e sopra il 100
  update public.game_heroes set level = 40, xp = 0, energy = 12, energy_at = now() where user_id = pg_temp.uid('Hal'); r := pg_temp.xp('Hal', 5);
  assert (r->>'levels')::int = 0 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Hal') - 12) < 0.5, 'R1: senza livello sotto il 100: niente';
  update public.game_heroes set level = 120, xp = 0, energy = 12, energy_at = now() where user_id = pg_temp.uid('Hal'); r := pg_temp.xp('Hal', 5);
  assert (r->>'levels')::int = 0 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Hal') - 12) < 0.5, 'R1: senza livello sopra il 100: niente';
  -- già piena: resta piena
  perform pg_temp.setup('Ann', 60, 50, 100); r := pg_temp.xp('Ann', 60);
  assert pg_temp.en('Ann') = pg_temp.mx(), 'R1: già piena resta piena';
  -- il bonus XP degli oggetti continua a valere (strumento da +4% XP): 1000 XP base → 1040
  insert into public.game_inventory (user_id, item_id, source) values (pg_temp.uid('Hal'), 't05', 'shop') on conflict do nothing;
  insert into public.game_equipped (user_id, slot, item_id) values (pg_temp.uid('Hal'), 'tool', 't05') on conflict (user_id, slot) do update set item_id = 't05';
  update public.game_heroes set level = 120, xp = 0, total_xp = 0 where user_id = pg_temp.uid('Hal');
  r := pg_temp.xp('Hal', 1000);
  assert (r->>'xp')::bigint = 1040 and (select total_xp from public.game_heroes where user_id = pg_temp.uid('Hal')) = 1040, 'R1: il bonus XP degli oggetti vale ancora';
  assert pg_temp.money() = m0, 'R1: nessun BC toccato';
  insert into t_log (msg) values ('OK R1 — ricarica solo se si parte sotto il 100: 50, 98→99, 99→100 sì; 100→101, 150, salti dal 100 no; salto 98→oltre 100 una ricarica; senza livello niente');
end $$;

-- R2 — duello in Arena: la risposta e il database seguono la ricarica effettiva
do $$
declare r jsonb; e0 numeric;
begin
  perform pg_temp.prep('Eve');
  update public.game_heroes set level = 99, a_for = 300, a_des = 150, a_vig = 150, a_spi = 50, a_frt = 150, stats_set = true where user_id = pg_temp.uid('Ann');
  update public.game_heroes set level = 1, xp = 0 where user_id = pg_temp.uid('Eve');
  -- livello 99 → 100 con il duello: energia al 100%
  perform pg_temp.setup('Ann', 99, 1, 40);
  r := pg_temp.duel('Ann', 'Eve');
  assert (r->>'won')::boolean and (r->>'levels')::int = 1 and pg_temp.lv('Ann') = 100, 'R2: premessa: 99 → 100 con il duello';
  assert (r->>'energy_full')::boolean and (r->>'energy')::numeric = pg_temp.mx() and pg_temp.en('Ann') = pg_temp.mx(), 'R2: 99 → 100: energia al 100% (risposta e database)';
  -- livello 100 → 101 con il duello: si paga il costo, nessuna ricarica
  perform pg_temp.setup('Ann', 100, 1, 40);
  r := pg_temp.duel('Ann', 'Eve');
  assert (r->>'won')::boolean and (r->>'levels')::int = 1 and pg_temp.lv('Ann') = 101, 'R2: premessa: 100 → 101 con il duello';
  assert not (r->>'energy_full')::boolean and (r->>'energy_cost')::numeric > 0, 'R2: dal 100: nessuna energia piena';
  assert abs(pg_temp.en('Ann') - (40 - (r->>'energy_cost')::numeric)) < 0.5 and abs((r->>'energy')::numeric - pg_temp.en('Ann')) < 0.5, 'R2: dal 100 si paga il costo del duello (risposta = database)';
  -- livello 150, senza salire: costo normale
  update public.game_heroes set level = 150, xp = 0, energy = 60, energy_at = now() where user_id = pg_temp.uid('Ann');
  r := pg_temp.duel('Ann', 'Eve');
  assert (r->>'won')::boolean and (r->>'levels')::int = 0 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Ann') - (60 - (r->>'energy_cost')::numeric)) < 0.5, 'R2: livello 150 senza salita: costo normale';
  -- sconfitta: Eve, debolissima, perde contro Ann: costo della sconfitta, nessuna ricarica
  perform pg_temp.setup('Eve', 1, 1, 50);
  r := pg_temp.duel('Eve', 'Ann');
  assert not (r->>'won')::boolean and not (r->>'energy_full')::boolean and abs(pg_temp.en('Eve') - (50 - (r->>'energy_cost')::numeric)) < 0.5, 'R2: sconfitta: costo, nessuna ricarica';
  insert into t_log (msg) values ('OK R2 — duello: 99→100 energia 100%; 100→101 e oltre costo normale (risposta = database); sconfitta invariata');
end $$;

-- R3 — boss: nella stessa lobby chi parte dal 99 si ricarica, chi parte dal 100 no
do $$
declare r jsonb; l bigint;
begin
  perform pg_temp.setup('Cid', 99, 5, 15);
  perform pg_temp.setup('Dan', 100, 5, 15);
  r := pg_temp.join_('Cid'); l := (r->>'lobby')::bigint; perform pg_temp.join_('Dan', l); perform pg_temp.start_('Cid');
  update public.game_lobbies set hp = 1 where id = l;
  r := pg_temp.act('Cid', 'attack');
  assert (r->>'defeated')::boolean and (r->'reward'->>'levels')::int > 0, 'R3: premessa: boss battuto, Cid sale di livello';
  assert pg_temp.en('Cid') = pg_temp.mx(), 'R3: Cid (dal 99) ha l''energia al 100%';
  assert pg_temp.lv('Dan') > 100 and abs(pg_temp.en('Dan') - 15) < 0.5, 'R3: Dan (dal 100) sale di livello ma l''energia resta com''era';
  insert into t_log (msg) values ('OK R3 — boss: ricarica per chi parte sotto il 100, non per chi parte dal 100 nella stessa lobby');
end $$;

-- R4 — con il limite di livello a 100: 99→100 ricarica, poi fermo e nessuna ricarica
do $$
declare r jsonb;
begin
  update public.system_settings set value_int = 100 where key = 'game_level_cap';
  perform pg_temp.setup('Fay', 99, 5, 10); r := pg_temp.xp('Fay', 100000);
  assert pg_temp.lv('Fay') = 100 and (r->>'energy_full')::boolean and pg_temp.en('Fay') = pg_temp.mx(), 'R4: con limite 100, 99 → 100 ricarica';
  update public.game_heroes set energy = 3, energy_at = now() where user_id = pg_temp.uid('Fay');
  r := pg_temp.xp('Fay', 100000);
  assert pg_temp.lv('Fay') = 100 and (r->>'levels')::int = 0 and not (r->>'energy_full')::boolean and abs(pg_temp.en('Fay') - 3) < 0.5, 'R4: al limite non sale e non ricarica';
  update public.system_settings set value_int = 9999 where key = 'game_level_cap';
  insert into t_log (msg) values ('OK R4 — con il limite di livello a 100 si ricarica per l''ultima volta salendo al 100, poi nulla');
end $$;

-- R5 — la ricarica con il tempo non cambia, anche sopra il 100; coerenza finale
do $$
declare e numeric;
begin
  update public.game_heroes set level = 120, energy = 0, energy_at = now() - interval '5 hours' where user_id = pg_temp.uid('Hal');
  e := pg_temp.en('Hal');
  assert e > 5 and e <= pg_temp.mx(), 'R5: sopra il 100 l''energia si ricarica ancora con il tempo (' || e || ')';
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'R5: saldi = registro';
  assert (select max(energy) from public.game_heroes) <= pg_temp.mx(), 'R5: energia mai oltre il massimo';
  insert into t_log (msg) values ('OK R5 — la ricarica con il tempo resta; saldi = registro, energia entro il massimo');
end $$;

select msg from t_log order by n;
rollback;
