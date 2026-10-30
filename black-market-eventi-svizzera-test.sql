-- =====================================================================
-- TEST DELLA MIGRAZIONE 032 (eventi «Torneo svizzero», durata e annullamento)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni del Black Market e la 032 (black-market-eventi-svizzera.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
-- =====================================================================
begin;
-- PROTEZIONE: il test crea utenti ed eventi di prova (il primo utente registrato diventa admin). Su un database con dati veri si ferma subito.
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-svizzera-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$ begin perform pg_temp.as_(n); return pg_temp.err(q); end $$;
create function pg_temp.err_auth(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end; end $$;
create function pg_temp.money() returns text language sql as $$
  select md5(coalesce((select string_agg(user_id || ':' || balance, ',' order by user_id) from public.wallets), '') || (select count(*)::text || coalesce(sum(amount), 0)::text from public.ledger_entries)) $$;
create function pg_temp.nick(n text) returns text language sql immutable as $$ select n $$;

do $$ declare n text; begin
  foreach n in array array['Admin','Org','Org2','Pl1','Pl2','Pl3','Pl4','Pl5','Pl6','Pl7','Pl8','Pl9','Pl10','Pl11','Pl12','Pl13','Pl14','Pl15','Pl16','Pl17'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova'); perform public.admin_set_role(pg_temp.uid('Org2'), 'organizer', 'secondo organizzatore');
  insert into t_log (msg) values ('OK Preparazione: 20 utenti');
end $$;

create function pg_temp.mk(org text, nm text, days integer default 7, swiss boolean default true, dt date default current_date) returns uuid language plpgsql as $$
begin perform pg_temp.as_(org); return public.create_event_ex(nm || ' ' || gen_random_uuid()::text, dt, days, swiss); end $$;
create function pg_temp.join_(n text, ev uuid) returns void language plpgsql as $$ begin perform pg_temp.as_(n); perform public.swiss_join(ev); end $$;
create function pg_temp.joinN(ev uuid, k integer) returns void language plpgsql as $$ begin for i in 1..k loop perform pg_temp.join_('Pl' || i, ev); end loop; end $$;
create function pg_temp.start(org text, ev uuid, r integer default null) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(org); return public.swiss_start(ev, r); end $$;
create function pg_temp.nextr(org text, ev uuid) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(org); return public.swiss_next_round(ev); end $$;
create function pg_temp.st(n text, ev uuid) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.swiss_state(ev); end $$;
create function pg_temp.nick_of(u uuid) returns text language sql as $$ select nickname from public.profiles where id = u $$;
-- gioca tutti i match in sospeso del turno: vince player_a (o a caso se rnd), con report di un giocatore e conferma dell'altro
create function pg_temp.playall(ev uuid, rnd boolean default false) returns integer language plpgsql as $$
declare m record; w uuid; c integer := 0;
begin
  for m in select * from public.matches where event_id = ev and status = 'pending' order by id loop
    w := case when rnd and random() < 0.5 then m.player_b else m.player_a end;
    perform pg_temp.as_(pg_temp.nick_of(m.player_a)); perform public.swiss_report(m.id, w);
    perform pg_temp.as_(pg_temp.nick_of(m.player_b)); perform public.swiss_report(m.id, w);
    c := c + 1;
  end loop; return c; end $$;
create function pg_temp.pairs(ev uuid) returns text language sql as $$
  select coalesce(string_agg(least(player_a::text, player_b::text) || '/' || greatest(player_a::text, player_b::text), ',' order by 1), '') from public.matches where event_id = ev $$;

-- W1 — creazione: permessi, durata, formato; il vecchio create_event funziona come prima
do $$
declare e uuid; r record;
begin
  assert pg_temp.err_as('Pl1', 'select public.create_event_ex(''Evento di prova'', current_date, 7, true)') like '%Permessi insufficienti%', 'W1: un giocatore normale non crea eventi';
  assert pg_temp.err_as('Org', 'select public.create_event_ex(''Evento senza durata'', current_date, null, true)') like '%durata%', 'W1: il torneo svizzero richiede la durata';
  assert pg_temp.err_as('Org', 'select public.create_event_ex(''Durata zero'', current_date, 0, true)') like '%da 1 a 90%' and pg_temp.err_as('Org', 'select public.create_event_ex(''Durata enorme'', current_date, 91, false)') like '%da 1 a 90%', 'W1: durata da 1 a 90';
  e := pg_temp.mk('Org', 'Remote League', 14, true, date '2026-11-01');
  select * into r from public.events where id = e;
  assert r.event_format = 'swiss' and r.event_status = 'open' and r.duration_days = 14 and r.current_round = 0 and r.rounds_planned is null and r.created_by = pg_temp.uid('Org'), 'W1: torneo svizzero creato in iscrizione';
  e := pg_temp.mk('Org', 'Serata libera', null, false);
  select * into r from public.events where id = e;
  assert r.event_format = 'manual' and r.duration_days is null, 'W1: evento a mano senza durata';
  e := pg_temp.mk('Org', 'Serata di 3 giorni', 3, false);
  assert (select duration_days from public.events where id = e) = 3, 'W1: durata anche sugli eventi a mano';
  perform pg_temp.as_('Org'); e := public.create_event('Evento vecchio stile', current_date);
  select * into r from public.events where id = e;
  assert r.event_format = 'manual' and r.event_status = 'open' and r.duration_days is null, 'W1: create_event com''era: formato a mano';
  assert (select count(*) from public.audit_logs where action = 'create_event') >= 4, 'W1: tutto finisce nell''audit';
  insert into t_log (msg) values ('OK W1 — creazione: permessi, durata, formato; create_event di prima intatto');
end $$;

-- W2 — gli eventi a mano non cambiano: match e verifica dell'organizzatore come sempre
do $$
declare e uuid; m uuid;
begin
  e := pg_temp.mk('Org', 'A mano', null, false);
  perform pg_temp.as_('Org'); m := public.create_match(e, 1, pg_temp.uid('Pl1'), pg_temp.uid('Pl2'));
  assert (select status from public.matches where id = m) = 'pending', 'W2: match a mano creato';
  perform public.verify_match(m, pg_temp.uid('Pl1'));
  assert (select status from public.matches where id = m) = 'verified' and (select winner_id from public.matches where id = m) = pg_temp.uid('Pl1'), 'W2: match verificato dall''organizzatore';
  assert pg_temp.err_as('Pl3', format('select public.swiss_join(%L)', e)) like '%non ha una lobby%', 'W2: non si entra in una lobby che non c''è';
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L)', e)) like '%non è un torneo svizzero%', 'W2: swiss_start solo sui tornei svizzeri';
  insert into t_log (msg) values ('OK W2 — gli eventi a mano funzionano come prima');
end $$;

-- W3 — lobby: iscrizione, uscita, tetto, chi può togliere
do $$
declare e uuid; s jsonb;
begin
  e := pg_temp.mk('Org', 'Lobby', 7);
  perform pg_temp.join_('Pl1', e); perform pg_temp.join_('Pl1', e); perform pg_temp.join_('Pl2', e); perform pg_temp.join_('Pl3', e);
  assert (select count(*) from public.event_participants where event_id = e) = 3, 'W3: tre iscritti, nessun doppione';
  s := pg_temp.st('Pl1', e);
  assert (s->'can'->>'leave')::boolean and not (s->'can'->>'join')::boolean and (s->'me'->>'joined')::boolean and not (s->'can'->>'start')::boolean and not (s->'can'->>'cancel')::boolean, 'W3: il giocatore iscritto può uscire, non avviare né annullare';
  s := pg_temp.st('Pl9', e);
  assert (s->'can'->>'join')::boolean and not (s->'can'->>'leave')::boolean, 'W3: chi non è iscritto può iscriversi';
  s := pg_temp.st('Org', e);
  assert (s->'can'->>'start')::boolean and (s->'can'->>'cancel')::boolean and (s->>'is_organizer')::boolean and (s->>'n_active')::int = 3 and (s->>'auto_rounds')::int = 2, 'W3: l''organizzatore può avviare (3 giocatori → 2 turni) e annullare';
  perform pg_temp.as_('Pl3'); perform public.swiss_leave(e);
  assert (select count(*) from public.event_participants where event_id = e) = 2, 'W3: uscita dalla lobby';
  assert pg_temp.err_as('Pl3', format('select public.swiss_leave(%L)', e)) like '%Non sei iscritto%', 'W3: non si esce due volte';
  assert pg_temp.err_as('Pl1', format('select public.swiss_kick(%L, %L)', e, pg_temp.uid('Pl2'))) like '%Permessi insufficienti%', 'W3: un giocatore non toglie gli altri';
  assert pg_temp.err_as('Org2', format('select public.swiss_kick(%L, %L)', e, pg_temp.uid('Pl2'))) like '%Non sei l''organizzatore%', 'W3: un altro organizzatore non gestisce questo evento';
  perform pg_temp.as_('Org'); perform public.swiss_kick(e, pg_temp.uid('Pl2'));
  assert (select count(*) from public.event_participants where event_id = e) = 1, 'W3: l''organizzatore toglie un iscritto';
  perform pg_temp.as_('Admin'); perform public.swiss_kick(e, pg_temp.uid('Pl1'));
  assert (select count(*) from public.event_participants where event_id = e) = 0, 'W3: anche l''amministratore gestisce';
  -- tetto: 64
  insert into public.event_participants (event_id, user_id) select e, pg_temp.uid(x) from unnest(array['Admin','Org','Org2','Pl1','Pl2','Pl3','Pl4','Pl5','Pl6','Pl7','Pl8','Pl9','Pl10','Pl11','Pl12','Pl13','Pl14','Pl15','Pl16','Pl17']) x;
  insert into auth.users (id, email, aud, role) select md5('fill' || i)::uuid, 'f' || i || '@t.local', 'authenticated', 'authenticated' from generate_series(1, 44) i;
  insert into public.profiles (id, nickname) select md5('fill' || i)::uuid, 'Fill' || i from generate_series(1, 44) i;
  insert into public.event_participants (event_id, user_id) select e, md5('fill' || i)::uuid from generate_series(1, 44) i;
  assert (select count(*) from public.event_participants where event_id = e) = 64, 'W3: 64 iscritti';
  insert into auth.users (id, email, aud, role) values (pg_temp.uid('Extra'), 'extra@t.local', 'authenticated', 'authenticated');
  insert into public.profiles (id, nickname) values (pg_temp.uid('Extra'), 'Extra');
  insert into public.wallets (user_id, balance) values (pg_temp.uid('Extra'), 0);
  assert pg_temp.err_as('Extra', format('select public.swiss_join(%L)', e)) like '%al completo%', 'W3: il 65° giocatore non entra';
  assert pg_temp.err_as('Pl1', format('select public.swiss_join(%L)', e)) is null, 'W3: chi è già dentro può richiamare l''iscrizione senza errori';
  insert into t_log (msg) values ('OK W3 — lobby: iscrizione, uscita, permessi, tetto');
end $$;

-- W4 — il numero di turni in base ai giocatori e la partenza (solo l'organizzatore)
do $$
declare e uuid; r jsonb; i integer; exp_ integer[] := array[1,2,2,3,3,3,3,4,4,4,4,4,4,4,4,5];
begin
  for i in 2..17 loop
    assert public._swiss_auto_rounds(i) = case when i <= 2 then 1 when i <= 4 then 2 when i <= 8 then 3 when i <= 16 then 4 else 5 end, 'W4: turni automatici per ' || i;
  end loop;
  e := pg_temp.mk('Org', 'Partenza', 7);
  perform pg_temp.join_('Pl1', e);
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L)', e)) like '%almeno 2 giocatori%', 'W4: servono 2 giocatori';
  perform pg_temp.joinN(e, 7);
  assert pg_temp.err_as('Pl1', format('select public.swiss_start(%L)', e)) like '%Permessi insufficienti%', 'W4: un giocatore non avvia';
  assert pg_temp.err_as('Org2', format('select public.swiss_start(%L)', e)) like '%Non sei l''organizzatore%', 'W4: un altro organizzatore non avvia';
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L, 7)', e)) like '%da 1 a 6%', 'W4: turni oltre n-1 respinti';
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L, 0)', e)) like '%da 1 a 6%', 'W4: zero turni respinto';
  perform pg_temp.as_('Org'); perform public.swiss_set_rounds(e, 2);
  assert (select rounds_planned from public.events where id = e) = 2, 'W4: turni scelti prima della partenza';
  r := pg_temp.start('Org', e);
  assert (r->>'rounds')::int = 2 and (r->>'pairs')::int = 3 and r->>'bye' is not null, 'W4: parte con i turni scelti (2), 3 match e un riposo (7 giocatori)';
  assert (select event_status from public.events where id = e) = 'running' and (select current_round from public.events where id = e) = 1, 'W4: stato in corso, turno 1';
  assert (select count(*) from public.matches where event_id = e and round = 1) = 3 and (select count(*) from public.event_byes where event_id = e and round = 1 and kind = 'bye') = 1, 'W4: tre match e un solo riposo';
  assert (select count(distinct u) from (select player_a u from public.matches where event_id = e union all select player_b from public.matches where event_id = e union all select user_id from public.event_byes where event_id = e) x) = 7, 'W4: ogni giocatore compare una volta sola nel turno';
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L)', e)) like '%già partito%', 'W4: non si riparte';
  assert pg_temp.err_as('Pl9', format('select public.swiss_join(%L)', e)) like '%iscrizioni sono chiuse%', 'W4: a torneo partito le iscrizioni sono chiuse';
  -- turni automatici
  e := pg_temp.mk('Org', 'Auto', 7); perform pg_temp.joinN(e, 8); r := pg_temp.start('Org', e);
  assert (r->>'rounds')::int = 3 and (r->>'pairs')::int = 4 and r->>'bye' is null, 'W4: 8 giocatori → 3 turni automatici, 4 match, nessun riposo';
  e := pg_temp.mk('Org', 'Due', 7); perform pg_temp.joinN(e, 2); r := pg_temp.start('Org', e);
  assert (r->>'rounds')::int = 1, 'W4: 2 giocatori → 1 turno';
  insert into t_log (msg) values ('OK W4 — partenza solo dell''organizzatore, turni automatici o scelti, primo turno e riposo');
