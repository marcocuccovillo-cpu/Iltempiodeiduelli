-- =====================================================================
-- TEST DELLA MIGRAZIONE 027 (La guerra degli Eroi: nuovi tipi di interazione nei dungeon a scelte)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…027 (… black-market-eroi-dungeon-scelte.sql, black-market-eroi-dungeon-interazioni.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. I dungeon 898–902 usati qui esistono solo dentro il test.
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

-- Preparazione: eroi pronti, dungeon di prova con percorsi che usano ogni nuova interazione
do $$
declare n text;
begin
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.setst('Ann', 10, 4, 4, 2, 0); perform pg_temp.setst('Bob', 4, 4, 4, 4, 4); perform pg_temp.setst('Cid', 6, 6, 4, 2, 2); perform pg_temp.setst('Dan', 6, 4, 6, 2, 2);
  foreach n in array array['Ann','Bob','Cid','Dan'] loop perform pg_temp.ready(n); end loop;
  perform pg_temp.setting('game_dng_drop_extra_pct', 0); perform pg_temp.setting('game_dng_drop_replay_pct', 0);
  -- prima i dungeon (senza oggetto), poi gli oggetti, poi il collegamento
  insert into public.game_dungeons (no, name, emoji, lore, boss_name, boss_emoji, boss_lore, rooms, ref_level, min_level, bc, xp, diff, kind, item_id)
  select g, 'Prova ' || g, '🧪', 'x', 'Capo ' || g, '👹', 'x', '[{"name":"Stanza","emoji":"🚪","boss":false},{"name":"Capo","emoji":"👹","boss":true}]'::jsonb, 10, 1, 100, 10, 0.01, 'path', null
    from unnest(array[898, 899, 900, 901]) g;
  insert into public.game_items (id, name, slot, tier, rarity, min_level, p_for, p_des, p_vig, p_spi, p_frt, xp_pct, extra_actions, descr, source, dungeon_no)
  select 'dt' || g, 'Oggetto di prova ' || g, 'weapon', 0, 'raro', 1, 1, 0, 0, 0, 0, 0, 0, 'prova', 'dungeon', g from unnest(array[898, 899, 900, 901]) g;
  update public.game_dungeons set item_id = 'dt' || no where no between 898 and 901;
  insert into public.game_dungeon_graphs (dungeon_no, graph) values
  (900, $j${"_start":"h1",
   "h1":{"t":"scene","n":"Atrio","x":"Un atrio di prova.","o":[
     {"id":"a","l":"Esplora la sala","r":"Trovi un’arma.","stay":true,"fx":{"pow":10}},
     {"id":"b","l":"Fruga tra le macerie","r":"Ti ferisci.","stay":true,"fx":{"hp":-10,"flag":"f_b"}},
     {"id":"c","l":"Il Supporto purifica l’altare","r":"Purificato.","role":"support","to":"h1","fx":{"flag":"pur"}},
     {"id":"d","l":"Il Tank sfonda la porta","r":"Sfondata.","role":"tank","to":"eTank"},
     {"id":"e","l":"Chi attraversa il ponte?","who":true,"by":{"tank":{"to":"eWT"},"dps":{"to":"eWD","r":"Il Danni trova un varco.","fx":{"pow":2}},"support":{"to":"eWS","fxw":{"hp":-10}}},"to":"eWD","fx":{"pow":1},"fxw":{"hp":-30}},
     {"id":"f","l":"Prova di Forza","chk":{"s":"for","b":100,"ok":"eCkOk","ko":"eCkKo","okfx":{"flag":"passed"},"kofx":{"hp":-5},"rok":"Bravo.","rko":"Peccato."}},
     {"id":"g","l":"Prova impossibile","chk":{"s":"for","b":0,"ok":"eCkOk","ko":"eCkKo","kofx":{"hp":-5},"rok":"Bravo.","rko":"Peccato."}},
     {"id":"h","l":"Prova di Destrezza","chk":{"s":"des","b":55,"ok":"eCkOk","ko":"eCkKo"}},
     {"id":"i","l":"Alla serratura","to":"lk1"}]},
   "lk1":{"t":"lock","n":"La serratura","x":"Cinque simboli.","sym":["A","B","C","D","E"],"code":[2,0,3],"tries":2,"ok":"eLkOk","ko":"eLkKo","okfx":{"pow":5},"kofx":{"hp":-10},"rok":"Scatta.","rko":"Si blocca.","h":{"if":"f_b","t":"Indizio: C A D."}},
   "eTank":{"t":"end","win":true,"title":"Porta sfondata","x":"x","text":"x","m":100},
   "eWT":{"t":"end","win":true,"title":"Il Tank passa","x":"x","text":"x","m":100},
   "eWD":{"t":"end","win":true,"title":"Il Danni passa","x":"x","text":"x","m":100},
   "eWS":{"t":"end","win":true,"title":"Il Supporto passa","x":"x","text":"x","m":100},
   "eCkOk":{"t":"end","win":true,"title":"Prova superata","x":"x","text":"x","m":140},
   "eCkKo":{"t":"end","win":false,"title":"Prova fallita","x":"x","text":"x","m":100},
   "eLkOk":{"t":"end","win":true,"title":"Serratura aperta","x":"x","text":"x","m":115},
   "eLkKo":{"t":"end","win":false,"title":"Serratura bloccata","x":"x","text":"x","m":100},
   "_flags":{"f_b":"Macerie","pur":"Altare purificato","passed":"Prova superata"}}$j$::jsonb),
  (901, $j${"_start":"s1","_clock":3,"_late":"eLate","_latetxt":"Il tempo è scaduto: i nemici vi raggiungono.",
   "s1":{"t":"scene","n":"Inizio","x":"Hai poche mosse.","o":[
     {"id":"a","l":"Avanti","to":"s2"},
     {"id":"q","l":"Una via costosa","to":"s2","cost":3},
     {"id":"w","l":"Scorciatoia","to":"eWin"}]},
   "s2":{"t":"scene","n":"Corridoio","x":"x","o":[
     {"id":"a","l":"Avanti","to":"s3"},
     {"id":"z","l":"Riposa un attimo","stay":true,"fx":{"hp":10}}]},
   "s3":{"t":"scene","n":"Bivio","x":"x","o":[
     {"id":"a","l":"Altra sala","to":"s4"},
     {"id":"w","l":"Uscita sicura","to":"eWin","cost":0},
     {"id":"x","l":"Uscita normale","to":"eWin"}]},
   "s4":{"t":"scene","n":"Altra sala","x":"x","o":[{"id":"a","l":"Avanti","to":"eWin"}]},
   "eWin":{"t":"end","win":true,"title":"Fuori in tempo","x":"x","text":"x","m":100},
   "eLate":{"t":"end","win":false,"title":"Troppo tardi","x":"x","text":"x","m":100}}$j$::jsonb);
  insert into public.game_dungeon_graphs (dungeon_no, graph) select g, '{"_start":"e","e":{"t":"end","win":true,"title":"x","x":"x","text":"x","m":100}}'::jsonb from unnest(array[898, 899]) g;
  -- 898 e 899 «completati» da tutti: così il 900 è aperto; il 901 si apre quando si completa il 900
  insert into public.game_dungeon_progress (user_id, dungeon_no, clears, first_clear_at, last_clear_at)
    select pg_temp.uid(u), g, 1, now(), now() from unnest(array['Ann','Bob','Cid','Dan']) u, unnest(array[898, 899]) g on conflict do nothing;
  insert into t_log (msg) values ('OK Preparazione: 4 eroi di livello 500, due dungeon di prova (900 con tutte le interazioni, 901 con l’orologio)');
end $$;

-- N1 — il motore: nuova firma, funzioni interne chiuse al browser, percorsi segreti
do $$
begin
  assert to_regprocedure('public.game_dungeon_choose(uuid,text,text)') is not null and to_regprocedure('public.game_dungeon_choose(uuid,text)') is null, 'N1: game_dungeon_choose ha 3 parametri (il terzo facoltativo) e non esiste più la vecchia firma';
  assert to_regprocedure('public._game_dng_fx(jsonb,jsonb)') is null and to_regprocedure('public._game_dng_fx(jsonb,jsonb,text)') is not null, 'N1: _game_dng_fx ha una sola firma';
  assert pg_temp.err_auth('Ann', $q$select public._game_dng_odds('{"members":[]}'::jsonb, 'for', 50)$q$) like '%permission denied%', 'N1: le probabilità non si chiamano dal browser';
  assert pg_temp.err_auth('Ann', $q$select public._game_dng_fx('{}'::jsonb, '{}'::jsonb, null)$q$) like '%permission denied%', 'N1: gli effetti non si chiamano dal browser';
  assert pg_temp.err_auth('Ann', $q$select * from public.game_dungeon_graphs$q$) like '%permission denied%', 'N1: i percorsi restano illeggibili dal browser';
  insert into t_log (msg) values ('OK N1 — firma nuova di game_dungeon_choose, funzioni interne e percorsi non raggiungibili dal browser');
end $$;

-- N2 — probabilità delle prove: dipende da come è costruito l'eroe, è limitata tra 5% e 95%, +4% per ogni compagno
do $$
declare sa jsonb; sb jsonb; sab jsonb; p numeric;
begin
  sa  := jsonb_build_object('members', jsonb_build_array(jsonb_build_object('user_id', pg_temp.uid('Ann'), 'hp', 10)));
  sb  := jsonb_build_object('members', jsonb_build_array(jsonb_build_object('user_id', pg_temp.uid('Bob'), 'hp', 10)));
  sab := jsonb_build_object('members', jsonb_build_array(jsonb_build_object('user_id', pg_temp.uid('Ann'), 'hp', 10), jsonb_build_object('user_id', pg_temp.uid('Bob'), 'hp', 10)));
  assert public._game_dng_odds(sa, 'for', 100) = 1 and public._game_dng_odds(sa, 'for', 0) = 0 and public._game_dng_odds(sa, 'for', 150) = 1 and public._game_dng_odds(sa, 'for', -5) = 0, 'N2: base ≥100 sempre, ≤0 mai';
  -- Ann: 10 punti su 20 in Forza (quota 0,5); Bob: 4 su 20 in ogni caratteristica (0,2)
  assert abs(public._game_dng_odds(sa, 'for', 50) - 0.74) < 0.001, 'N2: Ann ha il 74% (50 + 0,8 × (0,5 − 0,2)) in una prova di Forza';
  assert abs(public._game_dng_odds(sb, 'for', 50) - 0.50) < 0.001 and abs(public._game_dng_odds(sb, 'frt', 50) - 0.50) < 0.001, 'N2: Bob, bilanciato, resta al 50%';
  assert abs(public._game_dng_odds(sa, 'frt', 50) - 0.34) < 0.001, 'N2: Ann in Fortezza (0 punti) scende al 34%';
  assert abs(public._game_dng_odds(sab, 'for', 50) - 0.78) < 0.001, 'N2: in due si guadagna un 4%: vale il migliore, più i compagni';
  assert public._game_dng_odds(sa, 'for', 99) = 0.95 and public._game_dng_odds(sa, 'frt', 1) = 0.05, 'N2: tra il 5% e il 95%';
  assert public._game_dng_odds(sa, 'xyz', 50) = 0.34, 'N2: una caratteristica sconosciuta non dà vantaggi';
  p := public._game_dng_odds(jsonb_build_object('members', jsonb_build_array(jsonb_build_object('user_id', pg_temp.uid('Ann'), 'hp', 0))), 'for', 50);
  assert abs(p - 0.34) < 0.001, 'N2: un eroe KO non aiuta (resta la base meno il fattore di partenza)';
  insert into t_log (msg) values ('OK N2 — probabilità delle prove: 74% per chi ha investito, 50% per il bilanciato, limiti 5–95%, +4% per compagno, KO ignorati');
end $$;

-- N3 — stanza a più azioni, scelte di ruolo, probabilità visibili, niente fughe di segreti
do $$
declare run uuid; v jsonb; r jsonb;
begin
  run := pg_temp.begin_('Ann', 900);
  v := pg_temp.vw('Ann');
  assert v->'scene'->>'id' = 'h1' and v->'scene'->>'type' = 'scene' and jsonb_array_length(v->'scene'->'options') = 9, 'N3: la scena iniziale ha 9 opzioni';
  assert (pg_temp.opt(v, 'a')->>'stay')::boolean and not (pg_temp.opt(v, 'a')->>'locked')::boolean and not (pg_temp.opt(v, 'a')->>'done')::boolean, 'N3: l’azione «una tantum» è disponibile';
  assert (pg_temp.opt(v, 'c')->>'locked')::boolean and pg_temp.opt(v, 'c')->>'hint' = 'Serve un Supporto nel gruppo', 'N3: la scelta da Supporto è bloccata, con il motivo';
  assert (pg_temp.opt(v, 'd')->>'locked')::boolean and pg_temp.opt(v, 'd')->>'hint' = 'Serve un Tank nel gruppo', 'N3: la scelta da Tank è bloccata';
  assert (pg_temp.opt(v, 'f')->'chk'->>'odds')::int = 100 and (pg_temp.opt(v, 'g')->'chk'->>'odds')::int = 0 and pg_temp.opt(v, 'f')->'chk'->>'stat' = 'for', 'N3: le probabilità sono mostrate (100% e 0%)';
  assert (pg_temp.opt(v, 'h')->'chk'->>'odds')::int between 5 and 95, 'N3: una prova normale sta tra il 5 e il 95%';
  assert (pg_temp.opt(v, 'e')->>'who')::boolean and not (pg_temp.opt(v, 'e')->>'locked')::boolean, 'N3: «scegli l’eroe» è segnalato';
  assert v::text not like '%eCkOk%' and v::text not like '%"by"%' and v::text not like '%eWT%' and v::text not like '%"ok"%' and v::text not like '%rok%' and v::text not like '%kofx%', 'N3: la vista non svela esiti, destinazioni o effetti';
  -- azione una tantum: effetto, stessa scena, non ripetibile, il suo segno resta
  r := pg_temp.ch('Ann', run, 'a');
  assert r->>'status' = 'active' and r->'view'->'scene'->>'id' = 'h1' and (r->'view'->>'pow')::int = 10, 'N3: l’azione dà +10% e si resta nella stanza';
  assert (pg_temp.opt(r->'view', 'a')->>'done')::boolean and (pg_temp.opt(r->'view', 'a')->>'locked')::boolean and pg_temp.opt(r->'view', 'a')->>'hint' = 'Già fatto', 'N3: l’azione è segnata «già fatto»';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''a'')', run)) like '%già fatto questa azione%', 'N3: non si ripete';
  assert (pg_temp.rst(run)->'used') = '["h1:a"]'::jsonb, 'N3: lo stato ricorda le azioni fatte';
  -- una seconda azione: danni al gruppo e un indizio; la scena del serratura mostra l'indizio solo dopo
  r := pg_temp.ch('Ann', run, 'b');
  assert pg_temp.hpof(run, 'Ann') = round(pg_temp.mxof(run, 'Ann') * 0.9, 2) and (r->'view'->'flags'->0->>'label') = 'Macerie', 'N3: -10% PV e indizio trovato';
  -- scelte non disponibili
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''c'')', run)) like '%non è ancora disponibile%', 'N3: senza Supporto non si può';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''d'')', run)) like '%non è ancora disponibile%', 'N3: senza Tank non si può (Ann è «Danni»)';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''zz'')', run)) like '%Scelta non valida%', 'N3: opzione inesistente';
  perform pg_temp.ch('Ann', run, 'g');       -- chiude la partita (prova impossibile → fallisce)
  insert into t_log (msg) values ('OK N3 — stanza a più azioni (una tantum, “già fatto”), scelte di ruolo bloccate con il motivo, probabilità visibili, nessun segreto nella vista');
