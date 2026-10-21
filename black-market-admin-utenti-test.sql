-- =====================================================================
-- TEST DELLA MIGRAZIONE 012 (Email degli utenti nel pannello amministratore)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…012 (black-market-setup.sql … black-market-admin-utenti.sql).
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

-- Preparazione: Admin è il primo registrato; Org organizzatore; Mod moderatore; Marco ha «Accetto taglie» attivo, Luca no
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Mod','Marco','Luca'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Marco'); perform public.update_my_profile(null, true);
  perform pg_temp.as_('Admin');
  perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  perform public.admin_set_role(pg_temp.uid('Mod'), 'moderator', 'moderatore di test');
  insert into t_log (msg) values ('OK Preparazione: 5 utenti');
end $$;
-- A1 — struttura e permessi
do $$
begin
  assert has_function_privilege('authenticated', 'public.admin_user_overview()', 'execute') and not has_function_privilege('anon', 'public.admin_user_overview()', 'execute'), 'A1: solo utenti collegati (poi controlla il ruolo)';
  assert (select prosecdef from pg_proc where proname = 'admin_user_overview') and (select proconfig::text from pg_proc where proname = 'admin_user_overview') like '%search_path%', 'A1: security definer con search_path fisso';
  insert into t_log (msg) values ('OK A1 — funzione esposta ai soli utenti collegati, security definer con search_path fisso');
end $$;

-- A2 — l'amministratore vede email e opzione di ogni utente
do $$
declare r record;
begin
  perform pg_temp.as_('Admin');
  assert (select count(*) from public.admin_user_overview()) = 5, 'A2: una riga per ogni profilo';
  assert (select email from public.admin_user_overview() where id = pg_temp.uid('Luca')) = 'luca@test.local', 'A2: email corretta';
  assert (select email from public.admin_user_overview() where id = pg_temp.uid('Admin')) = 'admin@test.local', 'A2: email corretta (admin)';
  assert (select wanted_enabled from public.admin_user_overview() where id = pg_temp.uid('Marco')), 'A2: Marco accetta taglie';
  assert not (select wanted_enabled from public.admin_user_overview() where id = pg_temp.uid('Luca')), 'A2: Luca non accetta taglie';
  for r in select * from public.admin_user_overview() loop
    assert r.wanted_enabled = (select p.wanted_enabled from public.profiles p where p.id = r.id), 'A2: opzione = quella del profilo';
    assert r.email = (select u.email from auth.users u where u.id = r.id), 'A2: email = quella di Auth';
  end loop;
  insert into t_log (msg) values ('OK A2 — l''amministratore vede tutte le email e se ogni utente accetta taglie, coerenti con profili e Auth');
end $$;

-- A3 — chi non è amministratore non vede nulla
do $$
declare n text;
begin
  foreach n in array array['Org','Mod','Marco','Luca'] loop
    assert pg_temp.err_auth(n, 'select * from public.admin_user_overview()') is not null, 'A3: ' || n || ' non deve poterla usare';
  end loop;
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select * from public.admin_user_overview()') is not null, 'A3: senza accesso non funziona';
  insert into t_log (msg) values ('OK A3 — organizzatore, moderatore e duellanti ricevono un errore; senza login niente');
end $$;

-- A4 — un amministratore sospeso non può usarla
do $$
begin
  insert into auth.users (id, email, aud, role) values (pg_temp.uid('Adm2'), 'adm2@test.local', 'authenticated', 'authenticated');
  perform pg_temp.as_('Adm2'); perform public.register_profile('Adm2');
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Adm2'), 'admin', 'secondo admin di prova');
  perform pg_temp.as_('Adm2');
  assert (select count(*) from public.admin_user_overview()) = 6, 'A4: il secondo admin attivo la usa';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Adm2'), true, 'sospeso per prova');
  assert pg_temp.err_as('Adm2', 'select * from public.admin_user_overview()') is not null, 'A4: da sospeso non può';
  insert into t_log (msg) values ('OK A4 — un amministratore sospeso non può leggere le email');
end $$;

-- A5 — sola lettura: nessun dato è cambiato
do $$
declare b record;
begin
  select pg_temp.money() as m, (select count(*) from public.profiles) as np, (select count(*) from public.audit_logs) as na, (select md5(string_agg(id::text || wanted_enabled::text || role::text || suspended::text, ',' order by id)) from public.profiles) as pr into b;
  perform pg_temp.as_('Admin');
  perform * from public.admin_user_overview(); perform * from public.admin_user_overview();
  assert pg_temp.money() = b.m, 'A5: BC, wallet, registro, taglie invariati';
  assert (select count(*) from public.profiles) = b.np, 'A5: profili invariati (numero)';
  assert (select count(*) from public.audit_logs) = b.na, 'A5: nessuna scrittura nell''audit';
  assert (select md5(string_agg(id::text || wanted_enabled::text || role::text || suspended::text, ',' order by id)) from public.profiles) = b.pr, 'A5: profili invariati (contenuto)';
  insert into t_log (msg) values ('OK A5 — sola lettura: BC, registro, profili e audit identici a prima');
end $$;

select n, msg from t_log order by n;
rollback;