end $$;

-- W5 — risultati: uno indica, l'altro conferma o contesta; l'organizzatore decide
do $$
declare e uuid; m public.matches; m2 public.matches; r jsonb; ma text; mb text;
begin
  e := pg_temp.mk('Org', 'Risultati', 7); perform pg_temp.joinN(e, 4); perform pg_temp.start('Org', e);
  select * into m from public.matches where event_id = e order by id limit 1;
  select * into m2 from public.matches where event_id = e and id <> m.id limit 1;
  ma := pg_temp.nick_of(m.player_a); mb := pg_temp.nick_of(m.player_b);
  assert pg_temp.err_as('Pl9', format('select public.swiss_report(%L, %L)', m.id, m.player_a)) like '%Non giochi questo match%', 'W5: un estraneo non riporta';
  assert pg_temp.err_as(mb, format('select public.swiss_report(%L, %L)', m.id, pg_temp.uid('Pl9'))) like '%uno dei due giocatori%', 'W5: il vincitore dev''essere uno dei due';
  assert pg_temp.err_as(ma, format('select public.swiss_dispute(%L)', m.id)) like '%Nessun risultato da contestare%', 'W5: niente da contestare prima del report';
  perform pg_temp.as_(ma); r := public.swiss_report(m.id, m.player_a);
  assert r->>'state' = 'reported' and (select status from public.matches where id = m.id) = 'pending', 'W5: il primo report lascia il match in attesa';
  perform public.swiss_report(m.id, m.player_b);      -- chi ha riportato cambia idea
  assert (select winner_id from public.event_match_reports where match_id = m.id) = m.player_b and (select status from public.matches where id = m.id) = 'pending', 'W5: chi ha riportato può correggersi';
  perform public.swiss_report(m.id, m.player_a);
  assert pg_temp.err_as(ma, format('select public.swiss_dispute(%L)', m.id)) like '%Hai indicato tu%', 'W5: non si contesta il proprio report';
  assert (pg_temp.st('Pl9', e)) is not null, 'W5: lo stato si legge';
  perform pg_temp.as_(mb); r := public.swiss_report(m.id, m.player_a);
  assert r->>'state' = 'closed' and (select status from public.matches where id = m.id) = 'verified' and (select winner_id from public.matches where id = m.id) = m.player_a
     and (select verified_by from public.matches where id = m.id) = pg_temp.uid(mb) and (select verified_at from public.matches where id = m.id) is not null, 'W5: l''altro conferma → match verificato (verificato da chi conferma)';
  assert pg_temp.err_as(mb, format('select public.swiss_report(%L, %L)', m.id, m.player_b)) like '%già registrato%', 'W5: risultato definitivo';
  -- contestazione: altro vincitore indicato dall'avversario
  ma := pg_temp.nick_of(m2.player_a); mb := pg_temp.nick_of(m2.player_b);
  perform pg_temp.as_(ma); perform public.swiss_report(m2.id, m2.player_a);
  perform pg_temp.as_(mb); r := public.swiss_report(m2.id, m2.player_b);
  assert r->>'state' = 'disputed' and (select disputed from public.event_match_reports where match_id = m2.id), 'W5: indicare un altro vincitore = contestazione';
  assert pg_temp.err_as(ma, format('select public.swiss_report(%L, %L)', m2.id, m2.player_a)) like '%contestato%', 'W5: contestato: i giocatori non possono più riportare';
  assert (select status from public.matches where id = m2.id) = 'pending', 'W5: il match contestato resta in attesa';
  assert pg_temp.err_as(ma, format('select public.swiss_decide(%L, %L)', m2.id, m2.player_a)) like '%Permessi insufficienti%', 'W5: un giocatore non decide';
  assert pg_temp.err_as('Org2', format('select public.swiss_decide(%L, %L)', m2.id, m2.player_a)) like '%Non sei l''organizzatore%', 'W5: un altro organizzatore non decide';
  assert pg_temp.err_as('Org', format('select public.swiss_decide(%L, %L)', m2.id, pg_temp.uid('Pl9'))) like '%uno dei due giocatori%', 'W5: l''organizzatore sceglie tra i due';
  perform pg_temp.as_('Org'); r := public.swiss_decide(m2.id, m2.player_b);
  assert (select status from public.matches where id = m2.id) = 'verified' and (select winner_id from public.matches where id = m2.id) = m2.player_b and (select verified_by from public.matches where id = m2.id) = pg_temp.uid('Org'), 'W5: l''organizzatore decide';
  -- contesta con l'apposito pulsante
  e := pg_temp.mk('Org', 'Contesta', 7); perform pg_temp.joinN(e, 2); perform pg_temp.start('Org', e);
  select * into m from public.matches where event_id = e;
  ma := pg_temp.nick_of(m.player_a); mb := pg_temp.nick_of(m.player_b);
  perform pg_temp.as_(ma); perform public.swiss_report(m.id, m.player_a);
  perform pg_temp.as_(mb); perform public.swiss_dispute(m.id);
  assert (select disputed from public.event_match_reports where match_id = m.id) and (select disputed_by from public.event_match_reports where match_id = m.id) = pg_temp.uid(mb), 'W5: contestazione con il pulsante';
  -- decide anche un match senza report (fermo)
  e := pg_temp.mk('Org', 'Fermo', 7); perform pg_temp.joinN(e, 2); perform pg_temp.start('Org', e);
  select * into m from public.matches where event_id = e;
  perform pg_temp.as_('Org'); perform public.swiss_decide(m.id, m.player_a);
  assert (select status from public.matches where id = m.id) = 'verified', 'W5: l''organizzatore decide un match fermo';
  -- i match svizzeri non si creano a mano
  assert pg_temp.err_as('Org', format('select public.create_match(%L, 5, %L, %L)', e, pg_temp.uid('Pl3'), pg_temp.uid('Pl4'))) like '%li genera il sistema%', 'W5: niente match a mano nei tornei svizzeri';
  insert into t_log (msg) values ('OK W5 — risultati: report, conferma, contestazione, decisione dell''organizzatore');
