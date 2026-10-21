-- =====================================================================
-- TEST DELLA MIGRAZIONE 011 (Ladder: formati, Elo separati, tipo di sfida)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…011 (black-market-setup.sql … black-market-ladder-formati.sql).
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
  assert public._setting('ladder_wpa_pair_day') = 1, 'impostazioni: un solo match WPA al giorno per coppia (per tipo)';
end $$;

-- F1 — struttura, formati ammessi, permessi
do $$
declare e text;
begin
  assert exists (select 1 from information_schema.columns where table_name = 'ladder_matches' and column_name = 'kind')
     and exists (select 1 from information_schema.columns where table_name = 'matches' and column_name = 'bounty_eligible'), 'F1: colonne nuove';
  assert to_regclass('public.ladder_ratings_legacy') is not null, 'F1: la vecchia tabella Elo non è stata cancellata';
  assert (select relrowsecurity from pg_class where oid = 'public.ladder_ratings'::regclass), 'F1: RLS sulle classifiche';
  assert to_regprocedure('public.ladder_challenge(uuid,text,text,text)') is null and to_regprocedure('public.ladder_challenge(uuid,text,text,text,text)') is not null, 'F1: una sola ladder_challenge (niente ambiguità)';
  assert not has_table_privilege('authenticated', 'public.ladder_ratings', 'insert') and not has_table_privilege('authenticated', 'public.ladder_ratings', 'update')
     and not has_table_privilege('authenticated', 'public.ladder_ratings', 'delete') and not has_table_privilege('anon', 'public.ladder_ratings', 'select')
     and not has_table_privilege('authenticated', 'public.ladder_ratings_legacy', 'select'), 'F1: nessuna scrittura diretta, nessun accesso anonimo';
  assert not has_function_privilege('anon', 'public.ladder_challenge(uuid,text,text,text,text)', 'execute')
     and has_function_privilege('authenticated', 'public.ladder_challenge(uuid,text,text,text,text)', 'execute')
     and not has_function_privilege('authenticated', 'public._ladder_close(uuid,text,text,uuid,uuid,text)', 'execute'), 'F1: permessi delle funzioni';
  -- formati: solo Advanced ed Edison
  foreach e in array array['Traditional','GOAT','advanced','Edison ','',' ','Standard'] loop
    assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, %L, null, %L)', pg_temp.uid('Luca'), e, gen_random_uuid()::text)) like '%Advanced o Edison%', 'F1: rifiutato il formato «' || e || '»';
  end loop;
  assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, null, null, %L)', pg_temp.uid('Luca'), gen_random_uuid()::text)) like '%Advanced o Edison%', 'F1: formato mancante rifiutato';
  -- anche con un inserimento diretto (anche dall''amministratore del database) il formato è controllato
  e := pg_temp.err(format('insert into public.ladder_matches (challenger_id, opponent_id, format, client_request_id, expires_at) values (%L, %L, ''GOAT'', ''direct-0001'', now() + interval ''1 day'')', pg_temp.uid('Marco'), pg_temp.uid('Luca')));
  assert e like '%Advanced o Edison%', 'F1: nemmeno un inserimento diretto può usare un altro formato';
  assert (select count(*) from public.ladder_matches) = 0, 'F1: nessuna sfida creata per errore';
  insert into t_log (msg) values ('OK F1 — formati solo Advanced/Edison (anche a livello di tabella), vecchia tabella Elo conservata, permessi e RLS');
end $$;

