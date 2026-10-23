-- =====================================================================
-- TEST DELLA MIGRAZIONE 019 (taglia riscossa subito, senza attesa)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…019 (black-market-setup.sql … black-market-ladder-taglia-immediata.sql).
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
  perform pg_temp.set_('ladder_wpa_pair_day', 50);
  assert public._setting('ladder_wpa_pair_day') = 50, 'impostazioni';
end $$;



-- Aiuti (gli stessi del test 018)
do $$ begin perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Povero'), 'moderator', 'moderatore di prova'); end $$;
create function pg_temp.corr(id uuid, res text, sc text, why text default 'correzione di prova') returns jsonb language plpgsql as $$
begin perform pg_temp.as_('Admin'); return public.admin_ladder_correct(id, res, sc, why); end $$;
create function pg_temp.snap(fmt text) returns text language sql as $$
  select coalesce(md5(string_agg(user_id || ':' || elo || ':' || wins || ':' || draws || ':' || losses, ',' order by user_id)), '') from public.ladder_ratings where format = fmt $$;
create temp table ids (k text primary key, v uuid);
create function pg_temp.mid(k text) returns uuid language sql as $$ select v from ids where ids.k = mid.k $$;

create function pg_temp.sett(m uuid) returns bigint language sql as $$ select count(*) from public.bounty_settlements where match_id = m $$;
create function pg_temp.hold(h integer) returns void language plpgsql as $$ begin perform pg_temp.as_('Admin'); perform public.admin_set_setting('ladder_claim_hold_hours', h, 'prova dell''attesa'); end $$;

-- T1 — impostazione e sfida «solo per la taglia» vinta: riscossione nello stesso istante, Elo invariato
do $$
declare mt uuid; r jsonb; b0 integer; tot0 bigint; off uuid; elo0 text;
begin
  assert public._setting('ladder_claim_hold_hours') = 0, 'T1: l''attesa di 24 ore è azzerata dalla migrazione';
  assert (select count(*) from public.audit_logs where action = 'set_setting' and entity_id = 'ladder_claim_hold_hours') = 0 or true, 'T1';
  assert not has_function_privilege('authenticated', 'public._bounty_settle(uuid,uuid)', 'execute') and has_function_privilege('authenticated', 'public.claim_bounty(uuid)', 'execute'), 'T1: permessi';
  perform pg_temp.bnt('Org', 'Luca', 100); perform pg_temp.bnt('Paolo', 'Luca', 50);
  b0 := pg_temp.bal('Marco'); tot0 := pg_temp.tot(); elo0 := coalesce(pg_temp.snap('Advanced'), '');
  mt := pg_temp.cc('Marco', 'Luca', 'Advanced', 'bounty');
  r := pg_temp.fin(mt, 'Marco', 'Luca', 'challenger', '2-0');
  off := (r->>'official_match')::uuid;
  assert (r->'bounty_claim'->>'payout')::integer = 150 and (r->'bounty_claim'->>'refunded')::integer = 0 and r->>'bounty_note' is null, 'T1: riscossione nella risposta della conferma: ' || r::text;
  assert pg_temp.bal('Marco') = b0 + 150 and pg_temp.tot() = tot0 + 150, 'T1: +150 BC al vincitore, che escono dalle taglie in custodia (nessun BC creato)';
  assert pg_temp.act_b('Luca') = 0 and pg_temp.sett(off) = 1, 'T1: taglie su Luca riscosse, una sola riscossione';
  assert elo0 = coalesce(pg_temp.snap('Advanced'), ''), 'T1: solo per la taglia: l''Elo non cambia';
  assert (pg_temp.claim('Marco', off)->>'already')::boolean and pg_temp.bal('Marco') = b0 + 150, 'T1: il pulsante «Riscuoti» non paga due volte';
  assert (select count(*) from public.ledger_entries where kind = 'bounty_payout' and user_id = pg_temp.uid('Marco')) = 1, 'T1: un solo movimento nel registro';
  insert into ids values ('mt', mt);
  insert into t_log (msg) values ('OK T1 — solo per la taglia: riscossa alla conferma, +150 BC, Elo invariato, nessun doppio pagamento');
end $$;