end $$;

-- N4 — prove di abilità: riuscita certa e fallimento certo, con testo, effetti e cronaca
do $$
declare run uuid; r jsonb; hp0 numeric;
begin
  run := pg_temp.begin_('Ann', 900);
  r := pg_temp.ch('Ann', run, 'f');
  assert r->>'status' = 'cleared' and pg_temp.endid(r) = 'eCkOk' and (r->'result'->'ending'->>'m')::int = 140, 'N4: base 100% → riesce, finale 140%';
  assert pg_temp.rst(run)->'flags' ? 'passed', 'N4: l’effetto della riuscita (indizio) è applicato';
  assert (pg_temp.rst(run)->'log'->0->'chk') = '{"s":"for","p":100,"ok":true}'::jsonb and pg_temp.rst(run)->'log'->0->>'r' = 'Bravo.', 'N4: la cronaca registra la prova e il testo di riuscita';
  assert pg_temp.clears('Ann', 900) = 1, 'N4: dungeon completato';
  run := pg_temp.begin_('Ann', 900);
  r := pg_temp.ch('Ann', run, 'g');
  assert r->>'status' = 'failed' and pg_temp.endid(r) = 'eCkKo', 'N4: base 0% → fallisce';
  assert pg_temp.hpof(run, 'Ann') = round(pg_temp.mxof(run, 'Ann') * 0.95, 2) and pg_temp.rst(run)->'log'->0->>'r' = 'Peccato.' and not ((pg_temp.rst(run)->'log'->0->'chk'->>'ok')::boolean), 'N4: l’effetto del fallimento (−5% PV) e il testo sono applicati';
  -- una prova intermedia: l'esito segue il dado; su molte prove si vedono entrambi gli esiti
  declare ok_n integer := 0; ko_n integer := 0; i integer; rr jsonb;
  begin
    for i in 1..40 loop
      run := pg_temp.begin_('Bob', 900);
      rr := pg_temp.ch('Bob', run, 'h');
      if pg_temp.endid(rr) = 'eCkOk' then ok_n := ok_n + 1; else ko_n := ko_n + 1; end if;
    end loop;
    assert ok_n > 5 and ko_n > 5 and ok_n + ko_n = 40, format('N4: un 50%% vero vede entrambi gli esiti su 40 prove (riusciti %s, falliti %s)', ok_n, ko_n);
  end;
  insert into t_log (msg) values ('OK N4 — prove di abilità: 100% riesce, 0% fallisce, effetti e testi distinti, cronaca con la probabilità; il 50% dà entrambi gli esiti');
