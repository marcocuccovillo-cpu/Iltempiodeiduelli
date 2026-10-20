-- =====================================================================
-- TEST DELLA MIGRAZIONE 010 (Cancellare le notifiche lette)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…010 (black-market-setup.sql … black-market-notifiche-elimina.sql).
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

-- E1 — struttura e permessi
do $$
begin
  assert has_function_privilege('authenticated', 'public.notif_delete(uuid)', 'execute') and not has_function_privilege('anon', 'public.notif_delete(uuid)', 'execute'), 'E1: solo gli utenti collegati possono chiamarla';
  assert (select prosecdef from pg_proc where proname = 'notif_delete') and (select proconfig::text from pg_proc where proname = 'notif_delete') like '%search_path%', 'E1: security definer con search_path fisso';
  assert not has_table_privilege('authenticated', 'public.notifications', 'delete') and not has_table_privilege('authenticated', 'public.notifications', 'update'), 'E1: nessuna scrittura o cancellazione diretta dal browser';
  insert into t_log (msg) values ('OK E1 — funzione esposta ai soli utenti collegati, nessuna cancellazione diretta sulla tabella');
end $$;

-- Preparazione: Luca riceve 4 taglie (4 notifiche), Paolo 1
do $$
declare i integer;
begin
  for i in 1..4 loop perform pg_temp.bnt('Marco', 'Luca', 50 + i); end loop;
  perform pg_temp.bnt('Marco', 'Paolo', 60);
  assert pg_temp.nn('Luca') = 4 and pg_temp.nn('Paolo') = 1, 'E0: preparazione';
  insert into t_log (msg) values ('OK Preparazione: Luca 4 notifiche, Paolo 1');
end $$;

-- E2 — le non lette non si cancellano
do $$
declare idl uuid; m text;
begin
  select id into idl from public.notifications where user_id = pg_temp.uid('Luca') order by created_at limit 1;
  m := pg_temp.err_as('Luca', format('select public.notif_delete(%L)', idl));
  assert m like '%solo le notifiche già lette%', 'E2: una notifica non letta non si può cancellare (' || coalesce(m, 'nessun errore') || ')';
  perform pg_temp.as_('Luca');
  assert public.notif_delete() = 0, 'E2: «cancella tutte le lette» non tocca le non lette';
  assert pg_temp.nn('Luca') = 4 and public.notif_unread_count() = 4, 'E2: le 4 notifiche non lette sono ancora lì';
  insert into t_log (msg) values ('OK E2 — le notifiche non lette non si cancellano, né una per una né in blocco');
end $$;

-- E3 — una letta si cancella, le altre restano
do $$
declare idl uuid;
begin
  select id into idl from public.notifications where user_id = pg_temp.uid('Luca') order by created_at limit 1;
  perform pg_temp.as_('Luca');
  assert public.notif_mark_read(idl) = 1, 'E3: segnata come letta';
  assert public.notif_delete(idl) = 1, 'E3: cancellata';
  assert public.notif_delete(idl) = 0, 'E3: ripetere non fa danni';
  assert pg_temp.nn('Luca') = 3 and public.notif_unread_count() = 3, 'E3: restano 3 notifiche non lette';
  assert not exists (select 1 from public.notifications where id = idl), 'E3: la riga è sparita';
  insert into t_log (msg) values ('OK E3 — una notifica letta si cancella (e ripetere la richiesta è innocuo); le altre restano');
end $$;

