-- =====================================================================
-- TEST DELLA MIGRAZIONE 018 (correzione dei risultati Ladder già conclusi)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…018 (black-market-setup.sql … black-market-ladder-correzioni.sql).
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

-- Preparazione: utenti (il primo registrato diventa amministratore); Org è organizzatore
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Marco','Luca','Paolo','Povero'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  insert into t_log (msg) values ('OK Preparazione: 6 utenti, Admin = primo registrato, Org organizzatore');
end $$;
create function pg_temp.set_(k text, v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting(k, v, 'impostazione di prova'); end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.tot() returns bigint language sql as $$ select coalesce(sum(balance), 0) from public.wallets $$;
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
create function pg_temp.bnt(c text, t text, amt integer) returns uuid language plpgsql as $$
begin perform pg_temp.as_(c); return public.create_bounty(pg_temp.uid(t), amt, null, gen_random_uuid()::text); end $$;
create function pg_temp.nn(u text, k text default null) returns bigint language sql as $$
  select count(*) from public.notifications where user_id = pg_temp.uid(u) and (k is null or kind = k) $$;
create function pg_temp.prefs(u text, b boolean, l boolean, h boolean) returns void language plpgsql as $$
begin perform pg_temp.as_(u); perform public.notif_set_prefs(b, l, h); end $$;
-- Aiuti specifici: lancio di una sfida (restituisce l'id), chiusura completa, impostazioni
create function pg_temp.cc(a text, b text, fmt text, kind text default null) returns uuid language plpgsql as $$
begin perform pg_temp.as_(a); return public.ladder_challenge(pg_temp.uid(b), fmt, null, gen_random_uuid()::text, kind); end $$;
-- accetta (lo sfidato), invia il risultato (lo sfidante) e conferma (lo sfidato): result = challenger|opponent|draw
create function pg_temp.fin(id uuid, a text, b text, result text, score text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_(b); perform public.ladder_respond(id, true);
  perform pg_temp.as_(a); perform public.ladder_report(id, result, score);
  perform pg_temp.as_(b); return public.ladder_confirm(id);
end $$;
create function pg_temp.elo(u text, f text) returns integer language sql as $$ select elo from public.ladder_ratings where user_id = pg_temp.uid(u) and format = f $$;
create function pg_temp.claim(u text, m uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(u); return public.claim_bounty(m); end $$;
create function pg_temp.act_b(t text) returns integer language sql as $$ select count(*)::integer from public.bounties where target_id = pg_temp.uid(t) and status = 'active' $$;

-- Impostazioni larghe (i limiti giornalieri hanno i loro test nelle migrazioni 003/004); hold anti-accordi a 0 finché non lo proviamo
do $$ begin
  perform pg_temp.set_('ladder_max_pair_per_day', 50);
  perform pg_temp.set_('ladder_reward_max_day', 50);
  perform pg_temp.set_('ladder_reward_pair_day', 50);
  perform pg_temp.set_('ladder_max_open', 50);
  perform pg_temp.set_('ladder_claim_hold_hours', 0);
  perform pg_temp.set_('ladder_wpa_pair_day', 50);
  assert public._setting('ladder_wpa_pair_day') = 50, 'impostazioni';
end $$;


-- Aiuti: ruoli, istantanee, rigioco indipendente dell'Elo
do $$ begin perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Povero'), 'moderator', 'moderatore di prova'); end $$;
create temp table rp (u uuid primary key, e integer, w integer, d integer, l integer);
-- rigioca in ordine i match chiusi del formato (scritto a parte rispetto al database); se ov è dato, quel match ha l'esito ovr
create function pg_temp.replay(fmt text, ov uuid default null, ovr text default null) returns void language plpgsql as $$
declare m record; ea integer; eo integer; da integer; s numeric; res text; k integer := public._setting('ladder_k'); st integer := public._setting('ladder_start_elo');
begin
  delete from rp;
  for m in select * from public.ladder_matches where status = 'closed' and format = fmt and kind in ('ladder','both') order by closed_at, id loop
    insert into rp values (m.challenger_id, st, 0, 0, 0), (m.opponent_id, st, 0, 0, 0) on conflict do nothing;
    res := case when m.id = ov then ovr else m.reported_result end;
    select e into ea from rp where u = m.challenger_id; select e into eo from rp where u = m.opponent_id;
    s := case res when 'challenger' then 1 when 'opponent' then 0 else 0.5 end;
    da := round(k * (s - 1 / (1 + power(10, (eo - ea)::numeric / 400))))::integer;
    update rp set e = greatest(0, e + da), w = w + (res = 'challenger')::integer, d = d + (res = 'draw')::integer, l = l + (res = 'opponent')::integer where u = m.challenger_id;
    update rp set e = greatest(0, e - da), w = w + (res = 'opponent')::integer, d = d + (res = 'draw')::integer, l = l + (res = 'challenger')::integer where u = m.opponent_id;
  end loop;
end $$;
create function pg_temp.same(fmt text) returns boolean language sql as $$
  select (select count(*) from rp) = (select count(*) from public.ladder_ratings where format = fmt)
     and not exists (select 1 from rp left join public.ladder_ratings r on r.user_id = rp.u and r.format = fmt
                     where r.user_id is null or r.elo <> rp.e or r.wins <> rp.w or r.draws <> rp.d or r.losses <> rp.l) $$;
create function pg_temp.snap(fmt text) returns text language sql as $$
  select coalesce(md5(string_agg(user_id || ':' || elo || ':' || wins || ':' || draws || ':' || losses, ',' order by user_id)), '') from public.ladder_ratings where format = fmt $$;
create function pg_temp.corr(id uuid, res text, sc text, why text default 'correzione di prova') returns jsonb language plpgsql as $$
begin perform pg_temp.as_('Admin'); return public.admin_ladder_correct(id, res, sc, why); end $$;
create function pg_temp.offn() returns bigint language sql as $$ select count(*) from public.matches where source = 'ladder' $$;
create temp table ids (k text primary key, v uuid);
create function pg_temp.mid(k text) returns uuid language sql as $$ select v from ids where ids.k = mid.k $$;

-- C1 — struttura, permessi, controlli
do $$
declare m1 uuid; e text;
begin
  assert exists (select 1 from information_schema.columns where table_name = 'ladder_matches' and column_name = 'corrected_at')
     and exists (select 1 from information_schema.columns where table_name = 'ladder_matches' and column_name = 'correction_count'), 'C1: colonne nuove';
  assert not has_function_privilege('anon', 'public.admin_ladder_correct(uuid,text,text,text)', 'execute')
     and has_function_privilege('authenticated', 'public.admin_ladder_correct(uuid,text,text,text)', 'execute')
     and not has_function_privilege('authenticated', 'public._ladder_rebuild(text)', 'execute')
     and not has_function_privilege('authenticated', 'public._notify(uuid,text,text,text,text,text,uuid)', 'execute'), 'C1: permessi delle funzioni';
  m1 := pg_temp.cc('Marco', 'Luca', 'Advanced', 'ladder'); insert into ids values ('m1', m1);
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', m1)) like '%già conclusi%', 'C1: un match non chiuso non si corregge';
  perform pg_temp.fin(m1, 'Marco', 'Luca', 'challenger', '2-0');
  assert pg_temp.bal('Marco') = 1020 and (select count(*) from public.matches where ladder_match_id = m1) = 1, 'C1: premio e match ufficiale della partita';
  foreach e in array array['Marco','Povero','Org'] loop
    assert pg_temp.err_as(e, format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', m1)) like '%Permessi insufficienti%', 'C1: ' || e || ' non può correggere';
  end loop;
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''x'')', m1)) like '%Motivazione%', 'C1: motivazione obbligatoria';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', null)', m1)) like '%Motivazione%', 'C1: motivazione nulla';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''challenger'', ''0-2'', ''prova di correzione'')', m1)) like '%non validi%', 'C1: punteggio incoerente';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''pari'', ''1-1'', ''prova di correzione'')', m1)) like '%non validi%', 'C1: esito inventato';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''challenger'', ''2-0'', ''prova di correzione'')', m1)) like '%Nessuna modifica%', 'C1: stesso risultato';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', gen_random_uuid())) like '%non trovato%', 'C1: match inesistente';
  assert pg_temp.err_auth('Marco', format('update public.ladder_matches set reported_result = ''opponent'' where id = %L', m1)) is not null, 'C1: nessuna scrittura diretta';
  assert pg_temp.err(format('update public.ladder_matches set reported_result = ''opponent'', reported_score = ''0-2'' where id = %L', m1)) like '%già concluso%', 'C1: il guardiano dei match chiusi resta';
  insert into t_log (msg) values ('OK C1 — permessi (solo admin), motivazione, controlli, guardiano dei match chiusi');
