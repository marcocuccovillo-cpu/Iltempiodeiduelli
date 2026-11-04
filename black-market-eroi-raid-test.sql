-- =====================================================================
-- TEST DELLA MIGRAZIONE 039 (raid settimanale)
-- Da eseguire SOLO su un progetto Supabase di PROVA ancora vuoto, con tutte le migrazioni applicate fino a black-market-eroi-raid.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Alla fine mostra una riga "OK" per ogni scenario.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-raid-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.act(n text, a text, t text default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_raid_act(a, case when t is null then null else pg_temp.uid(t) end); end $$;
create function pg_temp.raid() returns public.game_raids language sql as $$ select * from public.game_raids where week_start = public._raid_week() $$;
create function pg_temp.set_(k text, v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting(k, v, 'impostazione di prova'); end $$;

-- Preparazione: 6 duellanti con eroe e punti assegnati
do $$
declare n text;
begin
  foreach n in array array['Admin','Ann','Bob','Cid','Dan','Eve'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
  end loop;
  insert into t_log (msg) values ('OK Preparazione: 6 eroi');
end $$;

-- R1 — Il raid della settimana nasce da solo, con PV calcolati sugli eroi attivi; il boss del giorno è spento
do $$
declare s jsonb; g public.game_raids;
begin
  perform pg_temp.as_('Ann'); s := public.game_raid_state();
  g := pg_temp.raid();
  assert (s->>'enabled')::boolean and g.id is not null and g.status = 'open' and g.boss_no = 1, 'R1: raid aperto con il primo boss';
  assert g.heroes_at_start = 6 and g.max_hp >= 1000 and g.hp = g.max_hp, 'R1: PV calcolati su 6 eroi attivi';
  assert (s->'raid'->'boss'->>'name') = 'Il Leviatano delle Maree Spezzate', 'R1: boss nel risultato';
  assert (s->'raid'->>'ends_at')::timestamptz = (public._raid_week() + 7)::timestamp at time zone 'Europe/Rome', 'R1: finisce lunedì prossimo a mezzanotte';
  perform public.game_raid_state(); assert (select count(*) from public.game_raids) = 1, 'R1: un solo raid per settimana';
  assert pg_temp.err_as('Bob', 'select public.game_boss_join(null)') like '%sostituito dal Raid%', 'R1: il boss del giorno è spento';
  insert into t_log (msg) values ('OK R1 — raid creato al primo accesso, PV dagli eroi attivi, uno per settimana; boss del giorno bloccato');
end $$;

-- R2 — Attacco: danni al boss condiviso, rappresaglia sui PV di oggi, classifica; azioni di supporto limitate
do $$
declare r jsonb; hp0 bigint; i int;
begin
  hp0 := (pg_temp.raid()).hp;
  r := pg_temp.act('Ann', 'attack');
  assert (r->>'amount')::bigint > 0 and (r->>'raid_hp')::bigint = hp0 - (r->>'amount')::bigint, 'R2: il colpo toglie PV al boss di tutti';
  assert (r->>'dodge')::boolean or (r->>'taken')::bigint > 0, 'R2: il boss reagisce (o l''eroe schiva)';
  assert (select dmg from public.game_raid_damage where user_id = pg_temp.uid('Ann')) = (r->>'amount')::bigint, 'R2: danno in classifica';
  r := pg_temp.act('Bob', 'attack');
  assert (r->>'raid_hp')::bigint = (pg_temp.raid()).hp, 'R2: anche il secondo eroe colpisce lo stesso boss';
  -- supporto: 3 al giorno
  perform pg_temp.act('Cid', 'guard'); perform pg_temp.act('Cid', 'study'); perform pg_temp.act('Cid', 'guard', 'Ann');
  assert pg_temp.err_as('Cid', 'select public.game_raid_act(''study'')') like '%azioni di supporto%', 'R2: massimo 3 azioni di supporto';
  r := pg_temp.act('Cid', 'attack'); assert (r->>'amount')::bigint > 0, 'R2: l''attacco resta libero';
  assert (select shield from public.game_raid_days where user_id = pg_temp.uid('Ann')) > 0, 'R2: scudo dato a un alleato';
  assert (pg_temp.raid()).weak > 0, 'R2: Studia scopre una debolezza per tutti';
  assert pg_temp.err_as('Dan', format('select public.game_raid_act(''heal'', %L)', pg_temp.uid('Eve'))) like '%non sta combattendo%', 'R2: si cura solo chi combatte oggi';
  insert into t_log (msg) values ('OK R2 — colpi sul boss comune, rappresaglia, classifica, scudo a un alleato, debolezza comune, limite di 3 supporti');
end $$;

-- R3 — KO e rianimazione da parte di un alleato
do $$
declare r jsonb; i int := 0;
begin
  update public.game_raid_days set shield = 0 where user_id = pg_temp.uid('Bob');
  while not coalesce((r->>'ko')::boolean, false) and i < 400 loop r := pg_temp.act('Bob', 'attack'); i := i + 1; end loop;
  assert (r->>'ko')::boolean, 'R3: a forza di attaccare si va KO';
  assert i between 5 and 60, format('R3: KO dopo un numero ragionevole di attacchi (%s)', i);
  assert pg_temp.err_as('Bob', 'select public.game_raid_act(''attack'')') like '%KO%', 'R3: da KO non si attacca';
  r := pg_temp.act('Dan', 'heal', 'Bob');
  assert r->>'note' = 'rianimato' and (select hp from public.game_raid_days where user_id = pg_temp.uid('Bob')) > 0, 'R3: un alleato rianima';
  insert into t_log (msg) values (format('OK R3 — KO dopo %s attacchi, rianimato da un alleato', i));
end $$;

-- R4 — Il boss cade: premi in base al danno (base + montepremi + podio), oggetti, registro, notifiche; una volta sola
do $$
declare r jsonb; t0 bigint; n int; tot numeric; best uuid; b0 int; rw public.game_raid_rewards; v_last jsonb;
begin
  update public.game_raids set hp = 5 where id = (pg_temp.raid()).id;     -- quasi a terra
  t0 := (select coalesce(sum(balance), 0) from public.wallets);
  r := pg_temp.act('Eve', 'attack');
  assert (r->>'defeated')::boolean and r->'reward' is not null, 'R4: colpo finale con premio immediato';
  assert (pg_temp.raid()).status = 'defeated' and (pg_temp.raid()).settled_at is not null, 'R4: raid chiuso e premiato';
  select count(*) into n from public.game_raid_damage where raid_id = (pg_temp.raid()).id and dmg > 0;
  assert (select count(*) from public.game_raid_rewards) = n, 'R4: premio a ogni duellante che ha colpito';
  assert not exists (select 1 from public.game_raid_rewards where user_id = pg_temp.uid('Dan')), 'R4: chi ha solo curato non ha colpito: niente premio';
  select * into rw from public.game_raid_rewards where rank = 1;
  assert rw.bc >= 350 + 500, 'R4: il primo prende base + podio + quota';
  assert (select bool_and(bc >= 350) from public.game_raid_rewards), 'R4: tutti almeno la base';
  assert (select sum(bc) from public.game_raid_rewards) = (select coalesce(sum(balance), 0) from public.wallets) - t0, 'R4: BC dati = BC nel registro';
  assert (select count(*) from public.ledger_entries where kind = 'game_raid_reward') = n, 'R4: un movimento a testa';
  assert (select count(*) from public.notifications where kind = 'raid_reward') = n, 'R4: notifica a tutti i premiati';
  assert (select count(*) from public.game_raid_rewards where item_id is not null) >= 1, 'R4: oggetti pescati';
  perform public._raid_settle((pg_temp.raid()).id);
  assert (select count(*) from public.ledger_entries where kind = 'game_raid_reward') = n, 'R4: nessun doppio premio';
  assert pg_temp.err_as('Ann', 'select public.game_raid_act(''attack'')') like '%già caduto%', 'R4: dopo la caduta non si attacca più';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'R4: ogni saldo coincide con il registro';
  insert into t_log (msg) values (format('OK R4 — boss caduto: %s premiati in base al danno (1° %s BC), oggetti, notifiche, nessun doppio premio, saldi = registro', n, rw.bc));
end $$;

-- R5 — Settimana nuova: boss successivo più duro; un raid non battuto paga la consolazione ridotta
do $$
declare g1 public.game_raids; g2 public.game_raids; s jsonb; rw public.game_raid_rewards;
begin
  g1 := pg_temp.raid();
  update public.game_raids set week_start = week_start - 7 where id = g1.id;
  perform pg_temp.as_('Ann'); s := public.game_raid_state(); g2 := pg_temp.raid();
  assert g2.boss_no = 2 and g2.diff > g1.diff, 'R5: dopo una vittoria arriva il boss 2, più duro';
  perform pg_temp.act('Ann', 'attack');
  update public.game_raids set week_start = week_start - 7 where id = g1.id;
  update public.game_raids set week_start = week_start - 7 where id = g2.id;
  s := public.game_raid_state();
  assert (select status from public.game_raids where id = g2.id) = 'escaped', 'R5: il raid non battuto scappa';
  select * into rw from public.game_raid_rewards where raid_id = g2.id and user_id = pg_temp.uid('Ann');
  assert not rw.won and rw.bc < 350 + 500 and rw.item_id is null, 'R5: consolazione ridotta, senza oggetti';
  assert (pg_temp.raid()).boss_no = 3 and (pg_temp.raid()).diff < g2.diff, 'R5: il boss scappato rende più facile la settimana dopo';
  assert s->'previous'->>'status' = 'escaped', 'R5: la pagina mostra com''è finita la settimana prima';
  insert into t_log (msg) values ('OK R5 — rotazione dei boss, difficoltà adattiva, consolazione per il raid scappato');
end $$;

-- R6 — Badge, vetrina, permessi, interruttore
do $$
declare s jsonb; v bigint;
begin
  perform pg_temp.as_('Ann');
  select value into v from public.badge_progress_extra() where metric = 'e_attacchi' limit 1;
  assert v >= (select count(*) from public.game_raid_log where user_id = pg_temp.uid('Ann') and action = 'attack'), 'R6: gli attacchi nel raid contano per i badge';
  select value into v from public.badge_progress_extra() where metric = 'e_boss' limit 1;
  assert v >= 1, 'R6: il raid vinto conta come boss sconfitto';
  s := public.public_showcase();
  assert s->'raid'->>'name' is not null and (s->'raid'->>'max_hp')::bigint > 0, 'R6: il raid nella vetrina della Home';
  begin execute 'set local role authenticated'; perform pg_temp.as_('Ann'); update public.game_raids set hp = 0; raise exception 'SCRITTO';
  exception when others then assert sqlerrm <> 'SCRITTO', 'R6: il browser non modifica il raid'; end;
  execute 'reset role';
  perform pg_temp.set_('game_raid_enabled', 0);
  perform pg_temp.as_('Ann'); assert (public.game_raid_state()->>'enabled')::boolean = false, 'R6: raid spento';
  assert pg_temp.err_as('Ann', 'select public.game_raid_act(''attack'')') like '%non è attivo%', 'R6: raid spento, niente attacchi';
  assert pg_temp.err_as('Bob', 'select public.game_boss_join(null)') is null or pg_temp.err_as('Bob', 'select public.game_boss_join(null)') not like '%sostituito%', 'R6: torna il boss del giorno';
  insert into t_log (msg) values ('OK R6 — badge, vetrina, permessi, interruttore game_raid_enabled');
end $$;

select msg as risultato from t_log order by n;
rollback;
