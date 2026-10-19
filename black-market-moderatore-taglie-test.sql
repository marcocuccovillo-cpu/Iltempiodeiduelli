-- =====================================================================
-- TEST DELLA MIGRAZIONE 006 (i moderatori gestiscono le taglie)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-setup.sql, black-market-moduli.sql, black-market-ladder.sql, black-market-ladder-rewards.sql, black-market-moderatore.sql e black-market-moderatore-taglie.sql.
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

-- Preparazione
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Mod','Marco','Luca','Paolo'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  perform pg_temp.as_('Admin');
  perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  perform public.admin_set_role(pg_temp.uid('Mod'), 'moderator', 'moderatore di test');
  insert into t_log (msg) values ('OK Preparazione: Admin, Org organizzatore, Mod moderatore, Marco, Luca, Paolo');
end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.bty(by text, tgt text, amt integer) returns uuid language plpgsql as $$
begin perform pg_temp.as_(by); return public.create_bounty(pg_temp.uid(tgt), amt, null, gen_random_uuid()::text); end $$;

-- T1 — Il moderatore congela e annulla le taglie
do $$
declare b1 uuid; b2 uuid; m uuid; ev uuid; mar0 integer; tot0 bigint;
begin
  b1 := pg_temp.bty('Marco', 'Luca', 100);
  b2 := pg_temp.bty('Paolo', 'Luca', 200);
  assert pg_temp.rows_as('Mod', 'select * from public.bounties') = 2, 'T1: il moderatore vede tutte le taglie';
  assert pg_temp.rows_as('Org', 'select * from public.bounties') = 0, 'T1: un organizzatore no';
  assert pg_temp.rows_as('Marco', 'select * from public.bounties') = 1, 'T1: un duellante vede solo le sue';
  assert pg_temp.err_as('Mod', format('select public.admin_set_bounty_review(%L, true, ''no'')', b1)) like '%Motivazione obbligatoria%', 'T1: motivazione obbligatoria';
  assert pg_temp.err_as('Marco', format('select public.admin_set_bounty_review(%L, true, ''revisione non autorizzata'')', b2)) like '%Permessi insufficienti%', 'T1: un duellante non congela';
  assert pg_temp.err_as('Org', format('select public.admin_cancel_bounty(%L, ''annullamento non autorizzato'')', b2)) like '%Permessi insufficienti%', 'T1: un organizzatore non annulla';
  assert pg_temp.err_as('Mod', format('select public.admin_set_bounty_review(%L, true, ''controllo del bersaglio'')', b1)) is null, 'T1: il moderatore congela una taglia';
  assert (select status::text from public.bounties where id = b1) = 'under_review', 'T1: taglia in revisione';
  -- riscossione sospesa sul bersaglio
  ev := pg_temp.ev('Torneo taglie'); m := pg_temp.mm(ev, 1, 'Paolo', 'Luca', 'Paolo');
  assert pg_temp.err_as('Paolo', format('select public.claim_bounty(%L)', m)) like '%in revisione%', 'T1: riscossione sospesa finché c''è una taglia in revisione';
  assert pg_temp.err_as('Mod', format('select public.admin_set_bounty_review(%L, false, ''verifica conclusa, tutto regolare'')', b1)) is null, 'T1: revisione tolta';
  assert (select status::text from public.bounties where id = b1) = 'active', 'T1: la taglia torna attiva';
  -- annullamento: la quota torna al creatore, nessun credito nuovo
  mar0 := pg_temp.bal('Marco'); tot0 := (select sum(balance) from public.wallets);
  assert pg_temp.err_as('Mod', format('select public.admin_cancel_bounty(%L, ''taglia abusiva'')', b1)) is null, 'T1: il moderatore annulla una taglia';
  assert (select status::text from public.bounties where id = b1) = 'cancelled', 'T1: taglia annullata';
  assert pg_temp.bal('Marco') = mar0 + 100 and (select sum(balance) from public.wallets) = tot0 + 100, 'T1: tornano al creatore soltanto i 100 BC che aveva versato';
  assert (select count(*) from public.ledger_entries where kind = 'bounty_refund' and ref_id = b1 and amount = 100 and user_id = pg_temp.uid('Marco')) = 1, 'T1: una riga di rimborso nel registro';
  assert pg_temp.err_as('Mod', format('select public.admin_cancel_bounty(%L, ''annullamento ripetuto'')', b1)) like '%già chiusa%', 'T1: non si annulla due volte (nessun doppio rimborso)';
  assert pg_temp.bal('Marco') = mar0 + 100, 'T1: saldo invariato dopo il tentativo ripetuto';
  assert (select count(*) from public.audit_logs where actor_id = pg_temp.uid('Mod') and action in ('bounty_review', 'cancel_bounty')) = 3, 'T1: audit di ogni intervento';
  perform pg_temp.as_('Paolo');
  assert (public.claim_bounty(m)->>'refunded')::int = 200, 'T1: dopo l''annullamento la riscossione riparte per le taglie rimaste (qui la quota è dello stesso Paolo: gli torna, senza guadagno)';
  insert into t_log (msg) values ('OK T1 — il moderatore vede, congela e annulla le taglie; rimborso solo del versato, una volta; riscossione sospesa durante la revisione; audit');