-- F2 — Elo e classifiche separate per formato
do $$
declare r jsonb; c uuid; s1 numeric; s2 numeric; n1 bigint; n2 bigint;
begin
  c := pg_temp.cc('Org', 'Admin', 'Advanced', 'ladder');
  r := pg_temp.fin(c, 'Org', 'Admin', 'challenger', '2-0');
  assert pg_temp.elo('Org', 'Advanced') = 1016 and pg_temp.elo('Admin', 'Advanced') = 984, 'F2: Advanced: 1016 / 984';
  assert pg_temp.elo('Org', 'Edison') is null and pg_temp.elo('Admin', 'Edison') is null, 'F2: in Edison nessuno è ancora classificato';
  c := pg_temp.cc('Admin', 'Org', 'Edison', 'ladder');
  r := pg_temp.fin(c, 'Admin', 'Org', 'challenger', '2-1');
  assert pg_temp.elo('Admin', 'Edison') = 1016 and pg_temp.elo('Org', 'Edison') = 984, 'F2: Edison parte da 1000 a prescindere dall''Advanced: 1016 / 984';
  assert pg_temp.elo('Org', 'Advanced') = 1016 and pg_temp.elo('Admin', 'Advanced') = 984, 'F2: l''Advanced non si è mosso';
  c := pg_temp.cc('Org', 'Povero', 'Advanced', 'ladder');
  r := pg_temp.fin(c, 'Org', 'Povero', 'challenger', '2-0');
  assert (r->>'format') = 'Advanced' and (r->>'kind') = 'ladder', 'F2: la chiusura riporta formato e tipo';
  assert (select wins from public.ladder_ratings where user_id = pg_temp.uid('Org') and format = 'Advanced') = 2
     and (select losses from public.ladder_ratings where user_id = pg_temp.uid('Org') and format = 'Edison') = 1
     and (select wins from public.ladder_ratings where user_id = pg_temp.uid('Org') and format = 'Edison') = 0, 'F2: vittorie e sconfitte tenute per formato';
  -- classifiche: una per formato, ciascuna con il suo primo posto
  assert (select rank from public.ladder_standings_v where nickname = 'Org' and format = 'Advanced') = 1, 'F2: Org primo in Advanced';
  assert (select rank from public.ladder_standings_v where nickname = 'Admin' and format = 'Edison') = 1, 'F2: Admin primo in Edison';
  assert (select rank from public.ladder_standings_v where nickname = 'Org' and format = 'Edison') = 2, 'F2: Org secondo in Edison';
  assert (select count(distinct format) from public.ladder_standings_v) = 2 and (select count(*) from public.ladder_standings_v where rank = 1 and format = 'Advanced') = 1, 'F2: due classifiche indipendenti';
  -- l''Elo è a somma zero in ogni formato
  select sum(elo), count(*) into s1, n1 from public.ladder_ratings where format = 'Advanced';
  select sum(elo), count(*) into s2, n2 from public.ladder_ratings where format = 'Edison';
  assert s1 = 1000 * n1 and s2 = 1000 * n2, 'F2: la somma dell''Elo di ogni formato non cambia (1000 per giocatore)';
  assert (select count(*) from public.ladder_ratings where format not in ('Advanced','Edison')) = 0, 'F2: nessun altro formato nelle classifiche';
  insert into t_log (msg) values ('OK F2 — Elo e classifiche separate per Advanced ed Edison, ognuno da 1000, vittorie/sconfitte per formato, somma zero');
end $$;

-- Taglie di prova: su Luca 100 (Paolo) + 50 (Marco, la quota "propria" di Marco); su Paolo 60 (Povero)
do $$ begin
  perform pg_temp.bnt('Paolo', 'Luca', 100); perform pg_temp.bnt('Marco', 'Luca', 50); perform pg_temp.bnt('Povero', 'Paolo', 60);
  assert pg_temp.act_b('Luca') = 2 and pg_temp.act_b('Paolo') = 1, 'preparazione taglie';
end $$;