end $$;

-- C2 — una piccola classifica e il ricalcolo senza modifiche (deve riprodurre esattamente la classifica viva)
do $$
declare s text;
begin
  insert into ids values ('m2', pg_temp.cc('Luca', 'Paolo', 'Advanced', 'ladder'));
  perform pg_temp.fin(pg_temp.mid('m2'), 'Luca', 'Paolo', 'opponent', '0-2');
  insert into ids values ('m3', pg_temp.cc('Marco', 'Paolo', 'Advanced', 'ladder'));
  perform pg_temp.fin(pg_temp.mid('m3'), 'Marco', 'Paolo', 'challenger', '2-1');
  insert into ids values ('m4', pg_temp.cc('Luca', 'Marco', 'Advanced', 'ladder'));
  perform pg_temp.fin(pg_temp.mid('m4'), 'Luca', 'Marco', 'draw', '1-1');
  insert into ids values ('m5', pg_temp.cc('Paolo', 'Luca', 'Advanced', 'ladder'));
  perform pg_temp.fin(pg_temp.mid('m5'), 'Paolo', 'Luca', 'challenger', '2-0');
  insert into ids values ('e1', pg_temp.cc('Marco', 'Luca', 'Edison', 'ladder'));
  perform pg_temp.fin(pg_temp.mid('e1'), 'Marco', 'Luca', 'challenger', '2-0');
  perform pg_temp.replay('Advanced'); assert pg_temp.same('Advanced'), 'C2: il rigioco indipendente coincide con la classifica viva (Advanced)';
  perform pg_temp.replay('Edison');   assert pg_temp.same('Edison'),   'C2: il rigioco indipendente coincide con la classifica viva (Edison)';
  s := pg_temp.snap('Advanced') || pg_temp.snap('Edison') || (select md5(string_agg(id || ':' || elo_challenger_before || ':' || elo_challenger_delta, ',' order by id)) from public.ladder_matches where status = 'closed');
  perform public._ladder_rebuild('Advanced'); perform public._ladder_rebuild('Edison');
  assert s = pg_temp.snap('Advanced') || pg_temp.snap('Edison') || (select md5(string_agg(id || ':' || elo_challenger_before || ':' || elo_challenger_delta, ',' order by id)) from public.ladder_matches where status = 'closed'),
    'C2: il ricalcolo senza modifiche non cambia nulla (classifiche e variazioni dei match)';
  insert into t_log (msg) values ('OK C2 — 5 match Advanced + 1 Edison; ricalcolo identico alla classifica viva');