end $$;

-- W6 — il turno successivo si sblocca solo con tutti i risultati; nessun rematch; riposi a rotazione; classifica
do $$
declare e uuid; k integer; r jsonb; n integer; st jsonb; bad integer; sz integer[] := array[8, 7, 9, 12, 11];
begin
  -- 8 giocatori, 3 turni: tutto con vincitori a caso
  foreach n in array sz loop
    e := pg_temp.mk('Org', 'Svizzera ' || n, 7); perform pg_temp.joinN(e, n); r := pg_temp.start('Org', e);
    k := (r->>'rounds')::int;
    for i in 1..k loop
      if i > 1 then perform pg_temp.nextr('Org', e); end if;
      assert (select count(*) from public.matches where event_id = e and round = i) = n / 2, 'W6: n=' || n || ' turno ' || i || ': ' || (n / 2) || ' match';
      assert (select count(*) from public.event_byes where event_id = e and round = i) = n % 2, 'W6: n=' || n || ' turno ' || i || ': riposo solo se dispari';
      assert (select count(distinct u) from (select player_a u from public.matches where event_id = e and round = i union all select player_b from public.matches where event_id = e and round = i union all select user_id from public.event_byes where event_id = e and round = i) x) = n, 'W6: n=' || n || ' turno ' || i || ': tutti giocano una volta';
      assert pg_temp.err_as('Org', format('select public.swiss_next_round(%L)', e)) like '%Mancano ancora%', 'W6: n=' || n || ' turno ' || i || ': con risultati mancanti il turno non parte';
      assert not (pg_temp.st('Org', e)->'can'->>'next')::boolean and not (pg_temp.st('Org', e)->'can'->>'finish')::boolean, 'W6: lo stato dice che non si può proseguire';
      perform pg_temp.playall(e, true);
    end loop;
    assert (select count(*) from (select least(player_a, player_b) a, greatest(player_a, player_b) b from public.matches where event_id = e group by 1, 2 having count(*) > 1) x) = 0, 'W6: n=' || n || ': nessun rematch';
    assert (select max(c) from (select count(*) c from public.event_byes where event_id = e and kind = 'bye' group by user_id) x) <= 1 or n % 2 = 0, 'W6: n=' || n || ': nessuno riposa due volte';
    assert (select sum(wins + byes) from public._swiss_table(e)) = (select count(*) from public.matches where event_id = e) + (select count(*) from public.event_byes where event_id = e), 'W6: n=' || n || ': vittorie = match + riposi';
    assert (select bool_and(points = 3 * (wins + byes)) from public._swiss_table(e)), 'W6: n=' || n || ': 3 punti a vittoria';
    assert (select count(*) from public._swiss_table(e)) = n and (select array_agg(rank order by rank) from public._swiss_table(e)) = (select array_agg(g) from generate_series(1, n) g), 'W6: n=' || n || ': classifica con posizioni 1..n';
    assert pg_temp.err_as('Org', format('select public.swiss_next_round(%L)', e)) like '%turni previsti sono stati giocati%', 'W6: n=' || n || ': oltre i turni previsti si ferma';
  end loop;
  -- stesso punteggio si affronta: con 8 giocatori dopo il turno 1 vincitori con vincitori e perdenti con perdenti
  e := pg_temp.mk('Org', 'Punteggi', 7); perform pg_temp.joinN(e, 8); perform pg_temp.start('Org', e); perform pg_temp.playall(e, true); perform pg_temp.nextr('Org', e);
  assert not exists (select 1 from public.matches m join public._swiss_table(e) a on a.user_id = m.player_a join public._swiss_table(e) b on b.user_id = m.player_b where m.event_id = e and m.round = 2 and a.points <> b.points), 'W6: nel turno 2 si affrontano giocatori con lo stesso punteggio';
  insert into t_log (msg) values ('OK W6 — turni solo a risultati completi, nessun rematch, riposi a rotazione, classifica coerente (n = 8, 7, 9, 12, 11)');
