-- =====================================================================
-- TEST DEI 10 SCENARI — da eseguire nel SQL Editor DOPO la migrazione 001.
-- Gira tutto dentro una transazione e finisce con ROLLBACK: non lascia dati.
-- Se un controllo fallisce compare un errore con il nome dello scenario.
-- Se tutto va bene l'ultima tabella mostra "OK" per ogni scenario.
-- =====================================================================
begin;
create temp table t_log (n serial, msg text);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-test-' || n)::uuid $$;
create function pg_temp.act(u uuid) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.bv(n text) returns integer language sql as $$ select coalesce((select bounty_value from public.bounty_value_v where target_id = pg_temp.uid(n)), 0) $$;
create function pg_temp.topup(n text, amt integer) returns void language plpgsql as $$
begin perform pg_temp.act(pg_temp.uid('Admin')); perform public.admin_adjust_balance(pg_temp.uid(n), amt, 'ricarica di test'); end $$;
create function pg_temp.bounty(c text, t text, amt integer) returns uuid language plpgsql as $$
begin perform pg_temp.act(pg_temp.uid(c)); return public.create_bounty(pg_temp.uid(t), amt, null, gen_random_uuid()::text); end $$;
create function pg_temp.mk_match(a text, b text, winner text) returns uuid language plpgsql as $$
declare ev uuid; m uuid;
begin
  perform pg_temp.act(pg_temp.uid('Org'));
  ev := public.create_event('Torneo di test ' || gen_random_uuid()::text, current_date);
  m := public.create_match(ev, 1, pg_temp.uid(a), pg_temp.uid(b));
  if winner is not null then perform public.verify_match(m, pg_temp.uid(winner)); end if;
  return m;
end $$;

-- Preparazione: 8 utenti (Admin e Org con ruoli, tutti disposti a ricevere taglie)
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Marco','Luca','Andrea','Giulia','Paolo','Povero'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.act(pg_temp.uid(n));
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  update public.profiles set role = 'admin' where id = pg_temp.uid('Admin');
  perform pg_temp.act(pg_temp.uid('Admin'));
  perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  assert pg_temp.bal('Marco') = 300, 'Bonus iniziale: ogni utente parte con 300 BC';
  insert into t_log (msg) values ('OK Preparazione: utenti, ruoli, bonus iniziale 300 BC');
end $$;

-- Scenario 1 — Taglia normale
do $$
declare m uuid; r jsonb; b0 integer;
begin
  perform pg_temp.topup('Giulia', 300);
  perform pg_temp.bounty('Marco', 'Luca', 200); perform pg_temp.bounty('Andrea', 'Luca', 300); perform pg_temp.bounty('Giulia', 'Luca', 500);
  assert pg_temp.bv('Luca') = 1000, 'S1: il Bounty Value di Luca deve essere 1000';
  m := pg_temp.mk_match('Paolo', 'Luca', 'Paolo'); b0 := pg_temp.bal('Paolo');
  perform pg_temp.act(pg_temp.uid('Paolo')); r := public.claim_bounty(m);
  assert (r->>'payout')::integer = 1000, 'S1: Paolo deve incassare 1000';
  assert pg_temp.bal('Paolo') = b0 + 1000, 'S1: saldo di Paolo +1000';
  assert pg_temp.bv('Luca') = 0, 'S1: il Bounty Value di Luca torna a zero';
  insert into t_log (msg) values ('OK Scenario 1 — taglia normale: 200+300+500 = 1000 BC, incassati da Paolo, valore azzerato');
end $$;

-- Scenario 2 — Il vincitore ha finanziato una quota
do $$
declare m uuid; r jsonb;
begin
  perform pg_temp.topup('Marco', 100); perform pg_temp.topup('Andrea', 300);
  perform pg_temp.bounty('Marco', 'Luca', 200); perform pg_temp.bounty('Andrea', 'Luca', 300);
  assert pg_temp.bal('Marco') = 0, 'S2: Marco ha impegnato tutto';
  m := pg_temp.mk_match('Marco', 'Luca', 'Marco');
  perform pg_temp.act(pg_temp.uid('Marco')); r := public.claim_bounty(m);
  assert (r->>'payout')::integer = 300 and (r->>'refunded')::integer = 200, 'S2: premio 300 e rimborso 200';
  assert pg_temp.bal('Marco') = 500, 'S2: saldo finale di Marco = 500';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Marco') and kind = 'bounty_payout' and amount = 300 and ref_id = (r->>'settlement_id')::uuid) = 1, 'S2: riga di registro del premio';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Marco') and kind = 'bounty_refund' and amount = 200 and ref_id = (r->>'settlement_id')::uuid) = 1, 'S2: riga di registro del rimborso';
  insert into t_log (msg) values ('OK Scenario 2 — il vincitore Marco riavuto 200 BC propri e incassa 300 BC di Andrea (registro con due righe distinte)');