end $$;

-- C3 — il match più vecchio passa all''altro giocatore: Elo ricalcolato per tutti, premio e match ufficiale seguono il nuovo vincitore
do $$
declare m1 uuid := pg_temp.mid('m1'); r jsonb; ed text := pg_temp.snap('Edison'); bm integer := pg_temp.bal('Marco'); bl integer := pg_temp.bal('Luca'); bp integer := pg_temp.bal('Paolo');
        tot bigint := pg_temp.tot(); x public.ladder_matches%rowtype;
begin
  perform pg_temp.replay('Advanced', m1, 'opponent');
  r := pg_temp.corr(m1, 'opponent', '0-2', 'risultato inserito al contrario');
  assert pg_temp.same('Advanced'), 'C3: la classifica coincide con il rigioco indipendente col risultato corretto';
  assert ed = pg_temp.snap('Edison'), 'C3: l''altro formato non cambia';
  select * into x from public.ladder_matches where id = m1;
  assert x.reported_result = 'opponent' and x.reported_score = '0-2' and x.status = 'closed' and x.correction_count = 1 and x.corrected_by = pg_temp.uid('Admin') and x.corrected_at is not null, 'C3: match aggiornato e segnato come corretto';
  assert x.elo_challenger_delta < 0 and x.elo_opponent_delta = -x.elo_challenger_delta and x.elo_challenger_before = 1000, 'C3: variazioni del match corrette';
  assert (select sum(elo) from public.ladder_ratings where format = 'Advanced') = 3000, 'C3: l''Elo totale resta costante';
  assert pg_temp.bal('Marco') = bm - 20 and pg_temp.bal('Luca') = bl + 20 and pg_temp.bal('Paolo') = bp and pg_temp.tot() = tot, 'C3: premio tolto al vecchio vincitore e dato al nuovo, BC totali invariati';
  assert x.reward_user = pg_temp.uid('Luca') and x.reward_amount = 20, 'C3: il match ricorda a chi è andato il premio';
  assert (select winner_id from public.matches where id = x.official_match_id) = pg_temp.uid('Luca'), 'C3: match WPA ufficiale al nuovo vincitore';
  assert (select count(*) from public.ledger_entries where ref_id = m1 and kind = 'admin_adjustment') = 2, 'C3: due movimenti nel registro';
  assert (r->>'reward_taken_back')::integer = 20 and (r->>'reward_given')::integer = 20 and (r->>'elo_recalculated')::boolean, 'C3: risposta';
  assert pg_temp.nn('Marco', 'ladder_correction') = 1 and pg_temp.nn('Luca', 'ladder_correction') = 1 and pg_temp.nn('Paolo', 'ladder_correction') = 0, 'C3: notifiche ai due giocatori';
  assert (select count(*) from public.audit_logs where action = 'admin_ladder_correct' and entity_id = m1::text and reason = 'risultato inserito al contrario') = 1, 'C3: audit';
  perform pg_temp.prefs('Paolo', true, false, true);
  perform pg_temp.corr(pg_temp.mid('m2'), 'opponent', '1-2', 'punteggio di prova');
  assert pg_temp.nn('Paolo', 'ladder_correction') = 0 and pg_temp.nn('Luca', 'ladder_correction') = 2, 'C3: la preferenza «sfide in Ladder» spenta vale anche per l''avviso di correzione';
  assert pg_temp.err(format('update public.ladder_matches set reported_result = ''challenger'', reported_score = ''2-0'' where id = %L', m1)) like '%già concluso%', 'C3: dopo la correzione il guardiano è di nuovo chiuso';
  insert into t_log (msg) values ('OK C3 — vincitore cambiato: Elo ricalcolato, premio e match WPA al nuovo vincitore, notifiche, audit');