end $$;

-- W7 — conclusione, turni aggiuntivi, stato
do $$
declare e uuid; s jsonb; w uuid;
begin
  e := pg_temp.mk('Org', 'Conclusione', 7); perform pg_temp.joinN(e, 4); perform pg_temp.start('Org', e, 2);
  assert pg_temp.err_as('Org', format('select public.swiss_finish(%L)', e)) like '%Mancano ancora%', 'W7: non si conclude con risultati mancanti';
  assert pg_temp.err_as('Org', format('select public.swiss_set_rounds(%L, 4)', e)) like '%da 1 a 3%', 'W7: turni oltre n-1 respinti anche in corso';
  perform pg_temp.playall(e); perform pg_temp.nextr('Org', e); perform pg_temp.playall(e);
  assert pg_temp.err_as('Org', format('select public.swiss_next_round(%L)', e)) like '%turni previsti%', 'W7: due turni giocati, previsti due';
  perform pg_temp.as_('Org'); perform public.swiss_set_rounds(e, 3);
  assert (pg_temp.st('Org', e)->'can'->>'next')::boolean, 'W7: aumentando i turni si può proseguire';
  assert pg_temp.err_as('Org', format('select public.swiss_set_rounds(%L, 1)', e)) like '%Numero di turni non valido%', 'W7: non si scende sotto i turni già giocati';
  perform pg_temp.nextr('Org', e); perform pg_temp.playall(e);
  assert pg_temp.err_as('Pl1', format('select public.swiss_finish(%L)', e)) like '%Permessi insufficienti%', 'W7: un giocatore non conclude';
  perform pg_temp.as_('Org'); s := public.swiss_finish(e);
  assert (s->>'finished')::boolean and (select event_status from public.events where id = e) = 'finished' and (select finished_at from public.events where id = e) is not null, 'W7: torneo concluso';
  assert (s->>'winner')::uuid = (select user_id from public._swiss_table(e) where rank = 1), 'W7: vincitore = primo in classifica';
  assert pg_temp.err_as('Org', format('select public.swiss_next_round(%L)', e)) like '%non è in corso%' and pg_temp.err_as('Pl1', format('select public.swiss_leave(%L)', e)) like '%non è in corso%', 'W7: concluso, niente più turni né ritiri';
  s := pg_temp.st('Pl2', e);
  assert s->'event'->>'status' = 'finished' and jsonb_array_length(s->'players') = 4 and jsonb_array_length(s->'rounds') = 3 and (s->'rounds'->0->>'round')::int = 3, 'W7: stato: 4 giocatori, 3 turni, dal più recente';
  assert (select bool_and(jsonb_array_length(x->'matches') = 2) from jsonb_array_elements(s->'rounds') x), 'W7: due match per turno';
  insert into t_log (msg) values ('OK W7 — conclusione, turni aggiuntivi, stato della pagina');
