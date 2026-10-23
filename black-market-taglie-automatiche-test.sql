-- =====================================================================
-- TEST DELLA MIGRAZIONE 020 (riscossione delle taglie sempre automatica)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…020 (black-market-setup.sql … black-market-taglie-automatiche.sql).
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




do $$ begin perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Povero'), 'moderator', 'moderatore di prova'); end $$;
create function pg_temp.sett(m uuid) returns bigint language sql as $$ select count(*) from public.bounty_settlements where match_id = m $$;
create function pg_temp.corr(id uuid, res text, sc text, why text default 'correzione di prova') returns jsonb language plpgsql as $$
begin perform pg_temp.as_('Admin'); return public.admin_ladder_correct(id, res, sc, why); end $$;

-- A1 — match verificato da un organizzatore: la taglia si riscuote da sola, senza pulsante
do $$
declare ev uuid; m uuid; b0 integer; tot0 bigint; r jsonb;
begin
  assert not has_function_privilege('authenticated', 'public._bounty_autoclaim(uuid)', 'execute') and not has_function_privilege('authenticated', 'public._bounty_sweep_target(uuid)', 'execute'), 'A1: funzioni interne non esposte';
  perform pg_temp.bnt('Org', 'Luca', 100); perform pg_temp.bnt('Paolo', 'Luca', 50);
  ev := pg_temp.ev('Torneo A1'); b0 := pg_temp.bal('Marco'); tot0 := pg_temp.tot();
  m := pg_temp.mm(ev, 1, 'Marco', 'Luca', 'Marco');
  assert pg_temp.sett(m) = 1 and pg_temp.bal('Marco') = b0 + 150 and pg_temp.tot() = tot0 + 150, 'A1: riscossa alla verifica: +150';
  assert pg_temp.act_b('Luca') = 0, 'A1: taglie su Luca riscosse';
  r := pg_temp.claim('Marco', m);
  assert (r->>'already')::boolean and pg_temp.bal('Marco') = b0 + 150, 'A1: il pulsante non paga due volte';
  assert (select count(*) from public.ledger_entries where kind = 'bounty_payout' and ref_id = (select id from public.bounty_settlements where match_id = m)) = 1, 'A1: un solo movimento';
  insert into t_log (msg) values ('OK A1 — verifica dell''organizzatore: taglia riscossa da sola');
end $$;

-- A2 — verifica del moderatore e quota propria restituita; se vince il bersaglio non si riscuote nulla
do $$
declare ev uuid; m uuid; b0 integer;
begin
  perform pg_temp.bnt('Marco', 'Paolo', 50); perform pg_temp.bnt('Org', 'Paolo', 100);
  ev := pg_temp.ev('Torneo A2'); b0 := pg_temp.bal('Marco');
  m := pg_temp.mm(ev, 1, 'Paolo', 'Marco', null);
  assert pg_temp.sett(m) = 0, 'A2: da verificare: niente';
  perform pg_temp.as_('Povero'); perform public.mod_verify_match(m, pg_temp.uid('Paolo'));
  assert pg_temp.sett(m) = 0 and pg_temp.act_b('Paolo') = 2, 'A2: ha vinto il bersaglio: nessuna riscossa';
  m := pg_temp.mm(ev, 2, 'Marco', 'Paolo', null);
  perform pg_temp.as_('Povero'); perform public.mod_verify_match(m, pg_temp.uid('Marco'));
  assert pg_temp.sett(m) = 1 and pg_temp.bal('Marco') = b0 + 150 and pg_temp.act_b('Paolo') = 0, 'A2: verifica del moderatore: +100 di taglie e 50 di quota propria';
  insert into t_log (msg) values ('OK A2 — moderatore, quota propria, vittoria del bersaglio');
end $$;

-- A3 — taglia in revisione: sospesa; appena la revisione finisce, la riscossione parte da sola
do $$
declare ev uuid; m uuid; b0 integer; bid uuid;
begin
  perform pg_temp.bnt('Org', 'Povero', 100); perform pg_temp.bnt('Paolo', 'Povero', 50);
  select id into bid from public.bounties where target_id = pg_temp.uid('Povero') and creator_id = pg_temp.uid('Org') and status = 'active';
  perform pg_temp.as_('Admin'); perform public.admin_set_bounty_review(bid, true, 'controllo di prova');
  ev := pg_temp.ev('Torneo A3'); b0 := pg_temp.bal('Luca');
  m := pg_temp.mm(ev, 1, 'Luca', 'Povero', 'Luca');
  assert pg_temp.sett(m) = 0 and pg_temp.bal('Luca') = b0, 'A3: in revisione: sospesa, il match è comunque verificato';
  perform pg_temp.as_('Admin'); perform public.admin_set_bounty_review(bid, false, 'controllo finito');
  assert pg_temp.sett(m) = 1 and pg_temp.bal('Luca') = b0 + 150 and pg_temp.act_b('Povero') = 0, 'A3: tolta la revisione la riscossione parte da sola';
  insert into t_log (msg) values ('OK A3 — revisione: sospesa, poi automatica');
end $$;

