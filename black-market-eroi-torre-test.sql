-- =====================================================================
-- TEST DELLA MIGRAZIONE 029 (La guerra degli Eroi: la Torre Infinita)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…028 (anche il pacchetto «unico» dei dungeon) e la 029 (black-market-eroi-torre.sql).
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

-- ---------- supporto per la Torre ----------
create function pg_temp.tst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_tower_state(); end $$;
create function pg_temp.climb(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_tower_climb(); end $$;
-- eroe di prova: livello, XP a zero, punti assegnati (bilanciati se f..r sono tutti uguali), energia piena, punti già assegnati
create function pg_temp.hero_(n text, l integer, f integer, d integer, v integer, s integer, r integer) returns void language sql as $$
  update public.game_heroes set level = l, xp = 0, a_for = f, a_des = d, a_vig = v, a_spi = s, a_frt = r, stats_set = true, energy = 100, energy_at = now() where user_id = pg_temp.uid(n) $$;
create function pg_temp.bal_(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.sure_win() returns void language sql as $$ update public.system_settings set value_int = 1 where key = 'game_tower_difficulty' $$;
create function pg_temp.sure_loss() returns void language sql as $$ update public.system_settings set value_int = 100000 where key = 'game_tower_difficulty' $$;
create function pg_temp.normal() returns void language sql as $$ update public.system_settings set value_int = 100 where key = 'game_tower_difficulty' $$;
create function pg_temp.fill(n text) returns void language sql as $$ update public.game_heroes set energy = 100, energy_at = now() where user_id = pg_temp.uid(n) $$;
create function pg_temp.best(n text) returns integer language sql as $$ select coalesce((select best_floor from public.game_tower where user_id = pg_temp.uid(n)), 0) $$;

do $$ declare n text; begin foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay'] loop perform public._game_ensure_hero(pg_temp.uid(n)); end loop; end $$;

-- T1 — catalogo: 12 boss, 60 reliquie ben formate
do $$
begin
  assert (select count(*) from public.game_tower_bosses) = 12 and (select count(distinct sprite) from public.game_tower_bosses) = 12, 'T1: 12 boss con 12 aspetti diversi';
  assert (select count(*) from public.game_tower_items) = 60 and (select count(*) from public.game_items where source = 'tower') = 60, 'T1: 60 reliquie, una ogni 10 piani fino al 600';
  assert (select bool_and(i.slot = (array['weapon','armor','helm','amulet','tool'])[((t.floor / 10) - 1) % 5 + 1]) from public.game_tower_items t join public.game_items i on i.id = t.item_id), 'T1: gli slot ruotano';
  assert (select bool_and((i.rarity = 'mitico') = (i.slot = 'tool')) from public.game_tower_items t join public.game_items i on i.id = t.item_id), 'T1: la reliquia ogni 5 è mitica, le altre no';
  assert (select bool_and(i.min_level = round(0.9 * t.floor)) from public.game_tower_items t join public.game_items i on i.id = t.item_id), 'T1: livello minimo = 0,9 × piano';
  assert (select count(distinct i.name) from public.game_items i where source = 'tower') = 60, 'T1: nomi tutti diversi';
  assert (select name from public.game_items where id = 'tw10') = 'Lama del Golem di Carta' and (select name from public.game_items where id = 'tw30') = 'Elmo della Strega delle Lanterne'
     and (select name from public.game_items where id = 'tw130') = 'Elmo del Golem di Carta Risvegliato' and (select name from public.game_items where id = 'tw600') = 'Reliquia dell’Arconte del Tempio Primordiale', 'T1: i nomi seguono il boss e il giro';
  assert (select p_des from public.game_items where id = 'tw600') between 150 and 215 and (select p_des from public.game_items where id = 'tw50') < (select p_des from public.game_items where id = 'tw600'), 'T1: i bonus crescono, senza superare i dungeon più alti';
  assert (select bool_and(xp_pct = 5 + t.floor / 20) from public.game_tower_items t join public.game_items i on i.id = t.item_id where i.slot = 'tool'), 'T1: bonus XP delle reliquie';
  assert (select max(p_for + p_des + p_vig + p_spi + p_frt) from public.game_items where source = 'tower') < 32000, 'T1: i bonus stanno nei limiti delle colonne';
  assert not exists (select 1 from public.game_items where source = 'tower' and (price_bc is not null or dungeon_no is not null or boss_no is not null)), 'T1: le reliquie non si comprano';
  insert into t_log (msg) values ('OK T1 — catalogo: 12 boss con aspetto diverso, 60 reliquie (slot a rotazione, una mitica ogni 5), nomi e potenza coerenti');
end $$;

-- T2 — i nemici: stessi per lo stesso piano, boss ogni 10, crescita continua, nomi dei giri, tratti
do $$
declare e jsonb; e2 jsonb; i integer; a numeric; b numeric; nn integer := 0; na integer := 0;
begin
  for i in 1..3000 loop
    e := public._game_tower_enemy(i);
    assert (e->>'boss')::boolean = (i % 10 = 0), format('T2: solo i piani multipli di 10 sono boss (%s)', i);
    assert e->>'name' <> '' and e->>'sprite' <> '' and (e->>'max_hp')::bigint >= 55 and (e->>'s_for')::bigint >= 1 and (e->>'level')::int = i, format('T2: nemico valido al piano %s', i);
    assert (e->>'boss')::boolean = (e->>'lore' is not null) and ((e->>'boss')::boolean = false or e->'affix' = 'null'::jsonb), format('T2: i boss hanno storia e nessun tratto (%s)', i);
    if not (e->>'boss')::boolean then
      nn := nn + 1; if e->'affix' <> 'null'::jsonb then na := na + 1; assert e->'affix'->>'key' in ('corazzato','furioso','veloce','mistico','anziano','fragile'), 'T2: tratti noti'; end if;
    end if;
  end loop;
  assert public._game_tower_enemy(77) = public._game_tower_enemy(77) and public._game_tower_enemy(10)->>'name' = 'Golem di Carta' and public._game_tower_enemy(120)->>'name' = 'Arconte del Tempio'
     and public._game_tower_enemy(130)->>'name' = 'Golem di Carta Risvegliato' and public._game_tower_enemy(150)->>'name' = 'Strega delle Lanterne Risvegliata'
     and public._game_tower_enemy(250)->>'name' = 'Kraken Notturno Ancestrale' and public._game_tower_enemy(600)->>'name' = 'Arconte del Tempio Primordiale'
     and public._game_tower_enemy(990)->>'name' like '% Supremo%' or public._game_tower_enemy(990)->>'name' like '% Suprema%', 'T2: stesso piano = stesso nemico; boss e giri con il nome giusto';
  assert na::numeric / nn between 0.5 and 0.7, format('T2: circa il 60%% dei piani normali ha un tratto (%s su %s)', na, nn);
  -- potenza (forza × punti vita) crescente per decina di piani
  for i in 0..28 loop
    select avg((x->>'s_for')::numeric * (x->>'max_hp')::numeric) into a from (select public._game_tower_enemy(g) x from generate_series(i * 100 + 1, i * 100 + 100) g) q;
    select avg((x->>'s_for')::numeric * (x->>'max_hp')::numeric) into b from (select public._game_tower_enemy(g) x from generate_series(i * 100 + 101, i * 100 + 200) g) q;
    assert b > a * 1.1, format('T2: la potenza media sale tra i piani %s-%s e quelli dopo', i * 100 + 1, i * 100 + 100);
  end loop;
  -- il nemico dei piani 1-9 è più debole di un livello normale; dal 10 a livello pieno
  assert (public._game_tower_enemy(1)->>'max_hp')::int < (public._game_tower_enemy(10)->>'max_hp')::int and (select count(distinct (public._game_tower_enemy(g))->>'sprite') from generate_series(1, 200) g) >= 20, 'T2: tanti aspetti diversi lungo la salita';
  assert (select count(distinct public._game_tower_enemy(g)->>'name') from generate_series(1, 400) g) >= 60, 'T2: i nomi non si ripetono troppo';
  insert into t_log (msg) values (format('OK T2 — 3000 piani: stesso nemico per lo stesso piano, boss ogni 10 con i giri («Risvegliato», «Ancestrale»…), %s%% dei piani normali con un tratto, potenza sempre crescente', round(100.0 * na / nn)));
end $$;

-- T3 — la stima di vittoria è onesta: eroi di vari livelli e build contro piani facili/difficili, e rispetto a combattimenti veri
do $$
declare l integer; prof text; ca jsonb; ch integer; wins integer; k integer; n integer := 0; e jsonb; w numeric[]; sim jsonb; f integer;
begin
  for l in select unnest(array[5, 30, 100, 300, 600]) loop
    for prof in select unnest(array['bil', 'fv', 'vetro', 'tank']) loop
      w := case prof when 'bil' then array[.2,.2,.2,.2,.2] when 'fv' then array[.4,.2,.4,0,0] when 'vetro' then array[.5,.3,.2,0,0] else array[.2,.1,.4,.1,.2] end;
      perform pg_temp.hero_('Bob', l, round((20 + 3 * (l - 1)) * w[1])::int, round((20 + 3 * (l - 1)) * w[2])::int, round((20 + 3 * (l - 1)) * w[3])::int, round((20 + 3 * (l - 1)) * w[4])::int, round((20 + 3 * (l - 1)) * w[5])::int);
      select to_jsonb(x) into ca from public._game_calc(pg_temp.uid('Bob')) x;
      f := greatest(1, round(l * 0.5));                  -- molto sotto il proprio livello: quasi sicura
      ch := (public._game_tower_card(ca, f)->>'chance')::int;
      assert ch >= 90, format('T3: livello %s %s al piano %s dovrebbe essere facile (stima %s%%)', l, prof, f, ch);
      f := round(l * 1.8);                                -- molto sopra: quasi persa
      ch := (public._game_tower_card(ca, f)->>'chance')::int;
      assert ch <= 10, format('T3: livello %s %s al piano %s dovrebbe essere proibitivo (stima %s%%)', l, prof, f, ch);
      n := n + 1;
    end loop;
  end loop;
  -- stima contro la realtà: 80 combattimenti veri per due situazioni sicure e due incerte
  perform pg_temp.hero_('Bob', 100, 12 * 3 + 20, 60, 120, 40, 60);
  select to_jsonb(x) into ca from public._game_calc(pg_temp.uid('Bob')) x;
  for f in select unnest(array[40, 70, 95, 130, 200]) loop
    e := public._game_tower_enemy(f); wins := 0;
    for k in 1..120 loop if public._game_sim(ca, e)->>'winner' = 'a' then wins := wins + 1; end if; end loop;
    ch := (public._game_tower_card(ca, f)->>'chance')::int;
    assert abs(wins * 100.0 / 120 - ch) <= 28, format('T3: al piano %s la stima (%s%%) è lontana dalla realtà (%s%%)', f, ch, round(wins * 100.0 / 120));
  end loop;
  assert (select bool_and((public._game_tower_card(ca, g)->>'chance')::int >= (public._game_tower_card(ca, g + 40)->>'chance')::int) from generate_series(1, 400, 7) g), 'T3: più in alto = mai più facile';
  insert into t_log (msg) values (format('OK T3 — stima di vittoria: %s eroi (livelli 5–600, 4 build) facili a metà del loro livello e proibitivi a 1,8×; vicina ai combattimenti veri', n));
end $$;

-- T4 — stato per un eroe nuovo; senza punti assegnati non si sale
do $$
declare s jsonb;
begin
  s := pg_temp.tst('Ann');
  assert (s->>'best_floor')::int = 0 and (s->>'next_floor')::int = 1 and (s->>'cost')::int = 6 and (s->>'stats_set')::boolean = false and s->'rank' = 'null'::jsonb, 'T4: stato iniziale';
  assert (s->'enemy'->>'floor')::int = 1 and jsonb_array_length(s->'upcoming') = 4 and (s->'upcoming'->0->>'floor')::int = 2 and (s->>'boss_floor')::int = 10 and (s->>'boss_in')::int = 10 and (s->'boss'->>'floor')::int = 10, 'T4: prossimo piano, anteprima dei 4 successivi e boss atteso';
  assert s->'enemy'->'reward'->>'bc' = '24' and s->'enemy'->'reward'->>'xp' = '63' and s->'boss'->'reward'->>'bc' is not null, 'T4: i premi si vedono prima';
  assert (s->'enemy' ? 's_for') and not (s->'upcoming'->0 ? 'reward') and jsonb_array_length(s->'top') = 0 and jsonb_array_length(s->'hall') = 0 and jsonb_array_length(s->'recent') = 0, 'T4: classifica, albo e cronologia vuoti';
  assert pg_temp.err_as('Ann', 'select public.game_tower_climb()') like '%assegna i tuoi punti%', 'T4: senza punti assegnati non si sale';
  assert pg_temp.err_auth('Ann', 'select * from public.game_tower') is not null and pg_temp.err_auth('Ann', 'select * from public.game_tower_fights') is not null
     and pg_temp.err_auth('Ann', 'select * from public.game_tower_firsts') is not null and pg_temp.err_auth('Ann', 'select * from public.game_tower_bosses') is not null
     and pg_temp.err_auth('Ann', 'select * from public.game_tower_items') is not null, 'T4: le tabelle della Torre sono chiuse al browser';
  assert pg_temp.err_auth('Ann', 'insert into public.game_tower (user_id, best_floor) values (''' || pg_temp.uid('Ann') || ''', 500)') is not null
     and pg_temp.err_auth('Ann', 'select public._game_tower_enemy(5)') is not null and pg_temp.err_auth('Ann', 'select public._game_tower_reward(5)') is not null, 'T4: niente scrittura diretta né funzioni interne dal browser';
  assert pg_temp.err('select set_config(''request.jwt.claims'', ''{"role":"anon"}'', true)') is null
     and pg_temp.err('set local role anon') is null and pg_temp.err('select public.game_tower_state()') is not null, 'T4: da anonimi non si entra';
  reset role;
  insert into t_log (msg) values ('OK T4 — eroe nuovo: piano 1, anteprima, premi visibili; senza punti non si sale; tabelle e funzioni interne chiuse al browser');
end $$;

-- T5 — sconfitta: si resta al piano, costa energia, nessun premio
do $$
declare r jsonb; b0 integer; t0 bigint;
begin
  perform pg_temp.hero_('Ann', 20, 20, 20, 20, 20, 20); perform pg_temp.sure_loss();
  b0 := pg_temp.bal_('Ann'); t0 := pg_temp.tot();
  r := pg_temp.climb('Ann');
  assert (r->>'won')::boolean = false and (r->>'floor')::int = 1 and (r->>'next_floor')::int = 1 and (r->>'best_floor')::int = 0 and (r->>'bc')::int = 0 and (r->>'xp')::int = 0 and r->'item' = 'null'::jsonb, 'T5: sconfitta senza premi';
  assert jsonb_array_length(r->'log') >= 1 and (r->>'energy_cost')::int = 6 and r->'enemy'->>'name' <> '' and not (r->'enemy' ? 's_for'), 'T5: la cronaca c’è, l’energia costa 6, il nemico è descritto senza numeri interni';
  assert round(pg_temp.en('Ann')) = 94 and pg_temp.bal_('Ann') = b0 and pg_temp.tot() = t0, 'T5: energia −6, nessun BC';
  assert (select losses from public.game_tower where user_id = pg_temp.uid('Ann')) = 1 and (select wins from public.game_tower where user_id = pg_temp.uid('Ann')) = 0
     and (select count(*) from public.game_tower_fights where user_id = pg_temp.uid('Ann') and not won) = 1, 'T5: contatori e cronologia';
  assert (select count(*) from public.ledger_entries where ref_type = 'game_tower') = 0, 'T5: nessuna riga di registro';
  r := pg_temp.climb('Ann');
  assert (r->>'floor')::int = 1 and round(pg_temp.en('Ann')) = 88, 'T5: si riprova sullo stesso piano';
  insert into t_log (msg) values ('OK T5 — sconfitta: stesso piano, energia −6 a tentativo, nessun BC/XP/oggetto, cronologia registrata');
end $$;

-- T6 — vittorie: premi esatti, una volta sola, registro corretto, fino al boss del piano 10 con la reliquia
do $$
declare r jsonb; b0 integer; t0 bigint; i integer; xp0 bigint; l0 integer;
begin
  perform pg_temp.hero_('Ann', 30, 30, 30, 30, 30, 30); perform pg_temp.sure_win(); perform pg_temp.fill('Ann');
  b0 := pg_temp.bal_('Ann'); t0 := pg_temp.tot();
  r := pg_temp.climb('Ann');
  assert (r->>'won')::boolean and (r->>'floor')::int = 1 and (r->>'next_floor')::int = 2 and (r->>'best_floor')::int = 1 and (r->>'bc')::int = 24 and (r->>'xp')::int = 63, 'T6: piano 1 = 24 BC e 63 XP';
  assert pg_temp.bal_('Ann') = b0 + 24 and pg_temp.tot() = t0 + 24 and round(pg_temp.en('Ann')) = 94, 'T6: portafoglio +24, energia −6';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Ann') and kind = 'game_dungeon_reward' and ref_type = 'game_tower' and amount = 24 and idempotency_key = 'gametower:' || pg_temp.uid('Ann') || ':1') = 1, 'T6: una riga di registro con chiave unica';
  for i in 2..9 loop
    r := pg_temp.climb('Ann');
    assert (r->>'won')::boolean and (r->>'floor')::int = i and (r->>'bc')::int = 20 + 4 * i and (r->>'xp')::int = 60 + 3 * i and r->'item' = 'null'::jsonb and (r->>'first_global')::boolean = false, format('T6: piano %s', i);
    perform pg_temp.fill('Ann');
  end loop;
  assert (pg_temp.tst('Ann')->'enemy'->>'boss')::boolean and (pg_temp.tst('Ann')->>'next_floor')::int = 10 and pg_temp.tst('Ann')->'boss' = 'null'::jsonb, 'T6: ora il prossimo è il boss e non c’è un altro boss annunciato';
  r := pg_temp.climb('Ann');
  assert (r->>'won')::boolean and (r->>'floor')::int = 10 and (r->>'bc')::int = 300 and (r->>'xp')::int = 270 and (r->>'first_global')::boolean and r->'item'->>'id' = 'tw10' and r->'enemy'->>'name' = 'Golem di Carta', 'T6: boss del 10 = 300 BC, 270 XP, la prima conquista e la reliquia';
  assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Ann') and item_id = 'tw10' and source = 'tower') and (select best_floor from public.game_tower where user_id = pg_temp.uid('Ann')) = 10, 'T6: reliquia nello zaino e piano 10 raggiunto';
  assert (select count(*) from public.ledger_entries where ref_type = 'game_tower' and user_id = pg_temp.uid('Ann')) = 10 and (select sum(amount) from public.ledger_entries where ref_type = 'game_tower') = 24 + (select sum(20 + 4 * g) from generate_series(2, 9) g) + 300, 'T6: 10 righe di registro, importi esatti';
  assert (select user_id from public.game_tower_firsts where floor = 10) = pg_temp.uid('Ann') and (select wins from public.game_tower where user_id = pg_temp.uid('Ann')) = 10, 'T6: albo della prima conquista e vittorie';
  -- il piano non si può rigiocare: il successivo è l'11
  r := pg_temp.climb('Ann');
  assert (r->>'floor')::int = 11 and (select count(*) from public.ledger_entries where idempotency_key = 'gametower:' || pg_temp.uid('Ann') || ':10') = 1, 'T6: nessun piano si ripete';
  -- gli XP passano dal solito calcolo (anche i bonus % degli oggetti) e possono far salire di livello
  assert (select level from public.game_heroes where user_id = pg_temp.uid('Ann')) >= 30 and (select total_xp from public.game_heroes where user_id = pg_temp.uid('Ann')) >= 63 + 270, 'T6: l’XP arriva all’eroe';
  insert into t_log (msg) values ('OK T6 — vittorie: BC e XP esatti (24/63 al piano 1, 300/270 al boss 10), registro unico per piano, reliquia e prima conquista, nessun piano si ripete');
end $$;

-- T7 — energia, ricarica al livello (solo sotto il 100), impostazioni dei premi
do $$
declare r jsonb; e0 numeric;
begin
  perform pg_temp.sure_win();
  -- energia insufficiente
  perform pg_temp.hero_('Bob', 20, 20, 20, 20, 20, 20); update public.game_heroes set energy = 5, energy_at = now() where user_id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Bob', 'select public.game_tower_climb()') like '%Energia insufficiente%', 'T7: con meno di 6 di energia non si sale';
  update public.game_heroes set energy = 6, energy_at = now() where user_id = pg_temp.uid('Bob');
  r := pg_temp.climb('Bob');
  assert (r->>'won')::boolean and round(pg_temp.en('Bob')) = 0, 'T7: con esattamente 6 si sale e resta 0';
  -- sotto il livello 100 salire di livello ricarica l'energia
  perform pg_temp.hero_('Cid', 50, 20, 20, 20, 20, 20); update public.game_heroes set xp = public._game_xp_need(50) - 1, energy = 30, energy_at = now() where user_id = pg_temp.uid('Cid');
  r := pg_temp.climb('Cid');
  assert (r->>'levels')::int >= 1 and (r->>'energy_full')::boolean and round(pg_temp.en('Cid')) = 100 and (r->>'level')::int = 51, 'T7: livello 50 → 51 ricarica l’energia';
  -- dal livello 100 non c'è più ricarica
  perform pg_temp.hero_('Dan', 150, 50, 50, 50, 50, 50); update public.game_heroes set xp = public._game_xp_need(150) - 1, energy = 30, energy_at = now() where user_id = pg_temp.uid('Dan');
  r := pg_temp.climb('Dan');
  assert (r->>'levels')::int >= 1 and not (r->>'energy_full')::boolean and round(pg_temp.en('Dan')) = 24, 'T7: dal livello 100 niente ricarica';
  -- impostazioni
  update public.system_settings set value_int = 200 where key = 'game_tower_bc_pct'; update public.system_settings set value_int = 50 where key = 'game_tower_xp_pct'; update public.system_settings set value_int = 10 where key = 'game_tower_energy';
  perform pg_temp.fill('Bob');
  r := pg_temp.climb('Bob');
  assert (r->>'floor')::int = 2 and (r->>'bc')::int = 56 and (r->>'xp')::int = 33 and (r->>'energy_cost')::int = 10 and round(pg_temp.en('Bob')) = 90, 'T7: percentuali e costo in energia regolabili (BC ×2, XP ×0,5, costo 10)';
  update public.system_settings set value_int = 100 where key in ('game_tower_bc_pct', 'game_tower_xp_pct'); update public.system_settings set value_int = 6 where key = 'game_tower_energy';
  insert into t_log (msg) values ('OK T7 — energia: serve il costo pieno, ricarica al livello solo sotto il 100, BC/XP/costo regolabili dall’admin');
end $$;

-- T8 — albo e classifica: la prima conquista è di uno solo, la classifica ordina per piano e poi per chi c’è arrivato prima
do $$
declare r jsonb; s jsonb; i integer;
begin
  perform pg_temp.sure_win();
  perform pg_temp.hero_('Eve', 40, 30, 30, 30, 30, 30); perform pg_temp.hero_('Fay', 40, 30, 30, 30, 30, 30);
  for i in 1..10 loop perform pg_temp.fill('Eve'); r := pg_temp.climb('Eve'); end loop;
  assert (r->>'floor')::int = 10 and (r->>'first_global')::boolean = false and r->'item'->>'id' = 'tw10', 'T8: Eve arriva al boss 10 dopo Ann: ha la reliquia ma non la prima conquista';
  for i in 1..3 loop perform pg_temp.fill('Fay'); r := pg_temp.climb('Fay'); end loop;
  s := pg_temp.tst('Fay');
  assert (s->>'best_floor')::int = 3 and (s->>'next_floor')::int = 4 and (s->>'boss_in')::int = 7, 'T8: Fay al piano 3, boss tra 7';
  assert (select count(*) from public.game_tower_firsts) = 1 and (s->'hall'->0->>'floor')::int = 10 and s->'hall'->0->>'nickname' = 'Ann' and s->'hall'->0->>'boss' = 'Golem di Carta', 'T8: albo con un solo nome per piano';
  assert (s->'top'->0->>'nickname') = 'Ann' and (s->'top'->0->>'best_floor')::int = 11 and (s->'top'->1->>'nickname') = 'Eve' and (s->'top'->1->>'best_floor')::int = 10, 'T8: classifica per piano (Ann 11, Eve 10)';
  assert (s->>'rank')::int = (select count(*) from jsonb_array_elements(s->'top') x where (x->>'best_floor')::int > 3) + 1, 'T8: il mio posto è coerente con la classifica';
  update public.profiles set suspended = true where id = pg_temp.uid('Ann');
  s := pg_temp.tst('Fay');
  assert not exists (select 1 from jsonb_array_elements(s->'top') x where x->>'nickname' = 'Ann'), 'T8: gli eroi sospesi non sono in classifica';
  update public.profiles set suspended = false where id = pg_temp.uid('Ann');
  assert pg_temp.err_auth('Fay', 'select * from public.game_tower') like '%permission denied%', 'T8: la tabella resta illeggibile anche per la classifica';
  insert into t_log (msg) values ('OK T8 — albo (una sola prima conquista a piano), classifica per piano e anzianità, sospesi esclusi');
end $$;

-- T9 — difficoltà regolabile e cronologia
do $$
declare e1 jsonb; e2 jsonb; s jsonb;
begin
  perform pg_temp.normal();
  e1 := public._game_tower_enemy(200);
  update public.system_settings set value_int = 200 where key = 'game_tower_difficulty';
  e2 := public._game_tower_enemy(200);
  update public.system_settings set value_int = 100 where key = 'game_tower_difficulty';
  assert abs((e2->>'s_for')::numeric / (e1->>'s_for')::numeric - 2) < 0.02 and abs((e2->>'max_hp')::numeric / (e1->>'max_hp')::numeric - 2) < 0.05, 'T9: difficoltà 200% = statistiche doppie';
  s := pg_temp.tst('Ann');
  assert jsonb_array_length(s->'recent') = 8 and (s->'recent'->0->>'at') >= (s->'recent'->7->>'at') and (s->'recent'->0->>'floor')::int = 11, 'T9: cronologia degli ultimi 8 tentativi, dal più recente';
  insert into t_log (msg) values ('OK T9 — difficoltà e cronologia');
end $$;

-- T10 — modulo spento e accesso
do $$
begin
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_tower_state()') like '%Modulo non attivo%' and pg_temp.err_as('Ann', 'select public.game_tower_climb()') like '%Modulo non attivo%', 'T10: a modulo spento la Torre è chiusa';
  perform pg_temp.mod(true);
  assert (pg_temp.tst('Ann')->>'best_floor')::int = 11, 'T10: riaccesa, i progressi ci sono';
  insert into t_log (msg) values ('OK T10 — modulo spento: la Torre si chiude e i progressi restano');
end $$;

-- T11 — nulla dal nulla: il registro è la somma esatta dei premi; nessuna riga doppia; saldo mai negativo
do $$
begin
  assert (select count(*) from public.ledger_entries where ref_type = 'game_tower') = (select count(distinct idempotency_key) from public.ledger_entries where ref_type = 'game_tower'), 'T11: chiavi uniche';
  assert not exists (select 1 from public.ledger_entries where ref_type = 'game_tower'
                       and amount not in ((public._game_tower_reward(split_part(idempotency_key, ':', 3)::int)->>'bc')::bigint, 2 * (public._game_tower_reward(split_part(idempotency_key, ':', 3)::int)->>'bc')::bigint)), 'T11: ogni pagamento è esattamente il premio del suo piano (o il doppio, nella prova con BC al 200%)';
  assert (select count(*) from public.ledger_entries where ref_type = 'game_tower') = (select sum(wins) from public.game_tower), 'T11: una riga di registro per ogni vittoria';
  assert (select count(*) from public.game_tower_fights where won) = (select sum(wins) from public.game_tower), 'T11: vittorie in cronologia = vittorie contate';
  assert not exists (select 1 from public.wallets where balance < 0), 'T11: nessun saldo negativo';
  insert into t_log (msg) values ('OK T11 — registro coerente con i piani vinti, nessun doppio pagamento');
end $$;

select msg as esito from t_log order by n;
rollback;