end $$;

-- C4 — cambia solo il punteggio (stesso vincitore): nessun movimento di BC, nessun cambio di Elo né di match ufficiale
do $$
declare m1 uuid := pg_temp.mid('m1'); mo text := pg_temp.money(); sn text := pg_temp.snap('Advanced'); off uuid := (select official_match_id from public.ladder_matches where id = pg_temp.mid('m1')); r jsonb;
begin
  r := pg_temp.corr(m1, 'opponent', '1-2');
  assert mo = pg_temp.money() and sn = pg_temp.snap('Advanced'), 'C4: solo il punteggio: né BC né Elo';
  assert (select official_match_id from public.ladder_matches where id = m1) = off and (r->>'reward_given')::integer = 0 and (r->>'reward_taken_back')::integer = 0, 'C4: match ufficiale invariato';
  assert (select reported_score from public.ladder_matches where id = m1) = '1-2' and (select correction_count from public.ladder_matches where id = m1) = 2, 'C4: punteggio e contatore';
  insert into t_log (msg) values ('OK C4 — correzione del solo punteggio');
end $$;

-- C5 — il match diventa un pareggio: premio tolto, match ufficiale rimosso, Elo ricalcolato
do $$
declare m1 uuid := pg_temp.mid('m1'); bl integer := pg_temp.bal('Luca'); n0 bigint := pg_temp.offn(); r jsonb; x public.ladder_matches%rowtype;
begin
  perform pg_temp.replay('Advanced', m1, 'draw');
  r := pg_temp.corr(m1, 'draw', '1-1', 'in realtà hanno pareggiato');
  select * into x from public.ladder_matches where id = m1;
  assert pg_temp.same('Advanced'), 'C5: Elo coincide con il rigioco indipendente';
  assert pg_temp.bal('Luca') = bl - 20 and x.reward_user is null and x.reward_amount = 0 and x.reward_note like '%pareggio%', 'C5: premio annullato';
  assert x.official_match_id is null and pg_temp.offn() = n0 - 1 and x.official_note like '%pareggio%', 'C5: match ufficiale rimosso';
  assert (select count(*) from public.matches where ladder_match_id = m1) = 0, 'C5: nessun match ufficiale collegato';
  insert into t_log (msg) values ('OK C5 — vittoria corretta in pareggio');
