-- =====================================================================
-- TEST DELLA MIGRAZIONE 004 (bonus 1000 BC, premi Ladder, match WPA dalla Ladder)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-setup.sql, black-market-moduli.sql, black-market-ladder.sql e black-market-ladder-rewards.sql.
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
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.tot() returns bigint language sql as $$ select coalesce(sum(balance), 0) from public.wallets $$;
create function pg_temp.set_(k text, v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting(k, v, 'impostazione di prova'); end $$;

-- R1 — Bonus iniziale 1000 BC
do $$
begin
  assert public._setting('initial_bonus') = 1000, 'R1: initial_bonus = 1000';
  assert (select count(*) from public.audit_logs where action = 'set_setting' and entity_id = 'initial_bonus' and reason like 'migrazione 004%') >= 1, 'R1: modifica del bonus tracciata in audit';
  assert pg_temp.bal('Marco') = 1000 and pg_temp.bal('Povero') = 1000, 'R1: ogni nuovo iscritto parte con 1000 BC';
  assert (select count(*) from public.ledger_entries where kind = 'initial_bonus' and amount = 1000) = 6, 'R1: 6 bonus da 1000 nel registro';
  assert public._setting('ladder_reward_bc') = 20 and public._setting('ladder_reward_max_day') = 3 and public._setting('ladder_reward_pair_day') = 1
     and public._setting('ladder_wpa_matches') = 1 and public._setting('ladder_reward_enabled') = 1 and public._setting('ladder_claim_hold_hours') = 24, 'R1: impostazioni di default';
  assert pg_temp.err_as('Marco', 'select public.admin_set_setting(''ladder_reward_bc'', 500, ''tentativo non autorizzato'')') like '%Permessi insufficienti%', 'R1: solo l''admin cambia i premi';
  insert into t_log (msg) values ('OK R1 — bonus iniziale 1000 BC per i nuovi iscritti, tracciato in audit; impostazioni Ladder presenti, modificabili solo dall''admin');
end $$;

-- R2 — Premio: la vittoria GENERA 20 BC per il vincitore, nessun trasferimento dallo sconfitto
do $$
declare r jsonb; mid uuid; t0 bigint; lg0 bigint;
begin
  t0 := pg_temp.tot(); lg0 := (select count(*) from public.ledger_entries);
  r := pg_temp.play('Marco', 'Luca', 'challenger', '2-0', 'Marco');
  mid := (select id from public.ladder_matches where challenger_id = pg_temp.uid('Marco') and opponent_id = pg_temp.uid('Luca') order by created_at desc limit 1);
  assert (r->>'reward')::int = 20 and (r->>'winner')::uuid = pg_temp.uid('Marco'), 'R2: premio 20 BC al vincitore nel risultato';
  assert pg_temp.bal('Marco') = 1020, 'R2: il vincitore ha 1020 BC';
  assert pg_temp.bal('Luca') = 1000, 'R2: lo sconfitto non perde BC (nessun trasferimento)';
  assert pg_temp.tot() = t0 + 20, 'R2: i BC totali aumentano di 20 (creati dal sistema)';
  assert (select count(*) from public.ledger_entries) = lg0 + 1, 'R2: un solo movimento nel registro';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Marco') and kind = 'ladder_reward' and amount = 20 and ref_type = 'ladder_match' and ref_id = mid and balance_after = 1020) = 1, 'R2: riga di registro corretta';
  assert (select reward_user from public.ladder_matches where id = mid) = pg_temp.uid('Marco') and (select reward_amount from public.ladder_matches where id = mid) = 20, 'R2: premio annotato sul match';
  assert (select user_id from public.ledger_entries where kind = 'ladder_reward') = pg_temp.uid('Marco'), 'R2: nessun movimento per lo sconfitto';
  -- idempotenza: la stessa operazione non si applica due volte
  perform pg_temp.as_('Marco');
  assert pg_temp.err_as('Luca', format('select public.ladder_confirm(%L)', mid)) like '%Non c''è un risultato%', 'R2: niente seconda conferma';
  assert public._ledger_move(pg_temp.uid('Marco'), 20, 'ladder_reward', 'ladder_match', mid, 'ladder:' || mid, 'duplicato') = -1, 'R2: stessa chiave = nessun doppio accredito';
  assert pg_temp.bal('Marco') = 1020, 'R2: saldo invariato dopo il tentativo duplicato';
  -- pareggio: nessun premio, nessun match ufficiale
  r := pg_temp.play('Paolo', 'Povero', 'draw', '1-1', 'Paolo');
  assert (r->>'reward')::int = 0 and r->>'official_match' is null and pg_temp.bal('Paolo') = 1000 and pg_temp.bal('Povero') = 1000, 'R2: il pareggio non dà BC né match ufficiale';
  -- vittoria di chi era stato sfidato (lato opponent)
  r := pg_temp.play('Paolo', 'Povero', 'opponent', '1-2', 'Paolo');
  assert (r->>'winner')::uuid = pg_temp.uid('Povero') and (r->>'reward')::int = 20 and pg_temp.bal('Povero') = 1020 and pg_temp.bal('Paolo') = 1000, 'R2: premio anche a chi vince da sfidato; lo sconfitto non perde nulla';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'R2: ogni saldo coincide con il registro';
  insert into t_log (msg) values ('OK R2 — vittoria = +20 BC creati dal sistema (registro, idempotenza, saldo coerente); sconfitto invariato; pareggio senza premio; premio anche a chi vince da sfidato');
end $$;

-- R3 — Limiti anti-abuso: 1 premio al giorno per avversario, 3 al giorno in totale; passate le 24 ore si riparte
do $$
declare r jsonb;
begin
  -- stessa coppia, stesso giorno: l'Elo conta, il premio e il match ufficiale no
  r := pg_temp.play('Marco', 'Luca', 'challenger', '2-1', 'Luca');
  assert (r->>'reward')::int = 0 and r->>'reward_note' like '%già premiata%', 'R3: seconda vittoria contro lo stesso avversario: nessun premio';
  assert r->>'official_match' is null and r->>'official_note' like '%già registrato%', 'R3: ... e nessun secondo match ufficiale nelle 24 ore';
  assert pg_temp.bal('Marco') = 1020 and (select elo from public.ladder_ratings where user_id = pg_temp.uid('Marco')) > 1016, 'R3: saldo fermo ma Elo aggiornato';
  r := pg_temp.play('Marco', 'Paolo', 'challenger', '2-0', 'Marco');
  assert (r->>'reward')::int = 20 and pg_temp.bal('Marco') = 1040, 'R3: seconda vittoria premiata (avversario diverso)';
  r := pg_temp.play('Marco', 'Povero', 'challenger', '2-0', 'Marco');
  assert (r->>'reward')::int = 20 and pg_temp.bal('Marco') = 1060, 'R3: terza vittoria premiata';
  r := pg_temp.play('Marco', 'Admin', 'challenger', '2-0', 'Marco');
  assert (r->>'reward')::int = 0 and r->>'reward_note' like '%limite giornaliero%' and pg_temp.bal('Marco') = 1060, 'R3: la quarta vittoria nelle 24 ore non è premiata';
  assert r->>'official_match' is not null, 'R3: ma resta un match ufficiale (avversario diverso)';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Marco') and kind = 'ladder_reward') = 3, 'R3: esattamente 3 premi nel registro';
  -- passate 24 ore si riparte (anticipo di 25 ore lo storico, solo per il test)
  alter table public.ladder_matches disable trigger ladder_matches_guard;
  update public.ladder_matches set closed_at = closed_at - interval '25 hours';
  alter table public.ladder_matches enable trigger ladder_matches_guard;
  update public.matches set verified_at = verified_at - interval '25 hours' where source = 'ladder';
  r := pg_temp.play('Marco', 'Luca', 'challenger', '2-0', 'Marco');
  assert (r->>'reward')::int = 20 and pg_temp.bal('Marco') = 1080 and r->>'official_match' is not null, 'R3: dopo 24 ore premio e match ufficiale tornano disponibili';
  assert (select max(round) from public.matches where source = 'ladder' and least(player_a, player_b) = least(pg_temp.uid('Marco'), pg_temp.uid('Luca')) and greatest(player_a, player_b) = greatest(pg_temp.uid('Marco'), pg_temp.uid('Luca'))) = 2, 'R3: il turno del secondo match ufficiale della coppia è 2';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'R3: saldi coerenti con il registro';
  insert into t_log (msg) values ('OK R3 — limiti: 1 premio/giorno per avversario, 3 premi/giorno, 1 match ufficiale/giorno per coppia; Elo sempre aggiornato; dopo 24 ore si riparte');
end $$;

-- R4 — Le vittorie Ladder sono match WPA ufficiali: evento automatico, Hall of Fame, Faction Wars
do $$
declare mo uuid; lm uuid; ev uuid; ombre uuid; lupi uuid; n0 bigint; pts0 bigint;
begin
  lm := (select id from public.ladder_matches where challenger_id = pg_temp.uid('Marco') and opponent_id = pg_temp.uid('Luca') and status = 'closed' order by closed_at limit 1);
  mo := (select official_match_id from public.ladder_matches where id = lm);
  assert mo is not null, 'R4: il match Ladder punta al match ufficiale';
  assert (select count(*) from public.matches where id = mo and status = 'verified' and source = 'ladder' and ladder_match_id = lm
            and winner_id = pg_temp.uid('Marco') and player_a = pg_temp.uid('Marco') and player_b = pg_temp.uid('Luca') and verified_by = pg_temp.uid('Luca') and verified_at is not null) = 1,
         'R4: match ufficiale verificato, vincitore corretto, verificato dal giocatore che ha confermato';
  ev := (select event_id from public.matches where id = mo);
  assert (select source from public.events where id = ev) = 'ladder' and (select created_by from public.events where id = ev) = pg_temp.uid('Admin'), 'R4: evento automatico creato a nome dell''amministratore';
  assert (select name from public.events where id = ev) like 'Ladder WPA 20__-__-__', 'R4: nome evento = Ladder WPA + data';
  assert (select count(*) from public.events where source = 'ladder') = 1, 'R4: un solo evento per giorno';
  assert not exists (select 1 from public.event_participants where event_id = ev), 'R4: nessun partecipante aggiunto (niente premi di partecipazione)';
  assert (select count(*) from public.matches where source = 'ladder') = (select count(*) from public.ladder_matches where official_match_id is not null), 'R4: un match ufficiale per ogni match Ladder che lo prevede';
  assert not exists (select 1 from public.matches m join public.ladder_matches l on l.id = m.ladder_match_id where l.reported_result = 'draw'), 'R4: i pareggi non diventano match ufficiali';
  -- Hall of Fame
  perform pg_temp.mod('hall_of_fame', true);
  assert (select count(*) from public.hof_matches_v where match_id = mo) = 1, 'R4: il match compare nella Hall of Fame';
  assert (select wins from public.hof_player_stats_v where player_id = pg_temp.uid('Marco')) = (select count(*) from public.matches where status = 'verified' and winner_id = pg_temp.uid('Marco')), 'R4: vittorie Hall of Fame = match verificati';
  assert (select events_participated from public.hof_player_stats_v where player_id = pg_temp.uid('Marco')) = 0, 'R4: nessuna partecipazione inventata';
  -- Faction Wars: i punti arrivano solo dopo l'iscrizione e non sono BC
  perform pg_temp.mod('faction_wars', true);
  perform pg_temp.as_('Marco'); ombre := public.create_faction('Ombre', null, 'O');
  perform pg_temp.as_('Luca'); lupi := public.create_faction('Lupi', null, 'L');
  perform pg_temp.as_('Paolo'); perform public.join_faction(lupi);
  assert (select coalesce(sum(points), 0) from public.faction_standings_v where season_id is null) = 0, 'R4: i match Ladder precedenti all''iscrizione non danno punti';
  pts0 := pg_temp.tot();
  perform pg_temp.play('Marco', 'Paolo', 'challenger', '2-0', 'Marco');   -- Ombre batte Lupi
  assert (select points from public.faction_standings_v where season_id is null and faction_id = ombre) = 3, 'R4: Ombre +3 per la vittoria Ladder ufficiale su un avversario di un''altra fazione';
  assert pg_temp.tot() = pts0 + 20, 'R4: i punti fazione non creano BC (cambia solo il premio Ladder di 20)';
  perform pg_temp.mod('faction_wars', false); perform pg_temp.mod('hall_of_fame', false);
  insert into t_log (msg) values ('OK R4 — vittoria Ladder = match WPA verificato nell''evento automatico del giorno; compare in Hall of Fame e dà punti fazione; pareggi esclusi');
end $$;

-- R5 — Taglie: attesa anti-accordi sui match Ladder, revisione dell''admin, nessuna attesa per i match degli organizzatori
do $$
declare b uuid; b2 uuid; mo uuid; r jsonb; ad0 integer; pa0 integer; e uuid; m uuid;
begin
  perform pg_temp.as_('Paolo'); b := public.create_bounty(pg_temp.uid('Luca'), 100, 'taglia di prova', gen_random_uuid()::text);
  ad0 := pg_temp.bal('Admin'); pa0 := pg_temp.bal('Paolo');
  r := pg_temp.play('Admin', 'Luca', 'challenger', '2-0', 'Admin');
  mo := (r->>'official_match')::uuid;
  assert mo is not null and (r->>'reward')::int = 20, 'R5: vittoria Ladder dell''Admin: match ufficiale e premio';
  assert pg_temp.err_as('Admin', format('select public.claim_bounty(%L)', mo)) like '%Match Ladder%24 ore%', 'R5: riscossione bloccata per 24 ore sui match Ladder';
  assert (select status from public.bounties where id = b) = 'active' and pg_temp.bal('Admin') = ad0 + 20, 'R5: nessun movimento dopo il rifiuto';
  update public.matches set verified_at = verified_at - interval '25 hours' where id = mo;      -- simula il passare delle 24 ore
  update public.bounties set created_at = created_at - interval '26 hours' where id = b;         -- (la taglia deve restare precedente al match)
  perform pg_temp.as_('Admin'); perform public.admin_set_bounty_review(b, true, 'verifica del match prima del pagamento');
  assert pg_temp.err_as('Admin', format('select public.claim_bounty(%L)', mo)) like '%in revisione%', 'R5: l''admin può congelare la taglia durante la verifica';
  perform pg_temp.as_('Admin'); perform public.admin_set_bounty_review(b, false, 'verifica conclusa, tutto regolare');
  perform pg_temp.as_('Admin'); r := public.claim_bounty(mo);
  assert (r->>'payout')::int = 100 and pg_temp.bal('Admin') = ad0 + 20 + 100, 'R5: dopo l''attesa la taglia si riscuote (+100)';
  assert pg_temp.err_as('Admin', format('select public.claim_bounty(%L)', mo)) is null, 'R5: seconda richiesta = stessa liquidazione, nessun doppio pagamento';
  assert pg_temp.bal('Admin') = ad0 + 120 and pg_temp.bal('Paolo') = pa0, 'R5: la quota era già stata addebitata al creatore alla pubblicazione: nessun secondo addebito';
  -- match degli organizzatori: nessuna attesa
  perform pg_temp.as_('Paolo'); b2 := public.create_bounty(pg_temp.uid('Povero'), 60, null, gen_random_uuid()::text);
  e := pg_temp.ev('Torneo di prova'); m := pg_temp.mm(e, 1, 'Luca', 'Povero', 'Luca');
  perform pg_temp.as_('Luca'); r := public.claim_bounty(m);
  assert (r->>'payout')::int = 60, 'R5: i match degli organizzatori si riscuotono subito (nessuna attesa)';
  -- attesa spenta
  perform pg_temp.set_('ladder_claim_hold_hours', 0);
  perform pg_temp.as_('Paolo'); perform public.create_bounty(pg_temp.uid('Admin'), 50, null, gen_random_uuid()::text);
  r := pg_temp.play('Povero', 'Admin', 'challenger', '2-0', 'Povero');
  perform pg_temp.as_('Povero'); r := public.claim_bounty((r->>'official_match')::uuid);
  assert (r->>'payout')::int = 50, 'R5: con attesa 0 la riscossione è immediata';
  perform pg_temp.set_('ladder_claim_hold_hours', 24);
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'R5: saldi coerenti con il registro';
  insert into t_log (msg) values ('OK R5 — taglia su match Ladder: bloccata 24 ore, congelabile dall''admin, poi riscossa una sola volta; match organizzatore senza attesa; attesa configurabile');
end $$;

-- R6 — Interruttori: premi e match ufficiali si spengono senza toccare l''Elo
do $$
declare r jsonb; e0 integer;
begin
  perform pg_temp.set_('ladder_reward_enabled', 0);
  r := pg_temp.play('Paolo', 'Admin', 'challenger', '2-0', 'Paolo');
  assert (r->>'reward')::int = 0 and r->>'reward_note' = 'premi spenti' and r->>'official_match' is not null, 'R6: premi spenti: nessun BC ma match ufficiale sì';
  perform pg_temp.set_('ladder_wpa_matches', 0);
  e0 := (select elo from public.ladder_ratings where user_id = pg_temp.uid('Povero'));
  r := pg_temp.play('Povero', 'Luca', 'challenger', '2-0', 'Povero');
  assert (r->>'reward')::int = 0 and r->>'official_match' is null and r->>'official_note' like '%spenti%', 'R6: anche i match ufficiali spenti';
  assert (select elo from public.ladder_ratings where user_id = pg_temp.uid('Povero')) > e0, 'R6: l''Elo funziona comunque';
  perform pg_temp.set_('ladder_reward_enabled', 1); perform pg_temp.set_('ladder_wpa_matches', 1);
  assert (select count(*) from public.audit_logs where action = 'set_setting' and entity_id in ('ladder_reward_enabled','ladder_wpa_matches')) = 4, 'R6: ogni cambio è nell''audit';
  insert into t_log (msg) values ('OK R6 — interruttori premi/match ufficiali: spenti non producono BC né match, l''Elo continua; cambi in audit');
end $$;

-- R7 — Contestazione e decisione dell''admin: premio e match ufficiale seguono la decisione; l''annullamento non produce nulla
do $$
declare c uuid; r jsonb; c2 uuid; pov0 integer; mo uuid; t0 bigint;
begin
  c := pg_temp.chal('Luca', 'Povero'); perform pg_temp.as_('Povero'); perform public.ladder_respond(c, true);
  perform pg_temp.as_('Luca'); perform public.ladder_report(c, 'challenger', '2-0');
  perform pg_temp.as_('Povero'); perform public.ladder_dispute(c, 'non è andata così');
  pov0 := pg_temp.bal('Povero');
  perform pg_temp.as_('Admin'); r := public.admin_ladder_resolve(c, 'opponent', '1-2', 'verificato con i testimoni');
  assert (r->>'winner')::uuid = pg_temp.uid('Povero') and (r->>'reward')::int = 20 and pg_temp.bal('Povero') = pov0 + 20, 'R7: il premio va a chi vince secondo la decisione';
  mo := (r->>'official_match')::uuid;
  assert (select winner_id from public.matches where id = mo) = pg_temp.uid('Povero') and (select verified_by from public.matches where id = mo) = pg_temp.uid('Admin'), 'R7: match ufficiale verificato dall''admin';
  t0 := pg_temp.tot();
  c2 := pg_temp.chal('Luca', 'Paolo'); perform pg_temp.as_('Paolo'); perform public.ladder_respond(c2, true);
  perform pg_temp.as_('Admin'); perform public.admin_ladder_void(c2, 'partita mai disputata');
  assert pg_temp.tot() = t0 and (select reward_amount from public.ladder_matches where id = c2) = 0 and (select official_match_id from public.ladder_matches where id = c2) is null, 'R7: match annullato = nessun premio, nessun match ufficiale';
  insert into t_log (msg) values ('OK R7 — decisione dell''admin: premio e match ufficiale assegnati al vincitore deciso; annullamento senza effetti economici');
end $$;

-- R8 — Contabilità: i BC creati sono solo premi Ladder registrati, mai tolti a nessuno
do $$
begin
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'R8: ogni saldo coincide con il registro';
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind = 'ladder_reward') = (select coalesce(sum(reward_amount), 0) from public.ladder_matches), 'R8: premi nel registro = premi annotati sui match';
  assert (select count(*) from public.ledger_entries where kind = 'ladder_reward') = (select count(*) from public.ladder_matches where reward_amount > 0), 'R8: un movimento per ogni match premiato';
  assert not exists (select 1 from public.ledger_entries le join public.ladder_matches l on l.id = le.ref_id
                      where le.kind = 'ladder_reward' and (le.user_id <> l.reward_user or le.amount <> l.reward_amount or l.status <> 'closed' or le.amount < 0)), 'R8: ogni premio è positivo e va al vincitore del match chiuso';
  assert not exists (select 1 from public.ledger_entries where kind = 'ladder_reward' and ref_type <> 'ladder_match'), 'R8: riferimento corretto';
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'R8: somma dei saldi = somma del registro';
  assert not exists (select 1 from public.ladder_matches where reward_amount > 0 and (reported_result = 'draw' or reward_user is null)), 'R8: nessun premio per pareggi';
  insert into t_log (msg) values ('OK R8 — contabilità: premi = registro = match, nessun premio negativo o per pareggio, saldi riconciliati');
