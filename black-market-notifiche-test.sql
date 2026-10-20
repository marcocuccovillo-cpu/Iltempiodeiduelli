-- =====================================================================
-- TEST DELLA MIGRAZIONE 009 (Notifiche)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…009 (black-market-setup.sql … black-market-notifiche.sql).
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

-- N1 — struttura, impostazione, RLS, nessun accesso anonimo
do $$
begin
  assert public._setting('notifications_enabled') = 1, 'N1: notifiche accese di default';
  assert (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname in ('notifications','notification_prefs','push_subscriptions','push_config') and c.relrowsecurity) = 4, 'N1: RLS su tutte e quattro le tabelle';
  assert not has_table_privilege('anon', 'public.notifications', 'select') and not has_table_privilege('anon', 'public.push_subscriptions', 'select'), 'N1: anon non legge';
  assert not has_table_privilege('authenticated', 'public.notifications', 'insert') and not has_table_privilege('authenticated', 'public.notifications', 'update')
     and not has_table_privilege('authenticated', 'public.notifications', 'delete') and not has_table_privilege('authenticated', 'public.push_subscriptions', 'insert')
     and not has_table_privilege('authenticated', 'public.push_config', 'select'), 'N1: nessuna scrittura diretta, push_config non leggibile';
  assert not has_function_privilege('authenticated', 'public._notify(uuid,text,text,text,text,text,uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public._trg_notify_bounty()', 'execute') and not has_function_privilege('anon', 'public.notif_mark_read(uuid)', 'execute'), 'N1: funzioni interne non esposte';
  assert (select prosecdef from pg_proc where proname = '_notify') and (select proconfig::text from pg_proc where proname = 'push_subscribe') like '%search_path=public%', 'N1: security definer con search_path fisso';
  insert into t_log (msg) values ('OK N1 — tabelle con RLS, nessun accesso anonimo, nessuna scrittura diretta, funzioni interne non esposte');
end $$;

-- N2 — taglia ricevuta: solo il bersaglio, senza rivelare l'autore; l'economia non cambia
do $$
declare a0 text; b1 uuid; b2 uuid; t text; bal_before integer;
begin
  a0 := pg_temp.money();
  select balance into bal_before from public.wallets where user_id = pg_temp.uid('Marco');
  b1 := pg_temp.bnt('Marco', 'Luca', 100);
  assert pg_temp.nn('Luca', 'bounty_received') = 1, 'N2: Luca riceve la notifica della taglia';
  assert pg_temp.nn('Marco') = 0 and pg_temp.nn('Paolo') = 0 and pg_temp.nn('Admin') = 0, 'N2: né l''autore né gli altri ricevono nulla';
  select title || ' ' || body into t from public.notifications where user_id = pg_temp.uid('Luca');
  assert t like '%100 BC%' and t like '%Bounty Value attuale: 100 BC%', 'N2: importo e Bounty Value nel testo';
  assert t not like '%Marco%', 'N2: l''autore della taglia non è rivelato';
  b2 := pg_temp.bnt('Paolo', 'Luca', 60);
  assert (select body from public.notifications where ref_id = b2) like '%60 BC%' and (select body from public.notifications where ref_id = b2) like '%Bounty Value attuale: 160 BC%', 'N2: la seconda taglia mostra il totale';
  assert (select balance from public.wallets where user_id = pg_temp.uid('Marco')) = bal_before - 100, 'N2: l''addebito della taglia è quello di sempre';
  assert (select count(*) from public.ledger_entries where kind = 'bounty_stake') = 2, 'N2: solo i due movimenti di taglia, nessuno per le notifiche';
  assert pg_temp.err_as('Marco', format('select public.create_bounty(%L, 100, null, %L)', pg_temp.uid('Luca'), 'rid-uguale-123')) is null, 'N2: la taglia riesce';
  assert pg_temp.err_as('Marco', format('select public.create_bounty(%L, 100, null, %L)', pg_temp.uid('Luca'), 'rid-uguale-123')) is null, 'N2: richiesta ripetuta senza errori';
  assert pg_temp.nn('Luca', 'bounty_received') = 3, 'N2: una richiesta ripetuta non crea una seconda notifica (3 taglie in tutto)';
  insert into t_log (msg) values ('OK N2 — taglia: avvisa solo il bersaglio, con importo e totale, senza rivelare l''autore; nessun effetto sul wallet; richiesta ripetuta = una sola notifica');
