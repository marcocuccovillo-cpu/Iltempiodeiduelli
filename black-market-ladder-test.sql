-- =====================================================================
-- TEST DELLA MIGRAZIONE 003 (Ladder Elo e avatar)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-setup.sql, black-market-moduli.sql e black-market-ladder.sql.
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

-- Preparazione: utenti (il primo registrato diventa amministratore)
do $$
declare n text;
begin
  foreach n in array array['Admin','Marco','Luca','Paolo','Povero'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  assert (select role from public.profiles where id = pg_temp.uid('Admin')) = 'admin', 'prep: il primo utente deve essere admin';
  insert into t_log (msg) values ('OK Preparazione: 5 utenti, Admin = primo registrato');
end $$;
create function pg_temp.chal(a text, b text, fmt text default 'Advanced') returns uuid language plpgsql as $$
begin perform pg_temp.as_(a); return public.ladder_challenge(pg_temp.uid(b), fmt, null, gen_random_uuid()::text); end $$;
create function pg_temp.play(a text, b text, result text, score text, reporter text) returns jsonb language plpgsql as $$
declare id uuid; other text; r jsonb;
begin
  id := pg_temp.chal(a, b);
  perform pg_temp.as_(b); perform public.ladder_respond(id, true);
  perform pg_temp.as_(reporter); perform public.ladder_report(id, result, score);
  other := case when reporter = a then b else a end;
  perform pg_temp.as_(other); r := public.ladder_confirm(id);
  return r;
end $$;
create function pg_temp.elo(n text) returns integer language sql as $$ select elo from public.ladder_ratings where user_id = pg_temp.uid(n) $$;

-- L1 — Ladder attiva per impostazione iniziale; avatar
do $$
declare img text := 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==';
begin
  assert public._module_on('ladder'), 'L1: la Ladder è attiva di default';
  perform pg_temp.as_('Marco'); perform public.set_my_avatar_img(img);
  assert (select avatar_img from public.profiles where id = pg_temp.uid('Marco')) = img, 'L1: avatar salvato';
  assert (select avatar_img from public.profiles where id = pg_temp.uid('Luca')) is null, 'L1: gli altri profili non cambiano';
  assert pg_temp.err_as('Marco', 'select public.set_my_avatar_img(''http://evil.example/x.png'')') like '%Formato immagine non valido%', 'L1: solo immagini incorporate';
  assert pg_temp.err_as('Marco', 'select public.set_my_avatar_img(''data:text/html;base64,PHNjcmlwdD4='')') like '%Formato immagine non valido%', 'L1: niente HTML camuffato';
  assert pg_temp.err_as('Marco', 'select public.set_my_avatar_img(''data:image/jpeg;base64,'' || repeat(''A'', 30000))') like '%troppo grande%', 'L1: limite di dimensione';
  assert pg_temp.err_auth('Marco', 'update public.profiles set avatar_img = ''data:image/png;base64,AAAA'' where id = ''' || pg_temp.uid('Luca') || '''') like '%permission denied%', 'L1: nessuna scrittura diretta sui profili';
  perform pg_temp.as_('Marco'); perform public.set_my_avatar_img(null);
  assert (select avatar_img from public.profiles where id = pg_temp.uid('Marco')) is null, 'L1: avatar rimosso';
  insert into t_log (msg) values ('OK L1 — Ladder attiva di default; avatar: valido salvato, URL esterni/HTML/troppo grande rifiutati, nessuna scrittura diretta');
end $$;

-- L2 — Elo: calcolo, conferma dell'altro giocatore, un solo conteggio
do $$
declare c uuid; r jsonb; money0 text; offi bigint;
begin
  money0 := pg_temp.money(); offi := (select count(*) from public.matches);
  c := pg_temp.chal('Marco', 'Luca');
  assert pg_temp.err_as('Marco', format('select public.ladder_report(%L, ''challenger'', ''2-0'')', c)) like '%accettato%', 'L2: niente risultato prima dell''accettazione';
  assert pg_temp.err_as('Marco', format('select public.ladder_respond(%L, true)', c)) like '%non trovata%', 'L2: chi sfida non accetta da solo';
  assert pg_temp.err_as('Paolo', format('select public.ladder_respond(%L, true)', c)) like '%non trovata%', 'L2: un terzo non risponde';
  perform pg_temp.as_('Luca'); perform public.ladder_respond(c, true);
  assert pg_temp.err_as('Paolo', format('select public.ladder_report(%L, ''challenger'', ''2-0'')', c)) like '%non trovato%', 'L2: un terzo non riporta';
  assert pg_temp.err_as('Marco', format('select public.ladder_report(%L, ''challenger'', ''0-2'')', c)) like '%non corrisponde%', 'L2: punteggio incoerente';
  assert pg_temp.err_as('Marco', format('select public.ladder_report(%L, ''boh'', ''2-0'')', c)) like '%non valido%', 'L2: esito non valido';
  perform pg_temp.as_('Marco'); perform public.ladder_report(c, 'challenger', '2-0');
  assert pg_temp.err_as('Marco', format('select public.ladder_confirm(%L)', c)) like '%dall''altro giocatore%', 'L2: chi riporta non conferma';
  assert pg_temp.err_as('Paolo', format('select public.ladder_confirm(%L)', c)) like '%non trovato%', 'L2: un terzo non conferma';
  assert not exists (select 1 from public.ladder_ratings), 'L2: nessun Elo prima della conferma';
  perform pg_temp.as_('Luca'); r := public.ladder_confirm(c);
  assert (r->>'challenger_delta')::int = 16 and (r->>'opponent_delta')::int = -16, 'L2: +16/-16 a parità di Elo (K=32)';
  assert pg_temp.elo('Marco') = 1016 and pg_temp.elo('Luca') = 984, 'L2: Elo 1016 / 984';
  assert (select wins from public.ladder_ratings where user_id = pg_temp.uid('Marco')) = 1 and (select losses from public.ladder_ratings where user_id = pg_temp.uid('Luca')) = 1, 'L2: V/S';
  assert pg_temp.err_as('Luca', format('select public.ladder_confirm(%L)', c)) like '%Non c''è un risultato%', 'L2: nessuna doppia conferma';
  assert pg_temp.elo('Marco') = 1016 and pg_temp.elo('Luca') = 984, 'L2: Elo invariato dopo il tentativo di doppia conferma';
  r := pg_temp.play('Paolo', 'Marco', 'challenger', '2-1', 'Marco');
  assert (r->>'challenger_delta')::int = 17 and pg_temp.elo('Paolo') = 1017 and pg_temp.elo('Marco') = 999, 'L2: chi batte il favorito guadagna di più (17)';
  r := pg_temp.play('Luca', 'Paolo', 'draw', '1-1', 'Paolo');
  assert (r->>'challenger_delta')::int > 0 and (r->>'opponent_delta')::int < 0, 'L2: nel pareggio guadagna chi ha l''Elo più basso';
  assert (select sum(draws) from public.ladder_ratings) = 2 and (select sum(elo) from public.ladder_ratings) = 3000, 'L2: Elo totale costante (3 giocatori x 1000)';
  assert pg_temp.money() = money0, 'L2: la Ladder non muove BC, registro, taglie o riscossioni';
  assert (select count(*) from public.matches) = offi, 'L2: nessun match ufficiale WPA creato';
  assert (select count(*) from public.ladder_standings_v) = 3 and (select rank from public.ladder_standings_v where user_id = pg_temp.uid('Paolo')) = 1, 'L2: classifica: solo chi ha giocato, Paolo primo';
  insert into t_log (msg) values ('OK L2 — Elo corretto (16/17), conferma solo dell''altro giocatore, mai contato due volte, pareggio, Elo totale costante, BC e match ufficiali intatti');
end $$;

-- L3 — Contestazione e risoluzione dell'amministratore
do $$
declare c uuid; c2 uuid; e0 integer; r jsonb;
begin
  c := pg_temp.chal('Marco', 'Povero');
  perform pg_temp.as_('Povero'); perform public.ladder_respond(c, true);
  perform pg_temp.as_('Marco'); perform public.ladder_report(c, 'challenger', '2-0');
  assert pg_temp.err_as('Marco', format('select public.ladder_dispute(%L, %L)', c, 'non sono d accordo')) like '%Hai inviato tu%', 'L3: chi riporta non contesta';
  assert pg_temp.err_as('Povero', format('select public.ladder_dispute(%L, ''x'')', c)) like '%almeno 5%', 'L3: motivo obbligatorio';
  perform pg_temp.as_('Povero'); perform public.ladder_dispute(c, 'Ho vinto io, 2-1 per me');
  assert (select status from public.ladder_matches where id = c) = 'disputed', 'L3: contestato';
  assert pg_temp.err_as('Povero', format('select public.ladder_confirm(%L)', c)) like '%Non c''è un risultato%', 'L3: un match contestato non si conferma';
  assert pg_temp.err_as('Marco', format('select public.admin_ladder_resolve(%L, ''opponent'', ''1-2'', ''risolto dall amministratore'')', c)) like '%Permessi insufficienti%', 'L3: solo l''admin risolve';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_resolve(%L, ''opponent'', ''1-2'', ''x'')', c)) like '%Motivazione%', 'L3: motivazione obbligatoria';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_resolve(%L, ''opponent'', ''2-0'', ''punteggio sbagliato di prova'')', c)) like '%non validi%', 'L3: punteggio incoerente rifiutato';
  e0 := pg_temp.elo('Marco');
  perform pg_temp.as_('Admin'); r := public.admin_ladder_resolve(c, 'opponent', '1-2', 'verificato con i due giocatori di persona');
  assert (select status from public.ladder_matches where id = c) = 'closed' and (select resolved_by from public.ladder_matches where id = c) = pg_temp.uid('Admin'), 'L3: chiuso dall''admin';
  assert pg_temp.elo('Marco') < e0 and pg_temp.elo('Povero') > 1000, 'L3: Elo aggiornato secondo la decisione dell''admin';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_resolve(%L, ''challenger'', ''2-0'', ''secondo tentativo di prova'')', c)) like '%non è risolvibile%', 'L3: nessuna seconda risoluzione';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_void(%L, ''annullamento di prova'')', c)) like '%già concluso%', 'L3: un match chiuso non si annulla';
  c2 := pg_temp.chal('Luca', 'Povero');
  assert pg_temp.err_as('Marco', format('select public.admin_ladder_void(%L, ''annullamento di prova'')', c2)) like '%Permessi insufficienti%', 'L3: solo l''admin annulla d''ufficio';
  e0 := (select sum(elo) from public.ladder_ratings);
  perform pg_temp.as_('Admin'); perform public.admin_ladder_void(c2, 'sfida abbandonata di prova');
  assert (select status from public.ladder_matches where id = c2) = 'voided' and (select sum(elo) from public.ladder_ratings) = e0, 'L3: annullata senza toccare l''Elo';
  assert (select count(*) from public.audit_logs where action in ('ladder_dispute','admin_ladder_resolve','admin_ladder_void')) = 3, 'L3: audit completo';
  insert into t_log (msg) values ('OK L3 — contestazione, risoluzione e annullamento solo da admin, con motivazione e audit; Elo coerente');
end $$;

-- L4 — Duplicati, limiti, scadenze, annullamento
do $$
declare req text := gen_random_uuid()::text; c uuid; c1 uuid;
begin
  perform pg_temp.as_('Luca');
  c := public.ladder_challenge(pg_temp.uid('Paolo'), 'GOAT', 'Rivincita?', req);
  assert public.ladder_challenge(pg_temp.uid('Paolo'), 'GOAT', 'Rivincita?', req) = c, 'L4: richiesta ripetuta = stessa sfida';
  assert pg_temp.err_as('Luca', format('select public.ladder_challenge(%L, ''GOAT'', null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%altro duellante%', 'L4: niente sfida a sé stessi';
  assert pg_temp.err_as('Paolo', format('select public.ladder_challenge(%L, ''GOAT'', null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%già una sfida aperta%', 'L4: una sola sfida aperta per coppia (anche al contrario)';
  assert pg_temp.err_as('Luca', format('select public.ladder_challenge(%L, ''Pippo'', null, %L)', pg_temp.uid('Marco'), gen_random_uuid()::text)) like '%Formato non valido%', 'L4: formato non valido';
  assert pg_temp.err_as('Luca', format('select public.ladder_challenge(%L, ''GOAT'', null, ''corta'')', pg_temp.uid('Marco'))) like '%Richiesta non valida%', 'L4: richiesta non valida';
  assert pg_temp.err_as('Luca', format('select public.ladder_cancel(%L)', c)) is null, 'L4: chi ha sfidato annulla la sfida in attesa';
  assert (select status from public.ladder_matches where id = c) = 'cancelled', 'L4: annullata';
  c := pg_temp.chal('Luca', 'Marco'); perform pg_temp.as_('Marco'); perform public.ladder_respond(c, false);
  assert (select status from public.ladder_matches where id = c) = 'declined', 'L4: rifiutata';
  assert pg_temp.err_as('Marco', format('select public.ladder_respond(%L, true)', c)) like '%non è più in attesa%', 'L4: non si cambia idea';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('ladder_max_open', 1, 'prova limite sfide aperte');
  c1 := pg_temp.chal('Povero', 'Luca');
  assert pg_temp.err_as('Povero', format('select public.ladder_challenge(%L, ''Advanced'', null, %L)', pg_temp.uid('Marco'), gen_random_uuid()::text)) like '%troppe sfide%', 'L4: limite di sfide aperte';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('ladder_max_open', 5, 'ripristino dopo la prova');
  update public.ladder_matches set expires_at = now() - interval '1 minute' where id = c1;
  assert pg_temp.err_as('Luca', format('select public.ladder_respond(%L, true)', c1)) like '%scaduta%', 'L4: non si accetta una sfida scaduta';
  perform pg_temp.as_('Luca'); assert public.ladder_expire() = 1, 'L4: la scadenza chiude le sfide';
  assert (select status from public.ladder_matches where id = c1) = 'expired', 'L4: scaduta';
  c := pg_temp.chal('Marco', 'Povero'); perform pg_temp.as_('Povero'); perform public.ladder_respond(c, true);
  update public.ladder_matches set responded_at = now() - interval '40 days' where id = c;
  perform pg_temp.as_('Luca'); assert public.ladder_expire() = 1, 'L4: una sfida accettata e mai giocata scade dopo 30 giorni';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('ladder_max_pair_per_day', 1, 'prova limite giornaliero');
  perform pg_temp.play('Luca', 'Povero', 'challenger', '2-0', 'Luca');
  assert pg_temp.err_as('Povero', format('select public.ladder_challenge(%L, ''Advanced'', null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%Limite giornaliero%', 'L4: limite di match al giorno tra la stessa coppia';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('ladder_max_pair_per_day', 3, 'ripristino dopo la prova');
  c := pg_temp.chal('Paolo', 'Luca'); perform pg_temp.as_('Luca'); perform public.ladder_respond(c, true);
  perform pg_temp.as_('Paolo'); perform public.ladder_report(c, 'draw', '1-1');
  assert pg_temp.err_as('Paolo', format('select public.ladder_cancel(%L)', c)) like '%non può più essere annullata%', 'L4: dopo il risultato non si annulla';
  perform pg_temp.as_('Luca'); perform public.ladder_confirm(c);
  insert into t_log (msg) values ('OK L4 — idempotenza, coppia unica, formati, limiti (aperte e giornaliero), scadenze, rifiuto/annullamento');
end $$;

-- L5 — Classifica: ordine e dati reali
do $$
begin
  perform pg_temp.as_('Povero');
  assert (select count(*) from public.ladder_standings_v) = (select count(*) from public.ladder_ratings), 'L5: solo chi ha giocato';
  assert not exists (select 1 from public.ladder_standings_v s where s.matches <> s.wins + s.draws + s.losses), 'L5: partite = V+P+S';
  assert (select count(*) from public.ladder_standings_v where user_id = pg_temp.uid('Admin')) = 0, 'L5: chi non ha mai giocato non è in classifica';
  assert (select array_agg(user_id order by rank, user_id) from public.ladder_standings_v) = (select array_agg(user_id order by elo desc, wins desc, user_id) from public.ladder_ratings), 'L5: ordinata per Elo';
  assert (select sum(wins) from public.ladder_ratings) = (select sum(losses) from public.ladder_ratings), 'L5: vittorie e sconfitte combaciano';
  assert (select sum(elo) - 1000 * count(*) from public.ladder_ratings) = 0, 'L5: nessun Elo creato dal nulla';
  insert into t_log (msg) values ('OK L5 — classifica coerente con i match chiusi; nessun Elo inventato');
end $$;

-- L6 — Visibilità, permessi e interruttore
do $$
declare c uuid;
begin
  c := pg_temp.chal('Marco', 'Luca');
  assert pg_temp.rows_as('Povero', format('select * from public.ladder_matches where id = %L', c)) = 0, 'L6: una sfida in corso la vedono solo i due giocatori';
  assert pg_temp.rows_as('Luca', format('select * from public.ladder_matches where id = %L', c)) = 1 and pg_temp.rows_as('Marco', format('select * from public.ladder_matches where id = %L', c)) = 1, 'L6: i due giocatori la vedono';
  assert pg_temp.rows_as('Admin', format('select * from public.ladder_matches where id = %L', c)) = 1, 'L6: l''admin la vede';
  assert pg_temp.rows_as('Povero', 'select * from public.ladder_matches where status = ''closed''') >= 3, 'L6: lo storico dei match chiusi è pubblico';
  assert pg_temp.err_auth('Marco', 'update public.ladder_ratings set elo = 4000') like '%permission denied%', 'L6: nessuna modifica diretta dell''Elo';
  assert pg_temp.err_auth('Marco', 'insert into public.ladder_matches (challenger_id, opponent_id, format, client_request_id, expires_at) values (gen_random_uuid(), gen_random_uuid(), ''GOAT'', ''xxxxxxxxxx'', now())') like '%permission denied%', 'L6: nessuna scrittura diretta sui match';
  assert pg_temp.err_auth('Marco', 'update public.ladder_matches set status = ''closed''') like '%permission denied%', 'L6: nessuna modifica diretta dello stato';
  assert pg_temp.err('delete from public.ladder_matches') like '%Storico protetto%' and pg_temp.err('delete from public.ladder_ratings') like '%Storico protetto%', 'L6: lo storico non si cancella';
  assert pg_temp.err('update public.ladder_matches set client_request_id = ''modificato-di-prova'' where status = ''closed''') like '%già concluso%', 'L6: un match chiuso non si modifica nemmeno dal proprietario';
  assert pg_temp.err_as('Marco', 'select public.admin_set_module(''ladder'', false, ''prova non autorizzata'')') like '%Permessi insufficienti%', 'L6: solo l''admin spegne la Ladder';
  perform pg_temp.mod('ladder', false);
  assert (select count(*) from public.ladder_standings_v) = 0, 'L6: a Ladder spenta la classifica è vuota';
  assert pg_temp.rows_as('Marco', 'select * from public.ladder_matches') = 0 and pg_temp.rows_as('Marco', 'select * from public.ladder_ratings') = 0, 'L6: a Ladder spenta i dati sono nascosti agli utenti';
  assert pg_temp.rows_as('Admin', 'select * from public.ladder_matches') >= 5, 'L6: l''admin li vede comunque';
  assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, ''GOAT'', null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%Modulo non attivo%', 'L6: sfida bloccata a modulo spento';
  assert pg_temp.err_as('Luca', format('select public.ladder_respond(%L, true)', c)) like '%Modulo non attivo%', 'L6: risposta bloccata';
  assert pg_temp.err_as('Luca', format('select public.ladder_report(%L, ''draw'', ''1-1'')', c)) like '%Modulo non attivo%', 'L6: risultato bloccato';
  assert pg_temp.err_as('Luca', format('select public.ladder_confirm(%L)', c)) like '%Modulo non attivo%', 'L6: conferma bloccata';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_void(%L, ''prova a modulo spento'')', c)) like '%Modulo non attivo%', 'L6: anche le funzioni admin sono bloccate';
  perform pg_temp.as_('Luca'); perform public.create_bounty(pg_temp.uid('Povero'), 60, null, gen_random_uuid()::text);
  assert (select bounty_value from public.most_wanted_v where id = pg_temp.uid('Povero')) = 60, 'L6: Most Wanted funziona a Ladder spenta';
  assert pg_temp.err_as('Admin', 'select public.admin_set_module(''ladder'', true, ''riattivazione di prova'')') is null, 'L6: riattivazione riuscita';
  assert public._module_on('ladder'), 'L6: riaccesa dall''admin';
  assert (select count(*) from public.audit_logs where action = 'set_module' and entity_id = 'ladder') = 2, 'L6: audit degli interruttori';
  insert into t_log (msg) values ('OK L6 — visibilità, nessuna scrittura diretta, storico protetto, interruttore server-side (a modulo spento ogni operazione è rifiutata), Black Market intatto');
end $$;

-- L7 — Permessi del database
do $$
declare t text; f text;
begin
  foreach t in array array['ladder_ratings','ladder_matches','ladder_standings_v'] loop
    assert not has_table_privilege('anon', 'public.' || t, 'select'), 'L7: anon non legge ' || t;
    assert has_table_privilege('authenticated', 'public.' || t, 'select'), 'L7: authenticated legge ' || t;
    assert not (has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update') or has_table_privilege('authenticated', 'public.' || t, 'delete')), 'L7: authenticated non scrive ' || t;
  end loop;
  foreach f in array array['set_my_avatar_img(text)','ladder_expire()','ladder_challenge(uuid,text,text,text)','ladder_respond(uuid,boolean)','ladder_cancel(uuid)','ladder_report(uuid,text,text)','ladder_confirm(uuid)','ladder_dispute(uuid,text)','admin_ladder_resolve(uuid,text,text,text)','admin_ladder_void(uuid,text)'] loop
    assert not has_function_privilege('anon', 'public.' || f, 'execute'), 'L7: anon non esegue ' || f;
    assert has_function_privilege('authenticated', 'public.' || f, 'execute'), 'L7: authenticated esegue ' || f;
  end loop;
  assert not has_function_privilege('authenticated', 'public._ladder_close(uuid,text,text,uuid,uuid,text)', 'execute'), 'L7: _ladder_close è interna';
  assert (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) = 0, 'L7: RLS su tutte le tabelle';
  insert into t_log (msg) values ('OK L7 — permessi del database coerenti: nessun accesso anonimo, nessuna scrittura diretta, funzioni interne non esposte, RLS ovunque');
end $$;

-- L8 — Il Black Market è intatto
do $$
begin
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'L8: ogni saldo coincide con il registro';
  assert (select count(*) from public.ledger_entries where kind not in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment')) = 0, 'L8: nessun nuovo tipo di movimento economico';
  assert (select count(*) from public.bounty_settlements) = 0, 'L8: nessuna riscossione generata dalla Ladder';
  insert into t_log (msg) values ('OK L8 — saldi e registro coerenti; la Ladder non genera movimenti, riscossioni o match ufficiali');
end $$;

select n, msg from t_log order by n;
rollback;
