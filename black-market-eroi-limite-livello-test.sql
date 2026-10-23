-- =====================================================================
-- TEST DELLA MIGRAZIONE 025 (limite di livello degli eroi, da 100 a 9999)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…025 (black-market-setup.sql … black-market-eroi-limite-livello.sql).
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

-- Preparazione: Admin (primo registrato), Org organizzatore e 8 duellanti
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Eve','Fay','Gus','Hal'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova');
  insert into t_log (msg) values ('OK Preparazione: 10 utenti');
end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.tot() returns bigint language sql as $$ select coalesce(sum(balance), 0) from public.wallets $$;
create function pg_temp.st(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_state(); end $$;
create function pg_temp.setst(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_set_stats(8, 4, 4, 2, 2); end $$;
create function pg_temp.act(n text, a text, t text default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(n); return public.game_boss_act(a, case when t is null then null else pg_temp.uid(t) end); end $$;
create function pg_temp.join_(n text, p_lobby bigint default null) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_join(p_lobby); end $$;
create function pg_temp.leave_(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_leave(); end $$;
create function pg_temp.start_(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_boss_start(); end $$;
create function pg_temp.lob(n text) returns bigint language sql as $$ select lobby_id from public.game_day_heroes where user_id = pg_temp.uid(n) and day = public._game_today() $$;
create function pg_temp.mod(on_ boolean) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', on_, 'prova del modulo'); end $$;
-- «passa un giorno»: sposta indietro di 1 giorno tutto ciò che è legato alla data
create function pg_temp.shift() returns void language plpgsql as $$
declare r record;
begin
  for r in select day from public.game_days order by day asc loop update public.game_days set day = day - 1 where day = r.day; end loop;
  for r in select distinct day from public.game_merchant_offers order by day asc loop update public.game_merchant_offers set day = day - 1 where day = r.day; end loop;
  alter table public.game_rewards disable trigger user;
  update public.game_rewards set day = day - 1;
  alter table public.game_rewards enable trigger user;
  -- anche le chiavi di idempotenza dei premi seguono la data (in produzione i giorni non si ripetono: qui sì)
  alter table public.ledger_entries disable trigger ledger_immutable;
  for r in select distinct split_part(idempotency_key, ':', 2)::date as dd from public.ledger_entries where idempotency_key like 'gameboss:%' order by 1 asc loop
    update public.ledger_entries set idempotency_key = 'gameboss:' || (r.dd - 1)::text || ':' || split_part(idempotency_key, ':', 3)
      where idempotency_key like 'gameboss:' || r.dd::text || ':%';
  end loop;
  alter table public.ledger_entries enable trigger ledger_immutable;
end $$;
create function pg_temp.exp_hp(p_no integer, p_cycle integer, uids uuid[]) returns bigint language plpgsql as $$
declare s numeric := 0; u uuid; c record;
begin
  foreach u in array uids loop select * into c from public._game_calc(u); s := s + c.s_for * 3; end loop;
  return greatest(50, ceil(s * public._setting('game_daily_actions') * (select coverage from public.game_bosses where no = p_no) * (1 + 0.25 * p_cycle)
                           * public._setting('game_boss_difficulty') / 100.0))::bigint;
end $$;


create function pg_temp.en(n text) returns numeric language sql as $$ select public._game_energy_of(pg_temp.uid(n)) $$;
create function pg_temp.setup(n text, lvl integer, xp_left integer, en numeric) returns void language plpgsql as $$
begin   -- livello, XP mancanti al prossimo livello, energia attuale
  update public.game_heroes set level = lvl, xp = public._game_xp_need(lvl) - xp_left, energy = en, energy_at = now() where user_id = pg_temp.uid(n);
end $$;
create function pg_temp.duel(a text, b text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(a); return public.game_duel(pg_temp.uid(b)); end $$;


create function pg_temp.lv(n text) returns integer language sql as $$ select level from public.game_heroes where user_id = pg_temp.uid(n) $$;
create function pg_temp.xp(n text) returns bigint language sql as $$ select xp from public.game_heroes where user_id = pg_temp.uid(n) $$;
create function pg_temp.txp(n text) returns bigint language sql as $$ select total_xp from public.game_heroes where user_id = pg_temp.uid(n) $$;
create function pg_temp.addxp(n text, x bigint) returns jsonb language sql as $$ select public._game_add_xp(pg_temp.uid(n), x) $$;
create function pg_temp.cap(v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting('game_level_cap', v, 'prova del limite di livello'); end $$;
-- gli eroi di prova
do $$ declare n text; begin
  foreach n in array array['Ann','Bob','Cid'] loop perform pg_temp.as_(n); perform public.game_state(); end loop;
end $$;

-- C1 — predefinito: 9999, come prima
do $$ begin
  if (select value_int from public.system_settings where key = 'game_level_cap') <> 9999 then raise exception 'C1: il limite predefinito non è 9999'; end if;
  if public._game_level_cap() <> 9999 then raise exception 'C1: _game_level_cap non è 9999'; end if;
  perform pg_temp.setup('Ann', 9998, 5, 100);
  perform pg_temp.addxp('Ann', 100000);
  if pg_temp.lv('Ann') <> 9999 or pg_temp.xp('Ann') <> 0 then raise exception 'C1: con 9999 l''eroe deve arrivare a 9999 (%, %)', pg_temp.lv('Ann'), pg_temp.xp('Ann'); end if;
  perform pg_temp.addxp('Ann', 100000);
  if pg_temp.lv('Ann') <> 9999 then raise exception 'C1: oltre 9999 non si sale'; end if;
  perform pg_temp.setup('Ann', 1, 5, 100);
  insert into t_log (msg) values ('OK C1: predefinito 9999 (nulla cambia rispetto a prima)');
end $$;

-- C2 — l'intervallo 100…9999 è imposto dal database
do $$ declare e text; begin
  foreach e in array array['99','0','10000','-5','1','100000'] loop
    if pg_temp.err_as('Admin', format($q$select public.admin_set_setting('game_level_cap', %s, 'valore fuori intervallo')$q$, e)) is null then
      raise exception 'C2: admin_set_setting ha accettato %', e; end if;
  end loop;
  if pg_temp.err_as('Admin', $q$select public.admin_set_setting('game_level_cap', 99, 'valore fuori intervallo')$q$) not like '%tra 100 e 9999%' then raise exception 'C2: messaggio errato'; end if;
  -- anche con SQL diretto (nessuna scorciatoia)
  if pg_temp.err($q$update public.system_settings set value_int = 50 where key = 'game_level_cap'$q$) is null then raise exception 'C2: update diretto a 50 accettato'; end if;
  if pg_temp.err($q$update public.system_settings set value_int = 10000 where key = 'game_level_cap'$q$) is null then raise exception 'C2: update diretto a 10000 accettato'; end if;
  if (select value_int from public.system_settings where key = 'game_level_cap') <> 9999 then raise exception 'C2: il valore è cambiato dopo i rifiuti'; end if;
  -- gli estremi sono validi
  perform pg_temp.cap(100); if public._game_level_cap() <> 100 then raise exception 'C2: 100 rifiutato'; end if;
  perform pg_temp.cap(9999); if public._game_level_cap() <> 9999 then raise exception 'C2: 9999 rifiutato'; end if;
  perform pg_temp.cap(1234); if public._game_level_cap() <> 1234 then raise exception 'C2: 1234 rifiutato'; end if;
  perform pg_temp.cap(9999);
  -- le altre impostazioni non sono toccate dal controllo
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('game_boss_bc', 7, 'prova altra impostazione');
  if public._setting('game_boss_bc') <> 7 then raise exception 'C2: altra impostazione non salvata'; end if;
  perform public.admin_set_setting('game_boss_bc', 100, 'ripristino dopo la prova');
  insert into t_log (msg) values ('OK C2: solo valori interi tra 100 e 9999 (anche con SQL diretto); estremi accettati; le altre impostazioni libere');
end $$;

-- C3 — chi non è amministratore non può cambiarlo (né dal browser né con funzioni)
do $$ declare n text; begin
  foreach n in array array['Ann','Org'] loop
    if pg_temp.err_as(n, $q$select public.admin_set_setting('game_level_cap', 500, 'tentativo non autorizzato')$q$) is null then raise exception 'C3: % ha cambiato il limite', n; end if;
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Bob'), 'moderator', 'moderatore di prova');
  if pg_temp.err_as('Bob', $q$select public.admin_set_setting('game_level_cap', 500, 'tentativo del moderatore')$q$) is null then raise exception 'C3: un moderatore ha cambiato il limite'; end if;
  if pg_temp.err_auth('Ann', $q$update public.system_settings set value_int = 500 where key = 'game_level_cap'$q$) is null then raise exception 'C3: scrittura diretta dal browser consentita'; end if;
  if public._game_level_cap() <> 9999 then raise exception 'C3: il limite è cambiato'; end if;
  -- ma tutti lo possono LEGGERE (la pagina lo mostra)
  if pg_temp.rows_as('Ann', $q$select 1 from public.system_settings where key = 'game_level_cap'$q$) <> 1 then raise exception 'C3: il limite non è leggibile'; end if;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Bob'), 'user', 'ripristino');
  insert into t_log (msg) values ('OK C3: solo l''amministratore lo modifica (utenti, organizzatori, moderatori e scritture dirette bloccati); lettura per tutti');
end $$;

-- C4 — il limite ferma la salita: livello 99 → 100 e basta
do $$ declare r jsonb; m0 text; begin
  m0 := pg_temp.money();
  perform pg_temp.cap(100);
  perform pg_temp.setup('Ann', 99, 5, 30);
  r := pg_temp.addxp('Ann', 10000000);
  if pg_temp.lv('Ann') <> 100 or pg_temp.xp('Ann') <> 0 then raise exception 'C4: atteso livello 100/xp 0, trovato %/%', pg_temp.lv('Ann'), pg_temp.xp('Ann'); end if;
  if (r->>'levels')::int <> 1 or (r->>'cap')::int <> 100 then raise exception 'C4: risposta errata %', r; end if;
  if pg_temp.en('Ann') < 99.9 then raise exception 'C4: salire di livello deve ancora ricaricare l''energia'; end if;
  if pg_temp.txp('Ann') < 10000000 then raise exception 'C4: il totale XP deve contare'; end if;
  -- ancora XP: non cambia nulla
  r := pg_temp.addxp('Ann', 5000);
  if pg_temp.lv('Ann') <> 100 or pg_temp.xp('Ann') <> 0 or (r->>'levels')::int <> 0 then raise exception 'C4: oltre il limite non si sale'; end if;
  -- chi è sotto il limite sale normalmente e si ferma al limite
  perform pg_temp.setup('Bob', 98, 10, 100);
  perform pg_temp.addxp('Bob', 1000000);
  if pg_temp.lv('Bob') <> 100 then raise exception 'C4: Bob doveva fermarsi a 100, è a %', pg_temp.lv('Bob'); end if;
  perform pg_temp.setup('Cid', 3, 10, 100);
  perform pg_temp.addxp('Cid', 25);
  if pg_temp.lv('Cid') <> 4 then raise exception 'C4: Cid sotto il limite deve salire normalmente'; end if;
  if pg_temp.money() <> m0 then raise exception 'C4: i BC sono cambiati'; end if;
  insert into t_log (msg) values ('OK C4: con limite 100 l''eroe si ferma a 100 (XP in eccesso persa, totale XP e ricarica energia ok, nessun BC mosso)');
end $$;

-- C5 — abbassare il limite NON toglie livelli: chi è sopra resta dov'è ma non sale
do $$ declare st0 jsonb; st1 jsonb; begin
  perform pg_temp.cap(9999);
  perform pg_temp.setup('Ann', 500, 40, 100);
  st0 := pg_temp.st('Ann');
  perform pg_temp.cap(100);
  if pg_temp.lv('Ann') <> 500 then raise exception 'C5: il livello è stato toccato dall''abbassamento'; end if;
  perform pg_temp.addxp('Ann', 100000);
  if pg_temp.lv('Ann') <> 500 or pg_temp.xp('Ann') <> 0 then raise exception 'C5: sopra il limite non si deve salire né accumulare XP'; end if;
  st1 := pg_temp.st('Ann');
  if st1->'me'->'stats' is distinct from st0->'me'->'stats' then raise exception 'C5: le statistiche sono cambiate'; end if;
  if (st1->'me'->>'level')::int <> 500 then raise exception 'C5: game_state non mostra il livello 500'; end if;
  insert into t_log (msg) values ('OK C5: abbassando il limite chi è già sopra resta al suo livello (statistiche intatte) ma non sale più');
end $$;

-- C6 — rialzando il limite si riprende a salire
do $$ begin
  perform pg_temp.cap(600);
  perform pg_temp.addxp('Ann', 1000000);
  if pg_temp.lv('Ann') <= 500 or pg_temp.lv('Ann') > 600 then raise exception 'C6: dopo il rialzo doveva salire fino a 600 al massimo (%)', pg_temp.lv('Ann'); end if;
  perform pg_temp.addxp('Ann', 100000000);
  if pg_temp.lv('Ann') <> 600 then raise exception 'C6: doveva fermarsi a 600 (%)', pg_temp.lv('Ann'); end if;
  insert into t_log (msg) values ('OK C6: rialzando il limite l''eroe riprende a salire e si ferma al nuovo limite');
end $$;

-- C7 — anche i duelli (e ogni altra fonte di XP) rispettano il limite
do $$ declare r jsonb; e0 numeric; begin
  perform pg_temp.cap(100);
  perform pg_temp.setst('Ann'); perform pg_temp.setst('Bob');
  perform pg_temp.setup('Ann', 100, 0, 100);
  perform pg_temp.setup('Bob', 5, 10, 100);
  r := pg_temp.duel('Ann', 'Bob');
  if (r->>'won')::boolean is not true then raise exception 'C7: Ann (liv. 100) doveva battere Bob (liv. 5): %', r; end if;
  if pg_temp.lv('Ann') <> 100 then raise exception 'C7: Ann ha superato il limite con un duello (%)', pg_temp.lv('Ann'); end if;
  if pg_temp.en('Ann') > 96 then raise exception 'C7: nessun livello guadagnato → l''energia deve scendere (%)', pg_temp.en('Ann'); end if;
  insert into t_log (msg) values ('OK C7: i duelli rispettano il limite (nessun livello oltre, nessuna ricarica energia senza livello)');
end $$;

-- C8 — audit: la modifica è tracciata con autore, vecchio e nuovo valore
do $$ begin
  perform pg_temp.cap(777);
  if not exists (select 1 from public.audit_logs where action = 'set_setting' and entity_id = 'game_level_cap'
                 and actor_id = pg_temp.uid('Admin') and (new_value->>'value')::int = 777 and (old_value->>'value')::int = 100 and reason = 'prova del limite di livello') then
    raise exception 'C8: audit mancante o incompleto'; end if;
  perform pg_temp.cap(9999);
  insert into t_log (msg) values ('OK C8: ogni modifica è nell''audit (chi, da quanto a quanto, motivazione)');
end $$;

-- C9 — con il gioco spento il limite non apre scorciatoie; game_state funziona a ogni limite
do $$ begin
  perform pg_temp.cap(100);
  perform pg_temp.setup('Ann', 4000, 0, 100);
  perform pg_temp.st('Ann');   -- eroe sopra il limite: la pagina deve poter caricare
  perform pg_temp.mod(false);
  if pg_temp.err_as('Ann', 'select public.game_state()') is null then raise exception 'C9: gioco spento ma game_state risponde'; end if;
  perform pg_temp.mod(true);
  perform pg_temp.cap(9999);
  insert into t_log (msg) values ('OK C9: game_state funziona anche con eroi sopra il limite; modulo spento sempre rispettato');
end $$;

-- C10 — i BC non si muovono mai per il limite
do $$ declare m0 text; begin
  m0 := pg_temp.money();
  perform pg_temp.cap(150); perform pg_temp.cap(9999);
  perform pg_temp.addxp('Bob', 5000);
  if pg_temp.money() <> m0 then raise exception 'C10: BC o registro cambiati'; end if;
  insert into t_log (msg) values ('OK C10: nessun BC creato, spostato o addebitato');
end $$;

-- C11 — rete di sicurezza: riga mancante o alterata fuori dal controllo → il limite in vigore resta sempre tra 100 e 9999
do $$ begin
  alter table public.system_settings disable trigger game_level_cap_check;
  update public.system_settings set value_int = 50 where key = 'game_level_cap';
  if public._game_level_cap() <> 100 then raise exception 'C11: 50 alterato doveva valere 100 (%)', public._game_level_cap(); end if;
  update public.system_settings set value_int = 20000 where key = 'game_level_cap';
  if public._game_level_cap() <> 9999 then raise exception 'C11: 20000 alterato doveva valere 9999'; end if;
  delete from public.system_settings where key = 'game_level_cap';
  if public._game_level_cap() <> 9999 then raise exception 'C11: riga mancante doveva valere 9999'; end if;
  insert into public.system_settings (key, value_int, description) values ('game_level_cap', 9999, 'Eroi: livello massimo raggiungibile (da 100 a 9999)');
  alter table public.system_settings enable trigger game_level_cap_check;
  insert into t_log (msg) values ('OK C11: riga mancante o alterata → il limite resta comunque tra 100 e 9999 (9999 se manca)');
end $$;

select msg as esito from t_log order by n;
rollback;