-- F3 — Ladder normale: Elo e premio sì, ma NON dà diritto alla taglia
do $$
declare c uuid; r jsonb; m uuid; b0 integer; t0 integer; e text; n0 bigint;
begin
  c := pg_temp.cc('Marco', 'Luca', 'Advanced', 'ladder');
  assert (select kind from public.ladder_matches where id = c) = 'ladder', 'F3: tipo registrato';
  assert (select kind from public.notifications where ref_id = c) = 'ladder_challenge' and (select body from public.notifications where ref_id = c) not like '%taglia%', 'F3: Luca riceve una sfida Ladder normale, senza parlare di taglia';
  assert pg_temp.rows_as('Luca', format('select 1 from public.ladder_matches where id = %L and kind = ''ladder''', c)) = 1, 'F3: lo sfidato vede il tipo PRIMA di accettare';
  b0 := (select balance from public.wallets where user_id = pg_temp.uid('Marco'));
  r := pg_temp.fin(c, 'Marco', 'Luca', 'challenger', '2-0');
  assert pg_temp.elo('Marco', 'Advanced') = 1016 and pg_temp.elo('Luca', 'Advanced') = 984, 'F3: l''Elo si muove';
  assert (r->>'reward')::int = 20 and (select balance from public.wallets where user_id = pg_temp.uid('Marco')) = b0 + 20, 'F3: il premio Ladder di 20 BC arriva';
  m := (r->>'official_match')::uuid;
  assert m is not null and (select bounty_eligible from public.matches where id = m) = false and (select status from public.matches where id = m) = 'verified', 'F3: è un match WPA ufficiale ma non valido per la taglia';
  t0 := (select count(*) from public.bounty_settlements);
  e := pg_temp.err_as('Marco', format('select public.claim_bounty(%L)', m));
  assert e like '%Ladder normale%', 'F3: la riscossione è rifiutata (' || coalesce(e, 'riuscita') || ')';
  assert pg_temp.act_b('Luca') = 2 and (select count(*) from public.bounty_settlements) = t0, 'F3: le taglie di Luca sono intatte';
  assert (select balance from public.wallets where user_id = pg_temp.uid('Marco')) = b0 + 20, 'F3: il saldo di Marco non cambia dopo il tentativo';
  -- accettazione: lo sfidante riceve l'avviso
  assert (select count(*) from public.notifications where user_id = pg_temp.uid('Marco') and kind = 'ladder_accepted' and ref_id = c) = 1, 'F3: Marco è avvisato che Luca ha accettato';
  insert into t_log (msg) values ('OK F3 — Ladder normale: Elo + 20 BC + match ufficiale, ma nessuna riscossione possibile; il tipo è visibile allo sfidato');
end $$;

-- F4 — Solo per la taglia: nessun Elo, nessun premio Ladder, ma il match ufficiale permette di riscuotere
do $$
declare c uuid; r jsonb; m uuid; b0 integer; ea integer; el integer; n0 bigint; t text;
begin
  ea := pg_temp.elo('Marco', 'Advanced'); el := pg_temp.elo('Luca', 'Advanced'); n0 := (select count(*) from public.ladder_ratings);
  c := pg_temp.cc('Marco', 'Luca', 'Edison', 'bounty');
  select title || ' | ' || body into t from public.notifications where ref_id = c;
  assert (select kind from public.notifications where ref_id = c) = 'bounty_challenge' and t like '%solo per la taglia%' and t like '%100 BC%' and t like '%Nessun Elo%', 'F4: Luca vede che è solo per la taglia e quanto (100 BC: la quota di Marco non è un guadagno)';
  b0 := (select balance from public.wallets where user_id = pg_temp.uid('Marco'));
  r := pg_temp.fin(c, 'Marco', 'Luca', 'challenger', '2-0');
  assert pg_temp.elo('Marco', 'Advanced') = ea and pg_temp.elo('Luca', 'Advanced') = el and (select count(*) from public.ladder_ratings) = n0, 'F4: nessun Elo cambia, nessuna riga di classifica nuova (nemmeno in Edison)';
  assert (r->>'reward')::int = 0 and (r->>'reward_note') like '%solo per la taglia%', 'F4: nessun premio Ladder';
  assert (select balance from public.wallets where user_id = pg_temp.uid('Marco')) = b0, 'F4: il saldo non si muove alla chiusura';
  assert (select elo_challenger_delta from public.ladder_matches where id = c) = 0 and (select elo_opponent_delta from public.ladder_matches where id = c) = 0, 'F4: variazioni Elo registrate a zero';
  m := (r->>'official_match')::uuid;
  assert m is not null and (select bounty_eligible from public.matches where id = m), 'F4: match ufficiale valido per la taglia (anche se nello stesso giorno c''era già un match ufficiale tra i due)';
  -- riscossione: 100 di Paolo a Marco, le sue 40 gli tornano indietro
  r := pg_temp.claim('Marco', m);
  assert (r->>'payout')::int = 100 and (r->>'refunded')::int = 50, 'F4: incassa 100 e riavrà le sue 50';
  assert (select balance from public.wallets where user_id = pg_temp.uid('Marco')) = b0 + 150 and pg_temp.act_b('Luca') = 0, 'F4: saldo +150, taglie di Luca chiuse';
  assert (pg_temp.claim('Marco', m)->>'already')::boolean, 'F4: una seconda richiesta non paga di nuovo';
  insert into t_log (msg) values ('OK F4 — solo per la taglia: niente Elo né premio Ladder, il match ufficiale permette la riscossione (una volta sola)');