end $$;

-- N3 — sfida in Ladder e "sfida per la taglia"
do $$
declare c1 uuid; c2 uuid; c3 uuid; t text;
begin
  -- Paolo non ha taglie addosso: sfida normale
  c1 := pg_temp.chal('Org', 'Paolo', 'Edison');
  assert pg_temp.nn('Paolo', 'ladder_challenge') = 1 and pg_temp.nn('Paolo', 'bounty_challenge') = 0, 'N3: sfida normale a chi non ha taglie';
  select body into t from public.notifications where ref_id = c1;
  assert t like '%Org%' and t like '%Edison%', 'N3: il testo nomina lo sfidante e il formato';
  assert pg_temp.nn('Org') = 0 and pg_temp.nn('Marco') = 0, 'N3: lo sfidante non riceve nulla';
  -- Luca ha addosso 100 (Marco), 60 (Paolo) e 100 (Marco): Paolo che lo sfida può incassare solo ciò che non è suo (200)
  c2 := pg_temp.chal('Paolo', 'Luca');
  select body into t from public.notifications where ref_id = c2 and kind = 'bounty_challenge';
  assert t is not null, 'N3: sfida per la taglia a chi ha una taglia addosso';
  assert t like '%Paolo%' and t like '%200 BC%', 'N3: importo = solo le quote che il cacciatore può incassare (non la propria)';
  assert (select title from public.notifications where ref_id = c2) like '%taglia%', 'N3: titolo da sfida per la taglia';
  -- sfida "normale" tra chi non c'entra nulla: Admin sfida Marco (nessuna taglia su Marco)
  perform pg_temp.chal('Admin', 'Marco');
  assert pg_temp.nn('Marco', 'ladder_challenge') = 1, 'N3: Marco riceve una sfida Ladder normale';
  insert into t_log (msg) values ('OK N3 — Ladder: sfida normale e "sfida per la taglia" (con la somma realmente incassabile), nessun avviso allo sfidante');
end $$;

-- N4 — preferenze
do $$
declare c uuid; n0 bigint;
begin
  assert (select count(*) from public.notification_prefs) = 0, 'N4: nessuna preferenza salvata = tutto acceso';
  perform pg_temp.prefs('Luca', false, null, null);
  n0 := pg_temp.nn('Luca');
  perform pg_temp.bnt('Admin', 'Luca', 50);
  assert pg_temp.nn('Luca') = n0, 'N4: con "taglia ricevuta" spento non arriva nulla';
  perform pg_temp.prefs('Luca', null, null, false);
  assert (select bounty from public.notification_prefs where user_id = pg_temp.uid('Luca')) = false, 'N4: aggiornare una voce non riaccende le altre';
  -- Luca ha ancora ladder acceso e hunt spento: la sfida per la taglia gli arriva come sfida Ladder normale
  c := pg_temp.chal('Org', 'Luca');
  assert (select kind from public.notifications where ref_id = c) = 'ladder_challenge', 'N4: hunt spento ma Ladder acceso: arriva come sfida normale';
  perform pg_temp.prefs('Luca', null, false, null);
  n0 := pg_temp.nn('Luca');
  perform pg_temp.chal('Povero', 'Luca');
  assert pg_temp.nn('Luca') = n0, 'N4: tutto spento: nessuna notifica';
  perform pg_temp.prefs('Luca', true, true, true);
  assert (select bounty and ladder and hunt from public.notification_prefs where user_id = pg_temp.uid('Luca')), 'N4: riaccendere funziona';
  assert (select count(*) from public.notification_prefs where user_id = pg_temp.uid('Marco')) = 0, 'N4: le preferenze di uno non toccano gli altri';
  -- interruttore globale
  perform pg_temp.set_('notifications_enabled', 0);
  n0 := (select count(*) from public.notifications);
  perform pg_temp.bnt('Admin', 'Paolo', 50);
  assert (select count(*) from public.notifications) = n0, 'N4: interruttore globale spento: nessuna notifica';
  perform pg_temp.set_('notifications_enabled', 1);
  insert into t_log (msg) values ('OK N4 — preferenze per tipo (con ripiego sulla sfida normale) e interruttore globale');
