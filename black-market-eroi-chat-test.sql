-- =====================================================================
-- TEST DELLA MIGRAZIONE «CHAT PUBBLICA E CHI È ONLINE» (La guerra degli Eroi)
-- Da eseguire su un database di PROVA vuoto, DOPO tutte le migrazioni precedenti
-- (… black-market-eroi-boss-attacco.sql e poi black-market-eroi-chat.sql).
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- Se un controllo fallisce compare un errore con il nome dello scenario.
-- =====================================================================
begin;
-- PROTEZIONE: il test crea utenti di prova e confronta conteggi globali (il primo utente registrato diventa admin).
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
create function pg_temp.mod(on_ boolean) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', on_, 'prova del modulo'); end $$;
create function pg_temp.st(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
create function pg_temp.send(n text, t text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_chat_send(t); end $$;
create function pg_temp.lst(n text, a bigint default null) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_chat_list(a); end $$;
create function pg_temp.ping(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_presence_ping(); end $$;
create function pg_temp.onl(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_online(); end $$;
create function pg_temp.hide(n text, i bigint, r text) returns void language plpgsql as $$ begin perform pg_temp.as_(n); perform public.game_chat_hide(i, r); end $$;
-- «passa del tempo»: sposta indietro i messaggi di una persona
create function pg_temp.age(n text, secs integer) returns void language sql as $$
  update public.game_chat set created_at = created_at - secs * interval '1 second' where user_id = pg_temp.uid(n) $$;
create function pg_temp.texts(j jsonb) returns text[] language sql as $$
  select coalesce(array_agg(e->>'t' order by o), '{}') from jsonb_array_elements(j->'msgs') with ordinality as x(e, o) $$;
create function pg_temp.nicks(j jsonb) returns text[] language sql as $$
  select coalesce(array_agg(e->>'n' order by o), '{}') from jsonb_array_elements(j) with ordinality as x(e, o) $$;
create function pg_temp.maxid() returns bigint language sql as $$ select coalesce(max(id), 0) from public.game_chat $$;
create function pg_temp.clear_chat() returns void language sql as $$ delete from public.game_chat; delete from public.game_presence $$;
-- impronta di tutto ciò che la chat NON deve toccare
create function pg_temp.eco() returns text language sql as $$
  select md5(coalesce((select string_agg(user_id || ':' || balance, ',' order by user_id) from public.wallets), '')
          || (select count(*)::text || coalesce(sum(amount), 0)::text from public.ledger_entries)
          || coalesce((select string_agg(user_id || ':' || level || ':' || xp || ':' || total_xp || ':' || energy::text || ':' || fights_total, ',' order by user_id) from public.game_heroes), '')
          || (select count(*)::text from public.game_inventory) || (select count(*)::text from public.game_equipped)
          || (select count(*)::text from public.game_day_log) || (select count(*)::text from public.game_duels) || (select count(*)::text from public.game_rewards)
          || (select count(*)::text from public.bounties)) $$;

-- Preparazione: Admin (primo registrato), Org organizzatore, Bob moderatore e quattro duellanti
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Eve'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin');
  perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova');
  perform public.admin_set_role(pg_temp.uid('Bob'), 'moderator', 'moderatore di prova');
  perform pg_temp.mod(true);
  foreach n in array array['Admin','Ann','Bob'] loop perform pg_temp.st(n); end loop;      -- creano la scheda eroe (serve per l'avatar)
  insert into t_log (msg) values ('OK Preparazione: 7 utenti (Admin, Org organizzatore, Bob moderatore)');
end $$;

do $$
declare n text; r jsonb; j jsonb; k bigint; e0 text; a0 bigint; i integer; txt text; ids bigint[];
begin
  -- C1 — permessi e tabelle chiuse
  foreach txt in array array['public.game_chat_send(text)','public.game_chat_list(bigint)','public.game_presence_ping()','public.game_online()','public.game_chat_hide(bigint,text)'] loop
    assert not has_function_privilege('anon', txt, 'execute') and has_function_privilege('authenticated', txt, 'execute'), 'C1: permessi di ' || txt;
  end loop;
  foreach txt in array array['public.game_chat','public.game_presence'] loop
    assert not has_table_privilege('authenticated', txt, 'select') and not has_table_privilege('authenticated', txt, 'insert')
       and not has_table_privilege('authenticated', txt, 'update') and not has_table_privilege('authenticated', txt, 'delete')
       and not has_table_privilege('anon', txt, 'select'), 'C1: ' || txt || ' chiusa al browser';
  end loop;
  assert (select relrowsecurity from pg_class where oid = 'public.game_chat'::regclass) and (select relrowsecurity from pg_class where oid = 'public.game_presence'::regclass), 'C1: RLS attiva';
  foreach n in array array['Ann','Bob','Admin'] loop
    assert pg_temp.err_auth(n, 'select * from public.game_chat') like '%permission denied%', 'C1: ' || n || ' non legge la chat';
    assert pg_temp.err_auth(n, 'select * from public.game_presence') like '%permission denied%', 'C1: ' || n || ' non legge la presenza';
    assert pg_temp.err_auth(n, 'insert into public.game_chat (user_id, body) values (auth.uid(), ''x'')') like '%permission denied%', 'C1: ' || n || ' non scrive direttamente';
    assert pg_temp.err_auth(n, 'update public.game_chat set hidden = true') like '%permission denied%', 'C1: ' || n || ' non modifica';
    assert pg_temp.err_auth(n, 'delete from public.game_chat') like '%permission denied%', 'C1: ' || n || ' non cancella';
    assert pg_temp.err_auth(n, 'insert into public.game_presence (user_id) values (auth.uid())') like '%permission denied%', 'C1: ' || n || ' non si segna online a mano';
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  assert pg_temp.err('select public.game_chat_send(''ciao'')') like '%Accesso richiesto%', 'C1: serve il login (invio)';
  assert pg_temp.err('select public.game_chat_list()') like '%Accesso richiesto%', 'C1: serve il login (elenco)';
  assert pg_temp.err('select public.game_presence_ping()') like '%Accesso richiesto%', 'C1: serve il login (ping)';
  assert pg_temp.err('select public.game_online()') like '%Accesso richiesto%', 'C1: serve il login (online)';
  assert (select count(*) from public.game_chat) = 0 and (select count(*) from public.game_presence) = 0, 'C1: i rifiuti non lasciano nulla';
  -- tutti i ruoli possono scrivere
  foreach n in array array['Admin','Org','Ann','Bob'] loop
    r := pg_temp.send(n, 'ciao da ' || n);
    assert r->>'t' = 'ciao da ' || n and r->>'n' = n and (r->>'u')::uuid = pg_temp.uid(n), 'C1: ' || n || ' scrive';
  end loop;
  assert (select count(*) from public.game_chat) = 4, 'C1: 4 messaggi';
  foreach n in array array['Admin','Org','Ann','Bob'] loop
    assert jsonb_array_length(pg_temp.lst(n)->'msgs') = 4, 'C1: ' || n || ' legge la chat';
    assert pg_temp.ping(n) ? 'last_id', 'C1: ' || n || ' si segna online';
    assert jsonb_typeof(pg_temp.onl(n)) = 'array', 'C1: ' || n || ' vede chi è online';
  end loop;
  insert into t_log (msg) values ('OK C1 — funzioni solo agli utenti, tabelle chiuse al browser (6 operazioni dirette rifiutate × 3 ruoli), serve il login, tutti i ruoli scrivono');

  -- C2 — un solo elenco per tutti, nessun messaggio privato
  j := pg_temp.lst('Ann');
  assert pg_temp.texts(j) = array['ciao da Admin','ciao da Org','ciao da Ann','ciao da Bob'], 'C2: ordine cronologico';
  foreach n in array array['Admin','Org','Bob','Cid','Dan'] loop
    assert pg_temp.texts(pg_temp.lst(n)) = pg_temp.texts(j), 'C2: ' || n || ' vede la stessa chat';
  end loop;
  assert (j->'msgs'->0) ? 'id' and (j->'msgs'->0) ? 'u' and (j->'msgs'->0) ? 'n' and (j->'msgs'->0) ? 'at' and (j->'msgs'->0) ? 't', 'C2: campi del messaggio';
  assert not exists (select 1 from jsonb_array_elements(j->'msgs') e where e ? 'email' or e ? 'to' or e ? 'dest' or e ? 'recipient'), 'C2: nessun destinatario né email';
  assert j::text not like '%@test.local%', 'C2: nessuna email in giro';
  assert (j->>'me')::uuid = pg_temp.uid('Ann'), 'C2: me';
  assert (j->>'last_id')::bigint = pg_temp.maxid(), 'C2: last_id = ultimo messaggio';
  assert not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'game_chat' and column_name in ('to_user','recipient_id','target_id','to_id')), 'C2: la tabella non ha un destinatario';
  -- solo i nuovi
  k := pg_temp.maxid();
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', 'nuovo uno');
  perform pg_temp.send('Cid', 'nuovo due');
  assert pg_temp.texts(pg_temp.lst('Bob', k)) = array['nuovo uno','nuovo due'], 'C2: con p_after solo i nuovi';
  assert pg_temp.texts(pg_temp.lst('Bob', pg_temp.maxid())) = '{}', 'C2: nessun nuovo = elenco vuoto';
  assert jsonb_typeof(pg_temp.lst('Bob', pg_temp.maxid())->'msgs') = 'array', 'C2: sempre un array';
  -- ultimi 60 / ultimi 100
  perform pg_temp.clear_chat();
  insert into public.game_chat (user_id, body, created_at) select pg_temp.uid('Ann'), 'm' || g, clock_timestamp() - (200 - g) * interval '1 second' from generate_series(1, 70) g;
  j := pg_temp.lst('Cid');
  assert jsonb_array_length(j->'msgs') = 60 and (pg_temp.texts(j))[1] = 'm11' and (pg_temp.texts(j))[60] = 'm70', 'C2: senza parametro gli ultimi 60, in ordine';
  k := pg_temp.maxid();
  insert into public.game_chat (user_id, body, created_at) select pg_temp.uid('Bob'), 'b' || g, clock_timestamp() - (100 - g) * interval '1 second' from generate_series(1, 130) g;
  j := pg_temp.lst('Cid', k);
  assert jsonb_array_length(j->'msgs') = 100 and (pg_temp.texts(j))[100] = 'b130' and (pg_temp.texts(j))[1] = 'b31', 'C2: con p_after al massimo 100, i più recenti';
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C2 — stessa chat per tutti, nessun destinatario né email, ordine, «solo i nuovi», ultimi 60 e tetto di 100');

  -- C3 — pulizia del testo
  perform pg_temp.send('Ann', E'  ciao \t\n   a   tutti \r ');
  assert (select body from public.game_chat order by id desc limit 1) = 'ciao a tutti', 'C3: spazi e a capo ripuliti';
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', '<b>"ciao"</b> & ''amici''');
  assert (select body from public.game_chat order by id desc limit 1) = '<b>"ciao"</b> & ''amici''', 'C3: il testo resta com''è (lo protegge il browser)';
  perform pg_temp.age('Ann', 5);
  assert pg_temp.err_as('Ann', 'select public.game_chat_send('''')') like '%Scrivi qualcosa%', 'C3: vuoto';
  assert pg_temp.err_as('Ann', 'select public.game_chat_send(null)') like '%Scrivi qualcosa%', 'C3: null';
  assert pg_temp.err_as('Ann', 'select public.game_chat_send(E''   \t\n  '')') like '%Scrivi qualcosa%', 'C3: solo spazi';
  assert pg_temp.err_as('Ann', 'select public.game_chat_send(E''\u200b\u200d\ufeff\u202e'')') like '%Scrivi qualcosa%', 'C3: solo caratteri invisibili';
  perform pg_temp.send('Ann', E'ab\u202ecd\u200bef\u2066gh');
  assert (select body from public.game_chat order by id desc limit 1) = 'abcdefgh', 'C3: inversione del testo e invisibili tolti';
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', E'a\u0001b\u007fc\u0085d');
  assert (select body from public.game_chat order by id desc limit 1) = 'a b c d', 'C3: caratteri di controllo sostituiti da spazi';
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', repeat('a', 400));
  assert (select char_length(body) from public.game_chat order by id desc limit 1) = 300, 'C3: massimo 300 caratteri (troncato)';
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', repeat('è', 300));
  assert (select char_length(body) from public.game_chat order by id desc limit 1) = 300, 'C3: 300 caratteri accentati interi';
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', '😀 ciao');
  assert (select body from public.game_chat order by id desc limit 1) = '😀 ciao', 'C3: emoji ok';
  assert pg_temp.err(format('insert into public.game_chat (user_id, body) values (%L, %L)', pg_temp.uid('Ann'), repeat('z', 301))) like '%game_chat_body_check%', 'C3: la tabella rifiuta anche 301 caratteri';
  assert pg_temp.err(format('insert into public.game_chat (user_id, body) values (%L, %L)', pg_temp.uid('Ann'), '')) like '%game_chat_body_check%', 'C3: la tabella rifiuta il vuoto';
  assert pg_temp.err(format('insert into public.game_chat (user_id, body) values (%L, %L)', gen_random_uuid(), 'x')) like '%foreign key%', 'C3: la tabella rifiuta un autore inesistente';
  assert (select count(*) from public.game_chat) = 7, 'C3: i rifiuti non salvano nulla (7 messaggi buoni)';
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C3 — pulizia spazi/controlli/invisibili, limite di 300, vuoti rifiutati, il testo non viene alterato (nessun HTML interpretato nel database)');

  -- C4 — limiti di frequenza
  perform pg_temp.send('Cid', 'primo');
  assert pg_temp.err_as('Cid', 'select public.game_chat_send(''secondo subito'')') like '%Troppo veloce%', 'C4: due messaggi in meno di 2 secondi';
  assert (select count(*) from public.game_chat where user_id = pg_temp.uid('Cid')) = 1, 'C4: il secondo non è salvato';
  perform pg_temp.send('Dan', 'io invece posso');
  perform pg_temp.age('Cid', 3);
  perform pg_temp.send('Cid', 'ora sì');
  assert (select count(*) from public.game_chat where user_id = pg_temp.uid('Cid')) = 2, 'C4: dopo 3 secondi si può';
  -- 20 al minuto
  perform pg_temp.clear_chat();
  insert into public.game_chat (user_id, body, created_at) select pg_temp.uid('Cid'), 'x' || g, clock_timestamp() - (10 + g) * interval '1 second' from generate_series(1, 20) g;
  assert pg_temp.err_as('Cid', 'select public.game_chat_send(''il ventunesimo'')') like '%Troppi messaggi%', 'C4: 20 in un minuto sono il massimo';
  perform pg_temp.send('Dan', 'Dan non è limitato da Cid');
  update public.game_chat set created_at = created_at - interval '2 minutes' where user_id = pg_temp.uid('Cid');
  perform pg_temp.send('Cid', 'passato il minuto');
  perform pg_temp.clear_chat();
  insert into public.game_chat (user_id, body, created_at) select pg_temp.uid('Cid'), 'y' || g, clock_timestamp() - (10 + g) * interval '1 second' from generate_series(1, 19) g;
  perform pg_temp.send('Cid', 'il ventesimo');
  assert (select count(*) from public.game_chat where user_id = pg_temp.uid('Cid')) = 20, 'C4: il ventesimo passa';
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C4 — 1 messaggio ogni 2 secondi e 20 al minuto per persona, gli altri non sono toccati, il limite scade col tempo');

  -- C5 — conservazione (ultimi 500, non oltre 7 giorni)
  insert into public.game_chat (user_id, body, created_at) select pg_temp.uid('Ann'), 'r' || g, clock_timestamp() - interval '1 hour' - (600 - g) * interval '1 second' from generate_series(1, 520) g;
  perform pg_temp.send('Bob', 'ultimo');
  assert (select count(*) from public.game_chat) = 500, 'C5: restano 500 messaggi (' || (select count(*) from public.game_chat) || ')';
  assert not exists (select 1 from public.game_chat where body = 'r21') and exists (select 1 from public.game_chat where body = 'r22') and exists (select 1 from public.game_chat where body = 'ultimo'), 'C5: spariscono i più vecchi';
  perform pg_temp.clear_chat();
  insert into public.game_chat (user_id, body, created_at) values (pg_temp.uid('Ann'), 'vecchio', clock_timestamp() - interval '8 days'), (pg_temp.uid('Ann'), 'quasi vecchio', clock_timestamp() - interval '6 days 23 hours');
  perform pg_temp.send('Bob', 'fresco');
  assert not exists (select 1 from public.game_chat where body = 'vecchio') and exists (select 1 from public.game_chat where body = 'quasi vecchio') and exists (select 1 from public.game_chat where body = 'fresco'), 'C5: oltre 7 giorni via, 6 giorni e 23 ore restano';
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C5 — si conservano gli ultimi 500 messaggi e non oltre 7 giorni');

  -- C6 — messaggi nascosti e account sospesi
  perform pg_temp.send('Ann', 'messaggio di Ann'); perform pg_temp.send('Dan', 'messaggio di Dan'); perform pg_temp.send('Eve', 'messaggio di Eve');
  a0 := (select id from public.game_chat where body = 'messaggio di Eve');
  assert 'messaggio di Eve' = any (pg_temp.texts(pg_temp.lst('Ann'))) and (pg_temp.lst('Ann')->>'last_id')::bigint = a0, 'C6: prima Eve si vede e last_id è il suo';
  update public.profiles set suspended = true where id = pg_temp.uid('Eve');
  j := pg_temp.lst('Ann');
  assert pg_temp.texts(j) = array['messaggio di Ann','messaggio di Dan'], 'C6: i messaggi di un sospeso spariscono';
  assert (pg_temp.ping('Ann')->>'last_id')::bigint = (select id from public.game_chat where body = 'messaggio di Dan'), 'C6: il ping non conta il sospeso';
  assert (j->>'last_id')::bigint = (select id from public.game_chat where body = 'messaggio di Dan'), 'C6: last_id non conta il sospeso';
  update public.profiles set suspended = false where id = pg_temp.uid('Eve');
  assert 'messaggio di Eve' = any (pg_temp.texts(pg_temp.lst('Ann'))), 'C6: tolta la sospensione tornano';
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C6 — i messaggi di un account sospeso non si vedono, tornano alla fine della sospensione');

  -- C7 — moderazione
  perform pg_temp.send('Ann', 'brutto messaggio'); perform pg_temp.send('Cid', 'messaggio buono'); perform pg_temp.send('Dan', 'altro messaggio');
  a0 := (select id from public.game_chat where body = 'brutto messaggio');
  assert not (pg_temp.lst('Ann')->>'staff')::boolean and not (pg_temp.lst('Org')->>'staff')::boolean and (pg_temp.lst('Bob')->>'staff')::boolean and (pg_temp.lst('Admin')->>'staff')::boolean, 'C7: «staff» solo moderatore e amministratore';
  foreach n in array array['Ann','Cid','Org'] loop
    assert pg_temp.err_as(n, format('select public.game_chat_hide(%s, ''motivo valido'')', a0)) like '%Permessi insufficienti%', 'C7: ' || n || ' non può nascondere';
  end loop;
  assert pg_temp.err_auth('Ann', format('select public.game_chat_hide(%s, ''motivo valido'')', a0)) like '%Permessi insufficienti%', 'C7: nemmeno dal ruolo del browser';
  perform set_config('request.jwt.claims', '{}', true);
  assert pg_temp.err(format('select public.game_chat_hide(%s, ''motivo valido'')', a0)) like '%Accesso richiesto%', 'C7: serve il login';
  assert not (select hidden from public.game_chat where id = a0) and (select count(*) from public.audit_logs where action = 'game_chat_hide') = 0, 'C7: i rifiuti non lasciano tracce';
  assert pg_temp.err_as('Bob', format('select public.game_chat_hide(%s, null)', a0)) like '%Motivazione obbligatoria%', 'C7: motivazione nulla';
  assert pg_temp.err_as('Bob', format('select public.game_chat_hide(%s, ''ok'')', a0)) like '%Motivazione obbligatoria%', 'C7: motivazione troppo corta';
  assert pg_temp.err_as('Bob', 'select public.game_chat_hide(99999999, ''motivo valido'')') like '%Messaggio inesistente%', 'C7: messaggio inesistente';
  perform pg_temp.hide('Bob', a0, 'insulti ad altri eroi');
  assert (select hidden and hidden_by = pg_temp.uid('Bob') and hidden_at is not null from public.game_chat where id = a0), 'C7: nascosto da Bob';
  assert 'brutto messaggio' <> all (pg_temp.texts(pg_temp.lst('Ann'))) and 'brutto messaggio' <> all (pg_temp.texts(pg_temp.lst('Cid'))), 'C7: nessuno lo vede più';
  assert pg_temp.texts(pg_temp.lst('Ann')) = array['messaggio buono','altro messaggio'], 'C7: gli altri messaggi restano';
  assert (select count(*) from public.audit_logs where action = 'game_chat_hide' and entity = 'game_chat' and entity_id = a0::text and actor_id = pg_temp.uid('Bob') and reason = 'insulti ad altri eroi'
            and old_value->>'body' = 'brutto messaggio' and (old_value->>'user_id')::uuid = pg_temp.uid('Ann')) = 1, 'C7: audit con autore, testo e motivazione';
  assert pg_temp.err_as('Admin', format('select public.game_chat_hide(%s, ''motivo valido'')', a0)) like '%già nascosto%', 'C7: non si nasconde due volte';
  assert (select count(*) from public.audit_logs where action = 'game_chat_hide') = 1, 'C7: un solo audit';
  -- last_id non conta i nascosti
  perform pg_temp.age('Ann', 5);
  perform pg_temp.send('Ann', 'ultimo di Ann');
  a0 := (select id from public.game_chat where body = 'ultimo di Ann');
  perform pg_temp.hide('Admin', a0, 'prova amministratore');
  assert (pg_temp.lst('Cid')->>'last_id')::bigint = (select max(id) from public.game_chat where not hidden), 'C7: last_id ignora i nascosti';
  assert (pg_temp.ping('Cid')->>'last_id')::bigint = (select max(id) from public.game_chat where not hidden), 'C7: anche il ping';
  -- la moderazione funziona anche a modulo spento
  perform pg_temp.age('Dan', 5);
  perform pg_temp.send('Dan', 'da nascondere a modulo spento');
  a0 := (select id from public.game_chat where body = 'da nascondere a modulo spento');
  perform pg_temp.mod(false);
  perform pg_temp.hide('Bob', a0, 'prova a modulo spento');
  assert (select hidden from public.game_chat where id = a0), 'C7: nascondere funziona anche a modulo spento';
  perform pg_temp.mod(true);
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C7 — solo moderatore e amministratore nascondono (motivazione obbligatoria), audit con testo e autore, i nascosti spariscono da elenco, last_id e ping');

  -- C8 — presenza e «chi è online»
  perform pg_temp.clear_chat();
  assert pg_temp.nicks(pg_temp.onl('Cid')) = '{}', 'C8: all''inizio nessuno online';
  r := pg_temp.ping('Ann'); assert r ? 'last_id' and (r->>'last_id')::bigint = 0, 'C8: ping (nessun messaggio: last_id 0)';
  perform pg_temp.ping('Bob'); perform pg_temp.ping('Cid');
  assert pg_temp.nicks(pg_temp.onl('Dan')) = array['Ann','Bob','Cid'], 'C8: online Ann, Bob, Cid, in ordine alfabetico';
  assert (select count(*) from public.game_presence) = 3, 'C8: una riga per persona (ping ripetuto non duplica)';
  perform pg_temp.ping('Ann'); perform pg_temp.ping('Ann');
  assert (select count(*) from public.game_presence where user_id = pg_temp.uid('Ann')) = 1, 'C8: un solo record per Ann';
  assert not exists (select 1 from jsonb_array_elements(pg_temp.onl('Dan')) e where e ? 'email' or e ? 'role' or e ? 'balance') and pg_temp.onl('Dan')::text not like '%@test.local%', 'C8: solo id, nickname e avatar';
  -- scadenza dei 90 secondi
  update public.game_presence set seen_at = clock_timestamp() - interval '80 seconds' where user_id = pg_temp.uid('Ann');
  update public.game_presence set seen_at = clock_timestamp() - interval '100 seconds' where user_id = pg_temp.uid('Bob');
  assert pg_temp.nicks(pg_temp.onl('Dan')) = array['Ann','Cid'], 'C8: 80 secondi ancora online, 100 no';
  perform pg_temp.ping('Bob');
  assert pg_temp.nicks(pg_temp.onl('Dan')) = array['Ann','Bob','Cid'], 'C8: un nuovo ping rimette online';
  -- scrivere ti segna online
  update public.game_presence set seen_at = clock_timestamp() - interval '10 minutes' where user_id = pg_temp.uid('Cid');
  assert 'Cid' <> all (pg_temp.nicks(pg_temp.onl('Dan'))), 'C8: Cid è offline';
  perform pg_temp.send('Cid', 'torno');
  assert 'Cid' = any (pg_temp.nicks(pg_temp.onl('Dan'))), 'C8: scrivere segna online';
  -- sospesi non compaiono
  update public.profiles set suspended = true where id = pg_temp.uid('Bob');
  assert 'Bob' <> all (pg_temp.nicks(pg_temp.onl('Dan'))), 'C8: un sospeso non risulta online';
  update public.profiles set suspended = false where id = pg_temp.uid('Bob');
  -- chi non ha mai fatto ping non compare
  assert 'Dan' <> all (pg_temp.nicks(pg_temp.onl('Ann'))), 'C8: chi non è mai passato non compare';
  -- anche chi guarda soltanto la lista non risulta online (la lista non scrive)
  perform pg_temp.lst('Dan'); perform pg_temp.onl('Dan');
  assert 'Dan' <> all (pg_temp.nicks(pg_temp.onl('Ann'))) and not exists (select 1 from public.game_presence where user_id = pg_temp.uid('Dan')), 'C8: leggere non segna online';
  -- pulizia delle righe vecchie
  update public.game_presence set seen_at = clock_timestamp() - interval '2 days' where user_id = pg_temp.uid('Bob');
  perform pg_temp.ping('Ann');
  assert not exists (select 1 from public.game_presence where user_id = pg_temp.uid('Bob')), 'C8: righe oltre il giorno eliminate';
  -- avatar dell'eroe nei messaggi e nell'elenco
  update public.game_heroes set avatar_card = 46986414, avatar_name = 'Dark Magician' where user_id = pg_temp.uid('Ann');
  perform pg_temp.ping('Ann'); perform pg_temp.age('Cid', 5); perform pg_temp.send('Ann', 'con avatar');
  assert (select e->>'ac' from jsonb_array_elements(pg_temp.onl('Dan')) e where e->>'n' = 'Ann') = '46986414', 'C8: avatar in «online»';
  assert (select e->>'an' from jsonb_array_elements(pg_temp.lst('Dan')->'msgs') e where e->>'n' = 'Ann' limit 1) = 'Dark Magician' and (select e->>'ac' from jsonb_array_elements(pg_temp.lst('Dan')->'msgs') e where e->>'n' = 'Ann' limit 1) = '46986414', 'C8: avatar nei messaggi';
  assert (select e->'ac' from jsonb_array_elements(pg_temp.onl('Dan')) e where e->>'n' = 'Cid') = 'null'::jsonb, 'C8: chi non ha avatar: null';
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C8 — online = visto negli ultimi 90 s (80 sì, 100 no), un record per persona, scrivere segna online, leggere no, sospesi esclusi, pulizia a 1 giorno, avatar nell''elenco');

  -- C9 — modulo spento, account sospeso
  perform pg_temp.send('Ann', 'prima dello spegnimento');
  perform pg_temp.mod(false);
  foreach n in array array['Ann','Admin','Bob'] loop
    assert pg_temp.err_as(n, 'select public.game_chat_send(''x'')') = 'Modulo non attivo', 'C9: ' || n || ' invio a modulo spento';
    assert pg_temp.err_as(n, 'select public.game_chat_list()') = 'Modulo non attivo', 'C9: ' || n || ' elenco a modulo spento';
    assert pg_temp.err_as(n, 'select public.game_presence_ping()') = 'Modulo non attivo', 'C9: ' || n || ' ping a modulo spento';
    assert pg_temp.err_as(n, 'select public.game_online()') = 'Modulo non attivo', 'C9: ' || n || ' online a modulo spento';
  end loop;
  perform pg_temp.mod(true);
  assert 'prima dello spegnimento' = any (pg_temp.texts(pg_temp.lst('Ann'))), 'C9: riacceso, i messaggi ci sono ancora';
  update public.profiles set suspended = true where id = pg_temp.uid('Eve');
  assert pg_temp.err_as('Eve', 'select public.game_chat_send(''x'')') like '%sospeso%' and pg_temp.err_as('Eve', 'select public.game_chat_list()') like '%sospeso%'
     and pg_temp.err_as('Eve', 'select public.game_presence_ping()') like '%sospeso%' and pg_temp.err_as('Eve', 'select public.game_online()') like '%sospeso%', 'C9: un account sospeso non usa la chat';
  update public.profiles set suspended = false where id = pg_temp.uid('Eve');
  perform pg_temp.clear_chat();
  insert into t_log (msg) values ('OK C9 — con il modulo spento ogni funzione rifiuta (3 ruoli × 4 funzioni), riacceso tutto torna; account sospeso fuori');

  -- C10 — nessun effetto sul resto del gioco
  e0 := pg_temp.eco(); a0 := (select count(*) from public.audit_logs);
  perform pg_temp.send('Ann', 'uno'); perform pg_temp.send('Bob', 'due'); perform pg_temp.ping('Cid'); perform pg_temp.lst('Dan'); perform pg_temp.onl('Dan');
  perform pg_temp.age('Ann', 5); perform pg_temp.send('Ann', 'tre');
  assert pg_temp.eco() = e0, 'C10: BC, ledger, eroi, energia, oggetti, boss, duelli, taglie: invariati';
  assert (select count(*) from public.audit_logs) = a0, 'C10: nessun audit per i messaggi normali';
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'C10: saldi = registro';
  insert into t_log (msg) values ('OK C10 — la chat non tocca BC, XP, energia, oggetti, boss, duelli, taglie né audit');
end $$;

select msg from t_log order by n;
rollback;
