-- =====================================================================
-- TEST DELLA MIGRAZIONE 005 (ruolo Moderatore e Funzioni Mod)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-setup.sql, black-market-moduli.sql, black-market-ladder.sql, black-market-ladder-rewards.sql e black-market-moderatore.sql.
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

-- Preparazione: Admin = primo registrato; Org organizzatore; Mod e Mod2 diventeranno moderatori
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Mod','Mod2','Marco','Luca','Paolo'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  insert into t_log (msg) values ('OK Preparazione: 7 utenti (Admin, Org organizzatore, Mod, Mod2, Marco, Luca, Paolo)');
end $$;
create function pg_temp.chal(a text, b text, fmt text default 'Advanced') returns uuid language plpgsql as $$
begin perform pg_temp.as_(a); return public.ladder_challenge(pg_temp.uid(b), fmt, null, gen_random_uuid()::text); end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.role_of(n text) returns text language sql as $$ select role::text from public.profiles where id = pg_temp.uid(n) $$;
-- sfida accettata e risultato inviato da 'a' (resta da confermare)
create function pg_temp.reported(a text, b text) returns uuid language plpgsql as $$
declare id uuid;
begin
  id := pg_temp.chal(a, b);
  perform pg_temp.as_(b); perform public.ladder_respond(id, true);
  perform pg_temp.as_(a); perform public.ladder_report(id, 'challenger', '2-0');
  return id;
end $$;

-- P1 — Solo l'amministratore assegna il ruolo di moderatore
do $$
begin
  assert 'moderator' = any (enum_range(null::public.app_role)::text[]), 'P1: il ruolo esiste';
  assert pg_temp.err_as('Marco', format('select public.admin_set_role(%L, ''moderator'', ''tentativo non autorizzato'')', pg_temp.uid('Marco'))) like '%Permessi insufficienti%', 'P1: un duellante non si fa moderatore';
  assert pg_temp.err_as('Org', format('select public.admin_set_role(%L, ''moderator'', ''tentativo non autorizzato'')', pg_temp.uid('Luca'))) like '%Permessi insufficienti%', 'P1: un organizzatore non assegna il ruolo';
  assert pg_temp.err_as('Admin', format('select public.admin_set_role(%L, ''moderator'', ''ok'')', pg_temp.uid('Mod'))) like '%Motivazione obbligatoria%', 'P1: motivazione obbligatoria';
  perform pg_temp.as_('Admin');
  perform public.admin_set_role(pg_temp.uid('Mod'), 'moderator', 'moderatore della community');
  perform public.admin_set_role(pg_temp.uid('Mod2'), 'moderator', 'secondo moderatore');
  assert pg_temp.role_of('Mod') = 'moderator' and pg_temp.role_of('Mod2') = 'moderator', 'P1: assegnato dall''admin';
  assert pg_temp.err_as('Mod', format('select public.admin_set_role(%L, ''moderator'', ''nomina di un amico'')', pg_temp.uid('Marco'))) like '%Permessi insufficienti%', 'P1: un moderatore non nomina moderatori';
  assert pg_temp.err_as('Mod', format('select public.admin_set_role(%L, ''admin'', ''promozione a sorpresa'')', pg_temp.uid('Mod'))) like '%Permessi insufficienti%', 'P1: un moderatore non si promuove';
  assert pg_temp.err_as('Mod', format('select public.admin_set_role(%L, ''user'', ''declassamento di prova'')', pg_temp.uid('Mod2'))) like '%Permessi insufficienti%', 'P1: un moderatore non toglie il ruolo a un altro';
  assert (select count(*) from public.audit_logs where action = 'set_role' and new_value->>'role' = 'moderator') = 2, 'P1: audit delle nomine';
  assert pg_temp.err_auth('Mod', format('update public.profiles set role = ''admin'' where id = %L', pg_temp.uid('Mod'))) like '%permission denied%', 'P1: nessuna scrittura diretta sul ruolo';
  insert into t_log (msg) values ('OK P1 — il ruolo Moderatore lo assegna solo l''admin (con motivazione e audit); nessuno può nominarsi o promuoversi');
end $$;