end $$;

-- N5 — privacy e permessi: ognuno vede e segna solo le proprie
do $$
declare mine bigint; idl uuid; r text;
begin
  assert pg_temp.rows_as('Luca', 'select 1 from public.notifications') = pg_temp.nn('Luca'), 'N5: Luca vede tutte e sole le sue';
  assert pg_temp.rows_as('Marco', format('select 1 from public.notifications where user_id = %L', pg_temp.uid('Luca'))) = 0, 'N5: Marco non vede le notifiche di Luca';
  assert pg_temp.rows_as('Admin', 'select 1 from public.notifications where user_id <> auth.uid()') = 0, 'N5: nemmeno l''admin legge le notifiche altrui';
  assert pg_temp.err_auth('Marco', format('insert into public.notifications (user_id, kind, title, body) values (%L, ''bounty_received'', ''x'', ''y'')', pg_temp.uid('Luca'))) like '%permission denied%', 'N5: nessun inserimento diretto';
  assert pg_temp.err_auth('Luca', 'update public.notifications set body = ''manomesso''') like '%permission denied%', 'N5: nessuna modifica diretta';
  assert pg_temp.err_auth('Luca', 'delete from public.notifications') like '%permission denied%', 'N5: nessuna cancellazione';
  assert pg_temp.err_auth('Marco', format('select public._notify(%L, ''bounty_received'', ''x'', ''y'', null, null, null)', pg_temp.uid('Luca'))) like '%permission denied%', 'N5: _notify non chiamabile dal browser';
  -- segna come lette
  perform pg_temp.as_('Luca');
  assert public.notif_unread_count() = pg_temp.nn('Luca'), 'N5: tutte non lette';
  select id into idl from public.notifications where user_id = pg_temp.uid('Luca') order by created_at limit 1;
  perform pg_temp.as_('Marco');
  assert public.notif_mark_read(idl) = 0, 'N5: Marco non può segnare come letta una notifica di Luca';
  perform pg_temp.as_('Luca');
  assert public.notif_mark_read(idl) = 1 and public.notif_mark_read(idl) = 0, 'N5: Luca segna una notifica (una volta sola)';
  assert public.notif_unread_count() = pg_temp.nn('Luca') - 1, 'N5: il contatore scende';
  assert public.notif_mark_read() = pg_temp.nn('Luca') - 1, 'N5: segna tutte';
  assert public.notif_unread_count() = 0, 'N5: nessuna non letta rimasta';
  assert (select body from public.notifications where id = idl) not like '%manomesso%' and (select count(*) from public.notifications where user_id = pg_temp.uid('Luca') and read_at is not null) = pg_temp.nn('Luca'), 'N5: solo read_at cambia';
  assert (select count(*) from public.notifications where user_id = pg_temp.uid('Paolo') and read_at is not null) = 0, 'N5: le notifiche degli altri restano non lette';
  perform pg_temp.as_('Povero');
  assert public.notif_unread_count() = 0, 'N5: contatore a zero per chi non ha nulla';
  insert into t_log (msg) values ('OK N5 — privacy: ognuno legge e segna solo le proprie, nessuna scrittura diretta, nemmeno l''admin legge le altrui');
end $$;

