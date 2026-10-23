-- =====================================================================
-- TEST DELLA MIGRAZIONE 027 (Boss del giorno: attacco libero e rappresaglia vera)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…027 (black-market-setup.sql … black-market-eroi-boss-attacco.sql).
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



create function pg_temp.lvl2(n text, l integer) returns void language sql as $$ update public.game_heroes set level = l, xp = 0 where user_id = pg_temp.uid(n) $$;
-- ---------- supporto per il boss ----------
create function pg_temp.ba(n text, a text, t text default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_boss_act(a, case when t is null then null else pg_temp.uid(t) end); end $$;
create function pg_temp.bjoin(n text, p_lobby bigint default null) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_join(p_lobby); end $$;
create function pg_temp.bstart(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_start(); end $$;
create function pg_temp.dh(n text) returns public.game_day_heroes language sql as $$ select * from public.game_day_heroes where user_id = pg_temp.uid(n) and day = public._game_today() $$;
create function pg_temp.lob(n text) returns public.game_lobbies language sql as $$ select l.* from public.game_lobbies l join public.game_day_heroes x on x.lobby_id = l.id where x.user_id = pg_temp.uid(n) and x.day = public._game_today() $$;
create function pg_temp.exp_hp(p_no integer, p_cycle integer, uids uuid[]) returns bigint language plpgsql as $$
declare s numeric := 0; u uuid; c record; bo public.game_bosses%rowtype;
begin
  select * into bo from public.game_bosses where no = p_no;
  foreach u in array uids loop select * into c from public._game_calc(u);
    s := s + c.s_for * 3 * least(1.0, (0.25 + 0.5 * (bo.coverage - 0.3) / 0.95) * (1 + 0.25 * p_cycle)) / (bo.retal * (1 + 0.1 * p_cycle)); end loop;
  return greatest(50, ceil(s * public._setting('game_boss_difficulty') / 100.0))::bigint;
end $$;

do $$
declare n text;
begin
  perform pg_temp.mod(true);
  perform pg_temp.setting('game_boss_min_players', 1);
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop
    perform pg_temp.st(n); perform pg_temp.setst(n, 10, 4, 4, 2, 0); perform pg_temp.lvl2(n, 50);
  end loop;
  insert into t_log (msg) values ('OK Preparazione: 8 eroi di livello 50');
end $$;

-- B1 — le funzioni ci sono e i permessi sono rimasti
do $$
begin
  assert has_function_privilege('authenticated', 'public.game_boss_act(text, uuid)', 'execute') and not has_function_privilege('anon', 'public.game_boss_act(text, uuid)', 'execute'), 'B1: act solo da autenticati';
  assert has_function_privilege('authenticated', 'public.game_boss_start()', 'execute') and not has_function_privilege('anon', 'public.game_boss_start()', 'execute'), 'B1: start solo da autenticati';
  insert into t_log (msg) values ('OK B1 — permessi invariati');
end $$;

-- B2 — l'attacco non consuma azioni; difendi/cura/studia sì; il boss colpisce davvero fino a mandarti KO
do $$
declare r jsonb; l bigint; i integer; hp0 bigint; k integer := 0; n_att integer := 0; lost numeric;
begin
  perform pg_temp.setting('game_boss_difficulty', 100000);                        -- boss enorme: non muore durante la prova
  r := pg_temp.bjoin('Ann'); l := (pg_temp.lob('Ann')).id;
  perform pg_temp.bjoin('Bob', l); perform pg_temp.bjoin('Cid', l);
  perform pg_temp.bstart('Ann');
  assert (pg_temp.lob('Ann')).max_hp > 1000000 and (pg_temp.dh('Ann')).actions_used = 0, 'B2: lobby partita, nessuna azione usata';
  hp0 := (pg_temp.dh('Ann')).max_hp;
  -- 5 attacchi: nessuna azione consumata
  for i in 1..5 loop r := pg_temp.ba('Ann', 'attack'); end loop;
  assert (pg_temp.dh('Ann')).actions_used = 0 and (r->>'actions_left')::int = 3, 'B2: cinque attacchi, tre azioni ancora disponibili';
  assert (pg_temp.dh('Ann')).dmg > 0 and (pg_temp.dh('Ann')).hp < hp0, 'B2: il boss ha reagito: Ann ha perso PV';
  -- le altre azioni sì
  r := pg_temp.ba('Bob', 'guard'); assert (r->>'actions_left')::int = 2 and (pg_temp.dh('Bob')).actions_used = 1, 'B2: difendi consuma un''azione';
  r := pg_temp.ba('Bob', 'study'); assert (r->>'actions_left')::int = 1, 'B2: studia consuma un''azione';
  update public.game_day_heroes set hp = hp - 1 where user_id = pg_temp.uid('Cid') and day = public._game_today();
  r := pg_temp.ba('Bob', 'heal', 'Cid'); assert (r->>'actions_left')::int = 0, 'B2: cura consuma un''azione';
  assert pg_temp.err_as('Bob', 'select public.game_boss_act(''guard'')') like 'Hai usato tutte le azioni di oggi (difendi, cura, studia)%', 'B2: finite le azioni di supporto, difendi è rifiutato';
  assert pg_temp.err_as('Bob', 'select public.game_boss_act(''study'')') like 'Hai usato tutte le azioni di oggi%', 'B2: anche studia';
  assert (pg_temp.ba('Bob', 'attack')->>'actions_left')::int = 0 and (pg_temp.dh('Bob')).actions_used = 3, 'B2: ma Bob può ancora attaccare, senza toccare il contatore';
  -- Ann attacca finché non cade: servono circa 1/rappresaglia (10) attacchi, non 3
  perform pg_temp.lvl2('Ann', 50);
  update public.game_day_heroes set hp = max_hp where user_id = pg_temp.uid('Ann') and day = public._game_today(); n_att := 0;
  loop
    exit when (pg_temp.dh('Ann')).hp <= 0 or n_att > 60;
    perform pg_temp.ba('Ann', 'attack'); n_att := n_att + 1;
  end loop;
  assert (pg_temp.dh('Ann')).hp = 0 and n_att between 5 and 30, 'B2: Ann va KO dopo ' || n_att || ' attacchi (attesi ~10)';
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like 'Sei esausto%', 'B2: da KO non si attacca';
  assert (pg_temp.dh('Ann')).actions_used = 0, 'B2: Ann non ha mai speso azioni';
  r := pg_temp.ba('Cid', 'heal', 'Ann');
  assert (pg_temp.dh('Ann')).hp > 0 and r->>'note' = 'rianimato', 'B2: un alleato la rianima con una cura';
  perform pg_temp.ba('Ann', 'attack');
  assert (select count(*) from public.game_day_log where action = 'attack') > 10, 'B2: gli attacchi sono nel registro del boss';
  perform pg_temp.setting('game_boss_difficulty', 100);
  insert into t_log (msg) values ('OK B2 — attacco libero e senza contatore; difendi/cura/studia limitati a 3; il boss ti manda KO dopo ~' || n_att || ' attacchi; cura = rianimazione');
end $$;

-- B3 — i PV del boss seguono la nuova formula (boss 1 e boss 10 al secondo giro)
do $$
declare l bigint; e bigint; r jsonb;
begin
  -- Dan, solo, contro il boss 10 al giro 2
  update public.game_days set boss_no = 10, cycle = 1 where day = public._game_today();
  perform pg_temp.bjoin('Dan'); r := pg_temp.bstart('Dan');
  e := pg_temp.exp_hp(10, 1, array[pg_temp.uid('Dan')]);
  assert (pg_temp.lob('Dan')).max_hp = e, 'B3: PV boss 10 giro 2 = ' || e || ' (trovati ' || (pg_temp.lob('Dan')).max_hp || ')';
  assert e < 20 * (select s_for * 3 from public._game_calc(pg_temp.uid('Dan'))), 'B3: pochi attacchi bastano ma costano molti PV';
  -- difficoltà dimezzata = PV dimezzati (stessa formula, un altro eroe)
  perform pg_temp.setting('game_boss_difficulty', 50);
  update public.game_days set boss_no = 1, cycle = 0 where day = public._game_today();
  perform pg_temp.bjoin('Eve'); perform pg_temp.bstart('Eve');
  assert (pg_temp.lob('Eve')).max_hp = pg_temp.exp_hp(1, 0, array[pg_temp.uid('Eve')]), 'B3: PV boss 1 a difficoltà 50%';
  perform pg_temp.setting('game_boss_difficulty', 100);
  assert (select count(*) from public.game_bosses) = 10 and (select min(coverage) from public.game_bosses) < (select max(coverage) from public.game_bosses), 'B3: la tabella dei boss è intatta';
  -- la difficoltà cresce: il boss 10 «costa» più PV in proporzione del boss 1 (stesso eroe)
  assert (select ((0.25 + 0.5 * (b.coverage - 0.3) / 0.95)) from public.game_bosses b where no = 10) > (select ((0.25 + 0.5 * (b.coverage - 0.3) / 0.95)) from public.game_bosses b where no = 1), 'B3: quota di PV da togliere crescente';
  insert into t_log (msg) values ('OK B3 — PV del boss: formula nuova (boss 10 giro 2, manopola della difficoltà)');
end $$;

-- B4 — una squadra che attacca e basta batte il boss 1, perdendo una quota ragionevole di PV, e tutti prendono i premi
do $$
declare l bigint; i integer; n text; guard integer := 0; lost numeric; mx numeric; r jsonb; hpl numeric; w integer;
begin
  update public.game_days set boss_no = 1, cycle = 0 where day = public._game_today();
  perform pg_temp.bjoin('Fay'); l := (pg_temp.lob('Fay')).id; perform pg_temp.bjoin('Gus', l); perform pg_temp.bjoin('Hal', l);
  perform pg_temp.bstart('Fay');
  assert (pg_temp.lob('Fay')).max_hp = pg_temp.exp_hp(1, 0, array[pg_temp.uid('Fay'), pg_temp.uid('Gus'), pg_temp.uid('Hal')]), 'B4: PV come da formula';
  while (pg_temp.lob('Fay')).status = 'open' and guard < 200 loop
    foreach n in array array['Fay','Gus','Hal'] loop
      exit when (pg_temp.lob('Fay')).status <> 'open';
      if (pg_temp.dh(n)).hp > 0 then perform pg_temp.ba(n, 'attack'); guard := guard + 1; end if;
    end loop;
  end loop;
  assert (pg_temp.lob('Fay')).status = 'defeated', 'B4: boss battuto dopo ' || guard || ' attacchi totali';
  assert guard between 4 and 60, 'B4: numero di attacchi ragionevole (' || guard || ')';
  select avg(1 - hp::numeric / max_hp) into lost from public.game_day_heroes where lobby_id = (pg_temp.lob('Fay')).id;
  assert lost between 0.03 and 0.7, 'B4: quota media di PV persa ' || round(lost, 3) || ' (attesa ~0.25)';
  assert (select count(*) from public.game_rewards where day = public._game_today() and user_id in (pg_temp.uid('Fay'), pg_temp.uid('Gus'), pg_temp.uid('Hal'))) = 3, 'B4: premi a tutti e tre';
  assert (select count(*) from public.ledger_entries where kind = 'game_boss_reward' and ref_id is null or kind = 'game_boss_reward') >= 3, 'B4: BC registrati';
  assert pg_temp.err_as('Fay', 'select public.game_boss_act(''attack'')') like 'Hai già sconfitto il boss di oggi%', 'B4: dopo la vittoria non si attacca più';
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'B4: saldi = registro';
  insert into t_log (msg) values ('OK B4 — squadra di 3 solo con attacchi: boss battuto in ' || guard || ' attacchi, PV persi in media ' || round(100 * lost) || '%, premi a tutti');
end $$;

-- B5 — chi non è in lobby, e il modulo spento
do $$
begin
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''attack'')') like 'Modulo non attivo%', 'B5: modulo spento: nessun attacco';
  perform pg_temp.mod(true);
  assert pg_temp.err_as('Ann', 'select public.game_boss_act(''zzz'')') = 'Azione non valida', 'B5: azione sconosciuta';
  insert into t_log (msg) values ('OK B5 — modulo spento e azioni non valide rifiutati');
end $$;

select msg as esito from t_log order by n;
rollback;