end $$;

-- N5 — scegli l'eroe e ruoli presenti: l'esito segue il ruolo dell'eroe scelto, il danno colpisce solo lui
do $$
declare run uuid; r jsonb; v jsonb;
begin
  run := pg_temp.party(900, 'Ann', 'tank', 'Bob', 'dps');
  v := pg_temp.vw('Ann');
  assert not (pg_temp.opt(v, 'd')->>'locked')::boolean and (pg_temp.opt(v, 'c')->>'locked')::boolean, 'N5: con un Tank la sua scelta si apre, quella del Supporto resta chiusa';
  assert pg_temp.err_as('Bob', format('select public.game_dungeon_choose(%L, ''e'', %L)', run, pg_temp.uid('Bob'))) like '%Solo il capo gruppo%', 'N5: solo il capo sceglie';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''e'')', run)) like '%Scegli quale eroe%', 'N5: senza eroe scelto no';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''e'', %L)', run, gen_random_uuid())) like '%Scegli quale eroe%', 'N5: un eroe che non è nel gruppo no';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''e'', ''abc'')', run)) like '%Scegli quale eroe%', 'N5: testo che non è un eroe no';
  r := pg_temp.chx('Ann', run, 'e', pg_temp.uid('Bob')::text);
  assert r->>'status' = 'cleared' and pg_temp.endid(r) = 'eWD', 'N5: Bob è «Danni» → strada dei Danni';
  assert pg_temp.hpof(run, 'Bob') = round(pg_temp.mxof(run, 'Bob') * 0.7, 2) and pg_temp.hpof(run, 'Ann') = pg_temp.mxof(run, 'Ann'), 'N5: −30% PV solo a Bob; Ann intatta';
  assert (pg_temp.rst(run)->>'pow')::int = 3 and pg_temp.rst(run)->'log'->0->>'w' = 'Bob' and pg_temp.rst(run)->'log'->0->>'r' = 'Il Danni trova un varco.', 'N5: gli effetti per tutti (dell’opzione e del ruolo) si sommano, il testo è quello del ruolo, la cronaca ricorda chi ha affrontato la prova';
  -- Ann (Tank) scelta
  run := pg_temp.party(900, 'Ann', 'tank', 'Bob', 'dps');
  r := pg_temp.chx('Ann', run, 'e', pg_temp.uid('Ann')::text);
  assert pg_temp.endid(r) = 'eWT' and pg_temp.hpof(run, 'Ann') = round(pg_temp.mxof(run, 'Ann') * 0.7, 2) and pg_temp.hpof(run, 'Bob') = pg_temp.mxof(run, 'Bob'), 'N5: il Tank scelto → strada del Tank, danno solo a lui';
  -- il Tank apre la porta
  run := pg_temp.party(900, 'Ann', 'tank', 'Bob', 'dps');
  r := pg_temp.ch('Ann', run, 'd');
  assert pg_temp.endid(r) = 'eTank' and r->>'status' = 'cleared', 'N5: la scelta da Tank funziona con un Tank nel gruppo';
  -- tre eroi: il Supporto purifica e poi viene scelto
  run := pg_temp.party(900, 'Ann', 'tank', 'Bob', 'dps', 'Cid', 'support');
  v := pg_temp.vw('Ann');
  assert not (pg_temp.opt(v, 'c')->>'locked')::boolean, 'N5: con un Supporto la sua scelta si apre';
  r := pg_temp.ch('Ann', run, 'c');
  assert r->>'status' = 'active' and r->'view'->'scene'->>'id' = 'h1' and r->'view'->'flags'->0->>'label' = 'Altare purificato', 'N5: il Supporto purifica, si resta nella stanza con il nuovo indizio';
  r := pg_temp.chx('Ann', run, 'e', pg_temp.uid('Cid')::text);
  assert pg_temp.endid(r) = 'eWS' and abs(pg_temp.hpof(run, 'Cid') - pg_temp.mxof(run, 'Cid') * 0.6) < 0.02 and pg_temp.hpof(run, 'Ann') = pg_temp.mxof(run, 'Ann'), 'N5: il Supporto scelto → strada del Supporto, danno dell’opzione e del ruolo solo a lui';
  insert into t_log (msg) values ('OK N5 — “scegli l’eroe”: strada e danno seguono l’eroe scelto; scelte di Tank/Supporto aperte solo se il ruolo c’è; solo il capo sceglie');