end $$;

-- F5 — Entrambe: Elo + premio + riscossione
do $$
declare c uuid; r jsonb; m uuid; b0 integer; ea integer; t text;
begin
  b0 := (select balance from public.wallets where user_id = pg_temp.uid('Marco'));
  c := pg_temp.cc('Marco', 'Paolo', 'Advanced', 'both');
  select body into t from public.notifications where ref_id = c;
  assert (select kind from public.notifications where ref_id = c) = 'bounty_challenge' and t like '%60 BC%' and t like '%anche l''Elo%', 'F5: Paolo vede: taglia da 60 BC e anche l''Elo in gioco';
  r := pg_temp.fin(c, 'Marco', 'Paolo', 'challenger', '2-1');
  assert pg_temp.elo('Marco', 'Advanced') > 1016 and pg_temp.elo('Paolo', 'Advanced') < 1000, 'F5: l''Elo Advanced si muove';
  assert (r->>'reward')::int = 20, 'F5: premio Ladder';
  m := (r->>'official_match')::uuid;
  assert (select bounty_eligible from public.matches where id = m), 'F5: match valido per la taglia';
  r := pg_temp.claim('Marco', m);
  assert (r->>'payout')::int = 60 and (select balance from public.wallets where user_id = pg_temp.uid('Marco')) = b0 + 20 + 60, 'F5: +20 BC Ladder +60 BC di taglia';
  insert into t_log (msg) values ('OK F5 — entrambe: Elo + premio Ladder + match ufficiale + riscossione della taglia');
end $$;