end $$;

-- Scenario 3 — Nessun risultato verificato
do $$
declare m uuid; e text;
begin
  perform pg_temp.topup('Andrea', 50); perform pg_temp.bounty('Andrea', 'Luca', 50);
  m := pg_temp.mk_match('Paolo', 'Luca', null);                 -- match registrato ma NON verificato
  perform pg_temp.act(pg_temp.uid('Paolo'));
  begin perform public.claim_bounty(m); e := null; exception when others then e := sqlerrm; end;
  assert e like '%non verificato%', 'S3: la riscossione senza verifica deve essere rifiutata (ricevuto: ' || coalesce(e, 'nessun errore') || ')';
  begin perform public.claim_bounty(gen_random_uuid()); e := null; exception when others then e := sqlerrm; end;
  assert e like '%inesistente%', 'S3: un match inventato deve essere rifiutato';
  assert pg_temp.bv('Luca') = 50, 'S3: la taglia di Luca resta intatta';
  insert into t_log (msg) values ('OK Scenario 3 — senza match verificato nessuna taglia viene liquidata');
end $$;

-- Scenario 4 — Doppia riscossione (richieste ripetute sullo stesso match)
do $$
declare m uuid; r1 jsonb; r2 jsonb; b0 integer; e text;
begin
  m := pg_temp.mk_match('Paolo', 'Luca', 'Paolo'); b0 := pg_temp.bal('Paolo');
  perform pg_temp.act(pg_temp.uid('Paolo')); r1 := public.claim_bounty(m); r2 := public.claim_bounty(m);
  assert (r1->>'payout')::integer = 50 and (r2->>'already')::boolean, 'S4: la seconda richiesta deve risultare gia'' evasa';
  assert pg_temp.bal('Paolo') = b0 + 50, 'S4: Paolo incassa una sola volta';
  assert (select count(*) from public.ledger_entries where ref_id = (r1->>'settlement_id')::uuid) = 1, 'S4: un solo movimento nel registro';
  perform pg_temp.act(pg_temp.uid('Luca'));
  begin perform public.claim_bounty(m); e := null; exception when others then e := sqlerrm; end;
  assert e like '%Solo il vincitore%', 'S4: lo sconfitto non puo'' riscuotere';
  insert into t_log (msg) values ('OK Scenario 4 — richieste ripetute: un solo pagamento (vincolo unique sul match + lock di riga)');
end $$;

-- Scenario 5 — Saldo insufficiente
do $$
declare e text; b0 integer;
begin
  perform pg_temp.topup('Povero', -200);
  assert pg_temp.bal('Povero') = 100, 'S5: Povero ha 100 BC';
  perform pg_temp.act(pg_temp.uid('Povero'));
  begin perform public.create_bounty(pg_temp.uid('Luca'), 150, null, gen_random_uuid()::text); e := null; exception when others then e := sqlerrm; end;
  assert e like '%Saldo insufficiente%', 'S5: deve essere rifiutata (ricevuto: ' || coalesce(e, 'nessun errore') || ')';
  assert pg_temp.bal('Povero') = 100, 'S5: il saldo resta invariato';
  assert (select count(*) from public.bounties where creator_id = pg_temp.uid('Povero')) = 0, 'S5: nessuna taglia creata';
  insert into t_log (msg) values ('OK Scenario 5 — 150 BC con 100 BC di saldo: rifiutata, saldo invariato');
end $$;

-- Scenario 6 — Taglia su sé stessi
do $$
declare e text;
begin
  perform pg_temp.act(pg_temp.uid('Marco'));
  begin perform public.create_bounty(pg_temp.uid('Marco'), 100, null, gen_random_uuid()::text); e := null; exception when others then e := sqlerrm; end;
  assert e like '%te stesso%', 'S6: deve essere rifiutata';
  insert into t_log (msg) values ('OK Scenario 6 — taglia su sé stessi: rifiutata');