end $$;

-- N6 — serratura a combinazione: errori di formato, feedback dopo ogni tentativo, tentativi limitati, indizio condizionato
do $$
declare run uuid; r jsonb; v jsonb;
begin
  run := pg_temp.begin_('Ann', 900);
  v := pg_temp.ch('Ann', run, 'i')->'view';
  assert v->'scene'->>'id' = 'lk1' and v->'scene'->>'type' = 'lock' and jsonb_array_length(v->'scene'->'options') = 0, 'N6: la serratura è una scena senza opzioni';
  assert (v->'scene'->'lock'->>'len')::int = 3 and (v->'scene'->'lock'->>'tries_left')::int = 2 and v->'scene'->'lock'->'symbols' = '["A","B","C","D","E"]'::jsonb and v->'scene'->'lock'->'feedback' = 'null'::jsonb, 'N6: 3 simboli su 5, 2 tentativi, nessun feedback';
  assert v->'scene'->>'text' = 'Cinque simboli.', 'N6: senza aver cercato tra le macerie, nessun indizio';
  assert v::text not like '%"code"%' and v::text not like '%[2, 0, 3]%' and v::text not like '%eLkOk%' and v::text not like '%Indizio%', 'N6: la combinazione non è nella vista';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'')', run)) like '%Combinazione non valida%', 'N6: serve una combinazione';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''0,1'')', run)) like '%Combinazione non valida%', 'N6: troppo corta';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''0,1,2,3'')', run)) like '%Combinazione non valida%', 'N6: troppo lunga';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''1,1,2'')', run)) like '%Combinazione non valida%', 'N6: simboli ripetuti';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''0,1,5'')', run)) like '%Combinazione non valida%', 'N6: simbolo che non esiste';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''0,1,-1'')', run)) like '%Combinazione non valida%', 'N6: indice negativo';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''a,b,c'')', run)) like '%Combinazione non valida%', 'N6: non numeri';
  assert (pg_temp.rst(run)->'lk') is null, 'N6: i tentativi non validi non contano';
  -- primo tentativo sbagliato (0 al posto giusto): feedback, danno, un tentativo in meno
  r := pg_temp.chx('Ann', run, 'lock', '0,1,2');
  assert r->>'status' = 'active' and r->'view'->'scene'->>'id' = 'lk1' and r->'view'->'scene'->'lock'->>'feedback' = '0 su 3 simboli al posto giusto. Tentativi rimasti: 1.' and (r->'view'->'scene'->'lock'->>'tries_left')::int = 1, 'N6: feedback e tentativi rimasti';
  assert pg_temp.hpof(run, 'Ann') = round(pg_temp.mxof(run, 'Ann') * 0.9, 2) and pg_temp.rst(run)->'log'-> -1 ->>'l' = 'A B C', 'N6: −10% PV e la cronaca mostra la combinazione provata';
  -- secondo sbagliato (2 al posto giusto): tentativi finiti → finale di fallimento
  r := pg_temp.chx('Ann', run, 'lock', '2,0,4');
  assert r->>'status' = 'failed' and pg_temp.endid(r) = 'eLkKo', 'N6: finiti i tentativi → serratura bloccata';
  assert pg_temp.err_as('Ann', format('select public.game_dungeon_choose(%L, ''lock'', ''2,0,3'')', run)) like '%non è in corso%', 'N6: a partita finita non si tenta più';
  -- con l'indizio delle macerie: il testo cambia; seconda prova giusta dopo una parziale
  run := pg_temp.begin_('Ann', 900);
  perform pg_temp.ch('Ann', run, 'b');
  v := pg_temp.ch('Ann', run, 'i')->'view';
  assert v->'scene'->>'text' = E'Cinque simboli.\n\nIndizio: C A D.', 'N6: dopo le macerie compare l’indizio';
  r := pg_temp.chx('Ann', run, 'lock', '2,0,4');
  assert r->'view'->'scene'->'lock'->>'feedback' = '2 su 3 simboli al posto giusto. Tentativi rimasti: 1.', 'N6: due simboli al posto giusto';
  r := pg_temp.chx('Ann', run, 'lock', '2,0,3');
  assert r->>'status' = 'cleared' and pg_temp.endid(r) = 'eLkOk' and (r->'result'->'ending'->>'m')::int = 115, 'N6: combinazione giusta → serratura aperta, finale 115%';
  assert (pg_temp.rst(run)->>'pow')::int = 5 and pg_temp.rst(run)->'log'-> -1 ->>'k' = 'l', 'N6: effetto della serratura aperta (+5%), cronaca della serratura';
  -- giusta al primo colpo
  run := pg_temp.begin_('Ann', 900);
  perform pg_temp.ch('Ann', run, 'i');
  r := pg_temp.chx('Ann', run, 'lock', ' 2, 0, 3 ');
  assert r->>'status' = 'cleared' and pg_temp.endid(r) = 'eLkOk', 'N6: giusta al primo colpo (spazi tollerati)';
  insert into t_log (msg) values ('OK N6 — serratura: formati non validi respinti senza consumare tentativi, feedback “N su 3”, 2 tentativi, indizio condizionato, combinazione mai nella vista');