end $$;

-- W8 — ritiri
do $$
declare e uuid; m public.matches; opp uuid; dropper text; s jsonb;
begin
  e := pg_temp.mk('Org', 'Ritiri', 7); perform pg_temp.joinN(e, 6); perform pg_temp.start('Org', e);
  select * into m from public.matches where event_id = e order by id limit 1;
  dropper := pg_temp.nick_of(m.player_a); opp := m.player_b;
  perform pg_temp.as_(dropper); perform public.swiss_leave(e);
  assert (select dropped from public.event_participants where event_id = e and user_id = m.player_a), 'W8: ritirato a torneo in corso';
  assert not exists (select 1 from public.matches where id = m.id), 'W8: il suo match in sospeso sparisce (nessun match ufficiale)';
  assert exists (select 1 from public.event_byes where event_id = e and round = 1 and user_id = opp and kind = 'forfeit'), 'W8: l''avversario vince a tavolino';
  assert (select points from public._swiss_table(e) where user_id = opp) = 3 and (select wins from public._swiss_table(e) where user_id = opp) = 0, 'W8: 3 punti, ma nessuna vittoria ufficiale';
  perform pg_temp.playall(e); perform pg_temp.nextr('Org', e);
  assert not exists (select 1 from public.matches where event_id = e and round = 2 and m.player_a in (player_a, player_b)), 'W8: il ritirato non viene più accoppiato';
  assert (select count(*) from public.matches where event_id = e and round = 2) = 2 and (select count(*) from public.event_byes where event_id = e and round = 2) = 1, 'W8: 5 giocatori rimasti → 2 match e un riposo';
  s := pg_temp.st('Org', e);
  assert (select bool_or((x->>'dropped')::boolean) from jsonb_array_elements(s->'players') x) and (s->>'n_active')::int = 5 and (s->>'n_total')::int = 6, 'W8: stato: 5 attivi su 6';
  assert pg_temp.err_as(dropper, format('select public.swiss_leave(%L)', e)) like '%Non sei iscritto%', 'W8: il ritiro è uno solo';
  -- l'organizzatore toglie un giocatore con match in sospeso
  select * into m from public.matches where event_id = e and round = 2 order by id limit 1;
  perform pg_temp.as_('Org'); perform public.swiss_kick(e, m.player_b);
  assert not exists (select 1 from public.matches where id = m.id) and exists (select 1 from public.event_byes where event_id = e and round = 2 and user_id = m.player_a and kind = 'forfeit'), 'W8: l''organizzatore toglie un giocatore: vittoria a tavolino all''avversario';
  insert into t_log (msg) values ('OK W8 — ritiri: a tavolino senza match ufficiali, niente più accoppiamenti');
