-- =====================================================================
-- TEST DELLA MIGRAZIONE 022 (annullamento dei risultati Ladder già conclusi)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…022 (black-market-setup.sql … black-market-ladder-annulla.sql).
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
create function pg_temp.canc(id uuid, why text default 'annullamento di prova') returns jsonb language plpgsql as $$
begin perform pg_temp.as_('Admin'); return public.admin_ladder_cancel_closed(id, why); end $$;
-- come replay, ma lasciando fuori del tutto il match indicato
create function pg_temp.replay_wo(fmt text, skip uuid) returns void language plpgsql as $$
declare m record; ea integer; eo integer; da integer; s numeric; k integer := public._setting('ladder_k'); st integer := public._setting('ladder_start_elo');
begin
  delete from rp;
  for m in select * from public.ladder_matches where status = 'closed' and format = fmt and kind in ('ladder','both') and id <> skip order by closed_at, id loop
    insert into rp values (m.challenger_id, st, 0, 0, 0), (m.opponent_id, st, 0, 0, 0) on conflict do nothing;
    select e into ea from rp where u = m.challenger_id; select e into eo from rp where u = m.opponent_id;
    s := case m.reported_result when 'challenger' then 1 when 'opponent' then 0 else 0.5 end;
    da := round(k * (s - 1 / (1 + power(10, (eo - ea)::numeric / 400))))::integer;
    update rp set e = greatest(0, e + da), w = w + (m.reported_result = 'challenger')::integer, d = d + (m.reported_result = 'draw')::integer, l = l + (m.reported_result = 'opponent')::integer where u = m.challenger_id;
    update rp set e = greatest(0, e - da), w = w + (m.reported_result = 'opponent')::integer, d = d + (m.reported_result = 'draw')::integer, l = l + (m.reported_result = 'challenger')::integer where u = m.opponent_id;
  end loop;
end $$;

-- N1 — struttura, permessi, controlli
do $$
declare m1 uuid; e text;
begin
  assert not has_function_privilege('anon', 'public.admin_ladder_cancel_closed(uuid,text)', 'execute')
     and has_function_privilege('authenticated', 'public.admin_ladder_cancel_closed(uuid,text)', 'execute'), 'N1: permessi della funzione';
  m1 := pg_temp.cc('Marco', 'Luca', 'Advanced', 'ladder'); insert into ids values ('m1', m1);
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''prova di annullamento'')', m1)) like '%solo i match già conclusi%', 'N1: un match non concluso non si annulla qui';
  perform pg_temp.fin(m1, 'Marco', 'Luca', 'challenger', '2-0');
  assert pg_temp.bal('Marco') = 1020 and (select count(*) from public.matches where ladder_match_id = m1) = 1, 'N1: premessa: premio e match ufficiale';
  foreach e in array array['Marco','Luca','Povero','Org'] loop
    assert pg_temp.err_as(e, format('select public.admin_ladder_cancel_closed(%L, ''prova di annullamento'')', m1)) like '%Permessi insufficienti%', 'N1: ' || e || ' non può annullare';
  end loop;
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''x'')', m1)) like '%Motivazione%', 'N1: motivazione obbligatoria';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, null)', m1)) like '%Motivazione%', 'N1: motivazione nulla';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''prova di annullamento'')', gen_random_uuid())) like '%non trovato%', 'N1: match inesistente';
  assert pg_temp.err('select public.admin_ladder_cancel_closed(gen_random_uuid(), ''prova di annullamento'')') is not null, 'N1: serve il login';
  assert (select status from public.ladder_matches where id = m1) = 'closed' and pg_temp.bal('Marco') = 1020, 'N1: i rifiuti non cambiano nulla';
  insert into t_log (msg) values ('OK N1 — solo amministratori, motivazione obbligatoria, match non conclusi esclusi');
end $$;

