-- =====================================================================
-- TEST DELLA MIGRAZIONE 002 (Hall of Fame, Faction Wars, Underground Challenges)
-- Da eseguire DOPO black-market-setup.sql e black-market-moduli.sql.
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

-- Preparazione: 8 utenti come nei test della 001
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Marco','Luca','Andrea','Giulia','Paolo','Povero'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  perform pg_temp.as_('Admin');
  perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  insert into t_log (msg) values ('OK Preparazione: 8 utenti, Admin e Org con ruolo');
end $$;

-- M1 — Moduli spenti per impostazione iniziale
do $$
begin
  assert (select count(*) from public.system_settings where key in ('module_hall_of_fame','module_faction_wars','module_underground') and value_int = 0) = 3, 'M1: i tre moduli devono nascere spenti';
  assert not public._module_on('hall_of_fame') and not public._module_on('faction_wars') and not public._module_on('underground'), 'M1: _module_on deve dire falso';
  insert into t_log (msg) values ('OK M1 — Hall of Fame, Faction Wars e Underground sono spenti per impostazione iniziale');
end $$;

-- M2 — Con i moduli spenti: dati esistenti invisibili, operazioni rifiutate dal DATABASE (non solo dall''interfaccia)
do $$
declare e uuid; m uuid; msg text; money0 text;
begin
  e := pg_temp.ev('Torneo con moduli spenti');
  m := pg_temp.mm(e, 1, 'Paolo', 'Luca', 'Paolo');                 -- esiste un match verificato vero
  assert (select count(*) from public.matches where status = 'verified') = 1, 'M2: il match di prova esiste';
  assert (select count(*) from public.hof_matches_v) = 0 and (select count(*) from public.hof_player_stats_v) = 0
     and (select count(*) from public.hof_records_v) = 0 and (select count(*) from public.hof_events_v) = 0
     and (select count(*) from public.faction_standings_v) = 0 and (select count(*) from public.challenges_v) = 0, 'M2: con il modulo spento le viste sono vuote';
  money0 := pg_temp.money();
  msg := pg_temp.err_as('Marco', 'select public.create_faction(''Fazione X'')');
  assert msg like '%Modulo non attivo%', 'M2: create_faction deve rifiutare, errore: ' || coalesce(msg,'nessun errore');
  assert msg like '%Modulo non attivo%', 'M2: create_faction deve rifiutare, errore: ' || msg;
  assert pg_temp.err_as('Marco', 'select public.join_faction(gen_random_uuid())') like '%Modulo non attivo%', 'M2: join_faction rifiutata';
  assert pg_temp.err_as('Marco', 'select public.leave_faction()') like '%Modulo non attivo%', 'M2: leave_faction rifiutata';
  assert pg_temp.err_as('Marco', format('select public.create_challenge(%L, null, %L)', pg_temp.uid('Luca'), 'richiesta-di-prova-1')) like '%Modulo non attivo%', 'M2: create_challenge rifiutata';
  assert pg_temp.err_as('Luca', 'select public.respond_challenge(gen_random_uuid(), true)') like '%Modulo non attivo%', 'M2: respond_challenge rifiutata';
  assert pg_temp.err_as('Org', 'select public.complete_challenge(gen_random_uuid())') like '%Modulo non attivo%', 'M2: complete_challenge rifiutata';
  assert pg_temp.err_as('Org', format('select public.link_challenge_match(gen_random_uuid(), %L)', m)) like '%Modulo non attivo%', 'M2: link_challenge_match rifiutata';
  assert pg_temp.err_as('Admin', 'select public.admin_faction_disband(gen_random_uuid(), ''prova di blocco'')') like '%Modulo non attivo%', 'M2: anche le funzioni admin rispettano l''interruttore';
  assert pg_temp.err_as('Admin', 'select public.admin_cancel_challenge(gen_random_uuid(), ''prova di blocco'')') like '%Modulo non attivo%', 'M2: admin_cancel_challenge rifiutata';
  assert pg_temp.err_as('Admin', 'select public.admin_create_season(''Stagione zero'', current_date, current_date + 30, ''prova di blocco'')') like '%Modulo non attivo%', 'M2: le stagioni richiedono almeno un modulo attivo';
  assert pg_temp.money() = money0, 'M2: nessun movimento economico';
  assert (select count(*) from public.factions) = 0 and (select count(*) from public.challenges) = 0, 'M2: nessun dato creato';
  insert into t_log (msg) values ('OK M2 — modulo spento: viste vuote e ogni funzione server (giocatori e admin) rifiuta con "Modulo non attivo"');
end $$;