-- A4 — vittorie già registrate e mai riscosse (prima della migrazione): la riscossione una tantum
do $$
declare ev uuid; m uuid; b0 integer; n integer;
begin
  perform pg_temp.bnt('Org', 'Marco', 100);
  ev := pg_temp.ev('Torneo A4'); b0 := pg_temp.bal('Paolo');
  alter table public.matches disable trigger matches_bounty_autoclaim;            -- com'era prima della migrazione
  m := pg_temp.mm(ev, 1, 'Paolo', 'Marco', 'Paolo');
  alter table public.matches enable trigger matches_bounty_autoclaim;
  assert pg_temp.sett(m) = 0 and pg_temp.act_b('Marco') = 1, 'A4: vittoria vecchia mai riscossa';
  -- la stessa ricerca della migrazione
  perform public._bounty_autoclaim(id) from public.matches where status = 'verified' and winner_id is not null and bounty_eligible and not exists (select 1 from public.bounty_settlements s where s.match_id = matches.id);
  assert pg_temp.sett(m) = 1 and pg_temp.bal('Paolo') = b0 + 100, 'A4: recuperata';
  insert into t_log (msg) values ('OK A4 — una tantum per le vittorie già registrate');
end $$;

-- A5 — dove non si riscuote: sfida Ladder normale, nessuna taglia, taglia nata dopo la vittoria
do $$
declare ev uuid; m uuid; r jsonb; n0 bigint;
begin
  perform pg_temp.bnt('Org', 'Luca', 100);
  r := pg_temp.fin(pg_temp.cc('Marco', 'Luca', 'Advanced', 'ladder'), 'Marco', 'Luca', 'challenger', '2-0');
  assert pg_temp.act_b('Luca') = 1 and r->'bounty_claim' = 'null'::jsonb, 'A5: Ladder normale: la taglia non è in gioco';
  ev := pg_temp.ev('Torneo A5'); m := pg_temp.mm(ev, 1, 'Marco', 'Povero', 'Marco');
  assert pg_temp.sett(m) = 0, 'A5: nessuna taglia sul perdente: nessuna riscossione';
  perform pg_temp.bnt('Org', 'Povero', 70);
  perform pg_temp.as_('Admin'); perform public._bounty_sweep_target(pg_temp.uid('Povero'));
  assert pg_temp.sett(m) = 0 and pg_temp.act_b('Povero') = 1, 'A5: una taglia nata dopo la vittoria non la riguarda';
  insert into t_log (msg) values ('OK A5 — nessuna riscossione dove non è dovuta');
end $$;

-- A6 — correzione dell'amministratore da pareggio a vittoria: il nuovo match ufficiale riscuote da solo
do $$
declare mt uuid; r jsonb; b0 integer; bm0 integer;
begin
  perform pg_temp.bnt('Org', 'Paolo', 100);
  mt := pg_temp.cc('Luca', 'Paolo', 'Advanced', 'both');
  r := pg_temp.fin(mt, 'Luca', 'Paolo', 'draw', '1-1');
  assert r->'bounty_claim' = 'null'::jsonb and pg_temp.act_b('Paolo') = 1, 'A6: pareggio: la taglia resta';
  b0 := pg_temp.bal('Luca');
  r := pg_temp.corr(mt, 'challenger', '2-0', 'ha vinto Luca');
  assert pg_temp.bal('Luca') = b0 + 100 + 20 and pg_temp.act_b('Paolo') = 0, 'A6: premio + taglia (' || b0 || ' → ' || pg_temp.bal('Luca') || ')';
  assert pg_temp.sett((select official_match_id from public.ladder_matches where id = mt)) = 1, 'A6: riscossione registrata';
  insert into t_log (msg) values ('OK A6 — correzione: pareggio → vittoria, taglia riscossa da sola');
end $$;

-- A7 — Ladder: stessa riscossione di prima (una sola, anche con il trigger) e riconciliazione
do $$
declare mt uuid; r jsonb; b0 integer;
begin
  perform pg_temp.bnt('Org', 'Luca', 100); perform pg_temp.bnt('Marco', 'Luca', 50);
  b0 := pg_temp.bal('Paolo');
  mt := pg_temp.cc('Paolo', 'Luca', 'Advanced', 'both');
  r := pg_temp.fin(mt, 'Paolo', 'Luca', 'challenger', '2-0');
  assert (r->'bounty_claim'->>'payout')::integer = 250 and pg_temp.bal('Paolo') = b0 + 250 + 20, 'A7: ' || r::text;
  assert (select count(*) from public.bounty_settlements s where s.match_id = (r->>'official_match')::uuid) = 1, 'A7: una sola riscossione';
  assert (select count(*) from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0)) = 0, 'A7: ogni saldo coincide con il registro';
  assert (select count(*) from public.bounties where status in ('settled') ) >= 5 and not exists (select 1 from public.bounties b where b.status = 'settled' and b.settlement_id is null), 'A7: taglie riscosse con riscossione collegata';
  insert into t_log (msg) values ('OK A7 — Ladder: una sola riscossione, saldi riconciliati');
end $$;

select n, msg from t_log order by n;
rollback;