end $$;

-- N7 — orologio: mosse limitate, costo per scelta, scadenza verso il finale «in ritardo»
do $$
declare run uuid; r jsonb;
begin
  run := pg_temp.begin_('Ann', 901);
  assert pg_temp.vw('Ann')->'clock' = '{"left":3,"total":3}'::jsonb, 'N7: all’inizio ci sono 3 mosse su 3';
  r := pg_temp.ch('Ann', run, 'a');
  assert r->'view'->'clock' = '{"left":2,"total":3}'::jsonb, 'N7: ogni scelta consuma una mossa';
  r := pg_temp.ch('Ann', run, 'z');                                 -- anche un’azione «una tantum» costa
  assert r->'view'->'clock' = '{"left":1,"total":3}'::jsonb and r->'view'->'scene'->>'id' = 's2', 'N7: anche l’azione nella stanza consuma una mossa';
  r := pg_temp.ch('Ann', run, 'a');                                 -- s3 con 0 mosse? sì: il tempo è finito
  assert r->>'status' = 'failed' and pg_temp.endid(r) = 'eLate', 'N7: a zero mosse, verso una scena normale, arriva il finale in ritardo';
  assert (select count(*) from jsonb_array_elements(pg_temp.rst(run)->'log') x where x->>'k' = 't' and x->>'r' like 'Il tempo è scaduto%') = 1, 'N7: la cronaca ricorda che il tempo è scaduto';
  -- arrivare a zero scegliendo direttamente un finale vale
  run := pg_temp.begin_('Ann', 901);
  perform pg_temp.ch('Ann', run, 'a'); perform pg_temp.ch('Ann', run, 'a');
  r := pg_temp.ch('Ann', run, 'x');
  assert r->>'status' = 'cleared' and pg_temp.endid(r) = 'eWin', 'N7: l’ultima mossa che porta a un finale non viene punita';
  -- scelta a costo zero: non consuma
  run := pg_temp.begin_('Ann', 901);
  perform pg_temp.ch('Ann', run, 'a'); perform pg_temp.ch('Ann', run, 'a');
  assert pg_temp.vw('Ann')->'clock' = '{"left":1,"total":3}'::jsonb and pg_temp.node(run) = 's3', 'N7: al bivio resta una mossa';
  r := pg_temp.ch('Ann', run, 'w');
  assert r->>'status' = 'cleared' and pg_temp.endid(r) = 'eWin', 'N7: l’uscita a costo zero porta al finale';
  -- una via costosa (costo 3) all’inizio consuma tutto
  run := pg_temp.begin_('Ann', 901);
  r := pg_temp.ch('Ann', run, 'q');
  assert r->>'status' = 'failed' and pg_temp.endid(r) = 'eLate', 'N7: la via da 3 mosse esaurisce il tempo prima di arrivare';
  -- un percorso che finisce subito: le mosse restano
  run := pg_temp.begin_('Ann', 901);
  r := pg_temp.ch('Ann', run, 'w');
  assert r->>'status' = 'cleared', 'N7: la scorciatoia porta alla vittoria';
  insert into t_log (msg) values ('OK N7 — orologio: 3 mosse, ogni scelta (anche le azioni nella stanza) ne consuma una, costo personalizzabile, scadenza → finale in ritardo, mai se si va a un finale');