-- N6 — dispositivi push
do $$
declare ep text := 'https://push.example.test/send/abcdef0123456789'; i integer;
begin
  perform pg_temp.as_('Luca');
  perform public.push_subscribe(ep, 'BP-p256dh-chiave-di-prova-0123456789', 'auth-di-prova-123', 'Chrome Android');
  assert (select count(*) from public.push_subscriptions where user_id = pg_temp.uid('Luca')) = 1, 'N6: dispositivo registrato';
  perform public.push_subscribe(ep, 'BP-p256dh-chiave-di-prova-0123456789', 'auth-di-prova-123', 'Chrome Android');
  assert (select count(*) from public.push_subscriptions) = 1, 'N6: stesso dispositivo = una sola riga';
  assert pg_temp.rows_as('Marco', 'select 1 from public.push_subscriptions') = 0, 'N6: Marco non vede i dispositivi di Luca';
  assert pg_temp.rows_as('Admin', 'select 1 from public.push_subscriptions') = 0, 'N6: nemmeno l''admin';
  assert pg_temp.err_as('Luca', 'select public.push_subscribe(''http://insicuro.test/x'', ''BP-p256dh-chiave-di-prova-0123456789'', ''auth-di-prova-123'')') like '%non valido%', 'N6: solo endpoint https';
  assert pg_temp.err_as('Luca', 'select public.push_subscribe(''https://x.test/y'', ''corta'', ''auth-di-prova-123'')') like '%non validi%', 'N6: chiavi troppo corte rifiutate';
  perform pg_temp.as_('Marco'); perform public.push_unsubscribe(ep);
  assert (select count(*) from public.push_subscriptions) = 1, 'N6: Marco non può togliere il dispositivo di Luca';
  perform public.push_subscribe(ep, 'BP-p256dh-chiave-di-prova-0123456789', 'auth-di-prova-123', 'stesso telefono');   -- stesso telefono, altro account
  assert (select user_id from public.push_subscriptions where endpoint = ep) = pg_temp.uid('Marco'), 'N6: lo stesso dispositivo passa a chi ha fatto l''accesso';
  perform pg_temp.as_('Luca'); perform public.push_unsubscribe(ep);
  assert (select count(*) from public.push_subscriptions) = 1, 'N6: Luca non toglie più un dispositivo non suo';
  perform pg_temp.as_('Marco'); perform public.push_unsubscribe(ep);
  assert (select count(*) from public.push_subscriptions) = 0, 'N6: ognuno disattiva il proprio';
  for i in 1..10 loop perform public.push_subscribe('https://push.example.test/dev' || i, 'BP-p256dh-chiave-di-prova-0123456789', 'auth-di-prova-123'); end loop;
  assert pg_temp.err_as('Marco', 'select public.push_subscribe(''https://push.example.test/dev11'', ''BP-p256dh-chiave-di-prova-0123456789'', ''auth-di-prova-123'')') like '%10 dispositivi%', 'N6: massimo 10 dispositivi';
  perform pg_temp.as_('Marco'); perform public.push_subscribe('https://push.example.test/dev3', 'BP-p256dh-chiave-di-prova-0123456789', 'auth-nuova-123456');
  assert (select auth from public.push_subscriptions where endpoint = 'https://push.example.test/dev3') = 'auth-nuova-123456', 'N6: un dispositivo già registrato si aggiorna anche al limite';
  -- notifica di prova a se stessi
  perform pg_temp.as_('Povero'); perform public.push_send_test();
  assert pg_temp.nn('Povero', 'test') = 1 and pg_temp.nn('Marco', 'test') = 0, 'N6: la prova arriva solo a chi la chiede';
  assert pg_temp.err_as('Povero', 'select public.push_send_test()') like '%Aspetta%', 'N6: prove ravvicinate rifiutate';
  perform pg_temp.set_('notifications_enabled', 0);
  assert pg_temp.err_as('Luca', 'select public.push_send_test()') like '%spente%', 'N6: la prova rispetta l''interruttore globale';
  perform pg_temp.set_('notifications_enabled', 1);
  insert into t_log (msg) values ('OK N6 — dispositivi push: solo https, privati, passano di mano col login, mai tolti da altri, massimo 10');
end $$;