end $$;

-- T2 — Limiti: le proprie taglie, i divieti della 005
do $$
declare b1 uuid; b2 uuid; b3 uuid;
begin
  b1 := pg_temp.bty('Mod', 'Marco', 60);
  b2 := pg_temp.bty('Luca', 'Mod', 70);
  b3 := pg_temp.bty('Luca', 'Marco', 80);
  assert pg_temp.err_as('Mod', format('select public.admin_cancel_bounty(%L, ''annullo la mia taglia'')', b1)) like '%che ti riguarda%', 'T2: non annulla una taglia che ha creato';
  assert pg_temp.err_as('Mod', format('select public.admin_set_bounty_review(%L, true, ''congelo la mia taglia'')', b1)) like '%che ti riguarda%', 'T2: non congela una taglia che ha creato';
  assert pg_temp.err_as('Mod', format('select public.admin_cancel_bounty(%L, ''taglia su di me'')', b2)) like '%che ti riguarda%', 'T2: non annulla una taglia in cui è il bersaglio';
  assert pg_temp.err_as('Admin', format('select public.admin_cancel_bounty(%L, ''decide l''''admin'')', b2)) is null, 'T2: l''admin può decidere su di esse';
  assert pg_temp.err_as('Mod', format('select public.admin_cancel_bounty(%L, ''taglia di altri'')', b3)) is null, 'T2: sulle taglie degli altri sì';
  assert pg_temp.err_as('Mod', 'select public.admin_adjust_balance(gen_random_uuid(), 100, ''credito non autorizzato'')') like '%Permessi insufficienti%', 'T2: niente rettifiche di saldo';
  assert pg_temp.err_as('Mod', format('select public.resolve_dispute(%L, ''chiusura non autorizzata'')', gen_random_uuid())) like '%Permessi insufficienti%', 'T2: le contestazioni generiche restano all''admin';
  assert pg_temp.err_as('Mod', 'select public.admin_set_setting(''max_bounty'', 9999, ''modifica non autorizzata'')') like '%Permessi insufficienti%', 'T2: niente impostazioni';
  assert pg_temp.err_as('Mod', 'select public.admin_export()') like '%Permessi insufficienti%', 'T2: niente esportazioni';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'T2: saldi coerenti con il registro';
  assert not exists (select 1 from public.ledger_entries where kind = 'admin_adjustment'), 'T2: nessuna rettifica di saldo';
  insert into t_log (msg) values ('OK T2 — il moderatore non gestisce le taglie che lo riguardano; restano vietati crediti, impostazioni, esportazioni e contestazioni generiche');
end $$;

select n, msg from t_log order by n;
rollback;