-- F6 — Controlli lato server sul tipo di sfida
do $$
declare c uuid; e text; k text;
begin
  -- nessuna taglia sull'avversario: solo Ladder normale
  assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, ''Advanced'', null, %L, ''both'')', pg_temp.uid('Povero'), gen_random_uuid()::text)) like '%non ha taglie%', 'F6: «entrambe» senza taglie rifiutato';
  assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, ''Advanced'', null, %L, ''bounty'')', pg_temp.uid('Povero'), gen_random_uuid()::text)) like '%non ha taglie%', 'F6: «solo taglia» senza taglie rifiutato';
  assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, ''Advanced'', null, %L, ''altro'')', pg_temp.uid('Povero'), gen_random_uuid()::text)) like '%Tipo di sfida non valido%', 'F6: tipo sconosciuto rifiutato';
  -- una taglia messa solo da me non è un guadagno: non posso sfidare per quella
  perform pg_temp.bnt('Marco', 'Admin', 50);
  assert pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, ''Advanced'', null, %L, ''bounty'')', pg_temp.uid('Admin'), gen_random_uuid()::text)) like '%non ha taglie che tu possa riscuotere%', 'F6: non si sfida per la propria taglia';
  c := pg_temp.cc('Marco', 'Admin', 'Advanced', 'ladder');
  assert (select kind from public.ladder_matches where id = c) = 'ladder', 'F6: ma una sfida normale è sempre possibile';
  perform pg_temp.as_('Marco'); perform public.ladder_cancel(c);
  -- gli altri possono incassare la taglia di Marco su Admin
  c := pg_temp.cc('Org', 'Admin', 'Edison', 'bounty');
  assert (select kind from public.ladder_matches where id = c) = 'bounty', 'F6: Org può sfidare Admin per la taglia di Marco';
  -- comportamento di prima (senza p_kind): automatico
  perform pg_temp.as_('Org'); perform public.ladder_cancel(c);
  perform pg_temp.as_('Org'); c := public.ladder_challenge(pg_temp.uid('Admin'), 'Advanced', null, gen_random_uuid()::text);
  assert (select kind from public.ladder_matches where id = c) = 'both', 'F6: senza p_kind e con taglie incassabili = entrambe (come prima)';
  perform public.ladder_cancel(c);
  perform pg_temp.as_('Marco'); c := public.ladder_challenge(pg_temp.uid('Povero'), 'Advanced', null, gen_random_uuid()::text);
  assert (select kind from public.ladder_matches where id = c) = 'ladder', 'F6: senza p_kind e senza taglie = Ladder normale (come prima)';
  perform public.ladder_cancel(c);
  -- richiesta ripetuta: stessa sfida, anche con parametri diversi non ne nasce una seconda
  perform pg_temp.as_('Marco'); k := gen_random_uuid()::text;
  c := public.ladder_challenge(pg_temp.uid('Povero'), 'Edison', null, k, 'ladder');
  assert public.ladder_challenge(pg_temp.uid('Povero'), 'Edison', null, k, 'ladder') = c and (select count(*) from public.ladder_matches where client_request_id = k) = 1, 'F6: richiesta ripetuta = una sola sfida';
  perform public.ladder_cancel(c);
  insert into t_log (msg) values ('OK F6 — il database rifiuta «per la taglia» se non ci sono taglie incassabili (le proprie non contano), tipi non validi; compatibilità con la chiamata senza tipo');
end $$;

-- F7 — Accettare e rifiutare: solo lo sfidato, avviso allo sfidante, una volta sola
do $$
declare c uuid; c2 uuid; n0 bigint;
begin
  c := pg_temp.cc('Org', 'Admin', 'Advanced', 'bounty');
  assert pg_temp.err_as('Org', format('select public.ladder_respond(%L, true)', c)) like '%non trovata%', 'F7: lo sfidante non può accettare al posto dello sfidato';
  assert pg_temp.err_as('Marco', format('select public.ladder_respond(%L, true)', c)) like '%non trovata%', 'F7: un terzo non può accettare';
  perform pg_temp.as_('Admin'); perform public.ladder_respond(c, false);
  assert (select status from public.ladder_matches where id = c) = 'declined', 'F7: rifiutata';
  assert (select count(*) from public.notifications where user_id = pg_temp.uid('Org') and kind = 'ladder_declined' and ref_id = c) = 1, 'F7: lo sfidante è avvisato del rifiuto';
  assert pg_temp.err_as('Admin', format('select public.ladder_respond(%L, true)', c)) like '%non è più in attesa%', 'F7: una sfida rifiutata non si accetta più';
  assert (select count(*) from public.notifications where ref_id = c) = 2, 'F7: nessuna notifica doppia (1 sfida ricevuta + 1 rifiuto)';
  -- con "sfida in Ladder" spento, lo sfidante non riceve l'avviso ma la sfida funziona lo stesso
  perform pg_temp.prefs('Org', null, false, null);
  c2 := pg_temp.cc('Org', 'Admin', 'Edison', 'ladder');
  n0 := pg_temp.nn('Org');
  perform pg_temp.as_('Admin'); perform public.ladder_respond(c2, true);
  assert (select status from public.ladder_matches where id = c2) = 'accepted' and pg_temp.nn('Org') = n0, 'F7: preferenza spenta: sfida accettata, nessun avviso allo sfidante';
  perform pg_temp.prefs('Org', null, true, null);
  perform pg_temp.as_('Org'); perform public.ladder_cancel(c2);
  assert (select count(*) from public.notifications where kind in ('ladder_accepted','ladder_declined') and ref_id = c2) = 0, 'F7: nessun avviso dopo l''annullamento';
  insert into t_log (msg) values ('OK F7 — accettare/rifiutare: solo lo sfidato, avviso allo sfidante (una volta), rispetta le preferenze');