-- N2 — annullare una vittoria con premio e match ufficiale: Elo, BC e match WPA tornano come se non fosse mai stata giocata
do $$
declare m1 uuid := pg_temp.mid('m1'); m2 uuid; m3 uuid; me uuid; r jsonb; x public.ladder_matches%rowtype; ed text; bm integer; tot bigint; off0 bigint := pg_temp.offn();
begin
  m2 := pg_temp.cc('Paolo', 'Marco', 'Advanced', 'ladder'); perform pg_temp.fin(m2, 'Paolo', 'Marco', 'challenger', '2-1'); insert into ids values ('m2', m2);
  m3 := pg_temp.cc('Luca', 'Paolo', 'Advanced', 'ladder'); perform pg_temp.fin(m3, 'Luca', 'Paolo', 'challenger', '2-0'); insert into ids values ('m3', m3);
  me := pg_temp.cc('Marco', 'Luca', 'Edison', 'ladder'); perform pg_temp.fin(me, 'Marco', 'Luca', 'challenger', '2-0'); insert into ids values ('me', me);
  ed := pg_temp.snap('Edison'); bm := pg_temp.bal('Marco'); tot := pg_temp.tot(); off0 := pg_temp.offn();
  perform pg_temp.replay_wo('Advanced', m1);
  r := pg_temp.canc(m1, 'partita mai giocata');
  assert pg_temp.same('Advanced'), 'N2: la classifica coincide con il rigioco indipendente senza quel match';
  assert ed = pg_temp.snap('Edison'), 'N2: l''altro formato non cambia';
  select * into x from public.ladder_matches where id = m1;
  assert x.status = 'voided' and x.resolved_by = pg_temp.uid('Admin') and x.resolution_reason = 'partita mai giocata' and x.corrected_at is not null, 'N2: match annullato con motivazione';
  assert x.reward_amount = 0 and x.reward_user is null and x.official_match_id is null and x.elo_challenger_delta is null and x.elo_opponent_delta is null, 'N2: niente premio, match ufficiale, variazioni Elo';
  assert x.reported_result = 'challenger' and x.reported_score = '2-0', 'N2: lo storico ricorda cosa era stato scritto';
  assert pg_temp.bal('Marco') = bm - 20 and pg_temp.tot() = tot - 20, 'N2: premio tolto al vincitore (20 BC)';
  assert pg_temp.offn() = off0 - 1 and not exists (select 1 from public.matches where ladder_match_id = m1), 'N2: match WPA rimosso';
  assert (select count(*) from public.ledger_entries where ref_id = m1 and kind = 'admin_adjustment' and amount = -20) = 1, 'N2: un movimento nel registro';
  assert (r->>'reward_taken_back')::int = 20 and (r->>'official_removed')::boolean and (r->>'elo_recalculated')::boolean, 'N2: risposta';
  assert pg_temp.nn('Marco', 'ladder_correction') = 1 and pg_temp.nn('Luca', 'ladder_correction') = 1 and pg_temp.nn('Paolo', 'ladder_correction') = 0, 'N2: notifiche ai due giocatori';
  assert (select count(*) from public.audit_logs where action = 'admin_ladder_cancel_closed' and entity_id = m1::text and reason = 'partita mai giocata') = 1, 'N2: audit';
  assert (select count(*) from public.ladder_ratings where format = 'Advanced' and wins + draws + losses > 0) = 3 and
         (select sum(wins) from public.ladder_ratings where format = 'Advanced') = 2, 'N2: contatori vittorie ricalcolati (2 match rimasti)';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''ancora una volta'')', m1)) like '%solo i match già conclusi%', 'N2: non si annulla due volte';
  assert pg_temp.err(format('update public.ladder_matches set status = ''closed'' where id = %L', m1)) like '%già concluso%', 'N2: dopo l''annullamento il guardiano è di nuovo chiuso';
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', m1)) like '%già conclusi%', 'N2: un match annullato non si corregge';
  insert into t_log (msg) values ('OK N2 — Elo ricalcolato senza il match, premio tolto, match WPA rimosso, notifiche, audit');
