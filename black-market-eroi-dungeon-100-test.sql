-- =====================================================================
-- TEST DELLA MIGRAZIONE 028 (La guerra degli Eroi: dungeon 56–100)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…027 e la 028 (black-market-eroi-dungeon-100.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Per i test usa nemici facili, quindi la difficoltà reale dei dungeon non è misurata qui.
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


create function pg_temp.chx(n text, p_run uuid, p_opt text, p_arg text default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_dungeon_choose(p_run, p_opt, p_arg); end $$;
create function pg_temp.rst(p_run uuid) returns jsonb language sql as $$ select state from public.game_runs where id = p_run $$;
create function pg_temp.hpof(p_run uuid, n text) returns numeric language sql as $$
  select (m->>'hp')::numeric from jsonb_array_elements(pg_temp.rst(p_run)->'members') m where m->>'user_id' = pg_temp.uid(n)::text $$;
create function pg_temp.mxof(p_run uuid, n text) returns numeric language sql as $$
  select (m->>'mx')::numeric from jsonb_array_elements(pg_temp.rst(p_run)->'members') m where m->>'user_id' = pg_temp.uid(n)::text $$;
create function pg_temp.endid(r jsonb) returns text language sql as $$ select r->'result'->'ending'->>'id' $$;
create function pg_temp.opt(v jsonb, id text) returns jsonb language sql as $$
  select o from jsonb_array_elements(v->'scene'->'options') o where o->>'id' = id $$;
-- una lobby di più eroi: il primo è il capo gruppo e fa partire
create function pg_temp.party(p_no integer, a text, ra text, b text, rb text, c text default null, rc text default null) returns uuid language plpgsql as $$
declare run uuid;
begin
  update public.game_heroes set energy = 100, energy_at = now() where user_id in (pg_temp.uid(a), pg_temp.uid(b)) or (c is not null and user_id = pg_temp.uid(c));
  run := pg_temp.cr(a, p_no, ra); perform pg_temp.jn(b, run, rb);
  if c is not null then perform pg_temp.jn(c, run, rc); end if;
  perform pg_temp.go(a, run); return run;
end $$;


-- ---------- supporto: controlli sul grafo e giocatori automatici ----------
create function pg_temp.targets(nd jsonb) returns text[] language sql as $$
  select case nd->>'t'
    when 'scene' then (select coalesce(array_agg(q.t), '{}'::text[]) from (
        select o->>'to' t from jsonb_array_elements(nd->'o') o where o ? 'to'
        union all select o->'chk'->>'ok' from jsonb_array_elements(nd->'o') o where o ? 'chk'
        union all select o->'chk'->>'ko' from jsonb_array_elements(nd->'o') o where o ? 'chk'
        union all select b.value->>'to' from jsonb_array_elements(nd->'o') o, jsonb_each(coalesce(o->'by', '{}'::jsonb)) b where b.value ? 'to') q where q.t is not null)
    when 'lock' then array[nd->>'ok', nd->>'ko']
    when 'fight' then array[nd->>'w', nd->>'l']
    when 'route' then (select array_agg(c->>'to') from jsonb_array_elements(nd->'c') c) || array[nd->>'d']
    else '{}'::text[] end $$;
-- null se il grafo è corretto, altrimenti il motivo
create function pg_temp.gcheck(g jsonb) returns text language plpgsql as $$
declare seen text[]; todo text[]; k text; nd jsonb; t text; ids text[]; x text; wins integer; fails integer;
begin
  seen := array[g->>'_start']; todo := array[g->>'_start'];
  if g ? '_late' then seen := seen || (g->>'_late'); todo := todo || (g->>'_late'); end if;
  while coalesce(array_length(todo, 1), 0) > 0 loop
    k := todo[1]; todo := todo[2:];
    nd := g->k;
    if nd is null then return 'nodo mancante ' || k; end if;
    foreach t in array pg_temp.targets(nd) loop
      if not (g ? t) then return 'destinazione inesistente ' || k || ' -> ' || t; end if;
      if not (t = any(seen)) then seen := seen || t; todo := todo || t; end if;
    end loop;
  end loop;
  select array_agg(key) into ids from jsonb_object_keys(g) key where left(key, 1) <> '_';
  foreach x in array ids loop if not (x = any(seen)) then return 'irraggiungibile ' || x; end if; end loop;
  select count(*) filter (where (v->>'win')::boolean), count(*) filter (where not (v->>'win')::boolean) into wins, fails from jsonb_each(g) e(k, v) where v->>'t' = 'end';
  if wins < 3 then return 'meno di 3 vittorie'; end if;
  if fails < 3 then return 'meno di 3 fallimenti'; end if;
  return null;
end $$;
-- lo stato del dungeon in corso, come lo vede il capo gruppo
create function pg_temp.view_of(p_run uuid) returns jsonb language sql as $$ select public._game_dng_view(p_run) $$;
create function pg_temp.leader_of(p_run uuid) returns uuid language sql as $$ select leader_id from public.game_runs where id = p_run $$;
create function pg_temp.say_(p_run uuid, p_opt text, p_arg text) returns jsonb language plpgsql as $$
begin perform pg_temp.act(pg_temp.leader_of(p_run)); return public.game_dungeon_choose(p_run, p_opt, p_arg); end $$;
create function pg_temp.endof(p_run uuid) returns text language sql as $$ select result->'ending'->>'id' from public.game_runs where id = p_run $$;
create function pg_temp.statusof(p_run uuid) returns text language sql as $$ select status from public.game_runs where id = p_run $$;

-- il giocatore automatico: mode 'best' (cerca il finale migliore) o 'random' (sceglie a caso). Restituisce il numero di mosse fatte.
create function pg_temp.bot(p_run uuid, mode text) returns integer language plpgsql as $$
declare r public.game_runs%rowtype; g jsonb; nd jsonb; v jsonb; o jsonb; vo jsonb; best text; bestscore integer; sc integer; steps integer := 0; arg text; rl text; mem jsonb; nstay integer; clk jsonb;
  code text; sym integer; perm integer[]; i integer; fxj jsonb; b record; limit_stay integer;
begin
  loop
    steps := steps + 1;
    if steps > 90 then raise exception 'BOT: troppe mosse nel dungeon %', (select dungeon_no from public.game_runs where id = p_run); end if;
    select * into r from public.game_runs where id = p_run;
    exit when r.status <> 'active';
    select graph into g from public.game_dungeon_graphs where dungeon_no = r.dungeon_no;
    nd := g->(r.state->>'node');
    v := pg_temp.view_of(p_run);
    arg := null; best := null; bestscore := -1;
    if nd->>'t' = 'lock' then
      if mode = 'best' then
        select string_agg(c, ',' order by ord) into code from jsonb_array_elements_text(nd->'code') with ordinality t(c, ord);
      else
        perm := array(select s from generate_series(0, jsonb_array_length(nd->'sym') - 1) s order by random());
        code := array_to_string(perm[1:jsonb_array_length(nd->'code')], ',');
      end if;
      perform pg_temp.say_(p_run, 'lock', code);
      continue;
    end if;
    clk := v->'clock';
    nstay := jsonb_array_length(coalesce(r.state->'used', '[]'::jsonb));
    for o in select * from jsonb_array_elements(nd->'o') loop
      select x into vo from jsonb_array_elements(v->'scene'->'options') x where x->>'id' = o->>'id';
      continue when vo is null or (vo->>'locked')::boolean;
      fxj := coalesce(o->'fx', '{}'::jsonb);
      if mode = 'random' then
        sc := floor(random() * 1000)::integer;
      else
        sc := case
          when fxj->>'flag' = 'sigillo' then 100
          when (o->>'who')::boolean then 90
          when fxj->>'flag' in ('key', 'indizio') and (o->>'stay')::boolean then 85
          when fxj->>'flag' in ('key', 'indizio') then 80
          when o ? 'chk' and (o->'chk'->'okfx'->>'flag') in ('key', 'indizio') then 75
          when (o->>'stay')::boolean and coalesce((fxj->>'hp')::integer, 0) >= 0 and (clk = 'null'::jsonb or nstay < 3) then 60 + coalesce((fxj->>'pow')::integer, 0) / 5
          when o ? 'role' and coalesce((fxj->>'pow')::integer, 0) > 0 then 50
          when (o->>'stay')::boolean then 0
          when o ? 'chk' then 45
          when o->>'to' like 'eF%' then 1
          else 40 end;
      end if;
      if sc > bestscore then bestscore := sc; best := o->>'id'; end if;
    end loop;
    if best is null then raise exception 'BOT: nessuna scelta disponibile (dungeon %, nodo %)', r.dungeon_no, r.state->>'node'; end if;
    select x into o from jsonb_array_elements(nd->'o') x where x->>'id' = best;
    if (o->>'who')::boolean then
      mem := r.state->'members';
      if mode = 'best' then
        select key into rl from jsonb_each(o->'by') e(key, value) where (value->'fx'->>'flag') is not null or coalesce((value->'fx'->>'pow')::integer, 0) > 0 limit 1;
        select m->>'user_id' into arg from jsonb_array_elements(mem) m where m->>'role' = rl limit 1;
      end if;
      if arg is null then select m->>'user_id' into arg from jsonb_array_elements(mem) m order by random() limit 1; end if;
    end if;
    perform pg_temp.say_(p_run, best, arg);
  end loop;
  return steps;
end $$;
-- una partita in 3 (Tank, Danni, Supporto) o da soli; il capo gruppo è il primo
create function pg_temp.play(p_no integer, mode text, solo boolean, hero text default 'Dan') returns uuid language plpgsql as $$
declare run uuid;
begin
  if solo then run := pg_temp.begin_(hero, p_no);
  else run := pg_temp.party(p_no, 'Ann', 'tank', 'Bob', 'dps', 'Cid', 'support'); end if;
  perform pg_temp.bot(run, mode);
  return run;
end $$;

-- Preparazione: eroi di livello 9999 con tutti i dungeon precedenti completati
do $$
declare n text;
begin
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.setst('Ann', 6, 3, 6, 3, 2); perform pg_temp.setst('Bob', 10, 4, 3, 1, 2); perform pg_temp.setst('Cid', 3, 3, 4, 8, 2); perform pg_temp.setst('Dan', 6, 4, 4, 3, 3);
  foreach n in array array['Ann','Bob','Cid','Dan'] loop
    perform pg_temp.ready(n);
    perform pg_temp.lvl2(n, 9999);
    perform pg_temp.unlock(n, (select max(no) - 1 from public.game_dungeons));
  end loop;
  perform pg_temp.setting('game_dng_drop_extra_pct', 0); perform pg_temp.setting('game_dng_drop_replay_pct', 0);
  insert into t_log (msg) values ('OK Preparazione: 4 eroi al livello 9999 con tutti i dungeon precedenti completati');
end $$;

-- C1 — il catalogo: dungeon 56–100, sempre più difficili, premi che proseguono la curva
do $$
declare s jsonb;
begin
  assert (select count(*) from public.game_dungeons where no between 56 and 100 and kind = 'path') = 45 and (select count(*) from public.game_dungeons) = 100, 'C1: i dungeon sono 100 in tutto, 45 nuovi';
  assert (select bool_and(b.ref_level > a.ref_level and b.min_level > a.min_level and b.bc > a.bc and b.xp > a.xp and b.diff > a.diff) from public.game_dungeons a join public.game_dungeons b on b.no = a.no + 1 where a.no >= 55), 'C1: livello, BC, XP e forza dei nemici crescono dal 55 in avanti';
  assert (select ref_level from public.game_dungeons where no = 100) >= 602 and (select min_level from public.game_dungeons where no = 100) = 602 - 2, 'C1: l’ultimo dungeon è al livello massimo';
  assert (select bool_and(min_level = ref_level - 2) from public.game_dungeons where no > 55), 'C1: livello minimo = consigliato − 2, come prima';
  assert (select bc from public.game_dungeons where no = 56) - (select bc from public.game_dungeons where no = 55) = 95 and (select bool_and(b.bc - a.bc = 95) from public.game_dungeons a join public.game_dungeons b on b.no = a.no + 1 where a.no >= 55), 'C1: +95 BC a ogni dungeon, come prima';
  assert (select xp from public.game_dungeons where no = 56) between 3856 and 5000, 'C1: l’XP prosegue la curva del 55 (3856)';
  assert (select count(*) from public.game_items where dungeon_no > 55 and source = 'dungeon') = 45 and (select count(*) from public.game_dungeons where item_id = 'd' || no and no > 55) = 45, 'C1: un oggetto per dungeon';
  assert (select bool_and(slot = (array['weapon','armor','helm','amulet','tool'])[(dungeon_no - 26) % 5 + 1]) from public.game_items where dungeon_no > 55), 'C1: gli slot ruotano come prima (arma, armatura, elmo, amuleto, reliquia)';
  assert (select bool_and(rarity = 'mitico') from public.game_items where dungeon_no > 55 and slot = 'tool') and (select bool_and(rarity in ('raro','epico','leggendario')) from public.game_items where dungeon_no > 55 and slot <> 'tool'), 'C1: reliquie mitiche, gli altri raro/epico/leggendario';
  assert (select bool_and(b.xp_pct > a.xp_pct) from public.game_items a join public.game_items b on b.dungeon_no = a.dungeon_no + 5 and b.slot = 'tool' where a.slot = 'tool' and a.dungeon_no >= 55), 'C1: l’XP% delle reliquie cresce';
  assert (select bool_and(b.p_for >= a.p_for) from public.game_items a join public.game_items b on b.dungeon_no = a.dungeon_no + 5 and b.slot = 'weapon' where a.slot = 'weapon' and a.dungeon_no >= 51), 'C1: le armi non peggiorano';
  assert (select max(p_for + p_des + p_vig + p_spi + p_frt) from public.game_items where dungeon_no > 55) < 32000, 'C1: i bonus stanno nei limiti delle colonne';
  assert (select count(*) from public.game_dungeon_graphs) = 100 - 25, 'C1: un percorso per ogni dungeon a scelte';
  s := pg_temp.dst('Ann');
  assert (s->>'total')::int = 100 and jsonb_array_length(s->'dungeons') = 100 and (s->'dungeons'->(100-1)->>'kind') = 'path', 'C1: lo stato elenca tutti i dungeon';
  assert not exists (select 1 from public.game_dungeons where no > 55 and abs(xp - 0.934 * (100 + 10 * ref_level)) > 0.5), 'C1: XP sulla curva dei dungeon precedenti';
  assert not exists (select 1 from public.game_dungeons d join public.game_items i on i.id = d.item_id where d.no > 55 and (i.min_level <> d.min_level or i.dungeon_no <> d.no)), 'C1: l’oggetto esclusivo richiede lo stesso livello del dungeon';
  insert into t_log (msg) values (format('OK C1 — catalogo: 45 dungeon nuovi, livelli minimi da %s a %s, BC +95 a dungeon,', (select min(min_level) from public.game_dungeons where no >= 56), (select max(min_level) from public.game_dungeons where no >= 56)) || ' XP della curva del 55, un oggetto a dungeon con slot a rotazione');
end $$;

-- C2 — percorsi: nessuna destinazione nel vuoto, tutto raggiungibile, ≥3 vittorie e ≥3 fallimenti, nessun segreto in chiaro nello stato
do $$
declare r record; bad text := '';
begin
  for r in select dungeon_no, pg_temp.gcheck(graph) e from public.game_dungeon_graphs where dungeon_no > 55 loop
    if r.e is not null then bad := bad || r.dungeon_no || ': ' || r.e || '; '; end if;
  end loop;
  assert bad = '', 'C2: percorsi non validi: ' || bad;
  assert not exists (select 1 from public.game_dungeon_graphs g where dungeon_no > 55 and (select count(*) from jsonb_each(g.graph) e where e.value->>'t' in ('scene', 'lock')) < 3), 'C2: almeno 3 bivi per dungeon';
  assert (select bool_and(g.graph ? 'eBest' and g.graph ? 'eGood' and g.graph ? 'eOk' and g.graph ? 'eDef' and (g.graph->'eBest'->>'m')::int = 140 and (g.graph->'eGood'->>'m')::int = 115 and (g.graph->'eOk'->>'m')::int = 85) from public.game_dungeon_graphs g where dungeon_no > 55), 'C2: finali al 140/115/85% in ogni dungeon';
  assert not exists (select 1 from public.game_dungeon_graphs g where dungeon_no > 55 and g.graph::text like '%§%'), 'C2: nessun segnaposto di testo rimasto';
  assert not exists (select 1 from public.game_dungeon_graphs g, jsonb_each(g.graph) e where dungeon_no > 55 and e.value->>'t' = 'end' and (coalesce(e.value->>'text', '') = '' or coalesce(e.value->>'title', '') = '')), 'C2: ogni finale ha titolo e testo';
  assert pg_temp.err_auth('Ann', 'select * from public.game_dungeon_graphs') like '%permission denied%', 'C2: i percorsi restano illeggibili dal browser';
  assert not exists (select 1 from public.game_dungeon_graphs g, jsonb_each(g.graph) e where g.dungeon_no > 55 and e.value->>'t' = 'end' and (e.key in ('eBest', 'eGood', 'eOk')) <> (e.value->>'win')::boolean), 'C2: i finali eBest/eGood/eOk sono vittorie, tutti gli altri fallimenti';
  assert not exists (select 1 from public.game_dungeon_graphs g, jsonb_each(g.graph) e where g.dungeon_no > 55 and e.value->>'t' = 'end' and (e.value->>'win')::boolean and (e.value->>'m')::int not in (85, 115, 140)), 'C2: le vittorie pagano solo 85/115/140%';
  assert not exists (select 1 from public.game_dungeon_graphs g, jsonb_each(g.graph) e, jsonb_array_elements(case when e.value->>'t' = 'scene' then e.value->'o' else '[]'::jsonb end) o where g.dungeon_no > 55 and o ? 'role' and o->>'role' not in ('tank', 'dps', 'support')), 'C2: i ruoli richiesti esistono';
  insert into t_log (msg) values ('OK C2 — tutti i percorsi sono coerenti (raggiungibili, ≥3 vittorie / ≥3 fallimenti / ≥3 bivi, finali 85-115-140%) e restano segreti');
end $$;

-- C3 — le interazioni: tutte e sei usate, ogni dungeon ne ha almeno due, serrature ben fatte
do $$
declare s jsonb; k text; cnt integer; r record;
begin
  s := pg_temp.dst('Ann');
  foreach k in array array['chk', 'lock', 'stay', 'who', 'role', 'clock'] loop
    select count(*) into cnt from jsonb_array_elements(s->'dungeons') e where (e->>'no')::int > 55 and e->'inter' ? k;
    assert cnt >= 5, format('C3: l’interazione %s è usata solo in %s dungeon', k, cnt);
  end loop;
  assert not exists (select 1 from jsonb_array_elements(s->'dungeons') e where (e->>'no')::int > 55 and jsonb_array_length(e->'inter') < 2), 'C3: ogni dungeon nuovo usa almeno 2 tipi di interazione';
  assert not exists (select 1 from jsonb_array_elements(s->'dungeons') e where (e->>'no')::int <= 55 and jsonb_array_length(e->'inter') > 0), 'C3: i dungeon 1–55 non usano interazioni nuove';
  -- serrature: 3 simboli diversi su 5, 3 tentativi, un indizio che parla di quei simboli
  for r in select g.dungeon_no, e.key, e.value nd, g.graph from public.game_dungeon_graphs g, jsonb_each(g.graph) e where g.dungeon_no > 55 and e.value->>'t' = 'lock' loop
    assert jsonb_array_length(r.nd->'sym') = 5 and jsonb_array_length(r.nd->'code') = 3 and (r.nd->>'tries')::int = 3, format('C3: serratura %s/%s non è 3 su 5 con 3 tentativi', r.dungeon_no, r.key);
    assert (select count(distinct c) from jsonb_array_elements_text(r.nd->'code') c) = 3 and not exists (select 1 from jsonb_array_elements_text(r.nd->'code') c where c::int not between 0 and 4), format('C3: serratura %s/%s ha un codice non valido', r.dungeon_no, r.key);
    assert (select count(distinct x) from jsonb_array_elements_text(r.nd->'sym') x) = 5, format('C3: serratura %s/%s ha simboli ripetuti', r.dungeon_no, r.key);
    assert r.nd->'h'->>'if' = 'indizio' and r.graph->'_flags' ? 'indizio', format('C3: serratura %s/%s senza indizio', r.dungeon_no, r.key);
  end loop;
  -- le prove di abilità: probabilità di base tra 30 e 90, statistica valida
  assert not exists (select 1 from public.game_dungeon_graphs g, jsonb_each(g.graph) e, jsonb_array_elements(case when e.value->>'t' = 'scene' then e.value->'o' else '[]'::jsonb end) o
                      where g.dungeon_no > 55 and o ? 'chk' and (not (o->'chk'->>'s' in ('for','des','vig','spi','frt')) or (o->'chk'->>'b')::int not between 30 and 90)), 'C3: prove con statistica o probabilità non valide';
  -- orologio: 5 azioni nella stanza + una mossa per ogni stadio successivo (la serratura non si conta)
  assert not exists (select 1 from public.game_dungeon_graphs g where g.dungeon_no > 55 and g.graph ? '_clock'
     and (g.graph->>'_clock')::int <> 5 + (select count(*) from jsonb_each(g.graph) e where e.key ~ '^s[0-9]+$' and e.key <> 's1' and e.value->>'t' = 'scene')), 'C3: l’orologio è 5 + gli stadi successivi';
  insert into t_log (msg) values ('OK C3 — tutte e sei le interazioni sono usate; ogni dungeon nuovo ne ha ≥2; serrature da 3 su 5 con indizio coerente');
end $$;

-- C4 — giocatore «perfetto»: in ogni dungeon un gruppo con Tank, Danni e Supporto che legge gli indizi arriva al finale migliore (con più tentativi se un dado va male)
do $$
declare p integer; run uuid; att integer; ok boolean; steps integer; tot integer := 0; maxatt integer := 0; bcb numeric;
begin
  update public.game_dungeons set diff = 0.0001 where no > 55;      -- nemici facili: le prove di abilità restano casuali
  for p in select no from public.game_dungeons where no > 55 order by no loop
    ok := false; att := 0;
    while not ok and att < 12 loop
      att := att + 1;
      run := pg_temp.play(p, 'best', false);
      ok := pg_temp.statusof(run) = 'cleared' and pg_temp.endof(run) = 'eBest';
    end loop;
    assert ok, format('C4: il dungeon %s non porta al finale migliore dopo %s tentativi', p, att);
    tot := tot + att; maxatt := greatest(maxatt, att);
  end loop;
  assert pg_temp.clears('Ann', 56) >= 1 and pg_temp.clears('Cid', 100) >= 1, 'C4: i dungeon risultano completati';
  insert into t_log (msg) values (format('OK C4 — in tutti i %s dungeon il gruppo con Tank/Danni/Supporto raggiunge il finale migliore (%s tentativi in tutto, al massimo %s per dungeon)', 45, tot, maxatt));
end $$;

-- C5 — giocatore a caso: ogni partita finisce (vittoria o fallimento) senza errori, anche con scelte insensate
do $$
declare p integer; i integer; run uuid; w integer := 0; l integer := 0;
begin
  for p in select no from public.game_dungeons where no > 55 order by no loop
    for i in 1..4 loop
      run := pg_temp.play(p, 'random', true, case when p = 100 then 'Ann' else 'Dan' end);
      assert pg_temp.statusof(run) in ('cleared', 'failed') and pg_temp.endof(run) is not null, format('C5: partita a caso senza esito nel dungeon %s', p);
      if pg_temp.statusof(run) = 'cleared' then w := w + 1; else l := l + 1; end if;
    end loop;
  end loop;
  assert w > 0 and l > 0, 'C5: tra le partite a caso ci sono sia vittorie sia fallimenti';
  insert into t_log (msg) values (format('OK C5 — %s partite a caso (%s vittorie, %s fallimenti): tutte arrivano a un finale', w + l, w, l));
end $$;

-- C6 — premi: alla prima vittoria BC, XP e oggetto esclusivo; alla replica meno; fallire dà solo la consolazione
do $$
declare run uuid; b0 integer; b1 integer; x0 bigint; d public.game_dungeons%rowtype; n integer; bonus numeric; exp_bc integer; rr jsonb;
begin
  select * into d from public.game_dungeons where no = 100;
  assert not exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Dan') and item_id = 'd' || 100), 'C6: Dan non ha ancora l’oggetto';
  -- Dan vince il dungeon 100 da solo (Ann l’ha già completato, lui no): premio pieno × 140%
  update public.game_dungeons set diff = 0.0001 where no = 100;
  b0 := pg_temp.bal('Dan');
  run := pg_temp.begin_('Dan', 100);
  perform pg_temp.bot(run, 'best');
  rr := (select result from public.game_runs where id = run);
  assert pg_temp.statusof(run) = 'cleared', 'C6: con nemici facili la partita si vince';
  if true then
    exp_bc := round(d.bc * case rr->'ending'->>'id' when 'eBest' then 1.4 when 'eGood' then 1.15 else 0.85 end)::integer;
    assert pg_temp.bal('Dan') - b0 = exp_bc, format('C6: BC attesi %s, ricevuti %s', exp_bc, pg_temp.bal('Dan') - b0);
    assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Dan') and item_id = 'd' || 100), 'C6: oggetto esclusivo ottenuto';
    assert (rr->'members'->0->>'xp')::bigint > 0, 'C6: XP assegnati';
  end if;
  -- fallire dà XP di consolazione e nessun BC
  b0 := pg_temp.bal('Dan');
  run := pg_temp.begin_('Dan', 100);
  perform pg_temp.as_('Dan'); rr := public.game_dungeon_abandon(run);
  assert rr->>'status' = 'failed' and pg_temp.bal('Dan') = b0 and (rr->'result'->'members'->0->>'xp')::bigint > 0, 'C6: ritirarsi fa fallire: XP di consolazione e nessun BC';
  insert into t_log (msg) values ('OK C6 — premi del dungeon finale: BC = base × finale, oggetto esclusivo, fallimento senza BC');
end $$;

-- C7 — accesso: serve il livello minimo e il dungeon precedente; l'ultimo richiede il livello massimo
do $$
declare run uuid;
begin
  perform pg_temp.lvl2('Cid', 600 - 1);
  update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid('Cid');
  assert pg_temp.err_as('Cid', format('select public.game_dungeon_create(%s, ''dps'')', 100)) like '%Serve il livello ' || 600 || '%', 'C7: un livello sotto il minimo non basta';
  perform pg_temp.lvl2('Cid', 600);
  assert pg_temp.err_as('Cid', format('select public.game_dungeon_create(%s, ''dps'')', 100)) is null, 'C7: al livello minimo si entra';
  perform pg_temp.as_('Cid'); perform public.game_dungeon_leave((select m.run_id from public.game_run_members m join public.game_runs r on r.id = m.run_id where m.user_id = pg_temp.uid('Cid') and r.status = 'lobby'));
  update public.game_dungeon_progress set clears = 0 where user_id = pg_temp.uid('Cid') and dungeon_no = 100 - 1;
  assert pg_temp.err_as('Cid', format('select public.game_dungeon_create(%s, ''dps'')', 100)) like '%bloccato%', 'C7: senza il precedente è bloccato';
  update public.game_dungeon_progress set clears = 1 where user_id = pg_temp.uid('Cid') and dungeon_no = 100 - 1;
  perform pg_temp.lvl2('Cid', 9999);
  insert into t_log (msg) values ('OK C7 — accesso: livello minimo e dungeon precedente');
end $$;

-- C8 — orologio: chi spreca le mosse non arriva al finale migliore
do $$
declare p integer; run uuid; r record; n integer := 0; ok boolean; o text;
begin
  for r in select g.dungeon_no from public.game_dungeon_graphs g where g.dungeon_no > 55 and g.graph ? '_clock' order by 1 loop
    n := n + 1;
    run := pg_temp.party(r.dungeon_no, 'Ann', 'tank', 'Bob', 'dps', 'Cid', 'support');
    -- il goloso: fa tutte le azioni «una tantum» che trova, poi esce
    declare st jsonb; nd jsonb; v jsonb; g jsonb; steps integer := 0;
    begin
      select graph into g from public.game_dungeon_graphs where dungeon_no = r.dungeon_no;
      while pg_temp.statusof(run) = 'active' and steps < 40 loop
        steps := steps + 1;
        select state into st from public.game_runs where id = run;
        nd := g->(st->>'node'); v := pg_temp.view_of(run);
        if nd->>'t' = 'lock' then
          perform pg_temp.say_(run, 'lock', (select string_agg(c, ',' order by ord) from jsonb_array_elements_text(nd->'code') with ordinality t(c, ord)));
        else
          select x->>'id' into o from jsonb_array_elements(v->'scene'->'options') x where (x->>'stay')::boolean and not (x->>'locked')::boolean limit 1;
          if o is null then
            select x->>'id' into o from jsonb_array_elements(nd->'o') x where x->>'to' not like 'eF%' and not (x ? 'stay') and not (x ? 'who') and not (x ? 'chk') and not (x ? 'role')
               and exists (select 1 from jsonb_array_elements(v->'scene'->'options') y where y->>'id' = x->>'id' and not (y->>'locked')::boolean) order by (x->>'id') desc limit 1;
          end if;
          if o is null then
            select x->>'id' into o from jsonb_array_elements(v->'scene'->'options') x where not (x->>'locked')::boolean and (x->'chk') <> 'null'::jsonb limit 1;
          end if;
          if o is null then select x->>'id' into o from jsonb_array_elements(v->'scene'->'options') x where not (x->>'locked')::boolean limit 1; end if;
          perform pg_temp.say_(run, o, (select m->>'user_id' from jsonb_array_elements(st->'members') m limit 1));
        end if;
      end loop;
    end;
    ok := pg_temp.statusof(run) = 'failed' or pg_temp.endof(run) <> 'eBest';
    assert ok, format('C8: nel dungeon %s a orologio chi spreca le mosse ha comunque il finale migliore', r.dungeon_no);
  end loop;
  assert n >= 5, 'C8: abbastanza dungeon a orologio';
  insert into t_log (msg) values (format('OK C8 — %s dungeon a orologio: chi fa tutte le azioni senza fermarsi non raggiunge il finale migliore', n));
end $$;

select msg as esito from t_log order by n;
rollback;