end $$;

-- W9 — durata dell'evento
do $$
declare e uuid; r jsonb;
begin
  e := pg_temp.mk('Org', 'Scaduto', 3, true, current_date - 10); perform pg_temp.joinN(e, 4);
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L)', e)) like '%durata dell''evento è terminata%', 'W9: evento già scaduto: non si avvia';
  assert not (pg_temp.st('Org', e)->'can'->>'start')::boolean and (pg_temp.st('Org', e)->'event'->>'expired')::boolean, 'W9: lo stato segnala la scadenza';
  assert (pg_temp.st('Org', e)->'event'->>'ends_on')::date = current_date - 8, 'W9: 3 giorni da 10 giorni fa = fine 8 giorni fa (contando il giorno di inizio)';
  e := pg_temp.mk('Org', 'Dura', 3, true, current_date - 2); perform pg_temp.joinN(e, 4); perform pg_temp.start('Org', e, 3);
  assert (pg_temp.st('Org', e)->'event'->>'ends_on')::date = current_date and not (pg_temp.st('Org', e)->'event'->>'expired')::boolean, 'W9: l''ultimo giorno è ancora valido';
  perform pg_temp.playall(e);
  perform pg_temp.nextr('Org', e);
  update public.events set event_date = current_date - 10 where id = e;      -- il tempo passa
  perform pg_temp.playall(e);       -- i risultati in corso si possono ancora registrare
  assert (select count(*) from public.matches where event_id = e and status = 'verified') = 4, 'W9: scaduto: i risultati si registrano ancora';
  assert pg_temp.err_as('Org', format('select public.swiss_next_round(%L)', e)) like '%durata dell''evento è terminata%', 'W9: scaduto: nessun nuovo turno';
  assert not (pg_temp.st('Org', e)->'can'->>'next')::boolean and (pg_temp.st('Org', e)->'can'->>'finish')::boolean, 'W9: si può solo concludere';
  perform pg_temp.as_('Org'); perform public.swiss_finish(e);
  assert (select event_status from public.events where id = e) = 'finished', 'W9: concluso dopo la scadenza';
  insert into t_log (msg) values ('OK W9 — durata: ultimo giorno incluso, dopo non si creano turni, si conclude');