end $$;

-- C6 — da pareggio a vittoria: premio e match ufficiale nascono (senza limiti giornalieri)
do $$
declare m1 uuid := pg_temp.mid('m1'); bm integer := pg_temp.bal('Marco'); n0 bigint := pg_temp.offn(); r jsonb; x public.ladder_matches%rowtype; o public.matches%rowtype;
begin
  perform pg_temp.replay('Advanced', m1, 'challenger');
  r := pg_temp.corr(m1, 'challenger', '2-0', 'ha vinto Marco');
  select * into x from public.ladder_matches where id = m1;
  assert pg_temp.same('Advanced'), 'C6: Elo coincide con il rigioco indipendente';
  assert pg_temp.bal('Marco') = bm + 20 and x.reward_user = pg_temp.uid('Marco') and x.reward_amount = 20 and x.reward_note is null, 'C6: premio al vincitore';
  select * into o from public.matches where id = x.official_match_id;
  assert o.winner_id = pg_temp.uid('Marco') and o.status = 'verified' and o.source = 'ladder' and o.ladder_match_id = m1 and not o.bounty_eligible and o.verified_by = pg_temp.uid('Admin'), 'C6: match ufficiale creato';
  assert pg_temp.offn() = n0 + 1 and x.correction_count = 4, 'C6: contatore dei match e delle correzioni';
  insert into t_log (msg) values ('OK C6 — da pareggio a vittoria: premio e match ufficiale creati');
end $$;

-- C7 — il vecchio vincitore ha già speso i BC: se ne recupera solo quanto c'è ancora
do $$
declare m5 uuid := pg_temp.mid('m5'); bl integer := pg_temp.bal('Luca'); r jsonb; bal integer := pg_temp.bal('Paolo');
begin
  assert (select reward_user from public.ladder_matches where id = m5) = pg_temp.uid('Paolo'), 'C7: premesse';
  perform public._ledger_move(pg_temp.uid('Paolo'), -(bal - 5), 'admin_adjustment', 'admin', gen_random_uuid(), 'test-svuota-' || gen_random_uuid(), 'prova: ha speso quasi tutto');
  r := pg_temp.corr(m5, 'opponent', '0-2', 'Paolo non ha vinto');
  assert pg_temp.bal('Paolo') = 0 and (r->>'reward_taken_back')::integer = 5 and (r->>'reward_given')::integer = 20 and pg_temp.bal('Luca') = bl + 20, 'C7: recupero parziale, il nuovo vincitore riceve il premio intero';
  perform pg_temp.replay('Advanced'); assert pg_temp.same('Advanced'), 'C7: Elo coerente';
  insert into t_log (msg) values ('OK C7 — recupero parziale del premio');
end $$;