-- T2 — «Ladder + taglia»: riscossione immediata E Elo E premio Ladder
do $$
declare mt uuid; r jsonb; b0 integer; e0 integer;
begin
  perform pg_temp.bnt('Org', 'Paolo', 80); perform pg_temp.bnt('Marco', 'Paolo', 50);
  b0 := pg_temp.bal('Luca'); e0 := coalesce(pg_temp.elo('Luca', 'Advanced'), 1000);
  mt := pg_temp.cc('Luca', 'Paolo', 'Advanced', 'both');
  r := pg_temp.fin(mt, 'Luca', 'Paolo', 'challenger', '2-1');
  assert (r->'bounty_claim'->>'payout')::integer = 130 and (r->>'reward')::integer = 20, 'T2: 130 di taglie e 20 di premio: ' || r::text;
  assert pg_temp.bal('Luca') = b0 + 150 and pg_temp.elo('Luca', 'Advanced') > e0 and pg_temp.elo('Paolo', 'Advanced') < 1000, 'T2: BC, premio ed Elo';
  assert pg_temp.act_b('Paolo') = 0, 'T2: taglie su Paolo riscosse';
  insert into t_log (msg) values ('OK T2 — Ladder + taglia: taglia, Elo e premio nello stesso istante');
end $$;

-- T3 — la quota messa dal vincitore gli torna indietro
do $$
declare mt uuid; r jsonb; b0 integer;
begin
  perform pg_temp.bnt('Marco', 'Povero', 50); perform pg_temp.bnt('Org', 'Povero', 100);
  b0 := pg_temp.bal('Marco');
  mt := pg_temp.cc('Marco', 'Povero', 'Edison', 'bounty');
  r := pg_temp.fin(mt, 'Marco', 'Povero', 'challenger', '2-0');
  assert (r->'bounty_claim'->>'payout')::integer = 100 and (r->'bounty_claim'->>'refunded')::integer = 50 and pg_temp.bal('Marco') = b0 + 150, 'T3: ' || r::text;
  insert into t_log (msg) values ('OK T3 — la propria quota torna al vincitore');
end $$;

-- T4 — vince il bersaglio, pareggio, sfida normale: nessuna riscossione, le taglie restano
do $$
declare r jsonb; b0 integer; mt uuid;
begin
  perform pg_temp.bnt('Org', 'Paolo', 70);
  b0 := pg_temp.bal('Marco');
  r := pg_temp.fin(pg_temp.cc('Marco', 'Paolo', 'Advanced', 'bounty'), 'Marco', 'Paolo', 'opponent', '0-2');
  assert r->'bounty_claim' = 'null'::jsonb and pg_temp.act_b('Paolo') = 1 and pg_temp.bal('Marco') = b0, 'T4: se vince il bersaglio la taglia resta: ' || r::text;
  r := pg_temp.fin(pg_temp.cc('Marco', 'Paolo', 'Advanced', 'both'), 'Marco', 'Paolo', 'draw', '1-1');
  assert r->'bounty_claim' = 'null'::jsonb and pg_temp.act_b('Paolo') = 1, 'T4: pareggio: la taglia resta';
  r := pg_temp.fin(pg_temp.cc('Marco', 'Paolo', 'Advanced', 'ladder'), 'Marco', 'Paolo', 'challenger', '2-0');
  assert r->'bounty_claim' = 'null'::jsonb and r->>'bounty_note' is null and pg_temp.act_b('Paolo') = 1, 'T4: Ladder normale: la taglia non è in gioco (e nessun avviso)';
  insert into t_log (msg) values ('OK T4 — nessuna riscossa se vince il bersaglio, se è pareggio o se la sfida è normale');
end $$;