end $$;

-- N3 — i turni del match ufficiale restano 1,2,3… senza buchi
do $$
declare a uuid; b uuid; c uuid; d uuid; ev uuid; rounds text;
begin
  perform pg_temp.set_('ladder_max_pair_per_day', 50);
  a := pg_temp.cc('Marco', 'Povero', 'Advanced', 'ladder'); perform pg_temp.fin(a, 'Marco', 'Povero', 'challenger', '2-0');
  b := pg_temp.cc('Marco', 'Povero', 'Advanced', 'ladder'); perform pg_temp.fin(b, 'Marco', 'Povero', 'opponent', '0-2');
  c := pg_temp.cc('Marco', 'Povero', 'Advanced', 'ladder'); perform pg_temp.fin(c, 'Marco', 'Povero', 'challenger', '2-1');
  select string_agg(mm.round::text, ',' order by mm.round) into rounds from public.matches mm where mm.ladder_match_id in (a, b, c);
  assert rounds = '1,2,3', 'N3: premessa: turni 1,2,3 (' || rounds || ')';
  perform pg_temp.canc(a, 'primo match inserito per errore');
  select string_agg(mm.round::text, ',' order by mm.round) into rounds from public.matches mm where mm.ladder_match_id in (b, c);
  assert rounds = '1,2', 'N3: dopo l''annullamento del primo i turni sono 1,2 (' || rounds || ')';
  d := pg_temp.cc('Marco', 'Povero', 'Advanced', 'ladder'); perform pg_temp.fin(d, 'Marco', 'Povero', 'challenger', '2-0');
  select string_agg(mm.round::text, ',' order by mm.round) into rounds from public.matches mm where mm.ladder_match_id in (b, c, d);
  assert rounds = '1,2,3', 'N3: e il match successivo è il 3, senza conflitti (' || rounds || ')';
  perform pg_temp.canc(c, 'secondo errore');
  select string_agg(mm.round::text, ',' order by mm.round) into rounds from public.matches mm where mm.ladder_match_id in (b, d);
  assert rounds = '1,2', 'N3: annullando quello in mezzo i turni si richiudono (' || rounds || ')';
  insert into ids values ('p1', b), ('p2', d);
  insert into t_log (msg) values ('OK N3 — turni dei match ufficiali sempre contigui');
end $$;

-- N4 — il vincitore ha già speso il premio: si recupera solo quanto c'è ancora
do $$
declare mm uuid; b0 integer; x public.ladder_matches%rowtype; r jsonb;
begin
  mm := pg_temp.cc('Luca', 'Povero', 'Advanced', 'ladder'); perform pg_temp.fin(mm, 'Luca', 'Povero', 'challenger', '2-0');
  select * into x from public.ladder_matches where id = mm;
  assert x.reward_user = pg_temp.uid('Luca') and x.reward_amount = 20, 'N4: premessa: premio a Luca';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Luca'), 5 - pg_temp.bal('Luca'), 'Luca ha speso quasi tutto');
  assert pg_temp.bal('Luca') = 5, 'N4: Luca ha 5 BC';
  r := pg_temp.canc(mm, 'annullo anche se ha speso');
  assert (r->>'reward_taken_back')::int = 5 and pg_temp.bal('Luca') = 0, 'N4: tolti solo i 5 BC rimasti, mai saldo negativo';
  assert (select balance from public.wallets where user_id = pg_temp.uid('Luca')) >= 0, 'N4: saldo non negativo';
  perform pg_temp.as_('Admin'); perform public.admin_adjust_balance(pg_temp.uid('Luca'), 1000, 'ripristino saldo di prova');
  insert into t_log (msg) values ('OK N4 — premio già speso: si recupera il possibile, saldo mai negativo');
end $$;