-- C8 — taglia già riscossa: il vincitore non si cambia, e il rifiuto non lascia tracce; il solo punteggio sì
do $$
declare mb uuid; off uuid; mo text; sn text; x public.ladder_matches%rowtype; e text; r jsonb;
begin
  perform pg_temp.bnt('Org', 'Luca', 100);
  mb := pg_temp.cc('Marco', 'Luca', 'Advanced', 'both'); insert into ids values ('mb', mb);
  perform pg_temp.fin(mb, 'Marco', 'Luca', 'challenger', '2-0');
  select official_match_id into off from public.ladder_matches where id = mb;
  assert off is not null and (select bounty_eligible from public.matches where id = off), 'C8: match ufficiale valido per la taglia';
  perform pg_temp.claim('Marco', off);
  mo := pg_temp.money(); sn := pg_temp.snap('Advanced'); select * into x from public.ladder_matches where id = mb;
  e := pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', mb));
  assert e like '%già stata riscossa una taglia%', 'C8: ' || coalesce(e, 'riuscita');
  e := pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''draw'', ''1-1'', ''prova di correzione'')', mb));
  assert e like '%già stata riscossa una taglia%', 'C8: anche il pareggio è rifiutato';
  assert mo = pg_temp.money() and sn = pg_temp.snap('Advanced') and (select reported_result from public.ladder_matches where id = mb) = 'challenger'
     and (select correction_count from public.ladder_matches where id = mb) = 0 and (select winner_id from public.matches where id = off) = pg_temp.uid('Marco'), 'C8: il rifiuto non cambia nulla';
  perform pg_temp.replay('Advanced', mb, 'challenger'); r := pg_temp.corr(mb, 'challenger', '2-1', 'punteggio sbagliato');
  assert (select reported_score from public.ladder_matches where id = mb) = '2-1' and pg_temp.same('Advanced'), 'C8: il solo punteggio si può correggere';
  insert into t_log (msg) values ('OK C8 — taglia già riscossa: vincitore bloccato, nessuna traccia del rifiuto; punteggio correggibile');
end $$;

-- C9 — sfida «solo per la taglia»: l'Elo non c'entra, si sposta solo il match ufficiale
do $$
declare mt uuid; off uuid; sn text; r jsonb; mo text;
begin
  perform pg_temp.bnt('Luca', 'Marco', 50);
  mt := pg_temp.cc('Paolo', 'Marco', 'Advanced', 'bounty'); insert into ids values ('mt', mt);
  perform pg_temp.fin(mt, 'Paolo', 'Marco', 'challenger', '2-0');
  select official_match_id into off from public.ladder_matches where id = mt;
  assert off is not null and (select winner_id from public.matches where id = off) = pg_temp.uid('Paolo'), 'C9: premesse';
  sn := pg_temp.snap('Advanced'); mo := pg_temp.money();
  r := pg_temp.corr(mt, 'opponent', '0-2', 'ha vinto Marco');
  assert sn = pg_temp.snap('Advanced') and mo = pg_temp.money() and not (r->>'elo_recalculated')::boolean, 'C9: né Elo né BC';
  assert (select winner_id from public.matches where id = off) = pg_temp.uid('Marco') and (select reported_result from public.ladder_matches where id = mt) = 'opponent', 'C9: match ufficiale al nuovo vincitore';
  insert into t_log (msg) values ('OK C9 — sfida per la taglia corretta: solo match ufficiale');
end $$;

-- C10 — modulo spento, sospensione, coerenza finale
do $$
declare e text; m1 uuid := pg_temp.mid('m1');
begin
  perform pg_temp.mod('ladder', false);
  e := pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', m1));
  assert e like '%Modulo non attivo%', 'C10: a Ladder spenta la correzione è rifiutata (' || coalesce(e, 'riuscita') || ')';
  perform pg_temp.mod('ladder', true);
  perform pg_temp.replay('Advanced'); assert pg_temp.same('Advanced'), 'C10: coerenza finale Advanced';
  perform pg_temp.replay('Edison');   assert pg_temp.same('Edison'),   'C10: coerenza finale Edison';
  assert (select count(*) from public.audit_logs where action = 'admin_ladder_correct') = 8, 'C10: 8 correzioni, 8 voci di audit';
  assert (select count(*) from public.ladder_matches where status = 'closed' and corrected_at is null) >= 3, 'C10: i match mai corretti non risultano corretti';
  insert into t_log (msg) values ('OK C10 — modulo spento, coerenza finale, audit');
end $$;

select n, msg from t_log order by n;
rollback;