-- E4 — nessuno tocca le notifiche altrui
do $$
declare idp uuid; n0 bigint;
begin
  perform pg_temp.as_('Paolo'); select id into idp from public.notifications where user_id = pg_temp.uid('Paolo');
  perform public.notif_mark_read(idp);
  n0 := (select count(*) from public.notifications);
  perform pg_temp.as_('Marco');
  assert public.notif_delete(idp) = 0, 'E4: Marco non può cancellare la notifica (letta) di Paolo';
  perform pg_temp.as_('Admin');
  assert public.notif_delete(idp) = 0 and public.notif_delete() = 0, 'E4: nemmeno l''admin cancella notifiche altrui';
  assert (select count(*) from public.notifications) = n0 and exists (select 1 from public.notifications where id = idp), 'E4: la notifica di Paolo c''è ancora';
  perform pg_temp.as_('Povero');
  assert public.notif_delete() = 0, 'E4: chi non ha notifiche non cancella nulla';
  insert into t_log (msg) values ('OK E4 — ognuno cancella solo le proprie, nemmeno l''admin tocca quelle altrui');
end $$;

-- E5 — cancellare tutte le lette: le non lette sopravvivono
do $$
declare ids uuid[];
begin
  perform pg_temp.as_('Luca');
  select array_agg(id order by created_at) into ids from public.notifications where user_id = pg_temp.uid('Luca');
  perform public.notif_mark_read(ids[1]); perform public.notif_mark_read(ids[2]);
  assert public.notif_delete() = 2, 'E5: cancella le 2 lette';
  assert pg_temp.nn('Luca') = 1 and exists (select 1 from public.notifications where id = ids[3]), 'E5: la non letta resta';
  assert public.notif_unread_count() = 1, 'E5: il contatore è 1';
  perform public.notif_mark_read();
  assert public.notif_delete() = 1 and pg_temp.nn('Luca') = 0, 'E5: segna tutte e cancella tutte: lista vuota';
  assert (select count(*) from public.notifications where user_id = pg_temp.uid('Paolo')) = 1, 'E5: quelle di Paolo non sono cambiate';
  insert into t_log (msg) values ('OK E5 — «cancella le lette» lascia intatte le non lette e le notifiche degli altri');
end $$;

-- E6 — manomissioni dal browser e accesso anonimo
do $$
begin
  assert pg_temp.err_auth('Luca', 'delete from public.notifications') like '%permission denied%', 'E6: DELETE diretto rifiutato';
  assert pg_temp.err_auth('Luca', 'select public.notif_delete(null)') is null, 'E6: la funzione invece funziona';
  assert (select count(*) from pg_proc where proname = 'notif_delete') = 1, 'E6: una sola versione della funzione';
  set local role anon;
  begin perform public.notif_delete(); assert false, 'E6: anonimo non deve poterla chiamare'; exception when insufficient_privilege then null; end;
  reset role;
  insert into t_log (msg) values ('OK E6 — nessuna cancellazione diretta, nessun accesso anonimo');
end $$;

-- E7 — economia e dati di gioco invariati; una notifica cancellata non si ricrea
do $$
declare m0 text; n bigint; b uuid;
begin
  m0 := pg_temp.money();
  perform pg_temp.bnt('Org', 'Luca', 70);
  n := pg_temp.nn('Luca');
  perform pg_temp.as_('Luca'); perform public.notif_mark_read(); perform public.notif_delete();
  assert pg_temp.nn('Luca') = 0, 'E7: pulita';
  perform pg_temp.as_('Marco');
  assert (select count(*) from public.bounties) >= 6, 'E7: le taglie ci sono ancora tutte';
  assert pg_temp.nn('Luca') = 0, 'E7: cancellata non si ricrea';
  assert not exists (select 1 from public.wallet_reconciliation_v where not ok), 'E7: saldi = registro';
  assert pg_temp.money() <> m0, 'E7: (controllo) la nuova taglia di prova ha mosso BC come sempre';
  assert (select coalesce(sum(balance), 0) from public.wallets) = (select coalesce(sum(amount), 0) from public.ledger_entries), 'E7: somma dei saldi = somma del registro';
  insert into t_log (msg) values ('OK E7 — taglie, wallet e registro intatti; una notifica cancellata non ricompare');
end $$;

select n, msg from t_log order by n;
rollback;