-- P2 — Il moderatore è anche un duellante: wallet, taglie, Ladder con premio
do $$
declare b uuid; r jsonb; c uuid;
begin
  assert pg_temp.bal('Mod') = 1000, 'P2: il moderatore ha il suo wallet';
  perform pg_temp.as_('Mod'); perform public.update_my_profile('M', true);
  b := public.create_bounty(pg_temp.uid('Marco'), 100, 'taglia del moderatore', gen_random_uuid()::text);
  assert pg_temp.bal('Mod') = 900, 'P2: può mettere una taglia';
  perform pg_temp.as_('Marco'); b := public.create_bounty(pg_temp.uid('Mod'), 60, null, gen_random_uuid()::text);
  assert (select bounty_value from public.most_wanted_v where id = pg_temp.uid('Mod')) = 60, 'P2: può ricevere taglie';
  c := pg_temp.chal('Mod', 'Luca'); perform pg_temp.as_('Luca'); perform public.ladder_respond(c, true);
  perform pg_temp.as_('Mod'); perform public.ladder_report(c, 'challenger', '2-0');
  perform pg_temp.as_('Luca'); r := public.ladder_confirm(c);
  assert (r->>'reward')::int = 20 and pg_temp.bal('Mod') = 920, 'P2: gioca in Ladder e riceve il premio come tutti';
  assert pg_temp.err_as('Mod', 'select public.ladder_expire()') is null, 'P2: ladder_expire funziona';
  insert into t_log (msg) values ('OK P2 — il moderatore gioca come un duellante: wallet, taglie, Ladder e premio');
end $$;

-- P3 — Cosa il moderatore NON può fare: moduli, crediti, ruoli, impostazioni, eventi, taglie, dati riservati
do $$
declare e uuid; t0 text; ev uuid;
begin
  ev := pg_temp.ev('Evento per i divieti');
  t0 := (select md5(string_agg(user_id || ':' || balance, ',' order by user_id)) from public.wallets);
  assert pg_temp.err_as('Mod', 'select public.admin_set_module(''ladder'', false, ''spegnimento non autorizzato'')') like '%Permessi insufficienti%', 'P3: niente moduli';
  assert pg_temp.err_as('Mod', format('select public.admin_adjust_balance(%L, 500, ''credito non autorizzato'')', pg_temp.uid('Mod'))) like '%Permessi insufficienti%', 'P3: niente rettifiche di saldo';
  assert pg_temp.err_as('Mod', 'select public.admin_set_setting(''ladder_reward_bc'', 500, ''modifica non autorizzata'')') like '%Permessi insufficienti%', 'P3: niente impostazioni (premi e bonus)';
  assert pg_temp.err_as('Mod', format('select public.award_participation(%L)', ev)) like '%Permessi insufficienti%', 'P3: niente premi di partecipazione';
  assert pg_temp.err_as('Mod', 'select public.create_event(''Evento abusivo'', current_date)') like '%Permessi insufficienti%', 'P3: non crea eventi';
  assert pg_temp.err_as('Mod', format('select public.add_participant(%L, %L)', ev, pg_temp.uid('Mod'))) like '%Permessi insufficienti%', 'P3: non aggiunge partecipanti';
  assert pg_temp.err_as('Mod', format('select public.create_match(%L, 1, %L, %L)', ev, pg_temp.uid('Marco'), pg_temp.uid('Luca'))) like '%Permessi insufficienti%', 'P3: non crea match';
  assert pg_temp.err_as('Mod', format('select public.verify_match(%L, %L)', gen_random_uuid(), pg_temp.uid('Luca'))) like '%Permessi insufficienti%', 'P3: verify_match resta degli organizzatori (usa mod_verify_match)';
  assert pg_temp.err_as('Mod', 'select public.admin_export()') like '%Permessi insufficienti%', 'P3: niente esportazione dei dati';
  assert pg_temp.err_as('Mod', format('select public.admin_cancel_bounty(%L, ''annullamento non autorizzato'')', gen_random_uuid())) like '%Permessi insufficienti%', 'P3: non annulla taglie';
  assert pg_temp.err_as('Mod', format('select public.admin_set_bounty_review(%L, true, ''revisione non autorizzata'')', gen_random_uuid())) like '%Permessi insufficienti%', 'P3: non congela taglie';
  assert pg_temp.err_as('Mod', format('select public.resolve_dispute(%L, ''chiusura non autorizzata'')', gen_random_uuid())) like '%Permessi insufficienti%', 'P3: non chiude le contestazioni generiche';
  assert pg_temp.err_as('Mod', 'select public.admin_create_season(''Stagione'', current_date, current_date, ''creazione non autorizzata'')') like '%Permessi insufficienti%', 'P3: niente stagioni (moduli)';
  assert pg_temp.rows_as('Mod', 'select * from public.audit_logs') = 0, 'P3: non legge l''audit';
  assert pg_temp.rows_as('Mod', 'select * from public.wallet_reconciliation_v') = 0, 'P3: non vede la quadratura saldi';
  assert pg_temp.rows_as('Mod', format('select * from public.wallets where user_id = %L', pg_temp.uid('Marco'))) = 0 and pg_temp.rows_as('Mod', format('select * from public.ledger_entries where user_id = %L', pg_temp.uid('Marco'))) = 0, 'P3: non vede wallet e registro altrui';
  assert pg_temp.rows_as('Mod', format('select * from public.ledger_entries where user_id = %L', pg_temp.uid('Mod'))) >= 2, 'P3: vede i propri movimenti';
  assert (select md5(string_agg(user_id || ':' || balance, ',' order by user_id)) from public.wallets) = t0, 'P3: nessun saldo è cambiato';
  assert pg_temp.err_as('Org', 'select public.admin_ladder_void(gen_random_uuid(), ''prova senza permessi'')') like '%Permessi insufficienti%' and pg_temp.err_as('Marco', 'select public.admin_set_suspended(gen_random_uuid(), true, ''prova senza permessi'')') like '%Permessi insufficienti%', 'P3: organizzatori e duellanti restano senza i poteri di moderazione';
  insert into t_log (msg) values ('OK P3 — il moderatore non può gestire moduli, crediti, impostazioni, ruoli, eventi, taglie, esportazioni, audit né vedere i saldi altrui');
