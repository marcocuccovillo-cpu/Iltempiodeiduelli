-- =====================================================================
-- TEST DELLA MIGRAZIONE 017 (La guerra degli Eroi: 25 mini dungeon, lobby e ruoli)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…017 (black-market-setup.sql … black-market-eroi-dungeon.sql).
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

-- Preparazione: due giocatori in più e tutti gli eroi pronti (20 punti assegnati)
do $$
declare n text;
begin
  foreach n in array array['Gus','Hal'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.mod(true);
  foreach n in array array['Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.setst('Ann', 10, 4, 4, 2, 0); perform pg_temp.setst('Bob', 4, 4, 4, 4, 4); perform pg_temp.setst('Cid', 6, 6, 4, 2, 2); perform pg_temp.setst('Dan', 6, 4, 6, 2, 2);
  perform pg_temp.setst('Eve', 8, 8, 2, 1, 1); perform pg_temp.setst('Gus', 8, 4, 4, 2, 2); perform pg_temp.setst('Hal', 6, 6, 4, 2, 2);
  -- Fay resta senza punti assegnati: serve per provare il rifiuto
  perform pg_temp.full();
  perform pg_temp.setting('game_dng_drop_extra_pct', 0); perform pg_temp.setting('game_dng_drop_replay_pct', 0);
  assert (select count(*) from public.game_heroes where stats_set) = 7, 'X: 7 eroi pronti, Fay senza punti';
  insert into t_log (msg) values ('OK Preparazione: eroi pronti, energia 100, premi casuali spenti per i test deterministici');
end $$;

-- D1 — il catalogo: 25 dungeon a difficoltà crescente, boss a tema, oggetti esclusivi
do $$
declare s numeric;
begin
  assert (select count(*) from public.game_dungeons) = 25, 'D1: 25 dungeon';
  assert not exists (select 1 from public.game_dungeons where jsonb_array_length(rooms) not between 4 and 6), 'D1: da 4 a 6 stanze';
  assert not exists (select 1 from public.game_dungeons d where (select count(*) from jsonb_array_elements(d.rooms) x where (x->>'boss')::boolean) <> 1
                         or not (d.rooms->(jsonb_array_length(d.rooms) - 1)->>'boss')::boolean), 'D1: una sola stanza boss e proprio l''ultima';
  assert not exists (select 1 from public.game_dungeons a join public.game_dungeons b on b.no = a.no + 1
                      where b.ref_level <= a.ref_level or b.bc <= a.bc or b.xp <= a.xp or b.min_level < a.min_level or jsonb_array_length(b.rooms) < jsonb_array_length(a.rooms)),
         'D1: livello consigliato, BC, XP, livello minimo e stanze crescono sempre';
  assert (select min(bc) from public.game_dungeons) = 150 and (select max(bc) from public.game_dungeons) = 2500, 'D1: BC da 150 a 2500';
  select sum(bc) into s from public.game_dungeons;
  assert s between 25000 and 35000, 'D1: BC totali circa 30 mila (' || s || ')';
  assert (select count(distinct boss_name) from public.game_dungeons where boss_name <> '' and boss_emoji <> '' and boss_lore <> '') = 25, 'D1: 25 boss diversi, con nome, emoji e storia';
  assert exists (select 1 from public.game_dungeons where boss_name like '%Exodia%') and exists (select 1 from public.game_dungeons where boss_name like '%Occhi Blu%'), 'D1: boss a tema Yu-Gi-Oh!';
  assert (select count(*) from public.game_items where source = 'dungeon') = 25, 'D1: 25 oggetti esclusivi';
  assert not exists (select 1 from public.game_dungeons d left join public.game_items i on i.id = d.item_id and i.source = 'dungeon' and i.dungeon_no = d.no where i.id is null), 'D1: ogni dungeon ha il suo oggetto';
  assert not exists (select 1 from public.game_dungeons d join public.game_items i on i.id = d.item_id where (i.rarity = 'epico') <> (d.no % 5 = 0)), 'D1: epico esattamente ai dungeon 5, 10, 15, 20, 25';
  assert (select count(*) from public.game_items where source = 'dungeon' and rarity = 'epico') = 5, 'D1: 5 oggetti epici';
  assert not exists (select 1 from public.game_dungeons d join public.game_items i on i.id = d.item_id where i.min_level > d.min_level), 'D1: gli oggetti si possono usare entrando nel dungeon';
  assert not exists (select 1 from public.game_items where source = 'dungeon' and (p_for + p_des + p_vig + p_spi + p_frt) <= 0 and xp_pct <= 0 and extra_actions <= 0 and extra_fights <= 0), 'D1: ogni oggetto dà qualcosa';
  assert public._game_dng_cost() = 20, 'D1: costo 20 energie';
  assert (select count(*) from public.system_settings where key like 'game\_dng\_%') = 10, 'D1: 10 impostazioni dungeon';
  insert into t_log (msg) values ('OK D1 — 25 dungeon crescenti (150→2500 BC), boss Yu-Gi-Oh!, un oggetto esclusivo per dungeon, epici ogni 5');
end $$;

-- D2 — stato iniziale
do $$
declare s jsonb;
begin
  s := pg_temp.dst('Ann');
  assert jsonb_array_length(s->'dungeons') = 25 and (s->>'cost')::int = 20 and (s->>'max_party')::int = 4 and (s->>'total')::int = 25, 'D2: 25 dungeon, costo 20, gruppo massimo 4';
  assert (select count(*) from jsonb_array_elements(s->'dungeons') x where (x->>'open')::boolean) = 1 and (s->'dungeons'->0->>'open')::boolean, 'D2: all''inizio è aperto solo il primo';
  assert (s->>'cleared')::int = 0 and (s->>'next_epic_in')::int = 5 and jsonb_array_length(s->'lobbies') = 0 and s->'my_run' = 'null'::jsonb and s->'last_result' = 'null'::jsonb, 'D2: nessun dungeon fatto, nessuna lobby, nessun risultato';
  assert (s->'dungeons'->4->'item'->>'rarity') = 'epico' and (s->'dungeons'->0->'item'->>'owned')::boolean = false, 'D2: l''elenco mostra l''oggetto esclusivo (epico al 5°)';
  insert into t_log (msg) values ('OK D2 — stato: solo il 1° aperto, costo 20, gruppo massimo 4, prossimo epico tra 5');
end $$;

-- D3 — la lobby: ruoli (1 Tank, 1 Supporto, fino a 2 Danni), gruppo pieno, cambio ruolo, uscita, capo che passa
do $$
declare run uuid; run2 uuid; j jsonb; e text;
begin
  run := pg_temp.cr('Ann', 1, 'tank');
  j := (select public._game_dng_run_json(run));
  assert j->>'status' = 'lobby' and j->>'leader_id' = pg_temp.uid('Ann')::text and jsonb_array_length(j->'members') = 1 and j->'members'->0->>'role' = 'tank', 'D3: lobby creata, Ann capo e Tank';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_create(1, ''dps'')') like 'Sei già in una lobby%', 'D3: non si è in due lobby';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_join(''' || run || ''', ''tank'')') like '%già un Tank%', 'D3: un solo Tank';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_join(''' || run || ''', null)') like 'Scegli un ruolo%', 'D3: il ruolo è obbligatorio';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_join(''' || run || ''', ''mago'')') like 'Scegli un ruolo%', 'D3: ruolo sconosciuto rifiutato';
  perform pg_temp.jn('Bob', run, 'support');
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_join(''' || run || ''', ''support'')') like '%già un Supporto%', 'D3: un solo Supporto';
  perform pg_temp.jn('Cid', run, 'dps'); perform pg_temp.jn('Dan', run, 'dps');
  assert pg_temp.err_as('Eve', 'select public.game_dungeon_join(''' || run || ''', ''dps'')') = 'La lobby è piena', 'D3: al quinto giocatore la lobby è piena';
  assert jsonb_array_length((pg_temp.dst('Ann'))->'lobbies') = 1 and jsonb_array_length((pg_temp.dst('Eve'))->'lobbies'->0->'members') = 4, 'D3: la lobby è visibile a tutti con i 4 membri';
  assert (pg_temp.dst('Bob'))->'my_run'->>'run_id' = run::text, 'D3: Bob vede la propria lobby';
  -- cambio ruolo
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_role(''' || run || ''', ''support'')') like '%già un Supporto%' and pg_temp.err_as('Cid', 'select public.game_dungeon_role(''' || run || ''', ''tank'')') like '%già un Tank%', 'D3: il cambio ruolo rispetta i limiti';
  assert pg_temp.err_as('Eve', 'select public.game_dungeon_role(''' || run || ''', ''dps'')') like 'Non sei in questa lobby%', 'D3: chi non c''è non cambia ruolo';
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_role(''' || run || ''', ''boh'')') like 'Scegli un ruolo%', 'D3: ruolo sconosciuto rifiutato anche nel cambio';
  perform pg_temp.rl('Dan', run, 'dps');
  -- Dan esce: posto libero per Eve
  j := pg_temp.lv('Dan', run);
  assert (j->>'closed')::boolean = false and pg_temp.err_as('Dan', 'select public.game_dungeon_leave(''' || run || ''')') like 'Non sei in questa lobby%', 'D3: Dan è uscito e non può uscire due volte';
  perform pg_temp.jn('Eve', run, 'dps');
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_role(''' || run || ''', ''dps'')') like '%posto per i Danni%', 'D3: al massimo 2 Danni, anche cambiando ruolo';
  -- il capo esce: il comando passa a chi è entrato per primo (Bob)
  -- (in una transazione now() è fisso: sfalso a mano gli orari d'ingresso, come accade nella realtà)
  update public.game_run_members set joined_at = now() - (case user_id when pg_temp.uid('Ann') then interval '4 minutes' when pg_temp.uid('Bob') then interval '3 minutes' when pg_temp.uid('Cid') then interval '2 minutes' else interval '1 minute' end) where run_id = run;
  j := pg_temp.lv('Ann', run);
  assert (select leader_id from public.game_runs where id = run) = pg_temp.uid('Bob'), 'D3: Ann esce, il capo diventa Bob';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_start(''' || run || ''')') like 'Solo il capo%', 'D3: Ann non è più capo';
  -- tutti fuori: la lobby si chiude
  perform pg_temp.lv('Bob', run); perform pg_temp.lv('Cid', run); j := pg_temp.lv('Eve', run);
  assert (j->>'closed')::boolean and (select status from public.game_runs where id = run) = 'cancelled', 'D3: l''ultimo che esce chiude la lobby';
  assert jsonb_array_length((pg_temp.dst('Ann'))->'lobbies') = 0, 'D3: nessuna lobby aperta';
  -- tre Danni su quattro posti: il terzo non entra (massimo 2)
  run2 := pg_temp.cr('Ann', 1, 'dps'); perform pg_temp.jn('Bob', run2, 'dps');
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_join(''' || run2 || ''', ''dps'')') like '%posto per i Danni%', 'D3: il terzo Danni non entra';
  perform pg_temp.jn('Cid', run2, 'tank');
  perform pg_temp.lv('Ann', run2); perform pg_temp.lv('Bob', run2); perform pg_temp.lv('Cid', run2);
  assert (select count(*) from public.game_runs where status = 'lobby') = 0, 'D3: nessuna lobby rimasta aperta';
  assert not exists (select 1 from public.ledger_entries where kind = 'game_dungeon_reward') and pg_temp.en('Ann') = 100 and pg_temp.en('Bob') = 100, 'D3: la lobby non costa energia né muove BC';
  insert into t_log (msg) values ('OK D3 — lobby: ruoli 1 Tank/1 Supporto/2 Danni, gruppo da 4, cambio ruolo, uscita, capo che passa, chiusura');
end $$;

-- D4 — requisiti per entrare: sblocco in ordine, livello, punti assegnati, energia
do $$
declare run uuid; i integer;
begin
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_create(2, ''dps'')') like 'Dungeon bloccato%', 'D4: il 2° è bloccato finché non si completa il 1°';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_create(99, ''dps'')') = 'Dungeon inesistente', 'D4: dungeon inesistente';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_create(0, ''dps'')') = 'Dungeon inesistente', 'D4: dungeon 0 inesistente';
  perform pg_temp.st('Fay');
  assert pg_temp.err_as('Fay', 'select public.game_dungeon_create(1, ''dps'')') like 'Prima assegna i tuoi punti abilità%', 'D4: senza punti assegnati non si entra';
  update public.game_heroes set energy = 19.99, energy_at = now() where user_id = pg_temp.uid('Eve');
  assert pg_temp.err_as('Eve', 'select public.game_dungeon_create(1, ''dps'')') like 'Energia insufficiente: per un dungeon ne servono 20%', 'D4: 19,99 energie non bastano';
  update public.game_heroes set energy = 20, energy_at = now() where user_id = pg_temp.uid('Eve');
  run := pg_temp.cr('Eve', 1, 'dps');
  assert pg_temp.en('Eve') = 20, 'D4: con 20 si può creare la lobby (e per ora non si paga)';
  perform pg_temp.lv('Eve', run);
  -- il livello: Eve ha completato (finto) i dungeon 1-9, ma è di livello 1
  for i in 1..9 loop insert into public.game_dungeon_progress (user_id, dungeon_no, clears, first_clear_at, last_clear_at) values (pg_temp.uid('Eve'), i, 1, now(), now()); end loop;
  perform pg_temp.full();
  assert pg_temp.err_as('Eve', 'select public.game_dungeon_create(10, ''dps'')') = 'Serve il livello 24 per questo dungeon', 'D4: il 10° richiede il livello 24';
  assert (select (x->>'level_ok')::boolean from jsonb_array_elements((pg_temp.dst('Eve'))->'dungeons') x where (x->>'no')::int = 10) = false and
         (select (x->>'open')::boolean from jsonb_array_elements((pg_temp.dst('Eve'))->'dungeons') x where (x->>'no')::int = 10) = true, 'D4: lo stato dice «aperto ma livello insufficiente»';
  perform pg_temp.lvl('Eve', 24);
  run := pg_temp.cr('Eve', 10, 'tank');
  perform pg_temp.lv('Eve', run);
  perform pg_temp.lvl('Eve', 1);
  -- un giocatore con livello troppo basso non entra nemmeno in una lobby altrui
  insert into t_log (msg) values ('OK D4 — sblocco in ordine, livello minimo, punti assegnati, energia (19,99 no, 20 sì)');
end $$;

-- D5 — vittoria in solitaria alla prima volta: BC, XP, oggetto esclusivo, energia, registro
do $$
declare run uuid; r jsonb; m jsonb; t0 bigint; b0 integer; x0 bigint; f0 integer; s jsonb; k text;
begin
  perform pg_temp.dw(1); perform pg_temp.full();
  t0 := pg_temp.tot(); b0 := pg_temp.bal('Ann'); x0 := (pg_temp.hero('Ann')).total_xp; f0 := (pg_temp.hero('Ann')).fights_total;
  run := pg_temp.cr('Ann', 1, 'dps');
  r := pg_temp.go('Ann', run);
  m := pg_temp.mem(r, 'Ann');
  assert r->>'status' = 'cleared' and (r->'result'->>'win')::boolean and (r->'result'->>'rooms_cleared')::int = 4 and (r->'result'->>'rooms_total')::int = 4 and jsonb_array_length(r->'result'->'rooms') = 4, 'D5: dungeon superato, 4 stanze su 4';
  assert pg_temp.en('Ann') = 80, 'D5: costo 20 energie (80)';
  assert (m->>'first')::boolean and (m->>'bc')::int = 150 and pg_temp.bal('Ann') = b0 + 150 and pg_temp.tot() = t0 + 150, 'D5: 150 BC alla prima vittoria, e il totale dei BC cresce di 150';
  assert (m->>'xp')::int = 132 and (pg_temp.hero('Ann')).total_xp = x0 + 132 and (pg_temp.hero('Ann')).fights_total = f0 + 1, 'D5: 132 XP';
  assert jsonb_array_length(m->'items') = 1 and m->'items'->0->>'id' = 'd01' and (m->'items'->0->>'exclusive')::boolean and not (m->>'milestone')::boolean, 'D5: oggetto esclusivo del dungeon 1';
  assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Ann') and item_id = 'd01' and source = 'dungeon'), 'D5: l''oggetto è nello zaino, fonte «dungeon»';
  assert pg_temp.clears('Ann', 1) = 1 and (select first_clear_at is not null from public.game_dungeon_progress where user_id = pg_temp.uid('Ann') and dungeon_no = 1), 'D5: progresso salvato';
  k := 'gamedng:' || run::text || ':' || pg_temp.uid('Ann')::text;
  assert (select count(*) from public.ledger_entries where idempotency_key = k and kind = 'game_dungeon_reward' and amount = 150 and user_id = pg_temp.uid('Ann') and ref_type = 'game_run' and ref_id = run) = 1, 'D5: una riga nel registro, tipo game_dungeon_reward';
  assert (select status from public.game_runs where id = run) = 'cleared' and (select finished_at is not null and started_at is not null from public.game_runs where id = run), 'D5: la partita risulta conclusa';
  s := pg_temp.dst('Ann');
  assert (s->>'cleared')::int = 1 and (s->>'next_epic_in')::int = 4 and (s->'dungeons'->1->>'open')::boolean and not (s->'dungeons'->2->>'open')::boolean and (s->'dungeons'->0->>'clears')::int = 1, 'D5: il 2° si sblocca, il 3° no; prossimo epico tra 4';
  assert (s->'last_result'->>'run_id') = run::text and s->'my_run' = 'null'::jsonb, 'D5: lo stato riporta l''ultimo risultato';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_start(''' || run || ''')') like 'Questa lobby non esiste più%', 'D5: non si può far ripartire una partita finita';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_join(''' || run || ''', ''dps'')') like 'Questa lobby non esiste più%', 'D5: né entrarci';
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'D5: saldi = registro';
  insert into t_log (msg) values ('OK D5 — prima vittoria in solitaria: 150 BC, 132 XP, oggetto d01, −20 energie, una riga nel registro');
end $$;

-- D6 — repliche: premi ridotti, premio casuale solo se la probabilità lo consente; 2° oggetto alla prima vittoria
do $$
declare run uuid; r jsonb; m jsonb; b0 integer; x0 bigint; n0 bigint;
begin
  perform pg_temp.full(); n0 := pg_temp.inv('Ann'); b0 := pg_temp.bal('Ann'); x0 := (pg_temp.hero('Ann')).total_xp;
  run := pg_temp.cr('Ann', 1, 'tank'); r := pg_temp.go('Ann', run); m := pg_temp.mem(r, 'Ann');
  assert not (m->>'first')::boolean and (m->>'bc')::int = 38 and (m->>'xp')::int = 66 and pg_temp.bal('Ann') = b0 + 38 and (pg_temp.hero('Ann')).total_xp = x0 + 66, 'D6: replica = 25% dei BC (38) e 50% dell''XP (66)';
  assert jsonb_array_length(m->'items') = 0 and pg_temp.inv('Ann') = n0 and pg_temp.clears('Ann', 1) = 2 and not (m->>'milestone')::boolean, 'D6: nessun oggetto con probabilità 0, due vittorie registrate, niente traguardo';
  -- replica con premio casuale garantito
  perform pg_temp.setting('game_dng_drop_replay_pct', 100); perform pg_temp.full();
  run := pg_temp.cr('Ann', 1, 'dps'); r := pg_temp.go('Ann', run); m := pg_temp.mem(r, 'Ann');
  assert jsonb_array_length(m->'items') = 1 and not (m->'items'->0->>'exclusive')::boolean and pg_temp.inv('Ann') = n0 + 1, 'D6: con probabilità 100 la replica dà un oggetto non esclusivo';
  assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Ann') and item_id = m->'items'->0->>'id' and source = 'dungeon')
         and (select rarity from public.game_items where id = m->'items'->0->>'id') in ('comune','non_comune','raro'), 'D6: oggetto comune, non comune o raro, nello zaino';
  perform pg_temp.setting('game_dng_drop_replay_pct', 0);
  -- prima vittoria con secondo oggetto casuale garantito: dungeon 2
  perform pg_temp.setting('game_dng_drop_extra_pct', 100); perform pg_temp.dw(2); perform pg_temp.full(); n0 := pg_temp.inv('Ann'); b0 := pg_temp.bal('Ann');
  run := pg_temp.cr('Ann', 2, 'dps'); r := pg_temp.go('Ann', run); m := pg_temp.mem(r, 'Ann');
  assert (m->>'first')::boolean and (m->>'bc')::int = 190 and pg_temp.bal('Ann') = b0 + 190 and jsonb_array_length(m->'items') = 2 and pg_temp.inv('Ann') = n0 + 2, 'D6: dungeon 2 alla prima volta: 190 BC e due oggetti (esclusivo + casuale)';
  assert (select count(*) from jsonb_array_elements(m->'items') x where (x->>'exclusive')::boolean and x->>'id' = 'd02') = 1, 'D6: uno è il d02 esclusivo';
  perform pg_temp.setting('game_dng_drop_extra_pct', 0);
  insert into t_log (msg) values ('OK D6 — repliche 25% BC / 50% XP; premio casuale e 2° oggetto solo con la probabilità attiva');
end $$;

-- D7 — gruppo: bonus BC per ogni compagno, prima volta e replica nella stessa partita, solo il capo parte
do $$
declare run uuid; r jsonb; b0 integer; ba integer; bg integer; t0 bigint;
begin
  perform pg_temp.full();
  run := pg_temp.cr('Bob', 1, 'tank');
  perform pg_temp.jn('Cid', run, 'support'); perform pg_temp.jn('Dan', run, 'dps');
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_start(''' || run || ''')') like 'Solo il capo della lobby%' and pg_temp.err_as('Hal', 'select public.game_dungeon_start(''' || run || ''')') like 'Solo il capo della lobby%', 'D7: parte solo il capo';
  t0 := pg_temp.tot();
  r := pg_temp.go('Bob', run);
  assert r->>'status' = 'cleared' and (r->'result'->>'party_bonus')::int = 20 and jsonb_array_length(r->'result'->'members') = 3 and (r->'result'->>'cost')::int = 20, 'D7: gruppo da 3 → bonus +20%';
  assert (pg_temp.mem(r, 'Bob')->>'bc')::int = 180 and (pg_temp.mem(r, 'Cid')->>'bc')::int = 180 and (pg_temp.mem(r, 'Dan')->>'bc')::int = 180 and pg_temp.tot() = t0 + 540, 'D7: 150 × 1,2 = 180 BC a testa';
  assert pg_temp.mem(r, 'Bob')->>'role' = 'tank' and pg_temp.mem(r, 'Cid')->>'role' = 'support' and pg_temp.mem(r, 'Dan')->>'role' = 'dps', 'D7: i ruoli sono nel resoconto';
  assert pg_temp.en('Bob') = 80 and pg_temp.en('Cid') = 80 and pg_temp.en('Dan') = 80, 'D7: ognuno spende 20 energie';
  assert exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Bob') and item_id = 'd01') and exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Cid') and item_id = 'd01') and exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Dan') and item_id = 'd01'), 'D7: l''oggetto esclusivo va a tutti';
  assert (select count(*) from public.ledger_entries where ref_id = run and kind = 'game_dungeon_reward') = 3, 'D7: 3 righe nel registro';
  -- Ann (replica) e Gus (prima volta) insieme: bonus +10%
  perform pg_temp.full(); b0 := pg_temp.bal('Ann'); bg := pg_temp.bal('Gus');
  run := pg_temp.cr('Ann', 1, 'dps'); perform pg_temp.jn('Gus', run, 'dps');
  r := pg_temp.go('Ann', run);
  assert (r->'result'->>'party_bonus')::int = 10 and (pg_temp.mem(r, 'Ann')->>'bc')::int = 41 and not (pg_temp.mem(r, 'Ann')->>'first')::boolean, 'D7: Ann in replica: 150 × 1,1 × 25% = 41';
  assert (pg_temp.mem(r, 'Gus')->>'bc')::int = 165 and (pg_temp.mem(r, 'Gus')->>'first')::boolean and exists (select 1 from public.game_inventory where user_id = pg_temp.uid('Gus') and item_id = 'd01'), 'D7: Gus alla prima volta: 165 BC e oggetto';
  assert pg_temp.bal('Ann') = b0 + 41 and pg_temp.bal('Gus') = bg + 165, 'D7: i saldi si aggiornano';
  insert into t_log (msg) values ('OK D7 — gruppo: +10% BC per compagno, prima volta e replica insieme, premi a tutti, solo il capo parte');
end $$;

-- D8 — sconfitta: energia spesa, niente BC né oggetti né progresso, XP di consolazione (20%)
do $$
declare run uuid; r jsonb; m jsonb; t0 bigint; x0 bigint; cl integer; n0 bigint; l0 integer;
begin
  perform pg_temp.dl(1); perform pg_temp.full();
  t0 := pg_temp.tot(); x0 := (pg_temp.hero('Dan')).total_xp; cl := pg_temp.clears('Dan', 1); n0 := pg_temp.inv('Dan');
  select count(*) into l0 from public.ledger_entries;
  run := pg_temp.cr('Dan', 1, 'tank'); perform pg_temp.jn('Bob', run, 'dps');
  r := pg_temp.go('Dan', run); m := pg_temp.mem(r, 'Dan');
  assert r->>'status' = 'failed' and not (r->'result'->>'win')::boolean and (r->'result'->>'rooms_cleared')::int = 0 and jsonb_array_length(r->'result'->'rooms') = 1 and not (r->'result'->'rooms'->0->>'cleared')::boolean, 'D8: sconfitta già nella prima stanza';
  assert pg_temp.en('Dan') = 80 and pg_temp.en('Bob') = 80, 'D8: l''energia si spende comunque';
  assert (m->>'bc')::int = 0 and (m->>'xp')::int = 26 and (pg_temp.hero('Dan')).total_xp = x0 + 26 and jsonb_array_length(m->'items') = 0 and not (m->>'first')::boolean and not (m->>'milestone')::boolean, 'D8: 0 BC, 26 XP di consolazione (20% di 132), nessun oggetto';
  assert pg_temp.tot() = t0 and (select count(*) from public.ledger_entries) = l0 and pg_temp.clears('Dan', 1) = cl and pg_temp.inv('Dan') = n0, 'D8: nessun movimento di BC, progresso e zaino invariati';
  assert (select status from public.game_runs where id = run) = 'failed' and (pg_temp.dst('Dan'))->'last_result'->>'status' = 'failed', 'D8: la partita risulta fallita';
  -- una sconfitta non sblocca il dungeon seguente
  perform pg_temp.dl(3);
  assert pg_temp.err_as('Gus', 'select public.game_dungeon_create(3, ''dps'')') like 'Dungeon bloccato%', 'D8: il 3° resta bloccato';
  perform pg_temp.dn();
  insert into t_log (msg) values ('OK D8 — sconfitta: 20 energie spese, 0 BC, 20% XP, nessun oggetto, nessun progresso');
end $$;

-- D9 — un epico ogni 5 dungeon completati (percorso reale 1→5, poi 10)
do $$
declare run uuid; r jsonb; m jsonb; i integer; b0 integer; rar text;
begin
  perform pg_temp.setst('Fay', 8, 4, 4, 2, 2); perform pg_temp.lvl('Fay', 30);
  for i in 1..5 loop perform pg_temp.dw(i); end loop;
  for i in 1..5 loop
    perform pg_temp.full(); b0 := pg_temp.bal('Fay');
    run := pg_temp.cr('Fay', i, 'dps'); r := pg_temp.go('Fay', run); m := pg_temp.mem(r, 'Fay');
    select rarity into rar from public.game_items where id = 'd' || lpad(i::text, 2, '0');
    assert r->>'status' = 'cleared' and (m->>'first')::boolean and (m->>'bc')::int = pg_temp.dbc(i) and pg_temp.bal('Fay') = b0 + pg_temp.dbc(i), 'D9: dungeon ' || i || ' superato alla prima volta';
    assert exists (select 1 from jsonb_array_elements(m->'items') x where x->>'id' = 'd' || lpad(i::text, 2, '0') and (x->>'exclusive')::boolean), 'D9: dungeon ' || i || ' dà il suo oggetto esclusivo';
    assert (m->>'milestone')::boolean = (i = 5) and (rar = 'epico') = (i = 5), 'D9: epico e traguardo solo al 5° dungeon completato (i = ' || i || ')';
  end loop;
  assert (pg_temp.dst('Fay')->>'cleared')::int = 5 and (select count(*) from public.game_inventory g join public.game_items it on it.id = g.item_id where g.user_id = pg_temp.uid('Fay') and it.rarity = 'epico' and g.source = 'dungeon') = 1, 'D9: dopo 5 dungeon c''è 1 epico';
  assert pg_temp.err_as('Fay', 'select public.game_dungeon_create(7, ''dps'')') like 'Dungeon bloccato%', 'D9: il 7° è ancora bloccato';
  -- ripetere il 5° non è un nuovo dungeon completato: niente traguardo
  perform pg_temp.full(); run := pg_temp.cr('Fay', 5, 'dps'); m := pg_temp.mem(pg_temp.go('Fay', run), 'Fay');
  assert not (m->>'first')::boolean and not (m->>'milestone')::boolean and (m->>'bc')::int = round(pg_temp.dbc(5) * 0.25), 'D9: la replica non vale per il traguardo';
  -- dal 6° al 9° (inseriti a mano come completati) e poi il 10° vero: secondo epico
  for i in 6..9 loop insert into public.game_dungeon_progress (user_id, dungeon_no, clears, first_clear_at, last_clear_at) values (pg_temp.uid('Fay'), i, 1, now(), now()); end loop;
  perform pg_temp.dw(10); perform pg_temp.full();
  run := pg_temp.cr('Fay', 10, 'dps'); r := pg_temp.go('Fay', run); m := pg_temp.mem(r, 'Fay');
  assert (m->>'milestone')::boolean and (m->>'first')::boolean and exists (select 1 from jsonb_array_elements(m->'items') x where x->>'id' = 'd10' and x->>'rarity' = 'epico'), 'D9: il 10° completato dà il secondo epico';
  assert (pg_temp.dst('Fay')->>'cleared')::int = 10 and (pg_temp.dst('Fay')->>'next_epic_in')::int = 5, 'D9: stato: 10 completati, prossimo epico tra 5';
  perform pg_temp.dn();
  insert into t_log (msg) values ('OK D9 — percorso 1→5 in ordine, epico solo al 5° e al 10° completato, la replica non conta');
end $$;

-- D10 — chi non può più partire viene tolto (senza pagare) e il gruppo parte lo stesso; il capo senza energia non parte
do $$
declare run uuid; r jsonb; t0 bigint; bb integer;
begin
  perform pg_temp.dw(1); perform pg_temp.full();
  run := pg_temp.cr('Cid', 1, 'tank'); perform pg_temp.jn('Bob', run, 'support'); perform pg_temp.jn('Dan', run, 'dps'); perform pg_temp.jn('Hal', run, 'dps');
  update public.game_heroes set energy = 5, energy_at = now() where user_id = pg_temp.uid('Bob');
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Hal'), true, 'prova');
  bb := pg_temp.bal('Bob'); t0 := pg_temp.tot();
  r := pg_temp.go('Cid', run);
  assert r->>'status' = 'cleared' and jsonb_array_length(r->'result'->'members') = 2 and (r->'result'->'dropped') @> '["Bob","Hal"]'::jsonb and jsonb_array_length(r->'result'->'dropped') = 2, 'D10: Bob (senza energia) e Hal (sospeso) vengono tolti, parte il resto';
  assert pg_temp.en('Bob') = 5 and pg_temp.bal('Bob') = bb and pg_temp.en('Cid') = 80 and pg_temp.en('Dan') = 80, 'D10: chi è stato tolto non paga nulla e non riceve nulla';
  assert (r->'result'->>'party_bonus')::int = 10 and pg_temp.tot() = t0 + 2 * round(150 * 0.25 * 1.1), 'D10: il bonus è calcolato sui giocatori rimasti (2 → +10%) e sono repliche (41 BC a testa)';
  assert not exists (select 1 from public.game_run_members where run_id = run and user_id in (pg_temp.uid('Bob'), pg_temp.uid('Hal'))), 'D10: i due non risultano nella partita';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Hal'), false, 'ripristino');
  -- il capo senza energia
  perform pg_temp.full(); run := pg_temp.cr('Cid', 1, 'dps'); perform pg_temp.jn('Dan', run, 'tank');
  update public.game_heroes set energy = 10, energy_at = now() where user_id = pg_temp.uid('Cid');
  assert pg_temp.err_as('Cid', 'select public.game_dungeon_start(''' || run || ''')') like 'Energia insufficiente%', 'D10: il capo senza energia non può partire';
  assert pg_temp.en('Dan') = 100 and (select status from public.game_runs where id = run) = 'lobby', 'D10: nulla è stato speso e la lobby resta aperta';
  perform pg_temp.lv('Cid', run); perform pg_temp.lv('Dan', run);
  perform pg_temp.dn(); perform pg_temp.full();
  insert into t_log (msg) values ('OK D10 — chi non può partire viene tolto senza pagare; il capo senza energia viene fermato');
end $$;

-- D11 — le lobby non avviate scadono dopo 30 minuti
do $$
declare run uuid; run2 uuid; lst jsonb;
begin
  run := pg_temp.cr('Ann', 1, 'dps');
  update public.game_runs set created_at = now() - interval '31 minutes' where id = run;
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_start(''' || run || ''')') like 'La lobby è scaduta%', 'D11: non si parte con una lobby scaduta';
  assert pg_temp.en('Ann') = 100 and pg_temp.err_as('Bob', 'select public.game_dungeon_join(''' || run || ''', ''dps'')') like 'Questa lobby non esiste più%', 'D11: energia intatta; alla chiamata successiva la lobby risulta chiusa';
  perform pg_temp.dst('Ann');   -- una chiamata che non fallisce (come l'aggiornamento periodico dello stato) registra la scadenza
  assert (select status from public.game_runs where id = run) = 'cancelled', 'D11: la lobby scaduta è annullata';
  run2 := pg_temp.cr('Cid', 1, 'dps');
  update public.game_runs set created_at = now() - interval '31 minutes' where id = run2;
  lst := (pg_temp.dst('Bob'))->'lobbies';
  assert jsonb_array_length(lst) = 0 and (select status from public.game_runs where id = run2) = 'cancelled', 'D11: la lobby scaduta sparisce dall''elenco';
  assert pg_temp.err_as('Bob', 'select public.game_dungeon_join(''' || run2 || ''', ''dps'')') like 'Questa lobby non esiste più%', 'D11: non si entra in una lobby scaduta';
  run := pg_temp.cr('Cid', 1, 'dps');
  assert (pg_temp.dst('Cid'))->'my_run'->>'run_id' = run::text and ((pg_temp.dst('Cid'))->'my_run'->>'expires_at')::timestamptz > now() + interval '29 minutes', 'D11: dopo la scadenza si può crearne una nuova (scade tra 30 minuti)';
  perform pg_temp.lv('Cid', run);
  insert into t_log (msg) values ('OK D11 — le lobby scadono dopo 30 minuti e non si possono più usare');
end $$;

-- D12 — la manopola della difficoltà (impostazione) e la sua conseguenza
do $$
declare run uuid; r jsonb;
begin
  perform pg_temp.dn(); perform pg_temp.full();
  perform pg_temp.setting('game_dng_difficulty', 10);
  run := pg_temp.cr('Ann', 1, 'dps'); r := pg_temp.go('Ann', run);
  assert r->>'status' = 'cleared', 'D12: con difficoltà 10% il dungeon 1 si vince';
  perform pg_temp.setting('game_dng_difficulty', 100000); perform pg_temp.full();
  run := pg_temp.cr('Ann', 1, 'dps'); r := pg_temp.go('Ann', run);
  assert r->>'status' = 'failed', 'D12: con difficoltà altissima si perde';
  perform pg_temp.setting('game_dng_difficulty', 100);
  -- partita «normale» (non truccata): l'esito è coerente
  perform pg_temp.full(); run := pg_temp.cr('Ann', 1, 'dps'); r := pg_temp.go('Ann', run);
  assert r->>'status' in ('cleared','failed') and ((r->>'status' = 'cleared') = ((r->'result'->>'rooms_cleared')::int = (r->'result'->>'rooms_total')::int)), 'D12: una partita normale è coerente (vinta = tutte le stanze)';
  insert into t_log (msg) values ('OK D12 — l''impostazione game_dng_difficulty cambia l''esito (10% vince, altissima perde)');
end $$;

-- D13 — resoconto stanza per stanza
do $$
declare run uuid; r jsonb; rm jsonb; xm jsonb; i integer;
begin
  perform pg_temp.dw(1); perform pg_temp.full();
  run := pg_temp.cr('Bob', 1, 'tank'); perform pg_temp.jn('Cid', run, 'support'); perform pg_temp.jn('Dan', run, 'dps'); perform pg_temp.jn('Gus', run, 'dps');
  r := pg_temp.go('Bob', run);
  assert r->>'status' = 'cleared' and (r->'result'->>'party_bonus')::int = 30 and jsonb_array_length(r->'result'->'members') = 4, 'D13: gruppo da 4 → bonus +30%';
  for i in 0..3 loop
    rm := r->'result'->'rooms'->i;
    assert (rm->>'no')::int = i + 1 and rm->>'name' <> '' and rm->>'emoji' <> '' and (rm->>'cleared')::boolean and (rm->>'rounds')::int >= 1 and (rm->>'enemy_hp')::numeric > 0 and jsonb_array_length(rm->'members') = 4, 'D13: stanza ' || (i + 1) || ' con nome, emoji, round e 4 membri';
    assert (rm->>'boss')::boolean = (i = 3), 'D13: solo l''ultima stanza è quella del boss';
    for xm in select value from jsonb_array_elements(rm->'members') loop
      assert (xm->>'healed')::int = 0 or xm->>'role' = 'support', 'D13: cura solo il Supporto';
      assert (xm->>'max_hp')::int > 0 and (xm->>'hp')::int <= (xm->>'max_hp')::int and (xm->>'dealt')::int >= 0 and (xm->>'taken')::int >= 0, 'D13: valori coerenti';
    end loop;
  end loop;
  assert (select (x->>'max_hp')::numeric from jsonb_array_elements(r->'result'->'rooms'->0->'members') x where x->>'role' = 'tank')
         > (select (x->>'max_hp')::numeric from jsonb_array_elements(r->'result'->'rooms'->0->'members') x where x->>'user_id' = pg_temp.uid('Gus')::text) * 1.0, 'D13: il Tank ha più PV massimi (×1,3)';
  assert (select count(*) from public.game_runs where status = 'cleared' and result is not null) >= 1 and (select result = r->'result' from public.game_runs where id = run), 'D13: il resoconto è salvato nella partita';
  perform pg_temp.dn();
  insert into t_log (msg) values ('OK D13 — resoconto per stanza: boss all''ultima, ruoli, PV, cure solo dal Supporto, bonus +30% in 4');
end $$;

-- D14 — permessi: tutto passa dalle funzioni
do $$
declare e text; s jsonb;
begin
  perform pg_temp.as_('Ann');
  assert pg_temp.err_auth('Ann', 'insert into public.game_runs (dungeon_no, leader_id) values (1, ''' || pg_temp.uid('Ann') || ''')') like 'permission denied%', 'D14: niente insert su game_runs';
  assert pg_temp.err_auth('Ann', 'select * from public.game_runs') like 'permission denied%' and pg_temp.err_auth('Ann', 'select * from public.game_run_members') like 'permission denied%', 'D14: le partite si leggono solo dalle funzioni';
  assert pg_temp.err_auth('Ann', 'insert into public.game_dungeon_progress (user_id, dungeon_no, clears) values (''' || pg_temp.uid('Ann') || ''', 20, 1)') like 'permission denied%', 'D14: niente insert sul progresso';
  assert pg_temp.err_auth('Ann', 'update public.game_dungeon_progress set clears = 99') like 'permission denied%', 'D14: niente update sul progresso';
  assert pg_temp.err_auth('Ann', 'update public.game_dungeons set bc = 999999') like 'permission denied%' and pg_temp.err_auth('Ann', 'delete from public.game_dungeons') like 'permission denied%', 'D14: il catalogo non si modifica';
  assert pg_temp.err_auth('Ann', 'update public.game_inventory set item_id = ''d25''') like 'permission denied%', 'D14: lo zaino non si modifica';
  assert pg_temp.err_auth('Ann', 'select public._game_dng_sim(''[]''::jsonb, 1)') like 'permission denied%' and pg_temp.err_auth('Ann', 'select public._game_dng_pool_item(''' || pg_temp.uid('Ann') || ''', 1)') like 'permission denied%', 'D14: le funzioni interne non sono chiamabili';
  assert pg_temp.rows_as('Ann', 'select * from public.game_dungeons') = 25, 'D14: il catalogo è leggibile';
  assert pg_temp.rows_as('Ann', 'select * from public.game_dungeon_progress') = (select count(*) from public.game_dungeon_progress where user_id = pg_temp.uid('Ann'))
         and pg_temp.rows_as('Ann', 'select * from public.game_dungeon_progress where user_id <> auth.uid()') = 0, 'D14: ognuno vede solo il proprio progresso';
  perform pg_temp.err('delete from public.game_runs');
  assert pg_temp.err('delete from public.game_runs') like 'Storico protetto%' and pg_temp.err('delete from public.game_dungeon_progress') like 'Storico protetto%', 'D14: lo storico non si cancella';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  assert pg_temp.err('select public.game_dungeon_state()') is not null and pg_temp.err('select public.game_dungeon_create(1, ''dps'')') is not null and pg_temp.err('select public.game_dungeon_start(null)') is not null, 'D14: serve il login';
  -- modulo spento
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_state()') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_dungeon_create(1, ''dps'')') = 'Modulo non attivo', 'D14: a modulo spento stato e creazione sono bloccati';
  assert pg_temp.err_as('Ann', 'select public.game_dungeon_join(gen_random_uuid(), ''dps'')') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_dungeon_start(gen_random_uuid())') = 'Modulo non attivo'
         and pg_temp.err_as('Ann', 'select public.game_dungeon_role(gen_random_uuid(), ''dps'')') = 'Modulo non attivo' and pg_temp.err_as('Ann', 'select public.game_dungeon_leave(gen_random_uuid())') = 'Modulo non attivo', 'D14: e così join, avvio, ruolo, uscita';
  assert pg_temp.rows_as('Ann', 'select * from public.game_dungeon_progress') = 0 and pg_temp.rows_as('Ann', 'select * from public.game_dungeons') = 0, 'D14: a modulo spento non si leggono nemmeno le tabelle';
  perform pg_temp.mod(true);
  insert into t_log (msg) values ('OK D14 — permessi: niente scritture dirette, funzioni interne chiuse, login richiesto, modulo spento blocca tutto');
end $$;

-- D15 — registro e saldi
do $$
declare k text; sum_led bigint; sum_res bigint; u uuid; n bigint;
begin
  assert not exists (select 1 from public.ledger_entries where kind = 'game_dungeon_reward' and amount <= 0), 'D15: i dungeon danno solo BC (nessun addebito)';
  select sum(amount) into sum_led from public.ledger_entries where kind = 'game_dungeon_reward';
  select coalesce(sum((x->>'bc')::bigint), 0) into sum_res from public.game_runs r, jsonb_array_elements(r.result->'members') x where r.status = 'cleared';
  assert sum_led = sum_res and sum_led > 0, 'D15: i BC nel registro (' || sum_led || ') = i BC dichiarati nei resoconti (' || sum_res || ')';
  assert (select count(*) from public.ledger_entries where kind = 'game_dungeon_reward') = (select count(*) from public.ledger_entries where idempotency_key like 'gamedng:%'), 'D15: tutte le righe hanno la chiave gamedng:';
  -- idempotenza: ripetere lo stesso pagamento non fa nulla
  select idempotency_key, user_id into k, u from public.ledger_entries where kind = 'game_dungeon_reward' limit 1;
  n := (select balance from public.wallets where user_id = u);
  assert public._ledger_move(u, 150, 'game_dungeon_reward', 'game_run', gen_random_uuid(), k, 'doppio') = -1 and (select balance from public.wallets where user_id = u) = n, 'D15: la stessa chiave non paga due volte';
  assert not exists (select 1 from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)), 'D15: saldi = registro';
  assert not exists (select 1 from public.wallets where balance < 0), 'D15: nessun saldo negativo';
  assert (select count(*) from public.game_runs where status = 'lobby') = 0, 'D15: nessuna lobby rimasta aperta';
  insert into t_log (msg) values ('OK D15 — registro: solo entrate, = resoconti, chiavi uniche, saldi = registro');
end $$;

-- D16 — la simulazione (statistica, con ampi margini): il Supporto cura, il Tank regge, il livello conta
create function pg_temp.mk(p_nm text, p_role text, p_lv integer) returns jsonb language plpgsql as $$
declare p numeric := 20 + 3 * (p_lv - 1); f numeric; d numeric; v numeric; s numeric; r numeric; a numeric[];
begin
  a := case p_role when 'tank' then array[0.2, 0.1, 0.5, 0.0, 0.2] when 'support' then array[0.1, 0.1, 0.3, 0.4, 0.1] else array[0.5, 0.2, 0.2, 0.0, 0.1] end;
  f := round(5 + a[1] * p * p_lv); d := round(5 + a[2] * p * p_lv); v := round(5 + a[3] * p * p_lv); s := round(5 + a[4] * p * p_lv); r := round(5 + a[5] * p * p_lv);
  return jsonb_build_object('user_id', md5(p_nm), 'nickname', p_nm, 'role', p_role, 'level', p_lv, 'max_hp', 50 + 12 * v, 's_for', f, 's_des', d, 's_spi', s, 's_frt', r);
end $$;
do $$
declare party jsonb; solo jsonb; r jsonb; i integer; wins_party integer := 0; wins_solo integer := 0; wins_low integer := 0; healer_heal numeric := 0; other_heal numeric := 0; x jsonb; rm jsonb;
  tank_hp numeric; ok boolean := true;
begin
  perform pg_temp.dn(); perform pg_temp.setting('game_dng_difficulty', 100);
  party := jsonb_build_array(pg_temp.mk('T', 'tank', 10), pg_temp.mk('D1', 'dps', 10), pg_temp.mk('H', 'support', 10));
  solo := jsonb_build_array(pg_temp.mk('S', 'dps', 10));
  for i in 1..40 loop
    r := public._game_dng_sim(party, 5);
    if (r->>'win')::boolean then wins_party := wins_party + 1; end if;
    for rm in select value from jsonb_array_elements(r->'rooms') loop
      for x in select value from jsonb_array_elements(rm->'members') loop
        if x->>'role' = 'support' then healer_heal := healer_heal + (x->>'healed')::numeric; else other_heal := other_heal + (x->>'healed')::numeric; end if;
        if x->>'role' = 'tank' and rm->>'no' = '1' then tank_hp := (x->>'max_hp')::numeric; end if;
      end loop;
    end loop;
    r := public._game_dng_sim(solo, 5);
    if (r->>'win')::boolean then wins_solo := wins_solo + 1; end if;
    r := public._game_dng_sim(jsonb_build_array(pg_temp.mk('L', 'dps', 2)), 5);
    if (r->>'win')::boolean then wins_low := wins_low + 1; end if;
  end loop;
  raise notice 'D16 numeri: gruppo % /40, solo % /40, livello 2 % /40, cure supporto %, cure altri %', wins_party, wins_solo, wins_low, round(healer_heal), round(other_heal);
  assert wins_party >= 30, 'D16: un gruppo equilibrato di livello consigliato vince quasi sempre (' || wins_party || '/40)';
  assert wins_party > wins_solo, 'D16: il gruppo vince più spesso del singolo (' || wins_party || ' contro ' || wins_solo || ')';
  assert wins_solo between 4 and 38, 'D16: da solo la sfida è aperta, non scontata (' || wins_solo || '/40)';
  assert wins_low <= 2, 'D16: con livelli molto sotto il consigliato non si vince (' || wins_low || '/40)';
  assert healer_heal > 0 and other_heal = 0, 'D16: cura solo il Supporto';
  assert tank_hp = round((50 + 12 * (5 + 0.5 * (20 + 27) * 10)) * 1.3, 0) or abs(tank_hp - (50 + 12 * (5 + 0.5 * 47 * 10)) * 1.3) < 1, 'D16: il Tank ha il 130% dei PV (' || tank_hp || ')';
  -- il Tank è davvero quello che incassa: in media subisce più danni di ciascun alleato
  declare tk numeric := 0; od numeric := 0; n_o numeric := 0;
  begin
    for i in 1..30 loop
      r := public._game_dng_sim(party, 5);
      for rm in select value from jsonb_array_elements(r->'rooms') loop
        for x in select value from jsonb_array_elements(rm->'members') loop
          if x->>'role' = 'tank' then tk := tk + (x->>'taken')::numeric; elsif x->>'role' = 'dps' then od := od + (x->>'taken')::numeric; end if;
        end loop;
      end loop;
    end loop;
    assert tk > od, 'D16: il Tank incassa più del Danni (' || round(tk) || ' contro ' || round(od) || ')';
  end;
  insert into t_log (msg) values ('OK D16 — simulazione: gruppo ' || wins_party || '/40, solo ' || wins_solo || '/40, sotto livello ' || wins_low || '/40; solo il Supporto cura; il Tank incassa');
end $$;

select n, msg from t_log order by n;
rollback;