end $$;

-- F8 — Limite del match ufficiale giornaliero: separato per match "normali" e "per la taglia"
do $$
declare c uuid; r jsonb;
begin
  -- tra Marco e Luca oggi ci sono già un match ufficiale normale (F3) e uno per la taglia (F4); un altro normale non diventa ufficiale, ma conta per l'Elo
  c := pg_temp.cc('Marco', 'Luca', 'Advanced', 'ladder');
  r := pg_temp.fin(c, 'Marco', 'Luca', 'challenger', '2-0');
  assert (r->>'official_match') is null and (r->>'official_note') like '%già registrato%', 'F8: secondo match normale dello stesso giorno: niente match ufficiale';
  assert (r->>'challenger_delta')::int <> 0, 'F8: ma l''Elo si muove';
  insert into t_log (msg) values ('OK F8 — un match "normale" non toglie il match ufficiale a quello "per la taglia" (limite separato)');
end $$;

-- F9 — Badge: le sfide solo per la taglia non sono partite di Ladder (ma sono match ufficiali)
do $$
declare lw integer; dw integer; pk integer;
begin
  perform pg_temp.as_('Marco');
  select max(value) into lw from public.badge_progress() where metric = 'ladder_win';
  select max(value) into dw from public.badge_progress() where metric = 'duel_win';
  select max(value) into pk from public.badge_progress() where metric = 'elo_peak';
  assert lw = 3, 'F9: vittorie di Ladder di Marco = 3 (F3 normale, F5 entrambe, F8 normale; la sfida solo per la taglia non conta) invece di ' || coalesce(lw::text, 'null');
  assert dw = 3, 'F9: vittorie ufficiali di Marco = 3 (F3, F4, F5) invece di ' || coalesce(dw::text, 'null');
  assert pk >= 1016, 'F9: il picco di Elo conta il formato giocato';
  insert into t_log (msg) values ('OK F9 — badge: la sfida solo per la taglia vale come match ufficiale ma non come partita di Ladder');
end $$;