end $$;

-- P4 — Verifica dei match ufficiali
do $$
declare ev uuid; m1 uuid; m2 uuid; m3 uuid; b uuid; r jsonb; mar0 integer;
begin
  ev := pg_temp.ev('Torneo da verificare');
  perform pg_temp.as_('Org');
  m1 := public.create_match(ev, 1, pg_temp.uid('Marco'), pg_temp.uid('Luca'));
  m2 := public.create_match(ev, 2, pg_temp.uid('Mod'), pg_temp.uid('Paolo'));
  m3 := public.create_match(ev, 3, pg_temp.uid('Luca'), pg_temp.uid('Paolo'));
  perform pg_temp.as_('Marco'); b := public.create_bounty(pg_temp.uid('Paolo'), 100, null, gen_random_uuid()::text);
  mar0 := pg_temp.bal('Marco');
  assert pg_temp.err_as('Marco', format('select public.mod_verify_match(%L, %L)', m1, pg_temp.uid('Marco'))) like '%Permessi insufficienti%', 'P4: un duellante non verifica';
  assert pg_temp.err_as('Org', format('select public.mod_verify_match(%L, %L)', m1, pg_temp.uid('Marco'))) like '%Permessi insufficienti%', 'P4: l''organizzatore usa verify_match, non la funzione mod';
  assert pg_temp.err_as('Mod', format('select public.mod_verify_match(%L, %L)', m1, pg_temp.uid('Paolo'))) like '%uno dei due giocatori%', 'P4: il vincitore deve essere uno dei due';
  assert pg_temp.err_as('Mod', format('select public.mod_verify_match(%L, null)', m1)) like '%uno dei due giocatori%', 'P4: vincitore obbligatorio';
  assert pg_temp.err_as('Mod', format('select public.mod_verify_match(%L, %L)', gen_random_uuid(), pg_temp.uid('Marco'))) like '%inesistente%', 'P4: match inesistente';
  assert pg_temp.err_as('Mod', format('select public.mod_verify_match(%L, %L)', m2, pg_temp.uid('Mod'))) like '%in cui giochi tu%', 'P4: non verifica un match in cui gioca';
  assert pg_temp.err_as('Mod', format('select public.mod_verify_match(%L, %L)', m1, pg_temp.uid('Marco'))) is null, 'P4: verifica un match di un evento non suo';
  assert (select status::text || winner_id::text || verified_by::text from public.matches where id = m1) = 'verified' || pg_temp.uid('Marco')::text || pg_temp.uid('Mod')::text, 'P4: match verificato, vincitore e verificatore registrati';
  assert (select count(*) from public.audit_logs where action = 'mod_verify_match' and actor_id = pg_temp.uid('Mod') and entity_id = m1::text) = 1, 'P4: audit';
  assert pg_temp.err_as('Mod2', format('select public.mod_verify_match(%L, %L)', m1, pg_temp.uid('Luca'))) like '%già verificato%', 'P4: un match verificato non si cambia';
  assert pg_temp.err_as('Mod2', format('select public.mod_verify_match(%L, %L)', m2, pg_temp.uid('Mod'))) is null, 'P4: un altro moderatore può verificare il match del collega';
  assert pg_temp.err_as('Admin', format('select public.mod_verify_match(%L, %L)', m3, pg_temp.uid('Luca'))) is null, 'P4: anche l''admin può usarla';
  -- la riscossione funziona come per ogni match ufficiale (nessuna attesa: non è un match Ladder)
  perform pg_temp.as_('Luca'); r := public.claim_bounty(m3);
  assert (r->>'payout')::int = 100 and pg_temp.bal('Marco') = mar0 and pg_temp.bal('Luca') >= 1100, 'P4: taglia riscossa dal vincitore verificato dal moderatore/admin';
  assert (select count(*) from public.matches where status = 'pending') = 0, 'P4: nessun match rimasto in attesa';
  insert into t_log (msg) values ('OK P4 — verifica dei match ufficiali: da qualsiasi evento, mai il proprio, mai due volte, con audit; le taglie si riscuotono come sempre');