-- M3 — Solo l'amministratore accende i moduli, con motivazione, e tutto finisce nell'audit
do $$
begin
  assert pg_temp.err_as('Marco', 'select public.admin_set_module(''hall_of_fame'', true, ''tentativo non autorizzato'')') like '%Permessi insufficienti%', 'M3: un utente non accende moduli';
  assert pg_temp.err_as('Org', 'select public.admin_set_module(''hall_of_fame'', true, ''tentativo non autorizzato'')') like '%Permessi insufficienti%', 'M3: nemmeno un organizzatore';
  assert pg_temp.err_as('Admin', 'select public.admin_set_module(''hall_of_fame'', true, ''x'')') like '%Motivazione obbligatoria%', 'M3: motivazione obbligatoria';
  assert pg_temp.err_as('Admin', 'select public.admin_set_module(''inesistente'', true, ''modulo che non c''''è'')') like '%Modulo sconosciuto%', 'M3: modulo sconosciuto';
  assert not public._module_on('hall_of_fame'), 'M3: i tentativi respinti non hanno acceso nulla';
  assert pg_temp.err_auth('Marco', 'update public.system_settings set value_int = 1 where key = ''module_hall_of_fame''') like '%permission denied%', 'M3: nessuna scrittura diretta sulle impostazioni';
  perform pg_temp.mod('hall_of_fame', true); perform pg_temp.mod('faction_wars', true); perform pg_temp.mod('underground', true);
  assert public._module_on('hall_of_fame') and public._module_on('faction_wars') and public._module_on('underground'), 'M3: acceso dall''admin';
  assert (select count(*) from public.audit_logs where action = 'set_module' and reason = 'attivazione di prova') = 3, 'M3: tre righe di audit con motivazione';
  assert pg_temp.err_as('Marco', 'select public.admin_faction_rename(gen_random_uuid(), ''Nome nuovo'', ''prova di permessi'')') like '%Permessi insufficienti%', 'M3: un utente non usa le funzioni admin';
  assert pg_temp.err_as('Marco', 'select public.admin_cancel_challenge(gen_random_uuid(), ''prova di permessi'')') like '%Permessi insufficienti%', 'M3: nemmeno quelle delle sfide';
  insert into t_log (msg) values ('OK M3 — solo l''admin, con motivazione, accende i moduli; tentativi non autorizzati respinti; audit scritto');
end $$;