-- F10 — Attesa anti-accordi invariata, riscossione dei match degli organizzatori invariata, economia coerente
do $$
declare c uuid; r jsonb; m uuid; ev uuid; mm uuid; b0 integer; e text;
begin
  -- l'attesa di 24 ore vale ancora per i match Ladder validi per la taglia
  perform pg_temp.set_('ladder_claim_hold_hours', 24);
  perform pg_temp.bnt('Luca', 'Povero', 80);
  c := pg_temp.cc('Org', 'Povero', 'Advanced', 'bounty');
  r := pg_temp.fin(c, 'Org', 'Povero', 'challenger', '2-0');
  e := pg_temp.err_as('Org', format('select public.claim_bounty(%L)', (r->>'official_match')::uuid));
  assert e like '%dopo 24 ore%', 'F10: l''attesa anti-accordi vale ancora (' || coalesce(e, 'riuscita') || ')';
  perform pg_temp.set_('ladder_claim_hold_hours', 0);
  assert (pg_temp.claim('Org', (r->>'official_match')::uuid)->>'payout')::int = 80, 'F10: dopo l''attesa (qui a 0) incassa 80';
  -- match di un organizzatore in un evento: riscuotibile come sempre (bounty_eligible = true di default)
  perform pg_temp.bnt('Luca', 'Org', 70);
  ev := pg_temp.ev('Torneo di prova');
  mm := pg_temp.mm(ev, 1, 'Paolo', 'Org', 'Paolo');
  assert (select bounty_eligible from public.matches where id = mm) and (select source from public.matches where id = mm) = 'organizer', 'F10: match dell''organizzatore valido per le taglie';
  b0 := (select balance from public.wallets where user_id = pg_temp.uid('Paolo'));
  r := pg_temp.claim('Paolo', mm);
  assert (r->>'payout')::int = 70 and (select balance from public.wallets where user_id = pg_temp.uid('Paolo')) = b0 + 70, 'F10: Paolo incassa 70 dal match dell''organizzatore: ' || r::text || ' saldo ' || (select balance from public.wallets where user_id = pg_temp.uid('Paolo'))::text || ' prima ' || b0::text;
  -- economia: nessun BC inventato dalle nuove sfide
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind = 'ladder_reward') = (select coalesce(sum(reward_amount), 0) from public.ladder_matches), 'F10: i premi Ladder nel registro = quelli scritti nei match';
  assert (select count(*) from public.ladder_matches where kind = 'bounty' and status = 'closed' and reward_amount > 0) = 0, 'F10: nessun premio per le sfide solo per la taglia';
  assert (select coalesce(sum(balance), 0) from public.wallets) = (select coalesce(sum(amount), 0) from public.ledger_entries), 'F10: somma dei saldi = somma del registro';
  assert not exists (select 1 from public.wallet_reconciliation_v where not ok), 'F10: ogni saldo = somma dei suoi movimenti';
  assert (select count(*) from public.ledger_entries where kind not in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward')) = 0, 'F10: nessun tipo di movimento nuovo';
  insert into t_log (msg) values ('OK F10 — attesa anti-accordi invariata, match degli organizzatori ancora riscuotibili, saldi = registro, nessun BC inventato');
end $$;

-- F11 — Permessi e interruttore del modulo
do $$
declare e text;
begin
  assert pg_temp.err_auth('Marco', 'insert into public.ladder_ratings (user_id, format, elo) values (auth.uid(), ''Advanced'', 5000)') like '%permission denied%', 'F11: nessuna scrittura diretta delle classifiche';
  assert pg_temp.err_auth('Marco', 'update public.ladder_matches set kind = ''both''') like '%permission denied%', 'F11: il tipo di sfida non si cambia dal browser';
  assert pg_temp.err_auth('Marco', 'update public.matches set bounty_eligible = true') like '%permission denied%', 'F11: l''idoneità del match non si cambia dal browser';
  assert pg_temp.err_auth('Marco', 'select * from public.ladder_ratings_legacy') like '%permission denied%', 'F11: la vecchia tabella non è esposta';
  assert pg_temp.rows_as('Marco', 'select 1 from public.ladder_standings_v') > 0 and pg_temp.rows_as('Marco', 'select 1 from public.ladder_ratings') > 0, 'F11: le classifiche si leggono';
  assert pg_temp.err_auth('Marco', 'select public._ladder_close(gen_random_uuid(), ''draw'', ''1-1'', null, null, null)') like '%permission denied%', 'F11: _ladder_close non è chiamabile dal browser';
  assert pg_temp.err_auth('Marco', format('select public.claim_bounty(%L)', gen_random_uuid())) like '%Match inesistente%', 'F11: claim_bounty resta chiamabile e controlla il match';
  -- modulo spento: nessuna sfida, classifiche vuote
  perform pg_temp.mod('ladder', false);
  e := pg_temp.err_as('Marco', format('select public.ladder_challenge(%L, ''Advanced'', null, %L, ''ladder'')', pg_temp.uid('Povero'), gen_random_uuid()::text));
  assert e is not null, 'F11: Ladder spenta = nessuna sfida (' || coalesce(e, 'riuscita') || ')';
  assert pg_temp.rows_as('Marco', 'select 1 from public.ladder_standings_v') = 0, 'F11: Ladder spenta = classifiche non visibili';
  perform pg_temp.mod('ladder', true);
  assert pg_temp.rows_as('Marco', 'select 1 from public.ladder_standings_v') > 0, 'F11: riaccesa, tornano visibili';
  insert into t_log (msg) values ('OK F11 — nessuna scrittura diretta (classifiche, tipo di sfida, idoneità), vecchia tabella non esposta, interruttore del modulo');
end $$;

select n, msg from t_log order by n;
rollback;