end $$;

-- N8 — lo stato dichiara le interazioni e non svela segreti; i dungeon di prima funzionano ancora
do $$
declare s jsonb; d jsonb; run uuid; r jsonb; v jsonb;
begin
  perform pg_temp.unlock('Ann', 55);
  d := pg_temp.dsel('Ann', 900);
  assert d->'inter' = '["chk","lock","stay","who","role"]'::jsonb and (d->>'forks')::int = 2 and (d->>'endings_total')::int = 8, 'N8: il dungeon 900 dichiara 5 interazioni, 2 bivi (scena + serratura), 8 finali';
  assert pg_temp.dsel('Ann', 901)->'inter' = '["stay","clock"]'::jsonb, 'N8: il dungeon 901 usa l’orologio (e una stanza a più azioni)';
  assert pg_temp.dsel('Ann', 30)->'inter' = '[]'::jsonb and pg_temp.dsel('Ann', 5)->'inter' = '[]'::jsonb and (pg_temp.dsel('Ann', 30)->>'forks')::int >= 3, 'N8: i dungeon di prima non dichiarano interazioni e hanno i loro bivi';
  assert pg_temp.dsel('Ann', 900)::text not like '%eLkOk%' and pg_temp.dsel('Ann', 900)::text not like '%code%', 'N8: lo stato non contiene il percorso';
  -- un dungeon a scelte di prima (30) si gioca con la chiamata a 2 argomenti, come il browser di prima
  run := pg_temp.begin_('Ann', 30);
  v := pg_temp.vw('Ann');
  assert v->'scene'->>'type' = 'scene' and jsonb_array_length(v->'scene'->'options') >= 2 and (v->'scene'->'options'->0->>'stay')::boolean = false and v->'clock' = 'null'::jsonb, 'N8: il dungeon 30 si vede come prima (nessuna azione speciale, nessun orologio)';
  r := pg_temp.ch('Ann', run, pg_temp.pick_to(run, 'eF%'));
  assert r->>'status' = 'failed' and r->'result'->'ending'->>'id' like 'eF%', 'N8: una scelta sbagliata del dungeon 30 porta al fallimento, come prima';
  -- il browser chiama con soli due parametri (il terzo è facoltativo)
  run := pg_temp.begin_('Ann', 30);
  assert pg_temp.err_auth('Ann', format('select public.game_dungeon_choose(p_run => %L, p_option => %L)', run, pg_temp.pick_to(run, 'eF%'))) is null, 'N8: la chiamata del browser con due parametri riesce';
  insert into t_log (msg) values ('OK N8 — 900 dichiara chk/lock/stay/who/role, 901 stay+orologio; i dungeon di prima restano identici, anche con la chiamata a 2 parametri');