-- M4 — Hall of Fame: statistiche vere, nessun dato inventato
do $$
declare e1 uuid; e2 uuid; m uuid; r jsonb; money0 text;
begin
  e1 := pg_temp.ev('Torneo Hall of Fame');
  perform pg_temp.mm(e1, 1, 'Paolo', 'Luca', 'Paolo'); perform pg_temp.mm(e1, 2, 'Paolo', 'Luca', 'Paolo'); perform pg_temp.mm(e1, 3, 'Paolo', 'Luca', 'Paolo');
  perform pg_temp.as_('Marco'); perform public.create_bounty(pg_temp.uid('Luca'), 200, null, gen_random_uuid()::text);
  m := pg_temp.mm(e1, 4, 'Paolo', 'Luca', 'Paolo');
  perform pg_temp.as_('Paolo'); r := public.claim_bounty(m);
  assert (r->>'payout')::integer = 200, 'M4: riscossione di prova da 200 BC';
  perform pg_temp.mm(e1, 5, 'Luca', 'Paolo', 'Luca');
  e2 := pg_temp.ev('Secondo torneo');
  perform pg_temp.mm(e2, 1, 'Marco', 'Andrea', 'Marco');
  perform pg_temp.mm(e2, 2, 'Giulia', 'Povero', null);             -- match NON verificato
  -- il match del test M2 (Paolo>Luca) è sempre esistito: ora, a modulo acceso, entra nelle statistiche
  assert (select wins from public.hof_player_stats_v where player_id = pg_temp.uid('Paolo')) = 5, 'M4: Paolo ha 5 vittorie (incluso il match di M2)';
  assert (select losses from public.hof_player_stats_v where player_id = pg_temp.uid('Paolo')) = 1, 'M4: Paolo ha 1 sconfitta';
  assert (select wins from public.hof_player_stats_v where player_id = pg_temp.uid('Luca')) = 1 and (select losses from public.hof_player_stats_v where player_id = pg_temp.uid('Luca')) = 5, 'M4: Luca 1-5';
  assert (select wins + losses from public.hof_player_stats_v where player_id = pg_temp.uid('Giulia')) = 0, 'M4: un match non verificato non conta';
  assert (select wins + losses + events_participated + bounty_claims from public.hof_player_stats_v where player_id = pg_temp.uid('Andrea')) = 1 + 1, 'M4: Andrea ha 1 sconfitta e 1 evento';
  assert (select count(*) from public.hof_player_stats_v where player_id = pg_temp.uid('Admin') and wins = 0 and losses = 0 and events_participated = 0 and bounty_claims = 0 and bounty_payout_total = 0) = 1, 'M4: chi non ha dati vede zeri, non numeri inventati';
  assert (select bounty_claims from public.hof_player_stats_v where player_id = pg_temp.uid('Paolo')) = 1 and (select bounty_payout_total from public.hof_player_stats_v where player_id = pg_temp.uid('Paolo')) = 200, 'M4: la riscossione compare nelle statistiche di Paolo';
  assert (select count(*) from public.hof_claims_v) = 1 and (select payout from public.hof_claims_v) = 200, 'M4: archivio delle riscossioni verificabili';
  assert (select count(*) from public.hof_matches_v) = 7, 'M4: 7 match verificati nell''archivio (7 = 6 di Paolo/Luca + 1 di Marco)';
  assert (select matches_verified from public.hof_events_v where event_id = e1) = 5 and (select matches_total from public.hof_events_v where event_id = e2) = 2 and (select matches_verified from public.hof_events_v where event_id = e2) = 1, 'M4: archivio eventi coerente';
  assert (select matches from public.hof_rivalries_v where player_1 = least(pg_temp.uid('Paolo'), pg_temp.uid('Luca')) and player_2 = greatest(pg_temp.uid('Paolo'), pg_temp.uid('Luca'))) = 6, 'M4: rivalità Paolo-Luca su 6 match';
  assert (select count(*) from public.hof_rivalries_v) = 1, 'M4: Marco-Andrea (1 match) non è una rivalità';
  assert (select holder_id from public.hof_records_v where record_key = 'most_wins') = pg_temp.uid('Paolo') and (select value from public.hof_records_v where record_key = 'most_wins') = 5, 'M4: record vittorie';
  assert (select value from public.hof_records_v where record_key = 'longest_win_streak' and holder_id = pg_temp.uid('Paolo')) = 5, 'M4: striscia di 5 vittorie consecutive';
  assert (select value from public.hof_records_v where record_key = 'biggest_claim') = 200 and (select ref_id from public.hof_records_v where record_key = 'biggest_claim') = m, 'M4: maggiore riscossione, con riferimento al match';
  assert (select count(*) from public.hof_milestones_v where milestone = 'wins_1') = 3 and (select count(*) from public.hof_milestones_v where milestone = 'wins_10') = 0, 'M4: traguardi solo se raggiunti davvero';
  assert (select count(*) from public.hof_milestones_v where milestone = 'first_claim' and player_id = pg_temp.uid('Paolo')) = 1, 'M4: traguardo prima riscossione';
  -- stagioni
  perform pg_temp.as_('Admin');
  perform public.admin_create_season('Stagione corrente', current_date - 30, current_date + 30, 'stagione di prova');
  perform public.admin_create_season('Stagione passata', date '2020-01-01', date '2020-12-31', 'stagione di prova');
  assert pg_temp.err_as('Admin', 'select public.admin_create_season(''Sovrapposta'', current_date, current_date + 5, ''prova di sovrapposizione'')') like '%si sovrappone%', 'M4: stagioni sovrapposte rifiutate';
  assert pg_temp.err_as('Marco', 'select public.admin_create_season(''Abusiva'', date ''2030-01-01'', date ''2030-12-31'', ''prova di permessi'')') like '%Permessi insufficienti%', 'M4: solo l''admin crea stagioni';
  assert (select wins from public.hof_season_stats_v h join public.seasons s on s.id = h.season_id where s.name = 'Stagione corrente' and h.player_id = pg_temp.uid('Paolo')) = 5, 'M4: statistiche della stagione corrente';
  assert (select wins from public.hof_season_stats_v h join public.seasons s on s.id = h.season_id where s.name = 'Stagione passata' and h.player_id = pg_temp.uid('Paolo')) = 0, 'M4: nessun dato inventato per la stagione passata';
  -- sola lettura dal browser
  assert pg_temp.rows_as('Povero', 'select * from public.hof_player_stats_v') >= 8, 'M4: un utente normale legge la Hall of Fame';
  assert pg_temp.err_auth('Marco', 'insert into public.seasons (name, starts_on, ends_on, created_by) values (''Abusiva'', current_date, current_date, gen_random_uuid())') like '%permission denied%', 'M4: nessuna scrittura diretta sulle stagioni';
  insert into t_log (msg) values ('OK M4 — Hall of Fame: statistiche, archivio, rivalità, record e traguardi coincidono con i match verificati; nessun dato inventato; stagioni protette');
end $$;