end $$;

-- Scenario 7 — Risultato manipolato / scritture dirette
do $$
declare m uuid; e text; v_paolo uuid := pg_temp.uid('Paolo'); v_luca uuid := pg_temp.uid('Luca');
begin
  m := pg_temp.mk_match('Paolo', 'Luca', null);
  perform pg_temp.act(v_paolo);
  begin perform public.verify_match(m, v_paolo); e := null; exception when others then e := sqlerrm; end;
  assert e like '%Permessi insufficienti%', 'S7: un giocatore non puo'' verificare un match';
  perform pg_temp.act(pg_temp.uid('Andrea'));
  begin perform public.verify_match(m, v_paolo); e := null; exception when others then e := sqlerrm; end;
  assert e like '%Permessi insufficienti%', 'S7: neppure un altro utente';
  begin
    execute 'set local role authenticated';
    update public.wallets set balance = 1000000 where user_id = v_paolo;
    raise exception 'FALLITO: la scrittura diretta sul wallet e'' stata permessa';
  exception when insufficient_privilege then null; end;
  begin
    execute 'set local role authenticated';
    update public.matches set status = 'verified', winner_id = v_paolo where id = m;
    raise exception 'FALLITO: la modifica diretta del match e'' stata permessa';
  exception when insufficient_privilege then null; end;
  begin update public.ledger_entries set amount = 999 where user_id = v_paolo; e := null; exception when others then e := sqlerrm; end;
  assert e like '%immutabile%', 'S7: il registro contabile non e'' modificabile';
  insert into t_log (msg) values ('OK Scenario 7 — verifica match, scritture dirette su wallet/match e modifiche al registro: tutto rifiutato');
end $$;

-- Scenario 8 — Entrambi hanno una taglia
do $$
declare m uuid; r jsonb;
begin
  perform pg_temp.topup('Andrea', 100); perform pg_temp.bounty('Andrea', 'Luca', 100); perform pg_temp.bounty('Giulia', 'Paolo', 100);
  m := pg_temp.mk_match('Paolo', 'Luca', 'Paolo');
  perform pg_temp.act(pg_temp.uid('Paolo')); r := public.claim_bounty(m);
  assert (r->>'payout')::integer = 100, 'S8: Paolo riscuote la taglia di Luca';
  assert pg_temp.bv('Luca') = 0 and pg_temp.bv('Paolo') = 100, 'S8: la taglia su Paolo resta attiva';
  insert into t_log (msg) values ('OK Scenario 8 — il vincitore riscuote quella del perdente, la propria resta attiva');
end $$;

-- Scenario 9 — Richiesta duplicata
do $$
declare req text := gen_random_uuid()::text; id1 uuid; id2 uuid; b0 integer;
begin
  perform pg_temp.topup('Marco', 100); b0 := pg_temp.bal('Marco');
  perform pg_temp.act(pg_temp.uid('Marco'));
  id1 := public.create_bounty(pg_temp.uid('Luca'), 50, 'Rivincita!', req); id2 := public.create_bounty(pg_temp.uid('Luca'), 50, 'Rivincita!', req);
  assert id1 = id2, 'S9: la stessa richiesta deve restituire la stessa taglia';
  assert pg_temp.bal('Marco') = b0 - 50, 'S9: un solo addebito';
  assert (select count(*) from public.ledger_entries where ref_id = id1) = 1, 'S9: un solo movimento nel registro';
  insert into t_log (msg) values ('OK Scenario 9 — richiesta duplicata: un solo addebito');
end $$;

-- Scenario 10 — Storico e coerenza contabile
do $$
begin
  perform pg_temp.act(pg_temp.uid('Admin'));
  assert (select count(*) from public.bounties where target_id = pg_temp.uid('Luca') and status = 'settled' and settlement_id is not null and settled_at is not null) >= 7, 'S10: tutte le quote riscosse restano nello storico';
  assert (select count(*) from public.bounty_settlements where target_id = pg_temp.uid('Luca')) = 4, 'S10: 4 liquidazioni su Luca (S1, S2, S4, S8)';
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'S10: ogni saldo deve coincidere con la somma del registro';
  assert (select count(*) from public.audit_logs) > 20, 'S10: audit presente';
  insert into t_log (msg) values ('OK Scenario 10 — storico consultabile e tutti i saldi coincidono con il registro contabile');
end $$;

select n, msg from t_log order by n;
rollback;