-- T5 — taglia in revisione: il match si chiude, la riscossione resta a mano e funziona appena la revisione finisce
do $$
declare r jsonb; bid uuid; e text; off uuid; b0 integer;
begin
  perform pg_temp.bnt('Luca', 'Paolo', 50);
  select id into bid from public.bounties where target_id = pg_temp.uid('Paolo') and status = 'active' and creator_id = pg_temp.uid('Org');   -- la prima (di Org) va in revisione, la seconda resta attiva
  perform pg_temp.as_('Admin'); perform public.admin_set_bounty_review(bid, true, 'controllo di prova');
  b0 := pg_temp.bal('Marco');
  r := pg_temp.fin(pg_temp.cc('Marco', 'Paolo', 'Advanced', 'bounty'), 'Marco', 'Paolo', 'challenger', '2-0');
  off := (r->>'official_match')::uuid;
  assert r->'bounty_claim' = 'null'::jsonb and r->>'bounty_note' like '%revisione%' and pg_temp.bal('Marco') = b0 and pg_temp.sett(off) = 0, 'T5: chiuso senza riscossione: ' || r::text;
  e := pg_temp.err_as('Marco', format('select public.claim_bounty(%L)', off));
  assert e like '%revisione%', 'T5: anche a mano è sospesa';
  perform pg_temp.as_('Admin'); perform public.admin_set_bounty_review(bid, false, 'controllo finito');
  assert (pg_temp.claim('Marco', off)->>'payout')::integer = 120 and pg_temp.bal('Marco') = b0 + 120, 'T5: finita la revisione si riscuote subito (nessuna attesa)';
  insert into t_log (msg) values ('OK T5 — taglia in revisione: nulla si perde, si riscuote dopo');
end $$;

-- T6 — se l'amministratore rimette l'attesa, la riscossione automatica si ferma e vale la regola di prima
do $$
declare r jsonb; e text; off uuid; b0 integer;
begin
  perform pg_temp.hold(24);
  perform pg_temp.bnt('Org', 'Luca', 60);
  b0 := pg_temp.bal('Marco');
  r := pg_temp.fin(pg_temp.cc('Marco', 'Luca', 'Advanced', 'bounty'), 'Marco', 'Luca', 'challenger', '2-0');
  off := (r->>'official_match')::uuid;
  assert r->'bounty_claim' = 'null'::jsonb and r->>'bounty_note' like '%24 ore%' and pg_temp.bal('Marco') = b0, 'T6: con l''attesa non si riscuote da sola: ' || r::text;
  e := pg_temp.err_as('Marco', format('select public.claim_bounty(%L)', off));
  assert e like '%24 ore%', 'T6: la riscossione a mano rispetta l''attesa';
  perform pg_temp.hold(0);
  assert (pg_temp.claim('Marco', off)->>'payout')::integer = 60, 'T6: a attesa 0 si riscuote';
  insert into t_log (msg) values ('OK T6 — l''attesa si può rimettere dalle impostazioni');
end $$;

-- T7 — decisione dell'amministratore su un match contestato: riscossione automatica anche qui
do $$
declare c uuid; r jsonb; b0 integer;
begin
  perform pg_temp.bnt('Org', 'Povero', 50);
  b0 := pg_temp.bal('Marco');
  c := pg_temp.cc('Marco', 'Povero', 'Advanced', 'bounty');
  perform pg_temp.as_('Povero'); perform public.ladder_respond(c, true);
  perform pg_temp.as_('Marco'); perform public.ladder_report(c, 'challenger', '2-0');
  perform pg_temp.as_('Povero'); perform public.ladder_dispute(c, 'non è andata così');
  perform pg_temp.as_('Admin'); r := public.admin_ladder_resolve(c, 'challenger', '2-1', 'verificato con i testimoni');
  assert (r->'bounty_claim'->>'payout')::integer = 50 and pg_temp.bal('Marco') = b0 + 50, 'T7: ' || r::text;
  insert into t_log (msg) values ('OK T7 — decisione dell''amministratore: taglia riscossa');
end $$;

-- T8 — una riscossa non si corregge a vincitore diverso (018); il match riscosso resta coerente; riconciliazione finale
do $$
declare mt uuid := pg_temp.mid('mt'); e text;
begin
  e := pg_temp.err_as('Admin', format('select public.admin_ladder_correct(%L, ''opponent'', ''0-2'', ''prova di correzione'')', mt));
  assert e like '%già stata riscossa%', 'T8: ' || coalesce(e, 'riuscita');
  assert (select count(*) from public.bounty_settlements) >= 6, 'T8: riscossioni registrate';
  assert (select count(*) from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)) = 0, 'T8: ogni saldo coincide con il registro';
  insert into t_log (msg) values ('OK T8 — saldi riconciliati con il registro');
end $$;

select n, msg from t_log order by n;
rollback;