end $$;

-- R9 — Sicurezza
do $$
declare lm uuid;
begin
  lm := (select id from public.ladder_matches where status = 'closed' limit 1);
  assert not has_function_privilege('authenticated', 'public._ladder_event(date)', 'execute') and not has_function_privilege('anon', 'public._ladder_event(date)', 'execute'), 'R9: _ladder_event è interna';
  assert not has_function_privilege('authenticated', 'public._ladder_close(uuid,text,text,uuid,uuid,text)', 'execute'), 'R9: _ladder_close è interna';
  assert has_function_privilege('authenticated', 'public.claim_bounty(uuid)', 'execute') and not has_function_privilege('anon', 'public.claim_bounty(uuid)', 'execute'), 'R9: permessi di claim_bounty invariati';
  assert pg_temp.err_auth('Marco', 'select public._ladder_close(gen_random_uuid(), ''challenger'', ''2-0'', null, null, null)') like '%permission denied%', 'R9: il browser non può chiudere un match';
  assert pg_temp.err_auth('Marco', format('update public.ladder_matches set reward_amount = 9999, reward_user = %L where id = %L', pg_temp.uid('Marco'), lm)) like '%permission denied%', 'R9: nessuna modifica diretta dei premi';
  assert pg_temp.err_auth('Marco', 'insert into public.ledger_entries (user_id, amount, kind, idempotency_key, balance_after) values (gen_random_uuid(), 500, ''ladder_reward'', ''x'', 500)') like '%permission denied%', 'R9: nessuna scrittura diretta nel registro';
  assert pg_temp.err_auth('Marco', 'insert into public.matches (event_id, player_a, player_b, created_by, source) values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), ''ladder'')') like '%permission denied%', 'R9: nessun match ufficiale creato a mano';
  assert pg_temp.err('insert into public.ledger_entries (user_id, amount, kind, idempotency_key, balance_after) values (gen_random_uuid(), 5, ''inventato'', ''y'', 5)') like '%ledger_entries_kind_check%', 'R9: i tipi di movimento restano limitati';
  assert pg_temp.err('update public.ledger_entries set amount = amount + 1') like '%Registro immutabile%' and pg_temp.err('delete from public.ledger_entries') like '%Registro immutabile%', 'R9: il registro resta immutabile';
  assert pg_temp.err('update public.matches set source = ''bogus''') like '%matches_source_check%', 'R9: valori di source controllati';
  assert (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) = 0, 'R9: RLS su tutte le tabelle';
  insert into t_log (msg) values ('OK R9 — permessi: funzioni interne non esposte, nessuna scrittura diretta su premi/registro/match, registro immutabile, RLS ovunque');
end $$;

select n, msg from t_log order by n;
rollback;
