-- =====================================================================
-- TEST DELLA MIGRAZIONE 026 (La guerra degli Eroi: 30 dungeon a scelte)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…026 (black-market-setup.sql … black-market-eroi-dungeon-scelte.sql).
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

-- ---------- supporto per i dungeon ----------
create function pg_temp.en(n text) returns numeric language sql as $$ select public._game_energy_of(pg_temp.uid(n)) $$;
create function pg_temp.full() returns void language sql as $$ update public.game_heroes set energy = 100, energy_at = now() where true $$;
create function pg_temp.cr(n text, p_no integer, p_role text) returns uuid language plpgsql as $$
begin perform pg_temp.as_(n); return (public.game_dungeon_create(p_no, p_role)->>'run_id')::uuid; end $$;
create function pg_temp.jn(n text, p_run uuid, p_role text) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_join(p_run, p_role); end $$;
create function pg_temp.rl(n text, p_run uuid, p_role text) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_role(p_run, p_role); end $$;
create function pg_temp.lv(n text, p_run uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_leave(p_run); end $$;
create function pg_temp.go(n text, p_run uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_start(p_run); end $$;
create function pg_temp.dst(n text) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_state(); end $$;
-- risultato di un giocatore dentro l'esito di una partita
create function pg_temp.mem(res jsonb, n text) returns jsonb language sql as $$
  select x from jsonb_array_elements(res->'result'->'members') x where x->>'user_id' = pg_temp.uid(n)::text $$;
-- leve di prova: il moltiplicatore di forza dei nemici (0.01 = vittoria sicura, 1000 = sconfitta sicura, 1 = normale)
create function pg_temp.dw(p_no integer) returns void language sql as $$ update public.game_dungeons set diff = 0.01 where no = p_no $$;
create function pg_temp.dl(p_no integer) returns void language sql as $$ update public.game_dungeons set diff = 1000 where no = p_no $$;
create function pg_temp.dn() returns void language sql as $$ update public.game_dungeons set diff = 1 where true $$;
create function pg_temp.setting(k text, v integer) returns void language sql as $$ update public.system_settings set value_int = v where key = k $$;
create function pg_temp.clears(n text, p_no integer) returns integer language sql as $$
  select coalesce((select clears from public.game_dungeon_progress where user_id = pg_temp.uid(n) and dungeon_no = p_no), 0) $$;
create function pg_temp.inv(n text) returns bigint language sql as $$ select count(*) from public.game_inventory where user_id = pg_temp.uid(n) $$;
create function pg_temp.dbc(p_no integer) returns integer language sql as $$ select bc from public.game_dungeons where no = p_no $$;
create function pg_temp.dxp(p_no integer) returns integer language sql as $$ select xp from public.game_dungeons where no = p_no $$;


-- ---------- supporto per i dungeon a scelte ----------
create function pg_temp.unlock(n text, upto integer) returns void language sql as $$
  insert into public.game_dungeon_progress (user_id, dungeon_no, clears, first_clear_at, last_clear_at)
  select pg_temp.uid(n), g, 1, now(), now() from generate_series(1, upto) g on conflict (user_id, dungeon_no) do nothing $$;
create function pg_temp.easy(p_no integer) returns void language sql as $$ update public.game_dungeons set diff = 0.01 where no = p_no $$;
create function pg_temp.hard(p_no integer) returns void language sql as $$ update public.game_dungeons set diff = 1000 where no = p_no $$;
create function pg_temp.node(p_run uuid) returns text language sql as $$ select state->>'node' from public.game_runs where id = p_run $$;
create function pg_temp.gnode(p_run uuid) returns jsonb language sql as $$
  select g.graph->(r.state->>'node') from public.game_runs r join public.game_dungeon_graphs g on g.dungeon_no = r.dungeon_no where r.id = p_run $$;
-- scelte per effetto (la prova legge il percorso segreto, che il browser non può leggere)
create function pg_temp.pick_fx(p_run uuid, k text, v text) returns text language sql as $$
  select o->>'id' from jsonb_array_elements(pg_temp.gnode(p_run)->'o') o where o->'fx'->>k = v limit 1 $$;
create function pg_temp.pick_to(p_run uuid, p_to text) returns text language sql as $$
  select o->>'id' from jsonb_array_elements(pg_temp.gnode(p_run)->'o') o where o->>'to' like p_to limit 1 $$;
create function pg_temp.pick_plain(p_run uuid) returns text language sql as $$   -- una scelta senza effetti né requisiti (la «neutra»)
  select o->>'id' from jsonb_array_elements(pg_temp.gnode(p_run)->'o') o where o->'fx' is null and not o ? 'req' and not o ? 'only' and o->>'to' not like 'eF%' limit 1 $$;
create function pg_temp.ch(n text, p_run uuid, p_opt text) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_choose(p_run, p_opt); end $$;
create function pg_temp.vw(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_dungeon_state()->'active'; end $$;
create function pg_temp.dsel(n text, p_no integer) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return (select e from jsonb_array_elements(public.game_dungeon_state()->'dungeons') e where (e->>'no')::int = p_no); end $$;
create function pg_temp.lvl2(n text, l integer) returns void language sql as $$ update public.game_heroes set level = l, xp = 0 where user_id = pg_temp.uid(n) $$;
create function pg_temp.ready(n text) returns void language sql as $$ select pg_temp.lvl2(n, 500); select pg_temp.unlock(n, 25); update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid(n) $$;
-- avvia un dungeon a scelte in solitaria e restituisce la partita
create function pg_temp.begin_(n text, p_no integer) returns uuid language plpgsql as $$
declare run uuid;
begin
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid(n);
  run := pg_temp.cr(n, p_no, 'dps'); perform pg_temp.go(n, run); return run;
end $$;

-- Preparazione: eroi pronti
do $$
declare n text;
begin
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.setst('Ann', 10, 4, 4, 2, 0); perform pg_temp.setst('Bob', 4, 4, 4, 4, 4); perform pg_temp.setst('Cid', 6, 6, 4, 2, 2); perform pg_temp.setst('Dan', 6, 4, 6, 2, 2);
  perform pg_temp.ready('Ann'); perform pg_temp.ready('Bob'); perform pg_temp.ready('Cid'); perform pg_temp.ready('Dan');
  perform pg_temp.setting('game_dng_drop_extra_pct', 0); perform pg_temp.setting('game_dng_drop_replay_pct', 0);
  insert into t_log (msg) values ('OK Preparazione: 4 eroi di livello 500 con i primi 25 dungeon completati, premi casuali spenti');
end $$;

-- E1 — il catalogo: 25 classici + 30 a scelte, sempre più difficili
do $$
declare s jsonb; n integer;
begin
  assert (select count(*) from public.game_dungeons) = 55 and (select count(*) from public.game_dungeons where kind = 'path') = 30 and (select min(no) from public.game_dungeons where kind = 'path') = 26, 'E1: 55 dungeon, 30 a scelte (26-55)';
  assert (select count(*) from public.game_dungeons where kind = 'classic') = 25 and not exists (select 1 from public.game_dungeons where kind = 'classic' and no > 25), 'E1: i classici restano i primi 25';
  assert (select bool_and(b.ref_level > a.ref_level and b.bc > a.bc and b.xp > a.xp and b.min_level > a.min_level) from public.game_dungeons a join public.game_dungeons b on b.no = a.no + 1 where a.no >= 25), 'E1: livello, BC e XP crescono dal 25 al 55';
  assert (select ref_level from public.game_dungeons where no = 26) > (select ref_level from public.game_dungeons where no = 25), 'E1: il 26 è più difficile del 25';
  assert (select bool_and(diff >= 1.04 and diff <= 1.3) from public.game_dungeons where kind = 'path') and (select max(diff) from public.game_dungeons where kind = 'path') > (select min(diff) from public.game_dungeons where kind = 'path'), 'E1: la forza dei nemici cresce';
  assert (select count(*) from public.game_dungeon_graphs) = 30, 'E1: 30 percorsi';
  -- ogni percorso: ≥3 finali di vittoria, ≥3 di fallimento, almeno 2 bivi
  assert not exists (select 1 from public.game_dungeon_graphs g where
      (select count(*) from jsonb_each(g.graph) e where e.value->>'t' = 'end' and (e.value->>'win')::boolean) < 3
   or (select count(*) from jsonb_each(g.graph) e where e.value->>'t' = 'end' and not (e.value->>'win')::boolean) < 3
   or (select count(*) from jsonb_each(g.graph) e where e.value->>'t' = 'scene') < 3), 'E1: ogni dungeon ha ≥3 vittorie, ≥3 fallimenti e ≥3 bivi';
  -- ogni bivio ha almeno 2 opzioni, tutte con destinazione esistente; i finali di fallimento esistono davvero come scelta
  assert not exists (select 1 from public.game_dungeon_graphs g, jsonb_each(g.graph) e, jsonb_array_elements(e.value->'o') o
                      where e.value->>'t' = 'scene' and not (g.graph ? (o->>'to'))), 'E1: nessuna scelta punta nel vuoto';
  assert (select count(*) from public.game_dungeon_graphs g where exists (select 1 from jsonb_each(g.graph) e, jsonb_array_elements(e.value->'o') o where e.value->>'t' = 'scene' and o->>'to' like 'eF%')) = 30, 'E1: in ogni dungeon c''è almeno una scelta che porta al fallimento';
  -- oggetti: uno per dungeon, una rotazione di slot, epici ogni 5
  assert (select count(*) from public.game_items where dungeon_no between 26 and 55 and source = 'dungeon') = 30, 'E1: 30 oggetti esclusivi';
  assert (select slot from public.game_items where id = 'd26') = 'weapon' and (select slot from public.game_items where id = 'd27') = 'armor' and (select slot from public.game_items where id = 'd30') = 'tool', 'E1: slot a rotazione';
  assert (select rarity from public.game_items where id = 'd30') = 'epico' and (select rarity from public.game_items where id = 'd45') = 'leggendario' and (select rarity from public.game_items where id = 'd55') = 'mitico' and (select rarity from public.game_items where id = 'd31') = 'raro', 'E1: epico ogni 5, poi leggendario e mitico';
  assert (select p_for from public.game_items where id = 'd26') > (select p_for from public.game_items where id = 'd21') and (select p_vig from public.game_items where id = 'd52') > (select p_vig from public.game_items where id = 'd47'), 'E1: gli oggetti nuovi sono più forti';
  assert (select count(*) from public.game_dungeons where item_id is not null and item_id = 'd' || lpad(no::text, 2, '0')) = 55, 'E1: ogni dungeon ha il suo oggetto';
  s := pg_temp.dst('Ann');
  assert (s->>'total')::int = 55 and jsonb_array_length(s->'dungeons') = 55 and (s->'dungeons'->25->>'kind') = 'path' and (s->'dungeons'->0->>'kind') = 'classic', 'E1: lo stato elenca i 55 dungeon con il tipo';
  assert (s->'dungeons'->25->>'forks')::int >= 3 and (s->'dungeons'->25->>'endings_total')::int >= 6 and (s->'dungeons'->25->>'endings_found')::int = 0 and (s->'dungeons'->0->>'forks')::int = 0, 'E1: bivi e finali dichiarati per i dungeon a scelte';
  insert into t_log (msg) values ('OK E1 — 55 dungeon (30 a scelte), difficoltà crescente, ≥3 vittorie / ≥3 fallimenti / ≥3 bivi ciascuno, un oggetto per dungeon');
end $$;

-- E2 — i percorsi sono segreti: il browser non vede né il grafo né gli effetti
do $$
declare s text;
begin
  assert pg_temp.rows_as('Ann', 'select 1 from public.game_dungeon_graphs') is null or true, 'x';
  assert pg_temp.err_auth('Ann', 'select * from public.game_dungeon_graphs') like 'permission denied%', 'E2: la tabella dei percorsi non è leggibile';
  assert pg_temp.err_auth('Ann', 'insert into public.game_dungeon_graphs (dungeon_no, graph) values (26, ''{}''::jsonb)') like 'permission denied%', 'E2: né scrivibile';
  assert pg_temp.err_auth('Ann', 'update public.game_dungeon_graphs set graph = ''{}''::jsonb') like 'permission denied%', 'E2: né modificabile';
  assert pg_temp.err_auth('Ann', 'select * from public.game_dungeon_endings') is null, 'E2: i propri finali sono leggibili';
  assert pg_temp.err_auth('Ann', 'insert into public.game_dungeon_endings (user_id, dungeon_no, ending) values (''' || pg_temp.uid('Ann') || ''', 26, ''x'')') like 'permission denied%', 'E2: ma non scrivibili';
  assert pg_temp.err_auth('Ann', 'select public._game_dng_clash(''[]''::jsonb, ''{}''::jsonb, 0, 1, 1)') like 'permission denied%', 'E2: gli scontri interni non sono chiamabili';
  assert pg_temp.err_auth('Ann', 'select public._game_dng_settle(gen_random_uuid(), true, ''{}''::jsonb)') like 'permission denied%', 'E2: né i premi';
  assert pg_temp.err_auth('Ann', 'select public._game_dng_advance(''{}''::jsonb, ''{}''::jsonb, 26)') like 'permission denied%', 'E2: né l''avanzamento';
  assert pg_temp.err_auth('Ann', 'select public._game_dng_start_classic(gen_random_uuid())') like 'permission denied%', 'E2: né la partenza classica interna';
  assert pg_temp.err_auth('Ann', 'select public._game_dng_state_base()') like 'permission denied%', 'E2: né lo stato interno';
  assert pg_temp.err_auth('Ann', 'select public.game_dungeon_choose(gen_random_uuid(), ''a'')') not like 'permission denied%', 'E2: le funzioni pubbliche sono chiamabili';
  assert has_function_privilege('anon', 'public.game_dungeon_choose(uuid, text)', 'execute') is false, 'E2: l''anonimo non può scegliere';
  s := pg_temp.dst('Ann')::text;
  assert s not like '%"fx"%' and s not like '%"graph"%' and s not like '%eF1%', 'E2: lo stato non contiene effetti né percorsi';
  insert into t_log (msg) values ('OK E2 — percorsi ed effetti segreti: nessun accesso dal browser, nessuna funzione interna chiamabile');
end $$;

-- E3 — la partenza: energia, scena iniziale, nessun effetto svelato; i classici funzionano come prima
do $$
declare run uuid; r jsonb; v jsonb; e0 numeric; sc jsonb; c0 jsonb;
begin
  perform pg_temp.easy(26);
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Ann');
  e0 := pg_temp.en('Ann');
  run := pg_temp.cr('Ann', 26, 'dps');
  assert (select status from public.game_runs where id = run) = 'lobby', 'E3: la lobby nasce come prima';
  r := pg_temp.go('Ann', run);
  assert r->>'status' = 'active' and r->'view' is not null and r->'result' is null, 'E3: la partenza non risolve il dungeon: è in corso';
  assert pg_temp.en('Ann') = e0 - 20, 'E3: costo 20 energie alla partenza';
  assert (select status from public.game_runs where id = run) = 'active' and (select started_at is not null and finished_at is null and last_move_at is not null from public.game_runs where id = run), 'E3: stato «active», orari impostati';
  v := r->'view'; sc := v->'scene';
  assert v->>'leader_id' = pg_temp.uid('Ann')::text and (v->>'pow')::int = 0 and jsonb_array_length(v->'flags') = 0 and jsonb_array_length(v->'members') = 1, 'E3: vista iniziale: potenza 0, nessun indizio';
  assert sc->>'id' = 's1' and length(sc->>'text') > 40 and jsonb_array_length(sc->'options') = 3 and (sc->>'title') = 'Ingresso', 'E3: scena iniziale con 3 scelte';
  assert not exists (select 1 from jsonb_array_elements(sc->'options') o where (o->>'locked')::boolean) and not (sc::text like '%"fx"%'), 'E3: nessuna scelta bloccata, nessun effetto svelato';
  assert (v->'members'->0->>'hp')::int = (v->'members'->0->>'max_hp')::int and (v->'members'->0->>'max_hp')::int > 0, 'E3: PV pieni';
  assert (pg_temp.dst('Ann')->'active'->>'run_id') = run::text and (pg_temp.dst('Ann')->>'path_minutes')::int = 120, 'E3: lo stato riporta il dungeon in corso';
  assert pg_temp.dst('Bob')->'active' = 'null'::jsonb, 'E3: gli altri non vedono nulla';
  -- un dungeon classico va ancora in un colpo
  perform pg_temp.dw(1); perform pg_temp.lvl2('Bob', 400);
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Bob');
  c0 := pg_temp.go('Bob', pg_temp.cr('Bob', 1, 'dps'));
  assert c0->>'status' = 'cleared' and (c0->'result'->>'rooms_total')::int = 4 and c0->'result'->'path' is null, 'E3: il dungeon 1 è ancora classico e si risolve subito';
  assert (pg_temp.dsel('Bob', 1)->>'kind') = 'classic', 'E3: tipo classico';
  insert into t_log (msg) values ('OK E3 — partenza: in corso, −20 energie, scena con 3 scelte senza effetti svelati; i classici invariati');
end $$;

-- E4 — chi può scegliere e che cosa
do $$
declare run uuid; v jsonb; o text; sc jsonb; e text; r jsonb;
begin
  run := (select id from public.game_runs where status = 'active' and leader_id = pg_temp.uid('Ann'));
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_choose(''' || run || ''', ''a'')') like 'Solo il capo gruppo può scegliere%', 'E4: solo il capo gruppo sceglie';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', ''zzz'')') = 'Scelta non valida', 'E4: scelta inesistente';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(gen_random_uuid(), ''a'')') like 'Questo dungeon non è in corso%', 'E4: partita inesistente';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', null)') = 'Scelta non valida', 'E4: scelta nulla';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_abandon(''' || run || ''')') is null, 'E4: il capo può arrendersi (lo si prova più avanti: qui la partita viene chiusa)';
  assert (select status from public.game_runs where id = run) = 'failed', 'E4: arresa = fallita';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', ''a'')') like 'Questo dungeon non è in corso%', 'E4: una partita chiusa non accetta scelte';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_abandon(''' || run || ''')') like 'Questo dungeon non è in corso%', 'E4: né si può arrendere due volte';
  -- il modulo spento blocca tutto
  run := pg_temp.begin_('Ann', 26);
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', ''a'')') like 'Modulo non attivo%', 'E4: modulo spento: nessuna scelta';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_abandon(''' || run || ''')') like 'Modulo non attivo%', 'E4: né resa';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_state()') like 'Modulo non attivo%', 'E4: né stato';
  perform pg_temp.mod(true);
  perform pg_temp.as_('Ann'); perform public.game_dungeon_abandon(run);
  insert into t_log (msg) values ('OK E4 — solo il capo sceglie; scelte inesistenti, partite chiuse e modulo spento rifiutati');
end $$;

-- E5 — percorso migliore del dungeon 26 (scheletro A): indizi, chiave, sigillo → finale migliore (140%)
do $$
declare run uuid; r jsonb; v jsonb; m jsonb; b0 integer; t0 bigint; x0 bigint; st jsonb;
begin
  perform pg_temp.easy(26);
  b0 := pg_temp.bal('Ann'); t0 := pg_temp.tot(); x0 := (pg_temp.hero('Ann')).total_xp;
  run := pg_temp.begin_('Ann', 26);
  -- bivio 1: prudenza (indizio, +8% potenza)
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  v := r->'view';
  assert r->>'status' = 'active' and (v->>'pow')::int = 8 and v->'flags'->0->>'id' = 'indizio' and v->'scene'->>'id' = 's2', 'E5: scelta prudente: +8% e indizio, si va al bivio 2';
  assert jsonb_array_length(v->'log') = 1 and v->'log'->0->>'k' = 'c' and length(v->'log'->0->>'r') > 10, 'E5: la cronaca racconta l''esito';
  -- bivio 2: la chiave
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'key'));
  v := r->'view';
  assert (v->>'pow')::int = 16 and (select count(*) from jsonb_array_elements(v->'flags')) = 2 and v->'scene'->>'id' = 's3', 'E5: chiave presa (+16%): lo scontro col nemico si è risolto da solo e si arriva al bivio finale';
  assert jsonb_array_length(v->'log') = 3 and v->'log'->2->>'k' = 'f' and (v->'log'->2->>'win')::boolean, 'E5: lo scontro è nella cronaca (vinto)';
  assert (select flags::text from (select (v->'flags') flags) q) like '%Sigillo d’Osso%', 'E5: l''indizio ha il nome del dungeon';
  -- bivio 3: sbloccato grazie alla chiave
  assert not exists (select 1 from jsonb_array_elements(v->'scene'->'options') o where (o->>'locked')::boolean), 'E5: con la chiave nessuna scelta è bloccata';
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'sigillo'));
  assert r->>'status' = 'cleared' and r->'result' is not null and (r->'result'->>'win')::boolean and r->'result'->'ending'->>'id' = 'eBest', 'E5: boss battuto, finale migliore';
  m := pg_temp.mem(r, 'Ann');
  assert (r->'result'->'ending'->>'m')::int = 140 and (m->>'bc')::int = round(2650 * 1.4) and (m->>'first')::boolean, 'E5: 140% dei BC (3710)';
  assert pg_temp.bal('Ann') = b0 + 3710 and pg_temp.tot() = t0 + 3710, 'E5: saldo e totale aumentano di 3710';
  assert (m->>'xp')::int = round(1536 * 1.4) and (pg_temp.hero('Ann')).total_xp = x0 + round(1536 * 1.4), 'E5: XP al 140%';
  assert m->'items'->0->>'id' = 'd26' and (m->'items'->0->>'exclusive')::boolean and exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Ann') and item_id = 'd26' and source = 'dungeon'), 'E5: oggetto esclusivo d26';
  assert pg_temp.clears('Ann', 26) = 1 and (r->'result'->>'rooms_total')::int = 2 and (r->'result'->>'rooms_cleared')::int = 2 and jsonb_array_length(r->'result'->'rooms') = 2 and (r->'result'->'rooms'->1->>'boss')::boolean, 'E5: 2 scontri (nemico e boss)';
  assert jsonb_array_length(r->'result'->'story') = 5, 'E5: cronaca di 5 voci (3 scelte + 2 scontri)';
  assert (select status from public.game_runs where id = run) = 'cleared' and (select finished_at is not null from public.game_runs where id = run), 'E5: partita conclusa';
  assert (select count(*) from public.ledger_entries where idempotency_key = 'gamedng:' || run::text || ':' || pg_temp.uid('Ann')::text and kind = 'game_dungeon_reward' and amount = 3710) = 1, 'E5: una riga di registro, tipo game_dungeon_reward';
  st := pg_temp.dst('Ann');
  assert (st->'last_result'->>'run_id') = run::text and st->'active' = 'null'::jsonb and (pg_temp.dsel('Ann', 26)->>'endings_found')::int = 1 and (pg_temp.dsel('Ann', 27)->>'open')::boolean, 'E5: fine partita: ultimo risultato, il 27 si sblocca, 1 finale scoperto';
  assert (r->'result'->'members'->0->>'endings_found')::int = 1 and (r->'result'->>'endings_total')::int = 7, 'E5: nel risultato i finali scoperti (1 su 7)';
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'E5: saldi = registro';
  insert into t_log (msg) values ('OK E5 — percorso migliore: +16% e due indizi, sigillo, finale migliore: 3710 BC (140%), 2150 XP, oggetto d26, il 27 si sblocca');
end $$;

-- E6 — altre strade: finale buono, finale appena sufficiente, replica a ritmo ridotto
do $$
declare run uuid; r jsonb; m jsonb; b0 integer; v jsonb; x text; n integer := 0; endings text[] := '{}';
begin
  perform pg_temp.easy(26);
  -- strada «eroica ma ruvida»: scelta rischiosa → scontro duro → bivio finale senza chiave → finale appena sufficiente (85%)
  b0 := pg_temp.bal('Ann');
  run := pg_temp.begin_('Ann', 26);
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'hp', '-20'));
  assert (r->'view'->>'pow')::int = 6 and jsonb_array_length(r->'view'->'log') = 2 and r->'view'->'log'->1->>'k' = 'f', 'E6: la scelta rischiosa dà +6% e fa scattare subito uno scontro (risolto da solo)';
  assert r->'view'->'scene'->>'id' = 's3' and jsonb_array_length(r->'view'->'flags') = 0, 'E6: si salta il bivio della chiave: nessun indizio';
  assert exists (select 1 from jsonb_array_elements(r->'view'->'scene'->'options') o where (o->>'locked')::boolean and o->>'hint' = 'Ti serve: Sigillo d’Osso'), 'E6: la scelta «con la chiave» è bloccata e spiega che cosa serve';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', ''' || (select o->>'id' from jsonb_array_elements(pg_temp.gnode(run)->'o') o where o ? 'req' limit 1) || ''')') like 'Questa scelta non è ancora disponibile%', 'E6: scegliere l''opzione bloccata è rifiutato dal server';
  r := pg_temp.ch('Ann', run, pg_temp.pick_plain(run));
  assert r->>'status' = 'cleared' and r->'result'->'ending'->>'id' = 'eOk' and (r->'result'->'ending'->>'m')::int = 85, 'E6: finale «sul filo» (85%)';
  m := pg_temp.mem(r, 'Ann');
  assert not (m->>'first')::boolean and (m->>'bc')::int = round(2650 * 0.85 * 0.25), 'E6: replica: 25% dei BC × 85% finale';
  assert (m->>'xp')::int = round(1536 * 0.85 * 0.5) and pg_temp.bal('Ann') = b0 + (m->>'bc')::int, 'E6: replica: 50% dell''XP × 85%';
  assert jsonb_array_length(m->'items') = 0 and pg_temp.clears('Ann', 26) = 2, 'E6: nessun nuovo oggetto, secondo completamento registrato';
  assert (m->>'endings_found')::int = 2, 'E6: secondo finale scoperto';
  -- strada intermedia: chiave ma niente sigillo → finale buono (115%)
  run := pg_temp.begin_('Ann', 26);
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'key'));
  r := pg_temp.ch('Ann', run, pg_temp.pick_plain(run));
  assert r->'result'->'ending'->>'id' = 'eGood' and (r->'result'->'ending'->>'m')::int = 115, 'E6: chiave senza sigillo: finale buono (115%)';
  assert (pg_temp.dsel('Ann', 26)->>'endings_found')::int = 3, 'E6: 3 finali scoperti';
  -- ripetere lo stesso finale non lo conta due volte
  run := pg_temp.begin_('Ann', 26);
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'key'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_plain(run));
  assert (pg_temp.dsel('Ann', 26)->>'endings_found')::int = 3 and pg_temp.clears('Ann', 26) = 4, 'E6: lo stesso finale non si conta due volte';
  insert into t_log (msg) values ('OK E6 — strade diverse, finali diversi (140% / 115% / 85%), scelta bloccata spiegata e rifiutata dal server, repliche ridotte, finali non contati due volte');
end $$;

-- E7 — le scelte fatali: fallimento immediato, XP di consolazione, nessun BC, nessun progresso
do $$
declare run uuid; r jsonb; m jsonb; b0 integer; t0 bigint; x0 bigint; c0 integer; i0 bigint; e text;
begin
  perform pg_temp.easy(27); perform pg_temp.ready('Ann'); perform pg_temp.unlock('Ann', 26);
  b0 := pg_temp.bal('Ann'); t0 := pg_temp.tot(); x0 := (pg_temp.hero('Ann')).total_xp; i0 := pg_temp.inv('Ann'); c0 := pg_temp.clears('Ann', 27);
  run := pg_temp.begin_('Ann', 27);
  r := pg_temp.ch('Ann', run, pg_temp.pick_to(run, 'eF%'));
  assert r->>'status' = 'failed' and not (r->'result'->>'win')::boolean and r->'result'->'ending'->>'id' = 'eF1' and r->'result'->'ending'->>'title' = 'Un passo falso', 'E7: la scelta fatale chiude il dungeon con fallimento';
  m := pg_temp.mem(r, 'Ann');
  assert (m->>'bc')::int = 0 and not (m->>'first')::boolean and jsonb_array_length(m->'items') = 0, 'E7: nessun BC e nessun oggetto';
  assert (m->>'xp')::int = round(1616 * 0.20) and (pg_temp.hero('Ann')).total_xp = x0 + round(1616 * 0.20), 'E7: XP di consolazione (20%)';
  assert pg_temp.bal('Ann') = b0 and pg_temp.tot() = t0 and pg_temp.inv('Ann') = i0 and pg_temp.clears('Ann', 27) = c0, 'E7: saldo, oggetti e progresso invariati';
  assert length(r->'result'->'ending'->>'text') > 30 and (r->'result'->>'rooms_total')::int = 0 and r->'result'->'story'->0->>'k' = 'c', 'E7: il racconto del fallimento c''è';
  assert (select status from public.game_runs where id = run) = 'failed' and pg_temp.en('Ann') = 80, 'E7: partita fallita, energia già spesa';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', ''a'')') like 'Questo dungeon non è in corso%', 'E7: finita';
  assert (pg_temp.dsel('Ann', 27)->>'endings_found')::int = 1 and not (pg_temp.dsel('Ann', 28)->>'open')::boolean, 'E7: il finale di fallimento è registrato, il 28 resta chiuso';
  assert (select count(*) from public.ledger_entries where idempotency_key like 'gamedng:' || run::text || '%') = 0, 'E7: nessuna riga nel registro';
  insert into t_log (msg) values ('OK E7 — scelta fatale: fallimento immediato, 20% XP, nessun BC/oggetto/progresso, finale registrato');
end $$;

-- E8 — sconfitta in combattimento (strada giusta ma squadra troppo debole)
do $$
declare run uuid; r jsonb; b0 integer;
begin
  perform pg_temp.hard(27); perform pg_temp.ready('Ann'); b0 := pg_temp.bal('Ann');
  run := pg_temp.begin_('Ann', 27);
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'forza'));
  assert r->>'status' = 'failed' and r->'result'->'ending'->>'id' = 'eDef' and r->'result'->'rooms'->0->>'cleared' = 'false' and (r->'result'->>'rooms_total')::int = 1, 'E8: scontro perso = finale di sconfitta';
  assert pg_temp.bal('Ann') = b0 and (r->'result'->'members'->0->>'bc')::int = 0, 'E8: niente BC';
  perform pg_temp.easy(27);
  insert into t_log (msg) values ('OK E8 — lo scontro perso chiude il dungeon con la sconfitta, senza premi');
end $$;

-- E9 — effetti: potenza, PV, indizi; le scelte «riposo» curano ma pagano un prezzo
do $$
declare run uuid; v jsonb; hp0 integer; hp1 integer; r jsonb;
begin
  perform pg_temp.easy(26); perform pg_temp.ready('Ann');
  run := pg_temp.begin_('Ann', 26);
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  v := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'hp', '-12'))->'view';
  assert v->'scene'->>'id' = 's3' and (v->>'pow')::int = 8, 'E9: scelta mediocre al bivio 2: nessuna chiave';
  -- scontro a nemico quasi nullo: i PV tornano pieni col riposo del 25%; poi la scelta «riposo» dà +35% PV e −12% potenza
  hp0 := (v->'members'->0->>'hp')::int;
  v := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'pow', '-12'))->'view';
  assert v is null, 'E9: dopo il riposo parte il boss e (con nemici facili) il dungeon finisce';
  assert (select result->'ending'->>'id' from public.game_runs where id = run) = 'eOk', 'E9: nessun sigillo né chiave: finale sul filo';
  -- PV mai letali per le scelte (floor 1): una scelta con −20% non uccide anche a PV bassi
  update public.game_dungeons set diff = 0.01 where no = 26;
  run := pg_temp.begin_('Ann', 26);
  update public.game_runs set state = jsonb_set(state, '{members,0,hp}', '3'::jsonb) where id = run;
  v := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'hp', '-20'))->'view';
  assert (v->'members'->0->>'hp')::int >= 1, 'E9: le scelte non uccidono mai (minimo 1 PV)';
  perform pg_temp.as_('Ann'); perform public.game_dungeon_abandon(run);
  insert into t_log (msg) values ('OK E9 — effetti su potenza/PV/indizi; le scelte non sono mai letali; il riposo costa potenza');
end $$;

-- E10 — scheletro «patto» (dungeon 28): opzioni nascoste finché non hai l'indizio, finale amaro del patto
do $$
declare run uuid; r jsonb; v jsonb; labels text; b0 integer; m jsonb;
begin
  perform pg_temp.easy(28); perform pg_temp.unlock('Ann', 27); perform pg_temp.ready('Ann'); perform pg_temp.unlock('Ann', 27);
  -- chi RIFIUTA il patto non vede le opzioni del patto e non può sceglierle
  run := pg_temp.begin_('Ann', 28);
  v := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'onore'))->'view';
  perform pg_temp.ch('Ann', run, pg_temp.pick_plain(run));
  v := pg_temp.vw('Ann');
  assert v->'scene'->>'id' = 's3', 'E10: terzo bivio';
  assert jsonb_array_length(v->'scene'->'options') = 3, 'E10: con «parola d’onore»: 3 scelte visibili (onore, senza accordi, fatale)';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_choose(''' || run || ''', ''' || (select o->>'id' from jsonb_array_elements(pg_temp.gnode(run)->'o') o where o->'fx'->>'flag' = 'oscuro') || ''')') = 'Scelta non valida', 'E10: l''opzione del patto non si può scegliere se non l''hai stretto (il server lo ricontrolla)';
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'puro'));
  assert r->'result'->'ending'->>'id' = 'eBest', 'E10: fiducia ripagata = finale migliore';
  -- chi ACCETTA il patto e lo onora: finale amaro (125%)
  b0 := pg_temp.bal('Ann');
  run := pg_temp.begin_('Ann', 28);
  v := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'patto'))->'view';
  assert (select (v->'members'->0->>'hp')::numeric < (v->'members'->0->>'max_hp')::numeric * 0.75), 'E10: il patto costa il 30% dei PV';
  perform pg_temp.ch('Ann', run, pg_temp.pick_plain(run));
  v := pg_temp.vw('Ann');
  assert jsonb_array_length(v->'scene'->'options') = 4, 'E10: con il patto: onorarlo, spezzarlo, senza accordi, fatale';
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'oscuro'));
  assert r->'result'->'ending'->>'id' = 'eDark' and (r->'result'->'ending'->>'m')::int = 125, 'E10: patto onorato = finale amaro (125%)';
  -- chi spezza il patto: malus alla potenza e ai PV
  run := pg_temp.begin_('Ann', 28);
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'patto'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_plain(run));
  v := pg_temp.ch('Ann', run, (select o->>'id' from jsonb_array_elements(pg_temp.gnode(run)->'o') o where o->'fx'->>'pow' = '-20'))->'result';
  assert v->'ending'->>'id' = 'eOk', 'E10: patto spezzato: finale solo sufficiente';
  insert into t_log (msg) values ('OK E10 — patto: opzioni nascoste e rifiutate dal server se non meritate; 3 finali di vittoria diversi');
end $$;

-- E11 — scheletro «prove» (dungeon 29): l'indizio si legge, l'errore costa
do $$
declare run uuid; v jsonb; r jsonb;
begin
  perform pg_temp.easy(29); perform pg_temp.unlock('Ann', 28); perform pg_temp.ready('Ann'); perform pg_temp.unlock('Ann', 28);
  run := pg_temp.begin_('Ann', 29);
  -- con l'indizio decifrato l'ultima scena aggiunge un suggerimento al testo
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'pow', '12'));
  v := pg_temp.vw('Ann');
  assert v->'scene'->>'id' = 's3' and v->'scene'->>'text' like E'%\n\nRicordate il cartello%', 'E11: con l''indizio il testo include il suggerimento';
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'punto'));
  assert r->'result'->'ending'->>'id' = 'eBest', 'E11: punto debole + indizio = finale migliore';
  -- senza l'indizio niente suggerimento
  run := pg_temp.begin_('Ann', 29);
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'hp', '15'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'hp', '-5'));
  v := pg_temp.vw('Ann');
  assert v->'scene'->>'text' not like '%Ricordate il cartello%', 'E11: senza indizio nessun suggerimento';
  -- la risposta sbagliata: −25% di potenza (con nemici normali il boss diventa quasi imbattibile)
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'pow', '-25'));
  assert r->'result'->'ending'->>'id' = 'eOk' or r->'result'->'ending'->>'id' = 'eDef', 'E11: risposta sbagliata: finale sul filo o sconfitta';
  insert into t_log (msg) values ('OK E11 — prove: l''indizio compare nel testo solo a chi l''ha decifrato; la risposta sbagliata costa potenza');
end $$;

-- E12 — gruppo: tutti pagano, il capo decide, tutti vedono, tutti ricevono premi (bonus +10% a testa)
do $$
declare run uuid; r jsonb; v jsonb; mb jsonb; ma jsonb; b0a integer; b0b integer; e0a numeric; e0b numeric; mmb jsonb;
begin
  perform pg_temp.easy(30); perform pg_temp.unlock('Ann', 29); perform pg_temp.unlock('Bob', 29); perform pg_temp.ready('Ann'); perform pg_temp.ready('Bob');
  perform pg_temp.unlock('Ann', 29); perform pg_temp.unlock('Bob', 29);
  b0a := pg_temp.bal('Ann'); b0b := pg_temp.bal('Bob');
  run := pg_temp.cr('Ann', 30, 'dps');
  perform pg_temp.jn('Bob', run, 'tank');
  e0a := pg_temp.en('Ann'); e0b := pg_temp.en('Bob');
  r := pg_temp.go('Ann', run);
  assert pg_temp.en('Ann') = e0a - 20 and pg_temp.en('Bob') = e0b - 20, 'E12: tutti pagano 20 energie';
  assert jsonb_array_length(r->'view'->'members') = 2 and (select count(*) from jsonb_array_elements(r->'view'->'members') x where (x->>'hp')::int = (x->>'max_hp')::int) = 2, 'E12: due membri a PV pieni';
  v := pg_temp.vw('Bob');
  assert v->>'run_id' = run::text and v->>'leader_id' = pg_temp.uid('Ann')::text and v->'scene'->>'id' = 's1', 'E12: anche Bob vede il dungeon in corso e chi decide';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_choose(''' || run || ''', ''a'')') like 'Solo il capo gruppo può scegliere%', 'E12: Bob non può scegliere';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_abandon(''' || run || ''')') like 'Solo il capo gruppo può arrendersi%', 'E12: né arrendersi';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_create(30, ''dps'')') like 'Hai un dungeon in corso%', 'E12: Bob non può aprire un''altra lobby mentre è dentro';
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_choose(''' || run || ''', ''a'')') like 'Solo il capo gruppo può scegliere%', 'E12: un estraneo non può scegliere';
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  perform pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'key'));
  r := pg_temp.ch('Ann', run, pg_temp.pick_fx(run, 'flag', 'sigillo'));
  assert r->>'status' = 'cleared', 'E12: gruppo vittorioso';
  ma := pg_temp.mem(r, 'Ann'); mb := pg_temp.mem(r, 'Bob');
  assert (r->'result'->>'party_bonus')::int = 10 and (ma->>'bc')::int = round(2650 + 95 * 4) * 0 + round((2650 + 95 * 4) * 1.1 * 1.4) and (mb->>'bc')::int = (ma->>'bc')::int, 'E12: bonus gruppo +10% e 140%: stessa cifra a tutti';
  assert pg_temp.bal('Ann') = b0a + (ma->>'bc')::int and pg_temp.bal('Bob') = b0b + (mb->>'bc')::int, 'E12: BC a entrambi';
  assert ma->'items'->0->>'id' = 'd30' and mb->'items'->0->>'id' = 'd30' and (ma->>'milestone')::boolean and (mb->>'milestone')::boolean, 'E12: d30 (epico) e traguardo per entrambi';
  assert pg_temp.dst('Bob')->'active' = 'null'::jsonb and pg_temp.dst('Ann')->'active' = 'null'::jsonb, 'E12: nessuno resta «dentro»';
  assert pg_temp.clears('Ann', 30) = 1 and pg_temp.clears('Bob', 30) = 1, 'E12: progresso per entrambi';
  insert into t_log (msg) values ('OK E12 — gruppo: tutti pagano e vedono, decide solo il capo, +10% BC a testa, premi per tutti (epico d30)');
end $$;

-- E13 — arresa e inattività
do $$
declare run uuid; r jsonb; x0 bigint; s jsonb; res jsonb;
begin
  perform pg_temp.easy(26); perform pg_temp.ready('Cid'); perform pg_temp.unlock('Cid', 25);
  x0 := (pg_temp.hero('Cid')).total_xp;
  run := pg_temp.begin_('Cid', 26);
  perform pg_temp.as_('Cid'); r := public.game_dungeon_abandon(run);
  assert r->>'status' = 'failed' and r->'result'->'ending'->>'id' = 'resa' and (r->'result'->'members'->0->>'bc')::int = 0, 'E13: resa = fallimento senza BC';
  assert (pg_temp.hero('Cid')).total_xp = x0 + round(1536 * 0.2), 'E13: XP di consolazione anche arrendendosi';
  -- inattività: dopo 120 minuti nessuno decide più
  run := pg_temp.begin_('Cid', 26);
  update public.game_runs set last_move_at = now() - interval '121 minutes' where id = run;
  res := pg_temp.ch('Cid', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
  assert res->>'status' = 'failed' and (res->>'expired')::boolean, 'E13: scelta dopo la scadenza: la spedizione è fallita';
  assert (select status from public.game_runs where id = run) = 'failed' and (select result->'ending'->>'id' from public.game_runs where id = run) = 'abbandono', 'E13: chiusa come «abbandono» (con la consolazione)';
  run := pg_temp.begin_('Cid', 26);
  update public.game_runs set last_move_at = now() - interval '121 minutes' where id = run;
  s := pg_temp.dst('Cid');
  assert s->'active' = 'null'::jsonb and (select status from public.game_runs where id = run) = 'failed', 'E13: aprendo lo stato, le spedizioni abbandonate si chiudono da sole';
  assert s->'last_result'->>'run_id' = run::text, 'E13: e compaiono come ultimo risultato';
  -- entro il tempo tutto normale
  run := pg_temp.begin_('Cid', 26);
  update public.game_runs set last_move_at = now() - interval '119 minutes' where id = run;
  assert pg_temp.dst('Cid')->'active'->>'run_id' = run::text, 'E13: dopo 119 minuti è ancora in corso';
  perform pg_temp.as_('Cid'); perform public.game_dungeon_abandon(run);
  -- la durata è una impostazione
  perform pg_temp.setting('game_dng_path_minutes', 10);
  run := pg_temp.begin_('Cid', 26);
  update public.game_runs set last_move_at = now() - interval '11 minutes' where id = run;
  assert pg_temp.dst('Cid')->'active' = 'null'::jsonb, 'E13: limite modificabile (10 minuti)';
  perform pg_temp.setting('game_dng_path_minutes', 120);
  insert into t_log (msg) values ('OK E13 — resa e abbandono: fallimento con XP di consolazione, nessun BC; limite di inattività impostabile');
end $$;

-- E14 — quando si è dentro non si può aprire altro; una lobby non può partire se il dungeon non è sbloccato
do $$
declare run uuid;
begin
  perform pg_temp.ready('Dan'); perform pg_temp.easy(26);
  run := pg_temp.begin_('Dan', 26);
  assert pg_temp.err_as('Dan', 'select public.game_dungeon_create(26, ''dps'')') like 'Hai un dungeon in corso%', 'E14: non si crea una lobby con un dungeon in corso';
  assert pg_temp.err_as('Dan', 'select public.game_dungeon_create(1, ''dps'')') like 'Hai un dungeon in corso%', 'E14: nemmeno di un dungeon classico';
  perform pg_temp.as_('Dan'); perform public.game_dungeon_abandon(run);
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Dan');
  assert pg_temp.err_as('Dan', 'select public.game_dungeon_create(40, ''dps'')') like 'Dungeon bloccato%', 'E14: il 40 è bloccato finché non si completa il 39';
  perform pg_temp.lvl2('Dan', 100);
  assert pg_temp.err_as('Dan', 'select public.game_dungeon_create(27, ''dps'')') like 'Dungeon bloccato%', 'E14: il 27 è bloccato finché non si completa il 26';
  perform pg_temp.unlock('Dan', 26);
  assert pg_temp.err_as('Dan', 'select public.game_dungeon_create(27, ''dps'')') like 'Serve il livello 119%', 'E14: serve il livello consigliato−2 (livello minimo)';
  perform pg_temp.lvl2('Dan', 500);
  assert pg_temp.err_as('Dan', 'select public.game_dungeon_create(27, ''dps'')') is null, 'E14: con livello e sblocco si entra';
  insert into t_log (msg) values ('OK E14 — sblocco in ordine, livello minimo, un solo dungeon alla volta');
end $$;

-- E15 — tutti i 30 percorsi giocabili davvero: passeggiate casuali, nessun vicolo cieco
do $$
declare no_ integer; i integer; run uuid; r jsonb; steps integer; opts jsonb; pick text; res_win integer := 0; res_fail integer := 0; ends text[] := '{}'; k integer; guard integer;
  seen_end jsonb := '{}'::jsonb; v jsonb; st text; strat integer;
begin
  perform pg_temp.setting('game_dng_path_minutes', 100000);
  for no_ in 26..55 loop
    perform pg_temp.easy(no_);
    for strat in 1..6 loop
      -- sblocca tutto e rimettiti in forma
      perform pg_temp.ready('Bob'); perform pg_temp.unlock('Bob', 54);
      run := pg_temp.begin_('Bob', no_);
      steps := 0;
      loop
        steps := steps + 1;
        if steps > 12 then raise exception 'E15: dungeon % non termina', no_; end if;
        v := pg_temp.vw('Bob');
        if v is null then exit; end if;
        opts := v->'scene'->'options';
        -- strategia 1: prima opzione sbloccata; 2: ultima; 3-6: casuale tra le sbloccate
        select o->>'id' into pick from (select o, row_number() over () rn from jsonb_array_elements(opts) o where not (o->>'locked')::boolean) q
          order by case when strat = 1 then rn when strat = 2 then -rn else (random() * 1000)::int end limit 1;
        r := pg_temp.ch('Bob', run, pick);
        exit when r->>'status' <> 'active';
      end loop;
      assert r->>'status' in ('cleared','failed') and r->'result'->'ending'->>'id' is not null, 'E15: esito non valido nel dungeon ' || no_;
      if (r->'result'->>'win')::boolean then res_win := res_win + 1; else res_fail := res_fail + 1; end if;
      seen_end := jsonb_set(seen_end, array[no_::text || ':' || (r->'result'->'ending'->>'id')], 'true'::jsonb);
    end loop;
  end loop;
  assert res_win > 0 and res_fail > 0, 'E15: sia vittorie sia fallimenti nelle passeggiate';
  assert (select count(*) from jsonb_object_keys(seen_end)) >= 90, 'E15: finali diversi raggiunti in tutti i dungeon (' || (select count(*) from jsonb_object_keys(seen_end)) || ')';
  assert not exists (select 1 from public.game_runs where status = 'active' and leader_id = pg_temp.uid('Bob')), 'E15: nessuna partita lasciata in sospeso';
  perform pg_temp.setting('game_dng_path_minutes', 120);
  insert into t_log (msg) values ('OK E15 — 30 dungeon × 6 passeggiate (prima/ultima/4 casuali): tutte terminano con un finale valido (' || res_win || ' vittorie, ' || res_fail || ' fallimenti)');
end $$;

-- E16 — nessun BC dal nulla: ogni BC ha una riga di registro «game_dungeon_reward»
do $$
declare bad integer;
begin
  select count(*) into bad from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0);
  assert bad = 0, 'E16: saldi = registro';
  assert (select count(*) from public.ledger_entries where kind = 'game_dungeon_reward' and ref_type = 'game_run') = (select count(*) from public.ledger_entries where kind = 'game_dungeon_reward'), 'E16: tutti i premi hanno riferimento alla partita';
  assert (select count(*) from (select idempotency_key from public.ledger_entries where kind = 'game_dungeon_reward' group by 1 having count(*) > 1) d) = 0, 'E16: nessun premio doppio';
  assert not exists (select 1 from public.ledger_entries where kind = 'game_dungeon_reward' and amount <= 0), 'E16: i premi sono solo entrate';
  assert (select count(*) from public.game_runs where status = 'cleared' and result->>'path' = 'true') > 0 and not exists (select 1 from public.game_runs where status = 'failed' and result->>'path' = 'true' and exists (select 1 from public.ledger_entries l where l.ref_id = game_runs.id)), 'E16: i fallimenti non hanno premi';
  insert into t_log (msg) values ('OK E16 — saldi = registro; premi solo come entrate, uno per giocatore e per partita; nessun premio per i fallimenti');
end $$;

-- E17 — difficoltà: la manopola globale vale anche per i dungeon a scelte, e i dungeon classici restano uguali
do $$
declare run uuid; r jsonb; n integer := 0; w integer := 0; i integer;
begin
  -- difficoltà massima: nessuna vittoria possibile con un eroe di livello 400 nel dungeon 55 (ref 403, nemici ×1.3 ×1.35)... e con la manopola al minimo, sempre vittoria
  update public.game_dungeons set diff = 1 where no = 26;
  perform pg_temp.setting('game_dng_difficulty', 10);
  perform pg_temp.ready('Bob'); perform pg_temp.unlock('Bob', 25);
  for i in 1..5 loop
    run := pg_temp.begin_('Bob', 26);
    perform pg_temp.ch('Bob', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
    perform pg_temp.ch('Bob', run, pg_temp.pick_fx(run, 'flag', 'key'));
    r := pg_temp.ch('Bob', run, pg_temp.pick_fx(run, 'flag', 'sigillo'));
    if (r->'result'->>'win')::boolean then w := w + 1; end if;
  end loop;
  assert w = 5, 'E17: con la manopola al minimo (10%) il dungeon è sempre vinto';
  perform pg_temp.setting('game_dng_difficulty', 100000);
  w := 0;
  for i in 1..5 loop
    run := pg_temp.begin_('Bob', 26);
    perform pg_temp.ch('Bob', run, pg_temp.pick_fx(run, 'flag', 'indizio'));
    r := pg_temp.ch('Bob', run, pg_temp.pick_fx(run, 'flag', 'key'));
    if r->>'status' = 'failed' then w := w + 1; end if;
  end loop;
  assert w = 5, 'E17: con la manopola altissima il primo scontro è sempre perso';
  perform pg_temp.setting('game_dng_difficulty', 100);
  insert into t_log (msg) values ('OK E17 — la manopola «difficoltà dei nemici» agisce anche sui dungeon a scelte');
end $$;

select msg as esito from t_log order by n;
rollback;