-- N5 — pareggio (nessun premio, nessun match ufficiale) e sfida solo per la taglia (nessun Elo)
do $$
declare md uuid; mt uuid; sn text; mo text; r jsonb; x public.ladder_matches%rowtype;
begin
  md := pg_temp.cc('Paolo', 'Povero', 'Advanced', 'ladder'); perform pg_temp.fin(md, 'Paolo', 'Povero', 'draw', '1-1');
  mo := pg_temp.money();
  perform pg_temp.replay_wo('Advanced', md);
  r := pg_temp.canc(md, 'pareggio mai avvenuto');
  assert pg_temp.same('Advanced') and (r->>'reward_taken_back')::int = 0 and not (r->>'official_removed')::boolean, 'N5: pareggio annullato: Elo ricalcolato, nessun BC, nessun match ufficiale';
  assert mo = pg_temp.money(), 'N5: nessun movimento di BC';
  -- sfida solo per la taglia, senza taglia sul bersaglio: nessun Elo, il match ufficiale sparisce
  perform pg_temp.set_('ladder_wpa_pair_day', 50);
  perform pg_temp.bnt('Luca', 'Povero', 50);          -- la taglia c'è, ma vince il bersaglio: nessuna riscossione, quindi il match è annullabile
  mt := pg_temp.cc('Org', 'Povero', 'Advanced', 'bounty'); perform pg_temp.fin(mt, 'Org', 'Povero', 'opponent', '0-2');
  select * into x from public.ladder_matches where id = mt;
  assert x.official_match_id is not null and x.kind = 'bounty', 'N5: premessa: match ufficiale della sfida per la taglia';
  assert not exists (select 1 from public.bounty_settlements where match_id = x.official_match_id), 'N5: nessuna taglia riscossa';
  sn := pg_temp.snap('Advanced'); mo := pg_temp.money();
  r := pg_temp.canc(mt, 'sfida per la taglia annullata');
  assert sn = pg_temp.snap('Advanced') and mo = pg_temp.money() and not (r->>'elo_recalculated')::boolean and (r->>'official_removed')::boolean, 'N5: né Elo né BC, match ufficiale rimosso';
  assert not exists (select 1 from public.matches where ladder_match_id = mt), 'N5: nessun match WPA rimasto';
  insert into t_log (msg) values ('OK N5 — pareggio e sfida per la taglia annullati senza toccare ciò che non c''entra');
end $$;

-- N6 — taglia già riscossa su quel match: si rifiuta senza lasciare tracce
do $$
declare mb uuid; off uuid; mo text; sn text; e text; x public.ladder_matches%rowtype;
begin
  perform pg_temp.bnt('Org', 'Luca', 100);
  mb := pg_temp.cc('Marco', 'Luca', 'Advanced', 'both'); perform pg_temp.fin(mb, 'Marco', 'Luca', 'challenger', '2-0');
  select official_match_id into off from public.ladder_matches where id = mb;
  assert exists (select 1 from public.bounty_settlements where match_id = off), 'N6: premessa: la taglia è stata riscossa';
  mo := pg_temp.money(); sn := pg_temp.snap('Advanced'); select * into x from public.ladder_matches where id = mb;
  e := pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''prova di annullamento'')', mb));
  assert e like '%già stata riscossa una taglia%', 'N6: ' || coalesce(e, 'riuscito');
  assert mo = pg_temp.money() and sn = pg_temp.snap('Advanced') and (select status from public.ladder_matches where id = mb) = 'closed'
     and exists (select 1 from public.matches where id = off) and (select correction_count from public.ladder_matches where id = mb) = x.correction_count, 'N6: il rifiuto non cambia nulla';
  insert into t_log (msg) values ('OK N6 — taglia già riscossa: annullamento rifiutato, nessuna traccia');
end $$;