end $$;

-- N9 — effetti (limiti di potenza, PV e orologio), scelte con indizio richiesto, costo oltre il tempo rimasto, scadenza per inattività
do $$
declare st jsonb; r jsonb; run uuid; ok boolean; msg text;
begin
  st := '{"pow":0,"flags":[],"members":[{"user_id":"u1","hp":50,"mx":100},{"user_id":"u2","hp":0,"mx":100}],"clk":2}'::jsonb;
  -- potenza: sempre tra −50% e +100%
  assert (public._game_dng_fx(public._game_dng_fx(st, '{"pow":80}'), '{"pow":80}')->>'pow')::int = 100, 'N9: potenza al massimo +100%';
  assert (public._game_dng_fx(public._game_dng_fx(st, '{"pow":-80}'), '{"pow":-80}')->>'pow')::int = -50, 'N9: potenza al minimo −50%';
  -- PV: un colpo non uccide (resta almeno 1), chi è già a terra non perde altro, una cura rialza chi era a terra, mai oltre il massimo
  r := public._game_dng_fx(st, '{"hp":-200}');
  assert (r->'members'->0->>'hp')::numeric = 1 and (r->'members'->1->>'hp')::numeric = 0, 'N9: −200% PV lascia 1 PV; chi è a terra resta a 0';
  r := public._game_dng_fx(st, '{"hp":30}');
  assert (r->'members'->0->>'hp')::numeric = 80 and (r->'members'->1->>'hp')::numeric = 30, 'N9: +30% cura e rialza chi era a terra';
  assert (public._game_dng_fx(st, '{"hp":100}')->'members'->0->>'hp')::numeric = 100, 'N9: i PV non superano il massimo';
  r := public._game_dng_fx(st, '{"hp":-10}', 'u1');
  assert (r->'members'->0->>'hp')::numeric = 40 and (r->'members'->1->>'hp')::numeric = 0, 'N9: l’effetto «solo lui» colpisce un solo eroe';
  r := public._game_dng_fx(public._game_dng_fx(st, '{"hp":-10}', 'u2'), '{"hp":-10}', 'nessuno');
  assert (r->'members'->0->>'hp')::numeric = 50, 'N9: un eroe inesistente non colpisce nessuno';
  -- orologio e indizi
  assert (public._game_dng_fx(st, '{"clk":-5}')->>'clk')::int = 0 and (public._game_dng_fx(st, '{"clk":3}')->>'clk')::int = 5, 'N9: l’orologio non scende sotto zero e può salire';
  assert not (public._game_dng_fx(st - 'clk', '{"clk":-1}') ? 'clk'), 'N9: senza orologio l’effetto sul tempo è ignorato';
  assert public._game_dng_fx(public._game_dng_fx(st, '{"flag":"x"}'), '{"flag":"x"}')->'flags' = '["x"]'::jsonb, 'N9: un indizio trovato due volte resta uno solo';
  assert public._game_dng_fx(st, null) = st and public._game_dng_fx(st, 'null'::jsonb) = st, 'N9: nessun effetto, nessun cambiamento';
  -- un dungeon con scelta che richiede l'indizio, costo oltre il tempo e scadenza
  insert into public.game_dungeons (no, name, emoji, lore, boss_name, boss_emoji, boss_lore, rooms, ref_level, min_level, bc, xp, diff, kind, item_id)
  values (902, 'Prova 902', '🧪', 'x', 'Capo 902', '👹', 'x', '[{"name":"Stanza","emoji":"🚪","boss":false},{"name":"Capo","emoji":"👹","boss":true}]'::jsonb, 10, 1, 100, 10, 0.01, 'path', null);
  insert into public.game_items (id, name, slot, tier, rarity, min_level, p_for, p_des, p_vig, p_spi, p_frt, xp_pct, extra_actions, descr, source, dungeon_no)
  values ('dt902', 'Oggetto di prova 902', 'weapon', 0, 'raro', 1, 1, 0, 0, 0, 0, 0, 0, 'prova', 'dungeon', 902);
  update public.game_dungeons set item_id = 'dt902' where no = 902;
  insert into public.game_dungeon_graphs (dungeon_no, graph) values (902, $j${"_start":"s1","_clock":2,"_late":"eLate","_latetxt":"Tempo scaduto.",
   "s1":{"t":"scene","n":"Sala","x":"x","o":[
     {"id":"r","l":"Serve l’indizio","req":["k1"],"to":"eWin"},
     {"id":"g","l":"Prendi l’indizio","fx":{"flag":"k1"},"to":"s1","cost":0},
     {"id":"big","l":"Costa cinque","cost":5,"to":"s2"},
     {"id":"e","l":"Esci","to":"eWin","cost":0}]},
   "s2":{"t":"scene","n":"Sala 2","x":"x","o":[{"id":"w","l":"Vai","to":"eWin"}]},
   "eWin":{"t":"end","win":true,"title":"Fine","x":"x","text":"x","m":100},
   "eLate":{"t":"end","win":false,"title":"In ritardo","x":"x","text":"x","m":100},
   "_flags":{"k1":"Indizio"}}$j$::jsonb);
  perform pg_temp.setting('game_dng_path_minutes', 120);
  update public.game_runs set status = 'failed', finished_at = now() where status in ('active', 'lobby'); update public.game_heroes set energy = 100, energy_at = now();
  run := pg_temp.begin_('Ann', 902);
  ok := false;
  begin perform pg_temp.ch('Ann', run, 'r'); ok := true; exception when others then msg := sqlerrm; end;
  assert not ok and msg like '%non è ancora disponibile%', 'N9: senza l’indizio la scelta non si può fare, nemmeno chiamando il server a mano';
  assert (pg_temp.opt(pg_temp.vw('Ann'), 'r')->>'locked')::boolean, 'N9: la scelta è mostrata bloccata';
  perform pg_temp.ch('Ann', run, 'g');
  assert pg_temp.vw('Ann')->'clock' = '{"left":2,"total":2}'::jsonb, 'N9: la scelta a costo zero non consuma tempo';
  r := pg_temp.ch('Ann', run, 'r');
  assert r->>'status' = 'cleared', 'N9: con l’indizio la scelta funziona';
  update public.game_heroes set energy = 100, energy_at = now();
  run := pg_temp.begin_('Ann', 902);
  r := pg_temp.ch('Ann', run, 'big');
  assert r->>'status' = 'failed' and (pg_temp.rst(run)->>'clk')::int = 0, 'N9: un costo più grande del tempo rimasto porta a zero, mai sotto';
  -- scadenza per inattività: dopo il tempo massimo la spedizione è fallita
  update public.game_heroes set energy = 100, energy_at = now();
  run := pg_temp.begin_('Ann', 902);
  update public.game_runs set last_move_at = now() - interval '10 hours' where id = run;
  r := pg_temp.ch('Ann', run, 'e');
  assert (r->>'expired')::boolean and r->>'status' = 'failed' and (select status from public.game_runs where id = run) = 'failed', 'N9: dopo troppo tempo senza scelte la spedizione fallisce';
  insert into t_log (msg) values ('OK N9 — effetti con limiti (potenza, PV, orologio, indizi doppi), scelta con indizio richiesto, costo oltre il tempo, scadenza per inattività');
end $$;

select msg as esito from t_log order by n;
rollback;