end $$;

-- P5 — Ladder: decisione dei match contestati
do $$
declare c uuid; c2 uuid; c3 uuid; r jsonb; luc0 integer; marco0 integer;
begin
  c := pg_temp.reported('Marco', 'Paolo');
  perform pg_temp.as_('Paolo'); perform public.ladder_dispute(c, 'non è andata così');
  c2 := pg_temp.reported('Mod', 'Luca');
  perform pg_temp.as_('Luca'); perform public.ladder_dispute(c2, 'contesto');
  c3 := pg_temp.chal('Luca', 'Marco');
  assert pg_temp.rows_as('Mod2', 'select * from public.ladder_matches where status = ''disputed''') = 2, 'P5: il moderatore vede i match contestati';
  assert pg_temp.rows_as('Org', 'select * from public.ladder_matches where status = ''disputed''') = 0, 'P5: un organizzatore no';
  assert pg_temp.rows_as('Admin', 'select * from public.ladder_matches where status = ''disputed''') = 2, 'P5: l''admin sì';
  assert pg_temp.err_as('Marco', format('select public.admin_ladder_resolve(%L, ''challenger'', ''2-0'', ''decisione non autorizzata'')', c)) like '%Permessi insufficienti%', 'P5: un duellante non decide';
  assert pg_temp.err_as('Org', format('select public.admin_ladder_void(%L, ''annullamento non autorizzato'')', c)) like '%Permessi insufficienti%', 'P5: un organizzatore non annulla';
  assert pg_temp.err_as('Mod', format('select public.admin_ladder_resolve(%L, ''challenger'', ''2-0'', ''decido il mio'')', c2)) like '%in cui giochi tu%', 'P5: non decide un proprio match';
  assert pg_temp.err_as('Mod', format('select public.admin_ladder_void(%L, ''annullo il mio'')', c2)) like '%in cui giochi tu%', 'P5: non annulla un proprio match';
  assert pg_temp.err_as('Mod', format('select public.admin_ladder_resolve(%L, ''challenger'', ''2-0'', ''no'')', c)) like '%Motivazione obbligatoria%', 'P5: motivazione obbligatoria';
  marco0 := pg_temp.bal('Marco');
  perform pg_temp.as_('Mod'); r := public.admin_ladder_resolve(c, 'opponent', '0-2', 'verificato con i testimoni');
  assert (r->>'winner')::uuid = pg_temp.uid('Paolo') and (select status from public.ladder_matches where id = c) = 'closed', 'P5: il moderatore decide il match contestato';
  assert (r->>'reward')::int = 20 and (r->>'official_match') is not null and pg_temp.bal('Marco') = marco0, 'P5: premio e match ufficiale seguono la decisione (regole della 004), lo sconfitto non perde BC';
  assert (select verified_by from public.matches where id = (r->>'official_match')::uuid) = pg_temp.uid('Mod'), 'P5: il moderatore risulta verificatore';
  assert (select count(*) from public.audit_logs where action = 'admin_ladder_resolve' and actor_id = pg_temp.uid('Mod')) = 1, 'P5: audit';
  perform pg_temp.as_('Mod2'); perform public.admin_ladder_void(c2, 'partita mai disputata');
  assert (select status from public.ladder_matches where id = c2) = 'voided' and (select reward_amount from public.ladder_matches where id = c2) = 0, 'P5: un altro moderatore annulla il match del collega, senza premi';
  perform pg_temp.as_('Mod'); perform public.admin_ladder_void(c3, 'sfida abbandonata');
  assert (select status from public.ladder_matches where id = c3) = 'voided', 'P5: annulla una sfida in attesa';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('ladder', false, 'prova modulo spento');
  assert pg_temp.err_as('Mod', format('select public.admin_ladder_void(%L, ''a modulo spento'')', c)) like '%Modulo non attivo%', 'P5: a Ladder spenta il moderatore è bloccato come l''admin';
  assert pg_temp.rows_as('Mod', 'select * from public.ladder_matches') >= 3, 'P5: ma vede lo storico per controllarlo';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('ladder', true, 'riattivazione di prova');
  insert into t_log (msg) values ('OK P5 — Ladder: il moderatore vede e decide i match contestati o li annulla (mai i propri), con audit; segue interruttore del modulo');