-- N7 — match ufficiale usato altrove (esclusione dalle fazioni): rifiutato
do $$
declare mx uuid; off uuid; e text; mo text;
begin
  mx := pg_temp.cc('Paolo', 'Luca', 'Advanced', 'ladder'); perform pg_temp.fin(mx, 'Paolo', 'Luca', 'challenger', '2-0');
  select official_match_id into off from public.ladder_matches where id = mx;
  insert into public.faction_match_exclusions (match_id, excluded_by, reason) values (off, pg_temp.uid('Admin'), 'prova');
  mo := pg_temp.money();
  e := pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''prova di annullamento'')', mx));
  assert e like '%usato altrove%', 'N7: ' || coalesce(e, 'riuscito');
  assert mo = pg_temp.money() and (select status from public.ladder_matches where id = mx) = 'closed' and exists (select 1 from public.matches where id = off), 'N7: nulla è cambiato';
  delete from public.faction_match_exclusions where match_id = off;
  perform pg_temp.canc(mx, 'ora si può');
  assert (select status from public.ladder_matches where id = mx) = 'voided', 'N7: tolta l''esclusione, si annulla';
  insert into t_log (msg) values ('OK N7 — match ufficiale usato altrove: rifiutato; poi annullabile');
end $$;

-- N8 — i limiti giornalieri si liberano: dopo l'annullamento si può rigiocare e il premio non conta più
do $$
declare ma uuid; mb uuid; e text; r jsonb; b0 integer;
begin
  perform pg_temp.set_('ladder_max_pair_per_day', 1); perform pg_temp.set_('ladder_reward_max_day', 1); perform pg_temp.set_('ladder_reward_pair_day', 1);
  ma := pg_temp.cc('Org', 'Luca', 'Advanced', 'ladder'); perform pg_temp.fin(ma, 'Org', 'Luca', 'challenger', '2-0');
  assert pg_temp.err_as('Org', format('select public.ladder_challenge(%L, ''Advanced'', null, %L, ''ladder'')', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%Limite giornaliero%', 'N8: premessa: limite coppia raggiunto';
  perform pg_temp.canc(ma, 'annullato per rigiocare');
  mb := pg_temp.cc('Org', 'Luca', 'Advanced', 'ladder');
  b0 := pg_temp.bal('Org');
  perform pg_temp.fin(mb, 'Org', 'Luca', 'challenger', '2-0');
  assert pg_temp.bal('Org') = b0 + 20, 'N8: il premio della nuova partita viene dato (quello annullato non conta nei limiti)';
  perform pg_temp.set_('ladder_max_pair_per_day', 50); perform pg_temp.set_('ladder_reward_max_day', 50); perform pg_temp.set_('ladder_reward_pair_day', 50);
  insert into t_log (msg) values ('OK N8 — limiti giornalieri liberati dall''annullamento');
end $$;

-- N9 — modulo spento, coerenza finale
do $$
declare mm uuid;
begin
  select id into mm from public.ladder_matches where status = 'closed' order by closed_at limit 1;
  perform pg_temp.mod('ladder', false);
  assert pg_temp.err_as('Admin', format('select public.admin_ladder_cancel_closed(%L, ''prova di annullamento'')', mm)) = 'Modulo non attivo', 'N9: modulo spento';
  perform pg_temp.mod('ladder', true);
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'N9: saldi = registro';
  assert not exists (select 1 from public.ladder_matches where status = 'closed' and (elo_challenger_delta is null or elo_opponent_delta is null)), 'N9: tutti i match chiusi hanno le variazioni';
  assert (select count(*) from public.ladder_matches where status = 'voided') >= 6, 'N9: i match annullati restano nello storico';
  perform pg_temp.replay('Advanced'); assert pg_temp.same('Advanced'), 'N9: classifica Advanced = rigioco indipendente';
  perform pg_temp.replay('Edison'); assert pg_temp.same('Edison'), 'N9: classifica Edison = rigioco indipendente';
  insert into t_log (msg) values ('OK N9 — modulo spento, saldi = registro, classifiche = rigioco, storico degli annullati');
end $$;

select msg from t_log order by n;
rollback;
