-- =====================================================================
-- TEST DELLA MIGRAZIONE 033 (i tornei svizzeri contano per l'Elo Advanced della Ladder)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni del Black Market, della Ladder, la 032 e la 033.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
-- Lo scenario E6 inserisce partite chiuse nella tabella ladder_matches: se la tua tabella ha colonne obbligatorie che il test non conosce,
-- lo scenario viene SALTATO (lo dice nell'esito) invece di fallire.
-- =====================================================================
begin;
-- PROTEZIONE: il test crea utenti ed eventi di prova (il primo utente registrato diventa admin). Su un database con dati veri si ferma subito.
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
do $$ begin
  if to_regclass('public.ladder_matches') is null or to_regclass('public.ladder_ratings') is null or to_regprocedure('public.swiss_elo(uuid)') is null then
    raise exception 'TEST NON ESEGUITO: servono la Ladder, la 032 e la 033 già applicate. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-elo-' || n)::uuid $$;
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
  foreach n in array array['Admin','Org','Pl1','Pl2','Pl3','Pl4','Pl5','Pl6','Pl7','Pl8','Lad1','Lad2','Lad3','Lad4','Lad5','Lad6'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova');
  insert into t_log (msg) values ('OK Preparazione: 16 utenti');
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


create function pg_temp.elo(n text) returns integer language sql as $$ select coalesce((select elo from public.ladder_ratings where user_id = pg_temp.uid(n) and format = 'Advanced'), 1000) $$;
create function pg_temp.wl(n text) returns text language sql as $$ select coalesce((select wins || '-' || losses from public.ladder_ratings where user_id = pg_temp.uid(n) and format = 'Advanced'), '-') $$;
create function pg_temp.snap() returns text language sql as $$
  select coalesce(string_agg(user_id || ':' || format || ':' || elo || ':' || wins || ':' || draws || ':' || losses, ',' order by user_id, format), '') from public.ladder_ratings $$;
create function pg_temp.play1(m uuid, w uuid) returns void language plpgsql as $$
declare r public.matches%rowtype;
begin select * into r from public.matches where id = m;
  perform pg_temp.as_(pg_temp.nick_of(r.player_a)); perform public.swiss_report(m, w);
  perform pg_temp.as_(pg_temp.nick_of(r.player_b)); perform public.swiss_report(m, w); end $$;
create function pg_temp.err_anon(q text) returns text language plpgsql as $$
begin begin execute 'set local role anon'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end; end $$;
create temp table t_money (h text);
insert into t_money select pg_temp.money();

-- E1 — un match svizzero verificato muove l'Elo Advanced dei due giocatori (come in Ladder); Edison e BC non si toccano
do $$
declare e uuid; m public.matches%rowtype; x public.event_match_elo%rowtype; j jsonb;
begin
  e := pg_temp.mk('Org', 'E1', 7); perform pg_temp.join_('Pl1', e); perform pg_temp.join_('Pl2', e); perform pg_temp.start('Org', e);
  select * into m from public.matches where event_id = e;
  assert pg_temp.elo('Pl1') = 1000 and not exists (select 1 from public.ladder_ratings where user_id in (pg_temp.uid('Pl1'), pg_temp.uid('Pl2'))), 'E1: prima del match nessun Elo';
  perform pg_temp.as_(pg_temp.nick_of(m.player_a)); perform public.swiss_report(m.id, pg_temp.uid('Pl1'));
  assert not exists (select 1 from public.ladder_ratings where user_id in (pg_temp.uid('Pl1'), pg_temp.uid('Pl2'))), 'E1: un solo report: l''Elo non si muove';
  perform pg_temp.as_(pg_temp.nick_of(m.player_b)); perform public.swiss_report(m.id, pg_temp.uid('Pl1'));
  assert pg_temp.elo('Pl1') = 1016 and pg_temp.elo('Pl2') = 984, 'E1: 1000 contro 1000 con K=32: +16 / -16';
  assert pg_temp.wl('Pl1') = '1-0' and pg_temp.wl('Pl2') = '0-1', 'E1: vittorie e sconfitte della Ladder aggiornate';
  select * into x from public.event_match_elo where match_id = m.id;
  assert x.event_id = e and x.format = 'Advanced' and x.a_before = 1000 and x.b_before = 1000 and x.a_delta = case when m.player_a = pg_temp.uid('Pl1') then 16 else -16 end and x.b_delta = -x.a_delta, 'E1: variazione registrata sul match';
  assert not exists (select 1 from public.ladder_ratings where format = 'Edison'), 'E1: Edison non si tocca';
  perform pg_temp.as_('Pl2'); j := public.swiss_elo(e);
  assert j->>'format' = 'Advanced' and (j->>'counts')::boolean and jsonb_array_length(j->'matches') = 1 and jsonb_array_length(j->'players') = 2, 'E1: swiss_elo: formato, conteggio, un match, due giocatori';
  assert (select (p->>'elo')::int from jsonb_array_elements(j->'players') p where (p->>'user_id')::uuid = pg_temp.uid('Pl1')) = 1016, 'E1: swiss_elo mostra l''Elo attuale';
  assert (j->'matches'->0->>'a_delta')::int = x.a_delta and (j->'matches'->0->>'b_before')::int = 1000, 'E1: swiss_elo mostra le variazioni';
  insert into t_log (msg) values ('OK E1 — il match verificato muove l''Elo Advanced (+16/−16, V/S), Edison intatto');
end $$;

-- E2 — contano solo i match verificati: in attesa e contestati no; deciso dall'organizzatore sì
do $$
declare e uuid; m1 public.matches%rowtype; m2 public.matches%rowtype; w uuid; l uuid;
begin
  e := pg_temp.mk('Org', 'E2', 7);
  perform pg_temp.join_('Pl3', e); perform pg_temp.join_('Pl4', e); perform pg_temp.join_('Pl5', e); perform pg_temp.join_('Pl6', e); perform pg_temp.start('Org', e);
  select * into m1 from public.matches where event_id = e order by id limit 1;
  select * into m2 from public.matches where event_id = e order by id desc limit 1;
  perform pg_temp.as_(pg_temp.nick_of(m1.player_a)); perform public.swiss_report(m1.id, m1.player_a);
  perform pg_temp.as_(pg_temp.nick_of(m2.player_a)); perform public.swiss_report(m2.id, m2.player_a);
  perform pg_temp.as_(pg_temp.nick_of(m2.player_b)); perform public.swiss_report(m2.id, m2.player_b);       -- contestato
  assert (select count(*) from public.ladder_ratings where user_id in (pg_temp.uid('Pl3'), pg_temp.uid('Pl4'), pg_temp.uid('Pl5'), pg_temp.uid('Pl6'))) = 0, 'E2: in attesa e contestato non muovono l''Elo';
  perform pg_temp.as_('Org'); perform public.swiss_decide(m2.id, m2.player_b);
  assert pg_temp.elo(pg_temp.nick_of(m2.player_b)) = 1016 and pg_temp.elo(pg_temp.nick_of(m2.player_a)) = 984, 'E2: deciso dall''organizzatore: conta';
  assert (select count(*) from public.ladder_ratings where user_id in (pg_temp.uid(pg_temp.nick_of(m1.player_a)), pg_temp.uid(pg_temp.nick_of(m1.player_b)))) = 0, 'E2: l''altro match è ancora in attesa';
  perform pg_temp.as_(pg_temp.nick_of(m1.player_b)); perform public.swiss_report(m1.id, m1.player_a);
  assert pg_temp.elo(pg_temp.nick_of(m1.player_a)) = 1016 and pg_temp.elo(pg_temp.nick_of(m1.player_b)) = 984, 'E2: confermato: conta';
  insert into t_log (msg) values ('OK E2 — in attesa e contestati non contano; confermati e decisi dall''organizzatore sì');
end $$;

-- E3 — gli eventi a match manuali non contano
do $$
declare e uuid; m uuid; s text := pg_temp.snap(); j jsonb;
begin
  perform pg_temp.as_('Org'); e := public.create_event_ex('E3 manuale ' || gen_random_uuid(), current_date, 3, false);
  m := public.create_match(e, 1, pg_temp.uid('Pl7'), pg_temp.uid('Pl8'));
  perform public.verify_match(m, pg_temp.uid('Pl7'));
  assert (select status from public.matches where id = m) = 'verified' and pg_temp.snap() = s, 'E3: match manuale verificato: Elo invariato';
  j := public.swiss_elo(e);
  assert not (j->>'counts')::boolean and jsonb_array_length(j->'matches') = 0, 'E3: swiss_elo: evento manuale non conta';
  insert into t_log (msg) values ('OK E3 — gli eventi a match manuali non muovono l''Elo');
end $$;

-- E4 — riposi (BYE) e vittorie a tavolino per ritiro non sono partite giocate
do $$
declare e uuid; s text; m public.matches%rowtype; bye uuid; n integer;
begin
  e := pg_temp.mk('Org', 'E4', 7);
  perform pg_temp.join_('Pl7', e); perform pg_temp.join_('Pl8', e); perform pg_temp.join_('Pl1', e);
  s := pg_temp.snap(); perform pg_temp.start('Org', e);
  select * into m from public.matches where event_id = e and round = 1;
  select user_id into bye from public.event_byes where event_id = e and round = 1;
  assert bye is not null and pg_temp.snap() = s, 'E4: il riposo non cambia nessun Elo';
  perform pg_temp.as_(pg_temp.nick_of(m.player_a)); perform public.swiss_leave(e);
  assert (select count(*) from public.event_byes where event_id = e and kind = 'forfeit') = 1 and pg_temp.snap() = s, 'E4: il ritiro (vittoria a tavolino) non cambia nessun Elo';
  assert not exists (select 1 from public.event_match_elo where event_id = e), 'E4: nessuna variazione registrata';
  insert into t_log (msg) values ('OK E4 — riposi e ritiri non muovono l''Elo');
end $$;

-- E5 — annullare un torneo toglie il suo effetto dall'Elo (anche V/S); i match verificati restano nell'evento
do $$
declare e uuid; s0 text; s1 text; m uuid;
begin
  e := pg_temp.mk('Org', 'E5', 7); perform pg_temp.join_('Pl5', e); perform pg_temp.join_('Pl6', e); perform pg_temp.start('Org', e);
  s0 := pg_temp.snap();
  select id into m from public.matches where event_id = e; perform pg_temp.play1(m, pg_temp.uid('Pl5'));
  s1 := pg_temp.snap(); assert s1 <> s0 and exists (select 1 from public.event_match_elo where event_id = e), 'E5: premessa: il match ha mosso l''Elo';
  perform pg_temp.as_('Org'); perform public.cancel_event(e, 'prova');
  assert pg_temp.snap() = s0, 'E5: annullato: Elo e V/S tornano come prima';
  assert not exists (select 1 from public.event_match_elo where event_id = e) and (select status from public.matches where id = m) = 'verified', 'E5: nessuna variazione registrata; il match resta verificato';
  assert not (public.swiss_elo(e)->>'counts')::boolean, 'E5: swiss_elo: non conta più';
  insert into t_log (msg) values ('OK E5 — l''annullamento toglie l''effetto dall''Elo');
end $$;

-- E6 — ordine cronologico con le partite della Ladder (una chiusa dopo il torneo, una prima); la Ladder di prima resta com'era
do $$
declare e uuid; m uuid; lm uuid;
begin
  -- (a) il torneo prima, la Ladder dopo: A vince il torneo contro B, poi C batte A in Ladder
  e := pg_temp.mk('Org', 'E6a', 7); perform pg_temp.join_('Lad1', e); perform pg_temp.join_('Lad2', e); perform pg_temp.start('Org', e);
  select id into m from public.matches where event_id = e; perform pg_temp.play1(m, pg_temp.uid('Lad1'));
  assert pg_temp.elo('Lad1') = 1016 and pg_temp.elo('Lad2') = 984, 'E6a: premessa: dopo il torneo 1016/984';
  insert into public.ladder_matches (challenger_id, opponent_id, format, kind, status, reported_result, closed_at)
    values (pg_temp.uid('Lad3'), pg_temp.uid('Lad1'), 'Advanced', 'ladder', 'closed', 'challenger', clock_timestamp() + interval '1 hour') returning id into lm;
  insert into public.ladder_matches (challenger_id, opponent_id, format, kind, status, reported_result, closed_at)
    values (pg_temp.uid('Lad3'), pg_temp.uid('Lad2'), 'Advanced', 'bounty', 'closed', 'challenger', clock_timestamp() + interval '2 hours');   -- solo per la taglia: non conta
  perform public._ladder_rebuild('Advanced');
  assert pg_temp.elo('Lad1') = 999 and pg_temp.elo('Lad2') = 984 and pg_temp.elo('Lad3') = 1017, 'E6a: ordine torneo → Ladder: 999 / 984 / 1017 (e il match «per la taglia» non conta)';
  assert (select elo_challenger_before || '/' || elo_opponent_before || '/' || elo_challenger_delta || '/' || elo_opponent_delta from public.ladder_matches where id = lm) = '1000/1016/17/-17', 'E6a: variazioni scritte sul match della Ladder';
  assert (select a_before + b_before from public.event_match_elo where event_id = e) = 2000 and pg_temp.wl('Lad1') = '1-1', 'E6a: il torneo conserva le sue variazioni';
  -- (b) la Ladder prima, il torneo dopo: C2 batte A2 in Ladder, poi A2 batte B2 nel torneo
  insert into public.ladder_matches (challenger_id, opponent_id, format, kind, status, reported_result, closed_at)
    values (pg_temp.uid('Lad6'), pg_temp.uid('Lad4'), 'Advanced', 'ladder', 'closed', 'challenger', clock_timestamp() - interval '1 hour');
  perform public._ladder_rebuild('Advanced');
  assert pg_temp.elo('Lad4') = 984 and pg_temp.elo('Lad6') = 1016, 'E6b: premessa: solo la Ladder: 984 / 1016';
  e := pg_temp.mk('Org', 'E6b', 7); perform pg_temp.join_('Lad4', e); perform pg_temp.join_('Lad5', e); perform pg_temp.start('Org', e);
  select id into m from public.matches where event_id = e; perform pg_temp.play1(m, pg_temp.uid('Lad4'));
  assert pg_temp.elo('Lad4') = 1001 and pg_temp.elo('Lad5') = 983 and pg_temp.elo('Lad6') = 1016, 'E6b: ordine Ladder → torneo: 1001 / 983 / 1016';
  insert into t_log (msg) values ('OK E6 — torneo e Ladder si rigiocano in ordine di tempo; il «solo taglia» non conta; i dati della Ladder restano coerenti');
exception when not_null_violation or check_violation or undefined_column or foreign_key_violation then
  insert into t_log (msg) values ('SALTATO E6 — la tabella ladder_matches ha colonne obbligatorie che questo test non conosce: provalo con partite vere della Ladder');
end $$;

-- E7 — il ricalcolo è deterministico: rifarlo non cambia nulla; l'Elo totale è conservato; vittorie+sconfitte = partite giocate
do $$
declare s text := pg_temp.snap(); r record;
begin
  perform public._ladder_rebuild('Advanced'); perform public._ladder_rebuild('Advanced');
  assert pg_temp.snap() = s, 'E7: ricalcolare due volte dà lo stesso risultato';
  assert (select sum(elo) from public.ladder_ratings where format = 'Advanced') = 1000 * (select count(*) from public.ladder_ratings where format = 'Advanced'), 'E7: la somma degli Elo è conservata';
  for r in select user_id, wins + losses + draws as g from public.ladder_ratings where format = 'Advanced' loop
    assert r.g = (select count(*) from public.event_match_elo x join public.matches mt on mt.id = x.match_id where r.user_id in (mt.player_a, mt.player_b))
              + (select count(*) from public.ladder_matches lm where lm.status = 'closed' and lm.format = 'Advanced' and lm.kind in ('ladder','both') and r.user_id in (lm.challenger_id, lm.opponent_id)), 'E7: partite giocate coerenti con i match contati';
  end loop;
  insert into t_log (msg) values ('OK E7 — ricalcolo deterministico, Elo conservato, conteggi coerenti');
end $$;

-- E8 — torneo completo di 4 giocatori su 2 turni: ogni match verificato è contato una volta
do $$
declare e uuid; n integer;
begin
  e := pg_temp.mk('Org', 'E8', 7); perform pg_temp.joinN(e, 4); perform pg_temp.start('Org', e);
  perform pg_temp.playall(e); perform pg_temp.nextr('Org', e); perform pg_temp.playall(e);
  select count(*) into n from public.matches where event_id = e and status = 'verified';
  assert n = 4 and (select count(*) from public.event_match_elo where event_id = e) = 4, 'E8: 4 match verificati, 4 variazioni';
  assert (select sum(a_delta + b_delta) from public.event_match_elo where event_id = e) = 0, 'E8: ogni match è a somma zero';
  assert (select sum(elo) from public.ladder_ratings where format = 'Advanced') = 1000 * (select count(*) from public.ladder_ratings where format = 'Advanced'), 'E8: Elo totale conservato';
  insert into t_log (msg) values ('OK E8 — torneo completo: 4 match contati una volta');
end $$;

-- E9 — permessi: tabella chiusa, ricalcolo interno, swiss_elo solo per chi è dentro e non sospeso, nessun movimento di BC
do $$
declare e uuid;
begin
  select id into e from public.events where name like 'E1 %';
  assert pg_temp.err_auth('Pl1', 'select * from public.event_match_elo') like '%permission denied%', 'E9: la tabella delle variazioni è chiusa al browser';
  assert pg_temp.err_auth('Pl1', 'insert into public.event_match_elo (match_id, event_id, format, a_before, b_before, a_delta, b_delta) select id, event_id, ''Advanced'', 1, 1, 1, -1 from public.matches limit 1') like '%permission denied%', 'E9: nessuno scrive le variazioni';
  assert pg_temp.err_auth('Pl1', 'select public._ladder_rebuild(''Advanced'')') like '%permission denied%', 'E9: il ricalcolo non è chiamabile dal browser';
  assert pg_temp.err_auth('Pl1', 'select public._swiss_elo_format()') like '%permission denied%', 'E9: funzione interna chiusa';
  assert pg_temp.err_anon(format('select public.swiss_elo(%L)', e)) like '%permission denied%', 'E9: swiss_elo non per anonimi';
  update public.profiles set suspended = true where id = pg_temp.uid('Pl8');
  assert pg_temp.err_as('Pl8', format('select public.swiss_elo(%L)', e)) like '%sospeso%', 'E9: un sospeso non legge';
  update public.profiles set suspended = false where id = pg_temp.uid('Pl8');
  assert pg_temp.err_as('Pl1', 'select public.swiss_elo(''00000000-0000-0000-0000-000000000000'')') like '%inesistente%', 'E9: evento inesistente';
  assert pg_temp.money() = (select h from t_money), 'E9: nessun movimento di BC in tutti gli scenari';
  insert into t_log (msg) values ('OK E9 — permessi, tabella chiusa, nessun movimento di BC');
end $$;

-- E10 — Edison: il ricalcolo di Edison non contiene i tornei e non cambia gli Elo Advanced
do $$
declare s text; sa text;
begin
  select string_agg(user_id || ':' || elo || ':' || wins || ':' || losses, ',' order by user_id) into s from public.ladder_ratings where format = 'Advanced';
  perform public._ladder_rebuild('Edison');
  select string_agg(user_id || ':' || elo || ':' || wins || ':' || losses, ',' order by user_id) into sa from public.ladder_ratings where format = 'Advanced';
  assert not exists (select 1 from public.ladder_ratings where format = 'Edison' and (wins + losses + draws) > 0), 'E10: Edison senza partite: nessuno ha giocato';
  assert s = sa, 'E10: gli Elo Advanced non cambiano';
  assert (select count(*) from public.event_match_elo) = (select count(*) from public.event_match_elo where format = 'Advanced'), 'E10: i tornei sono solo in Advanced';
  insert into t_log (msg) values ('OK E10 — Edison non è toccato dai tornei');
end $$;

select msg as esito from t_log order by n;
rollback;