end $$;

-- P6 — Rimuovere un duellante (sospensione)
do $$
declare t0 text;
begin
  t0 := (select md5(string_agg(user_id || ':' || balance, ',' order by user_id)) from public.wallets);
  assert pg_temp.err_as('Mod', format('select public.admin_set_suspended(%L, true, ''no'')', pg_temp.uid('Paolo'))) like '%Motivazione obbligatoria%', 'P6: motivazione obbligatoria';
  assert pg_temp.err_as('Mod', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto'')', pg_temp.uid('Mod'))) like '%te stesso%', 'P6: non sospende sé stesso';
  assert pg_temp.err_as('Mod', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto'')', pg_temp.uid('Admin'))) like '%amministratori o altri moderatori%', 'P6: non sospende l''admin';
  assert pg_temp.err_as('Mod', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto'')', pg_temp.uid('Mod2'))) like '%amministratori o altri moderatori%', 'P6: non sospende un altro moderatore';
  assert pg_temp.err_as('Marco', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto'')', pg_temp.uid('Paolo'))) like '%Permessi insufficienti%', 'P6: un duellante non sospende';
  assert pg_temp.err_as('Org', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto'')', pg_temp.uid('Paolo'))) like '%Permessi insufficienti%', 'P6: un organizzatore non sospende';
  assert pg_temp.err_as('Mod', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto'')', gen_random_uuid())) like '%inesistente%', 'P6: utente inesistente';
  assert pg_temp.err_as('Mod', format('select public.admin_set_suspended(%L, true, ''comportamento scorretto in Ladder'')', pg_temp.uid('Paolo'))) is null, 'P6: sospende un duellante';
  assert (select suspended from public.profiles where id = pg_temp.uid('Paolo')), 'P6: Paolo è sospeso';
  assert pg_temp.err_as('Paolo', format('select public.ladder_challenge(%L, ''GOAT'', null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%Account sospeso%', 'P6: il sospeso non può agire';
  assert pg_temp.err_as('Luca', format('select public.ladder_challenge(%L, ''GOAT'', null, %L)', pg_temp.uid('Paolo'), gen_random_uuid()::text)) like '%non disponibile%', 'P6: non si può sfidare un sospeso';
  assert (select count(*) from public.wallets) = 7 and (select count(*) from public.profiles where id = pg_temp.uid('Paolo')) = 1 and (select md5(string_agg(user_id || ':' || balance, ',' order by user_id)) from public.wallets) = t0, 'P6: storico e saldi intatti (nessuna cancellazione)';
  assert pg_temp.err_as('Mod2', format('select public.admin_set_suspended(%L, false, ''errore, riattivato'')', pg_temp.uid('Paolo'))) is null, 'P6: riattivazione riuscita';
  assert not (select suspended from public.profiles where id = pg_temp.uid('Paolo')), 'P6: Paolo è di nuovo attivo';
  assert (select count(*) from public.audit_logs where action = 'set_suspended' and actor_id in (pg_temp.uid('Mod'), pg_temp.uid('Mod2'))) = 2, 'P6: audit delle sospensioni';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Mod2'), true, 'prova di sospensione del moderatore');
  assert pg_temp.err_as('Mod2', format('select public.admin_ladder_void(%L, ''da sospeso'')', gen_random_uuid())) like '%Account sospeso%', 'P6: un moderatore sospeso perde i poteri';
  assert pg_temp.rows_as('Mod2', 'select * from public.ladder_matches where status = ''disputed''') = 0, 'P6: e non vede più i match riservati';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Mod2'), false, 'fine della prova');
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Mod'), true, 'sospendo anche il primo moderatore');
  assert (select suspended from public.profiles where id = pg_temp.uid('Mod')), 'P6: l''admin può sospendere un moderatore';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Mod'), false, 'fine della prova');
  insert into t_log (msg) values ('OK P6 — rimozione di un duellante = sospensione motivata e annullabile; non tocca admin/moderatori né lo storico; il moderatore sospeso perde i poteri');
end $$;

-- P7 — Regressione dei ruoli e permessi del database
do $$
declare f text;
begin
  assert pg_temp.err_as('Org', 'select public.create_event(''Evento dell''''organizzatore'', current_date)') is null, 'P7: l''organizzatore crea ancora eventi';
  assert pg_temp.err_as('Marco', 'select public.create_event(''Evento abusivo'', current_date)') like '%Permessi insufficienti%', 'P7: il duellante no';
  assert pg_temp.err_as('Marco', 'select public.admin_adjust_balance(gen_random_uuid(), 5, ''prova senza permessi'')') like '%Permessi insufficienti%' and pg_temp.err_as('Admin', format('select public.admin_adjust_balance(%L, 5, ''rettifica di prova'')', pg_temp.uid('Marco'))) is null, 'P7: l''admin conserva i suoi poteri';
  assert pg_temp.err_as('Admin', 'select public.admin_set_module(''ladder'', true, ''conferma modulo'')') is null, 'P7: l''admin gestisce i moduli';
  foreach f in array array['is_staff()','mod_verify_match(uuid,uuid)'] loop
    assert not has_function_privilege('anon', 'public.' || f, 'execute'), 'P7: anon non esegue ' || f;
    assert has_function_privilege('authenticated', 'public.' || f, 'execute'), 'P7: authenticated esegue ' || f;
  end loop;
  assert not has_function_privilege('authenticated', 'public._need_role(public.app_role[])', 'execute'), 'P7: _need_role resta interna';
  assert pg_temp.rows_as('Marco', 'select * from public.ladder_matches where status = ''accepted''') >= 0, 'P7: lettura ordinaria Ladder';
  assert (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) = 0, 'P7: RLS su tutte le tabelle';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'P7: saldi coerenti con il registro';
  assert (select count(*) from public.ledger_entries where kind = 'admin_adjustment') = 1, 'P7: l''unica rettifica è quella dell''admin';
  insert into t_log (msg) values ('OK P7 — organizzatori e duellanti invariati, admin conserva ogni potere, permessi del database coerenti, saldi riconciliati');
end $$;

select n, msg from t_log order by n;
rollback;