-- N7 — chiave pubblica VAPID: solo l'admin la imposta, tutti la leggono, audit
do $$
declare k text := 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U'; a0 bigint;
begin
  perform pg_temp.as_('Marco');
  assert public.push_public_key() is null, 'N7: nessuna chiave finché l''admin non la imposta';
  assert pg_temp.err_as('Marco', format('select public.admin_set_push_key(%L, ''prova di motivazione'')', k)) is not null, 'N7: un giocatore non imposta la chiave';
  assert public.push_public_key() is null, 'N7: la chiave non è cambiata';
  a0 := (select count(*) from public.audit_logs);
  assert pg_temp.err_as('Admin', format('select public.admin_set_push_key(%L, ''no'')', k)) like '%Motivazione%', 'N7: serve la motivazione';
  assert pg_temp.err_as('Admin', 'select public.admin_set_push_key(''chiave troppo corta'', ''prova di motivazione'')') like '%non valida%', 'N7: chiave non valida rifiutata';
  perform pg_temp.as_('Admin'); perform public.admin_set_push_key(k, 'impostazione chiave push');
  perform pg_temp.as_('Povero');
  assert public.push_public_key() = k, 'N7: tutti leggono la chiave pubblica';
  assert (select count(*) from public.audit_logs where action = 'set_push_key') = 1 and (select count(*) from public.audit_logs) = a0 + 1, 'N7: audit della modifica';
  assert pg_temp.err_auth('Marco', 'select 1 from public.push_config') like '%permission denied%', 'N7: la tabella non è leggibile direttamente';
  assert not exists (select 1 from public.audit_logs where action = 'set_push_key' and (old_value::text || new_value::text) ~* 'private'), 'N7: nessuna chiave privata nell''audit';
  insert into t_log (msg) values ('OK N7 — chiave VAPID pubblica: la imposta solo l''admin, motivazione e audit, chiave privata mai nel database');
end $$;

-- N8 — a prova di errore: una notifica non blocca mai taglie e sfide
do $$
declare n0 bigint; m0 text; id1 uuid; id2 uuid;
begin
  alter table public.notifications rename to notifications_guasta;           -- simula un guasto delle notifiche
  begin
    id1 := pg_temp.bnt('Marco', 'Paolo', 50);
    id2 := pg_temp.chal('Marco', 'Povero');
    assert id1 is not null and id2 is not null, 'N8: taglia e sfida riescono anche con le notifiche guaste';
    assert (select count(*) from public.bounties where id = id1) = 1 and (select count(*) from public.ladder_matches where id = id2) = 1, 'N8: taglia e sfida sono state scritte';
    assert (select count(*) from public.ledger_entries where ref_id = id1 and kind = 'bounty_stake') = 1, 'N8: addebito della taglia scritto';
  end;
  alter table public.notifications_guasta rename to notifications;
  assert (select count(*) from public.notifications where ref_id in (id1, id2)) = 0, 'N8: nessuna notifica per quegli eventi (non recuperata, ma niente di rotto)';
  insert into t_log (msg) values ('OK N8 — con le notifiche guaste, taglie e sfide Ladder riescono comunque e il registro contabile è intatto');
end $$;

-- N9 — compatibilità: riscossione, Ladder, wallet e Shop come prima
do $$
declare r jsonb; v uuid; cl jsonb; ev uuid; m uuid; n0 bigint;
begin
  perform pg_temp.set_('ladder_claim_hold_hours', 0);
  n0 := (select count(*) from public.notifications);
  -- Marco sfida Luca (ha taglie addosso di altri) e vince: il match ufficiale permette di riscuotere
  r := pg_temp.play('Marco', 'Luca', 'challenger', '2-0', 'Marco');
  assert (r->>'winner')::uuid = pg_temp.uid('Marco'), 'N9: la Ladder funziona come prima';
  assert (select count(*) from public.notifications) = n0 + 1, 'N9: la sfida ha generato una sola notifica';
  perform pg_temp.as_('Marco');
  select id into m from public.matches where source = 'ladder' and winner_id = pg_temp.uid('Marco') order by verified_at desc limit 1;
  cl := public.claim_bounty(m);
  assert (cl->>'payout')::integer > 0, 'N9: la riscossione paga come prima';
  assert not exists (select 1 from public.wallet_reconciliation_v where not ok), 'N9: saldi = registro contabile';
  assert (select coalesce(sum(balance), 0) from public.wallets) = (select coalesce(sum(amount), 0) from public.ledger_entries), 'N9: somma dei saldi = somma del registro';
  assert not exists (select 1 from public.ledger_entries where kind not in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward','shop_purchase')), 'N9: nessun nuovo tipo di movimento';
  assert (select count(*) from public.shop_items) >= 30, 'N9: lo Shop è intatto';
  insert into t_log (msg) values ('OK N9 — Ladder, riscossione, wallet e Shop invariati; saldi riconciliati; nessun movimento creato dalle notifiche');
end $$;

select n, msg from t_log order by n;
rollback;