end $$;

-- W10 — annullamento
do $$
declare e uuid; e2 uuid; m uuid; r jsonb; s jsonb; vm uuid;
begin
  -- lobby senza match: iscrizioni tolte
  e := pg_temp.mk('Org', 'Da annullare', 7); perform pg_temp.joinN(e, 3);
  assert pg_temp.err_as('Pl1', format('select public.cancel_event(%L)', e)) like '%Permessi insufficienti%', 'W10: un giocatore non annulla';
  assert pg_temp.err_as('Org2', format('select public.cancel_event(%L)', e)) like '%Non sei l''organizzatore%', 'W10: un altro organizzatore non annulla';
  perform pg_temp.as_('Org'); r := public.cancel_event(e, 'Pochi iscritti');
  assert (r->>'cancelled')::boolean and (r->>'registrations_removed')::int = 3 and (r->>'verified_kept')::int = 0, 'W10: annullata la lobby: iscrizioni tolte';
  assert (select event_status from public.events where id = e) = 'cancelled' and (select cancel_reason from public.events where id = e) = 'Pochi iscritti' and (select cancelled_by from public.events where id = e) = pg_temp.uid('Org'), 'W10: stato e motivo registrati';
  assert not exists (select 1 from public.event_participants where event_id = e), 'W10: nessun iscritto rimasto (non conta come evento disputato)';
  assert pg_temp.err_as('Org', format('select public.cancel_event(%L)', e)) like '%già annullato%', 'W10: non si annulla due volte';
  assert pg_temp.err_as('Pl9', format('select public.swiss_join(%L)', e)) like '%iscrizioni sono chiuse%', 'W10: nessuna iscrizione a un evento annullato';
  assert pg_temp.err_as('Org', format('select public.swiss_start(%L)', e)) like '%annullato%', 'W10: non si avvia un evento annullato';
  assert (pg_temp.st('Pl1', e)->'event'->>'status') = 'cancelled' and not (pg_temp.st('Org', e)->'can'->>'cancel')::boolean, 'W10: lo stato lo mostra annullato';
  assert (select count(*) from public.audit_logs where action = 'cancel_event' and entity_id = e::text) = 1, 'W10: audit';
  -- torneo in corso con un match verificato e uno in sospeso
  e := pg_temp.mk('Org', 'A metà', 7); perform pg_temp.joinN(e, 4); perform pg_temp.start('Org', e);
  select id into vm from public.matches where event_id = e order by id limit 1;
  perform pg_temp.as_('Org'); perform public.swiss_decide(vm, (select player_a from public.matches where id = vm));
  r := public.cancel_event(e, null);
  assert (r->>'pending_removed')::int = 1 and (r->>'verified_kept')::int = 1 and (r->>'registrations_removed')::int = 0, 'W10: a metà torneo: tolto il match in sospeso, tenuto il verificato';
  assert (select count(*) from public.matches where event_id = e) = 1 and (select status from public.matches where event_id = e) = 'verified' and (select count(*) from public.event_participants where event_id = e) = 4, 'W10: restano il match verificato e gli iscritti';
  assert pg_temp.err_as('Pl1', format('select public.swiss_report(%L, %L)', vm, pg_temp.uid('Pl1'))) like '%non è in un torneo svizzero in corso%', 'W10: nessun risultato su evento annullato';
  assert pg_temp.err_as('Org', format('select public.swiss_next_round(%L)', e)) like '%non è in corso%', 'W10: nessun turno su evento annullato';
  -- evento a mano
  e2 := pg_temp.mk('Org', 'Vecchio', null, false); perform pg_temp.as_('Org'); m := public.create_match(e2, 1, pg_temp.uid('Pl1'), pg_temp.uid('Pl2'));
  r := public.cancel_event(e2, 'Annullato per prova');
  assert (r->>'pending_removed')::int = 1 and (select event_status from public.events where id = e2) = 'cancelled' and not exists (select 1 from public.matches where event_id = e2), 'W10: anche gli eventi a mano si annullano';
  assert pg_temp.err_as('Org', format('select public.create_match(%L, 1, %L, %L)', e2, pg_temp.uid('Pl1'), pg_temp.uid('Pl2'))) like '%Evento annullato%', 'W10: su un evento annullato non si aggiungono match';
  -- l'evento automatico della Ladder non si annulla
  alter table public.events add column if not exists source text;
  insert into public.events (id, name, event_date, created_by, source) values (gen_random_uuid(), 'Ladder del giorno', current_date, pg_temp.uid('Admin'), 'ladder') returning id into e2;
  assert pg_temp.err_as('Admin', format('select public.cancel_event(%L)', e2)) like '%Ladder non si può annullare%', 'W10: l''evento della Ladder resta';
  assert not (pg_temp.st('Admin', e2)->'can'->>'cancel')::boolean, 'W10: lo stato non offre l''annullamento della Ladder';
  insert into t_log (msg) values ('OK W10 — annullamento: lobby, torneo a metà, evento a mano, Ladder protetta, audit');