-- M5 — Faction Wars: iscrizione, regole, punteggio calcolato dalle fonti ufficiali, separato dai BC
do $$
declare ombre uuid; lupi uuid; e uuid; m_paolo_marco uuid; m_same uuid; m_andrea uuid; m_marco uuid; money0 text; sid uuid;
begin
  perform pg_temp.as_('Marco'); ombre := public.create_faction('Ombre', 'Chi duella nell''oscurità', 'O');
  perform pg_temp.as_('Andrea'); perform public.join_faction(ombre);
  perform pg_temp.as_('Paolo'); lupi := public.create_faction('Lupi', null, 'L');
  perform pg_temp.as_('Luca'); perform public.join_faction(lupi);
  -- regole
  assert pg_temp.err_as('Marco', 'select public.create_faction(''Altra fazione'')') like '%Fai già parte di una fazione%', 'M5: una sola fazione alla volta (creare)';
  assert pg_temp.err_as('Andrea', format('select public.join_faction(%L)', lupi)) like '%Fai già parte di una fazione%', 'M5: una sola fazione alla volta (aderire)';
  assert pg_temp.err_as('Giulia', 'select public.create_faction(''ombre'')') like '%Esiste già%', 'M5: nome già usato (senza distinzione tra maiuscole)';
  assert pg_temp.err_as('Giulia', 'select public.create_faction(''Ab'')') like '%da 3 a 30%', 'M5: nome troppo corto';
  assert pg_temp.err_as('Giulia', 'select public.join_faction(gen_random_uuid())') like '%non disponibile%', 'M5: fazione inesistente';
  assert pg_temp.err_as('Povero', 'select public.kick_faction_member(gen_random_uuid())') like '%Solo il capo%', 'M5: solo il capo rimuove';
  assert pg_temp.err_as('Andrea', 'select public.update_faction(''x'', ''y'')') like '%Solo il capo%', 'M5: solo il capo modifica';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('faction_max_members', 2, 'prova del limite di membri');
  assert pg_temp.err_as('Giulia', format('select public.join_faction(%L)', ombre)) like '%al completo%', 'M5: fazione al completo';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('faction_max_members', 20, 'ripristino dopo la prova');
  -- punteggio: i match già giocati PRIMA dell'iscrizione non contano
  assert (select coalesce(sum(points), 0) from public.faction_standings_v where season_id is null) = 0, 'M5: i match precedenti all''iscrizione non danno punti';
  money0 := pg_temp.money();
  e := pg_temp.ev('Torneo fazioni');
  m_paolo_marco := pg_temp.mm(e, 1, 'Paolo', 'Marco', 'Paolo');    -- Lupi batte Ombre: +3 Lupi
  m_same := pg_temp.mm(e, 2, 'Luca', 'Paolo', 'Luca');             -- stessa fazione: 0 punti
  m_andrea := pg_temp.mm(e, 3, 'Andrea', 'Giulia', 'Andrea');      -- Ombre batte un non iscritto: +3 Ombre
  m_marco := pg_temp.mm(e, 4, 'Marco', 'Povero', 'Marco');         -- +3 Ombre
  assert (select points from public.faction_standings_v where season_id is null and faction_id = lupi) = 3, 'M5: Lupi 3 punti';
  assert (select points from public.faction_standings_v where season_id is null and faction_id = ombre) = 6, 'M5: Ombre 6 punti';
  assert (select rank from public.faction_standings_v where season_id is null and faction_id = ombre) = 1 and (select rank from public.faction_standings_v where season_id is null and faction_id = lupi) = 2, 'M5: classifica';
  assert (select count(*) from public.faction_scored_matches_v) = (select count(distinct match_id) from public.faction_scored_matches_v) and (select count(*) from public.faction_scored_matches_v) = 3, 'M5: ogni match conta una volta sola';
  assert not exists (select 1 from public.faction_scored_matches_v where match_id = m_same), 'M5: il match tra compagni non conta';
  assert pg_temp.money() = money0, 'M5: il punteggio delle fazioni non muove BC, registro, taglie o riscossioni';
  assert (select count(*) from public.ledger_entries where kind not in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment')) = 0, 'M5: nessun nuovo tipo di movimento economico';
  -- stagioni
  select id into sid from public.seasons where name = 'Stagione corrente';
  assert (select points from public.faction_standings_v where season_id = sid and faction_id = ombre) = 6, 'M5: classifica della stagione corrente';
  assert (select points from public.faction_standings_v f join public.seasons s on s.id = f.season_id where s.name = 'Stagione passata' and f.faction_id = ombre) = 0, 'M5: storico stagione passata a zero';
  -- il punteggio non cambia se i membri cambiano fazione dopo
  perform pg_temp.as_('Andrea'); perform public.leave_faction();
  assert (select points from public.faction_standings_v where season_id is null and faction_id = ombre) = 6, 'M5: uscire non cancella i punti già guadagnati';
  assert pg_temp.err_as('Andrea', format('select public.join_faction(%L)', lupi)) like '%da poco%', 'M5: periodo di attesa dopo l''uscita';
  perform pg_temp.as_('Admin'); perform public.admin_faction_move_member(pg_temp.uid('Andrea'), lupi, 'caso eccezionale di prova');
  assert (select points from public.faction_standings_v where season_id is null and faction_id = ombre) = 6 and (select points from public.faction_standings_v where season_id is null and faction_id = lupi) = 3, 'M5: lo spostamento non riscrive il passato';
  perform pg_temp.mm(e, 5, 'Andrea', 'Giulia', 'Andrea');
  assert (select points from public.faction_standings_v where season_id is null and faction_id = lupi) = 6, 'M5: le nuove vittorie di Andrea contano per i Lupi';
  -- esclusione eccezionale di un match
  perform pg_temp.as_('Admin'); perform public.admin_faction_exclude_match(m_paolo_marco, 'risultato in revisione');
  assert (select points from public.faction_standings_v where season_id is null and faction_id = lupi) = 3, 'M5: match escluso dal punteggio';
  perform public.admin_faction_include_match(m_paolo_marco, 'revisione conclusa');
  assert (select points from public.faction_standings_v where season_id is null and faction_id = lupi) = 6, 'M5: match reintegrato';
  assert (select count(*) from public.audit_logs where action in ('exclude_match_from_factions','include_match_in_factions','move_faction_member')) = 3, 'M5: interventi admin nell''audit';
  assert pg_temp.err_as('Admin', format('select public.admin_faction_exclude_match(%L, ''x'')', m_marco)) like '%Motivazione%', 'M5: motivazione obbligatoria';
  -- guida
  assert pg_temp.err_as('Paolo', 'select public.leave_faction()') like '%cedere la guida%', 'M5: il capo non può abbandonare con membri a bordo';
  perform pg_temp.as_('Paolo'); perform public.transfer_faction_leadership(pg_temp.uid('Luca'));
  assert (select role from public.faction_members where user_id = pg_temp.uid('Luca') and left_at is null) = 'leader', 'M5: guida ceduta';
  perform public.leave_faction();
  perform pg_temp.as_('Luca'); perform public.kick_faction_member(pg_temp.uid('Andrea'));
  assert not exists (select 1 from public.faction_members where user_id = pg_temp.uid('Andrea') and left_at is null), 'M5: membro rimosso dal capo';
  -- scioglimento da parte dell'admin, con storico preservato
  perform pg_temp.as_('Admin'); perform public.admin_faction_disband(lupi, 'scioglimento di prova');
  assert (select status from public.factions where id = lupi) = 'disbanded' and not exists (select 1 from public.faction_members where faction_id = lupi and left_at is null), 'M5: fazione sciolta';
  assert (select points from public.faction_standings_v where season_id is null and faction_id = lupi) > 0, 'M5: la fazione sciolta resta nello storico con i suoi punti';
  assert (select count(*) from public.faction_members where faction_id = lupi) >= 3, 'M5: i periodi di appartenenza non si cancellano';
  -- integrità a livello di tabella
  assert pg_temp.err('insert into public.faction_members (faction_id, user_id) values (''' || ombre || ''', ''' || pg_temp.uid('Marco') || ''')') like '%faction_members_one_active%', 'M5: il DB impedisce due appartenenze attive';
  assert pg_temp.err('delete from public.faction_members') like '%Storico protetto%', 'M5: lo storico dei membri non si cancella';
  assert pg_temp.err('delete from public.factions') like '%Storico protetto%', 'M5: le fazioni non si cancellano';
  assert pg_temp.err_auth('Marco', 'update public.factions set name = ''Hack''') like '%permission denied%', 'M5: nessuna scrittura diretta';
  assert pg_temp.err_auth('Marco', 'insert into public.faction_match_exclusions (match_id, reason, excluded_by) values (gen_random_uuid(), ''abuso'', gen_random_uuid())') like '%permission denied%', 'M5: nessuna esclusione diretta';
  assert pg_temp.rows_as('Marco', 'select * from public.faction_match_exclusions') = 0, 'M5: le esclusioni le vede solo l''admin';
  assert pg_temp.rows_as('Marco', 'select * from public.faction_members_v') >= 1, 'M5: i membri attivi sono pubblici';
  insert into t_log (msg) values ('OK M5 — Faction Wars: regole di adesione, punteggio dai match verificati (una volta sola, storico stabile), BC intatti, interventi admin con audit, storico protetto');
end $$;

-- M6 — Underground Challenges: una sfida non è un risultato ufficiale
do $$
declare c uuid; c2 uuid; c3 uuid; e uuid; m uuid; money0 text; stats0 text; fac0 integer; req text := gen_random_uuid()::text; n integer;
begin
  perform pg_temp.as_('Marco');
  c := public.create_challenge(pg_temp.uid('Luca'), 'Ti aspetto nei sotterranei', req);
  assert public.create_challenge(pg_temp.uid('Luca'), 'Ti aspetto nei sotterranei', req) = c, 'M6: richiesta ripetuta = stessa sfida';
  assert (select count(*) from public.challenges where challenger_id = pg_temp.uid('Marco')) = 1, 'M6: una sola sfida creata';
  assert pg_temp.err_as('Marco', format('select public.create_challenge(%L, null, %L)', pg_temp.uid('Marco'), gen_random_uuid()::text)) like '%altro duellante%', 'M6: niente sfida a sé stessi';
  assert pg_temp.err_as('Luca', format('select public.create_challenge(%L, null, %L)', pg_temp.uid('Marco'), gen_random_uuid()::text)) like '%già una sfida aperta%', 'M6: niente sfida doppia tra gli stessi due';
  assert pg_temp.err_as('Marco', format('select public.create_challenge(%L, null, %L)', pg_temp.uid('Andrea'), 'corta')) like '%non valida%', 'M6: richiesta non valida';
  assert pg_temp.err_as('Andrea', format('select public.respond_challenge(%L, true)', c)) like '%non trovata%', 'M6: un terzo non può rispondere';
  assert pg_temp.err_as('Luca', format('select public.cancel_challenge(%L)', c)) like '%Solo chi ha lanciato%', 'M6: l''avversario non annulla prima di rispondere';
  -- accettare non genera nulla di ufficiale
  money0 := pg_temp.money(); n := (select count(*) from public.matches); stats0 := (select string_agg(player_id || ':' || wins || ':' || losses, ',' order by player_id) from public.hof_player_stats_v);
  fac0 := (select coalesce(sum(points), 0) from public.faction_standings_v);
  perform pg_temp.as_('Luca'); perform public.respond_challenge(c, true);
  assert (select status from public.challenges where id = c) = 'accepted', 'M6: sfida accettata';
  assert (select count(*) from public.matches) = n, 'M6: accettare non crea match';
  assert (select string_agg(player_id || ':' || wins || ':' || losses, ',' order by player_id) from public.hof_player_stats_v) = stats0, 'M6: accettare non crea vittorie nella Hall of Fame';
  assert (select coalesce(sum(points), 0) from public.faction_standings_v) = fac0, 'M6: accettare non crea punti fazione';
  assert pg_temp.money() = money0, 'M6: accettare non muove BC né riscossioni';
  -- collegamento del match
  assert pg_temp.err_as('Marco', format('select public.link_challenge_match(%L, gen_random_uuid())', c)) like '%Permessi insufficienti%', 'M6: solo organizzatori e admin collegano il match';
  update public.challenges set responded_at = responded_at - interval '1 hour' where id = c;   -- nel test tutto avviene in una transazione sola: simula il tempo trascorso
  e := pg_temp.ev('Sotterranei');
  m := pg_temp.mm(e, 1, 'Marco', 'Luca', null);
  perform pg_temp.as_('Org'); perform public.link_challenge_match(c, m);
  assert (select status from public.challenges where id = c) = 'in_progress' and (select match_id from public.challenges where id = c) = m, 'M6: sfida in corso con il match collegato';
  assert pg_temp.err_as('Org', format('select public.complete_challenge(%L)', c)) like '%prima verificato%', 'M6: non si completa senza il match verificato';
  assert (select match_status from public.challenges_v where id = c) = 'pending' and (select match_winner_id from public.challenges_v where id = c) is null, 'M6: nessun vincitore finché il match non è verificato';
  assert pg_temp.err_as('Org', format('select public.link_challenge_match(%L, %L)', c, m)) like '%deve essere accettata%', 'M6: non si ricollega';
  assert pg_temp.err_as('Marco', format('select public.cancel_challenge(%L)', c)) like '%non può più essere annullata%', 'M6: una sfida in corso non si annulla dai giocatori';
  -- verifica UFFICIALE con il processo esistente, poi conferma della sfida
  perform pg_temp.as_('Org'); perform public.verify_match(m, pg_temp.uid('Marco'));
  perform public.complete_challenge(c);
  assert (select status from public.challenges where id = c) = 'completed' and (select completed_by from public.challenges where id = c) = pg_temp.uid('Org'), 'M6: sfida completata dall''organizzatore';
  assert (select match_winner_id from public.challenges_v where id = c) = pg_temp.uid('Marco'), 'M6: il vincitore è letto dal match ufficiale';
  assert pg_temp.err_as('Org', format('select public.complete_challenge(%L)', c)) like '%non è in corso%', 'M6: nessun doppio completamento';
  assert pg_temp.err_as('Admin', format('select public.admin_cancel_challenge(%L, ''prova di annullamento'')', c)) like '%già chiusa%', 'M6: una sfida completata non si annulla';
  -- un match serve una sola sfida (vincolo del DB)
  perform pg_temp.as_('Marco'); c2 := public.create_challenge(pg_temp.uid('Luca'), null, gen_random_uuid()::text);
  perform pg_temp.as_('Luca'); perform public.respond_challenge(c2, true);
  assert pg_temp.err('update public.challenges set status = ''in_progress'', match_id = ''' || m || ''' where id = ''' || c2 || '''') like '%challenges_match_id_key%', 'M6: il DB impedisce di collegare lo stesso match a due sfide';
  -- rifiuto, annullamento e scadenza
  perform pg_temp.as_('Luca'); perform public.cancel_challenge(c2);
  assert (select status from public.challenges where id = c2) = 'cancelled', 'M6: annullata da un partecipante dopo l''accettazione';
  perform pg_temp.as_('Andrea'); c3 := public.create_challenge(pg_temp.uid('Giulia'), null, gen_random_uuid()::text);
  perform pg_temp.as_('Giulia'); perform public.respond_challenge(c3, false);
  assert (select status from public.challenges where id = c3) = 'declined', 'M6: rifiutata';
  assert pg_temp.err_as('Giulia', format('select public.respond_challenge(%L, true)', c3)) like '%non è più in attesa%', 'M6: non si cambia idea dopo il rifiuto';
  perform pg_temp.as_('Andrea'); c3 := public.create_challenge(pg_temp.uid('Giulia'), null, gen_random_uuid()::text);   -- dopo il rifiuto si può riprovare
  update public.challenges set expires_at = now() - interval '1 minute' where id = c3;
  assert pg_temp.err_as('Giulia', format('select public.respond_challenge(%L, true)', c3)) like '%scaduta%', 'M6: non si accetta una sfida scaduta';
  perform pg_temp.as_('Giulia'); assert public.expire_challenges() = 1, 'M6: la scadenza chiude le sfide in attesa';
  assert (select status from public.challenges where id = c3) = 'expired', 'M6: stato scaduta';
  -- limite di sfide aperte
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('challenge_max_open', 1, 'prova del limite sfide');
  perform pg_temp.as_('Povero'); perform public.create_challenge(pg_temp.uid('Marco'), null, gen_random_uuid()::text);
  assert pg_temp.err_as('Povero', format('select public.create_challenge(%L, null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%troppe sfide%', 'M6: limite di sfide aperte';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('challenge_max_open', 5, 'ripristino dopo la prova');
  -- moderazione admin
  perform pg_temp.as_('Admin'); perform public.admin_cancel_challenge((select id from public.challenges where challenger_id = pg_temp.uid('Povero')), 'moderazione di prova');
  assert (select status from public.challenges where challenger_id = pg_temp.uid('Povero')) = 'cancelled', 'M6: moderazione admin';
  assert (select count(*) from public.audit_logs where action in ('create_challenge','accept_challenge','decline_challenge','cancel_challenge','link_challenge_match','complete_challenge','admin_cancel_challenge')) >= 9, 'M6: tutto nell''audit';
  -- sicurezza diretta
  assert pg_temp.err_auth('Marco', 'insert into public.challenges (challenger_id, opponent_id, client_request_id, expires_at) values (gen_random_uuid(), gen_random_uuid(), ''x'', now())') like '%permission denied%', 'M6: nessuna scrittura diretta';
  assert pg_temp.err_auth('Marco', 'update public.challenges set status = ''completed''') like '%permission denied%', 'M6: nessuna modifica diretta';
  assert pg_temp.err('delete from public.challenges') like '%Storico protetto%', 'M6: lo storico delle sfide non si cancella';
  insert into t_log (msg) values ('OK M6 — Underground: stati e scadenze, risposta solo dell''avversario, match collegato, completamento solo dopo verify_match; nessun risultato, punto, BC o riscossione generato dalla sfida');
end $$;

-- M7 — Interruttori indipendenti e Most Wanted/Black Market intatti
do $$
declare t uuid; before_n integer; m uuid;
begin
  -- spegnere un solo modulo non ferma gli altri
  perform pg_temp.mod('hall_of_fame', false);
  assert (select count(*) from public.hof_player_stats_v) = 0 and (select count(*) from public.hof_matches_v) = 0, 'M7: Hall of Fame spenta = vuota';
  assert (select count(*) from public.faction_standings_v) > 0 and (select count(*) from public.challenges_v) > 0, 'M7: gli altri moduli continuano a funzionare';
  assert pg_temp.rows_as('Marco', 'select * from public.hof_matches_v') = 0, 'M7: nemmeno via API diretta si legge la Hall of Fame spenta';
  perform pg_temp.mod('hall_of_fame', true);
  -- spegnere Faction Wars: dati nascosti ai non admin, visibili all'admin, scritture bloccate
  perform pg_temp.mod('faction_wars', false);
  assert pg_temp.rows_as('Marco', 'select * from public.factions') = 0 and pg_temp.rows_as('Marco', 'select * from public.faction_members') = 0, 'M7: tabelle fazioni nascoste agli utenti con il modulo spento';
  assert pg_temp.rows_as('Admin', 'select * from public.factions') >= 2, 'M7: l''admin le vede comunque (per gestirle)';
  assert pg_temp.err_as('Luca', 'select public.leave_faction()') like '%Modulo non attivo%', 'M7: scritture bloccate con il modulo spento';
  perform pg_temp.mod('faction_wars', true);
  -- spegnere Underground
  perform pg_temp.mod('underground', false);
  assert pg_temp.rows_as('Marco', 'select * from public.challenges') = 0 and pg_temp.rows_as('Marco', 'select * from public.challenges_v') = 0, 'M7: sfide nascoste con il modulo spento';
  assert pg_temp.err_as('Marco', format('select public.create_challenge(%L, null, %L)', pg_temp.uid('Andrea'), gen_random_uuid()::text)) like '%Modulo non attivo%', 'M7: create_challenge bloccata';
  perform pg_temp.mod('underground', true);
  -- tutti spenti: Most Wanted e Black Market funzionano come prima
  perform pg_temp.mod('hall_of_fame', false); perform pg_temp.mod('faction_wars', false); perform pg_temp.mod('underground', false);
  perform pg_temp.as_('Giulia'); perform public.create_bounty(pg_temp.uid('Povero'), 50, 'taglia a moduli spenti', gen_random_uuid()::text);
  assert (select bounty_value from public.most_wanted_v where id = pg_temp.uid('Povero')) = 50, 'M7: Most Wanted aggiornato a moduli spenti';
  assert pg_temp.rows_as('Marco', 'select * from public.most_wanted_v') >= 1, 'M7: Most Wanted leggibile';
  m := pg_temp.mm(pg_temp.ev('Evento a moduli spenti'), 1, 'Paolo', 'Povero', 'Paolo');
  perform pg_temp.as_('Paolo'); assert (public.claim_bounty(m)->>'payout')::integer = 50, 'M7: riscossione a moduli spenti';
  perform pg_temp.as_('Admin'); assert (select bool_and(ok) from public.wallet_reconciliation_v), 'M7: i saldi coincidono con il registro';
  insert into t_log (msg) values ('OK M7 — ogni interruttore agisce da solo; con tutti spenti Most Wanted, taglie e riscossioni funzionano come prima e i saldi quadrano');
end $$;

-- M8 — Permessi del database: nessun accesso anonimo, nessuna scrittura diretta
do $$
declare t text; f text;
begin
  foreach t in array array['seasons','factions','faction_members','faction_match_exclusions','challenges',
     'hof_matches_v','hof_player_stats_v','hof_season_stats_v','hof_claims_v','hof_rivalries_v','hof_events_v','hof_milestones_v','hof_records_v',
     'faction_scored_matches_v','faction_standings_v','faction_members_v','challenges_v'] loop
    assert not has_table_privilege('anon', 'public.' || t, 'select'), 'M8: anon non deve leggere ' || t;
    assert not has_table_privilege('authenticated', 'public.' || t, 'insert') and not has_table_privilege('authenticated', 'public.' || t, 'update')
       and not has_table_privilege('authenticated', 'public.' || t, 'delete'), 'M8: authenticated non deve scrivere ' || t;
    assert has_table_privilege('authenticated', 'public.' || t, 'select'), 'M8: authenticated legge ' || t;
  end loop;
  foreach f in array array['admin_set_module(text,boolean,text)','admin_create_season(text,date,date,text)','create_faction(text,text,text)','join_faction(uuid)',
     'leave_faction()','transfer_faction_leadership(uuid)','kick_faction_member(uuid)','update_faction(text,text)','admin_faction_disband(uuid,text)',
     'admin_faction_rename(uuid,text,text)','admin_faction_move_member(uuid,uuid,text)','admin_faction_exclude_match(uuid,text)','admin_faction_include_match(uuid,text)',
     'expire_challenges()','create_challenge(uuid,text,text)','respond_challenge(uuid,boolean)','cancel_challenge(uuid)','link_challenge_match(uuid,uuid)',
     'complete_challenge(uuid)','admin_cancel_challenge(uuid,text)'] loop
    assert not has_function_privilege('anon', 'public.' || f, 'execute'), 'M8: anon non deve eseguire ' || f;
    assert has_function_privilege('authenticated', 'public.' || f, 'execute'), 'M8: authenticated esegue ' || f;
  end loop;
  assert not has_function_privilege('authenticated', 'public._require_module(text)', 'execute'), 'M8: _require_module è interna';
  assert (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) = 0, 'M8: RLS attiva su tutte le tabelle';
  insert into t_log (msg) values ('OK M8 — nessun accesso per anon, nessuna scrittura diretta per authenticated, RLS su tutte le tabelle, funzioni interne non esposte');
end $$;

-- M9 — Il registro contabile e i saldi non sono stati toccati dai moduli
do $$
begin
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'M9: ogni saldo coincide con il registro';
  assert (select count(*) from public.audit_logs where action in ('set_module','create_faction','create_season','create_challenge','complete_challenge')) >= 10, 'M9: audit dei moduli';
  assert not exists (select 1 from public.audit_logs where new_value::text ilike '%password%' or new_value::text ilike '%token%' or old_value::text ilike '%token%'), 'M9: nessun segreto nell''audit';
  insert into t_log (msg) values ('OK M9 — saldi e registro coerenti, audit dei moduli presente e senza segreti');
end $$;

select n, msg from t_log order by n;
rollback;