end $$;

-- W11 — permessi, soldi, chiusura delle tabelle
do $$
declare m0 text; e uuid;
begin
  assert pg_temp.err_auth('Pl1', 'select * from public.event_byes') like '%permission denied%', 'W11: event_byes chiusa';
  assert pg_temp.err_auth('Pl1', 'select * from public.event_match_reports') like '%permission denied%', 'W11: event_match_reports chiusa';
  assert pg_temp.err_auth('Pl1', 'insert into public.event_byes (event_id, round, user_id) select id, 1, id from public.profiles limit 1') like '%permission denied%', 'W11: nessuna scrittura diretta sui riposi';
  assert pg_temp.err_auth('Pl1', format('select public._swiss_close(%L, %L, %L)', gen_random_uuid(), pg_temp.uid('Pl1'), pg_temp.uid('Pl1'))) like '%permission denied for function _swiss_close%', 'W11: _swiss_close interna';
  assert pg_temp.err_auth('Pl1', format('select public._swiss_make_round(%L, 1, %L)', gen_random_uuid(), pg_temp.uid('Pl1'))) like '%permission denied for function _swiss_make_round%', 'W11: _swiss_make_round interna';
  assert pg_temp.err_auth('Pl1', format('select * from public._swiss_table(%L)', gen_random_uuid())) like '%permission denied for function _swiss_table%', 'W11: _swiss_table interna';
  assert pg_temp.err_auth('Pl1', format('select public._swiss_drop(%L, %L, %L)', gen_random_uuid(), pg_temp.uid('Pl1'), pg_temp.uid('Pl1'))) like '%permission denied for function _swiss_drop%', 'W11: _swiss_drop interna';
  assert not has_function_privilege('anon', 'public.swiss_state(uuid)', 'execute') and not has_function_privilege('anon', 'public.swiss_report(uuid, uuid)', 'execute')
     and not has_function_privilege('anon', 'public.cancel_event(uuid, text)', 'execute') and not has_function_privilege('anon', 'public.create_event_ex(text, date, integer, boolean)', 'execute'), 'W11: anon escluso';
  assert has_function_privilege('authenticated', 'public.swiss_state(uuid)', 'execute') and has_function_privilege('authenticated', 'public.swiss_report(uuid, uuid)', 'execute'), 'W11: authenticated può usare gli RPC';
  assert pg_temp.err_auth('Pl1', format('select public.swiss_state(%L)', gen_random_uuid())) like '%Evento inesistente%', 'W11: evento inesistente';
  -- niente soldi: nessun movimento nel registro per tutto ciò che è stato fatto
  assert (select count(*) from public.ledger_entries where kind not in ('initial_bonus','admin_adjustment')) = 0, 'W11: nessun movimento di BC causato dai tornei';
  -- sospeso non gioca
  perform pg_temp.as_('Admin'); update public.profiles set suspended = true where id = pg_temp.uid('Pl17');
  e := pg_temp.mk('Org', 'Sospesi', 7);
  assert pg_temp.err_as('Pl17', format('select public.swiss_join(%L)', e)) like '%sospeso%', 'W11: un account sospeso non si iscrive';
  update public.profiles set suspended = false where id = pg_temp.uid('Pl17');
  insert into t_log (msg) values ('OK W11 — permessi, tabelle chiuse, nessun movimento di BC, sospesi esclusi');
end $$;


-- W12 — ultima spiaggia: se non si può evitare un rematch, il turno si crea lo stesso e lo dice
do $$
declare e uuid; r jsonb; pl uuid[]; i integer; j integer;
begin
  e := pg_temp.mk('Org', 'Rematch', 7); perform pg_temp.joinN(e, 4); perform pg_temp.start('Org', e, 3);
  perform pg_temp.playall(e); perform pg_temp.nextr('Org', e); perform pg_temp.playall(e); perform pg_temp.nextr('Org', e); perform pg_temp.playall(e);
  assert (select count(*) from (select 1 from public.matches where event_id = e group by least(player_a, player_b), greatest(player_a, player_b)) x) = 6, 'W12: 4 giocatori, 3 turni: tutti hanno affrontato tutti';
  update public.events set rounds_planned = 4 where id = e;       -- (forzato: dal sistema non si può chiedere)
  r := pg_temp.nextr('Org', e);
  assert (r->>'pairs')::int = 2 and (r->>'rematches')::int = 2, 'W12: il turno si crea con 2 rematch inevitabili';
  assert (select count(*) from public.matches where event_id = e and round = 4) = 2, 'W12: due match nel turno 4';
  insert into t_log (msg) values ('OK W12 — rematch solo se inevitabile');
end $$;

select msg as esito from t_log order by n;
rollback;
