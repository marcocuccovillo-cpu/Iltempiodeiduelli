-- =====================================================================
-- TEST DELLA MIGRAZIONE 024 (ricarica dell'energia solo per l'amministratore)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…024 (black-market-setup.sql … black-market-eroi-admin-energia.sql).
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
create function pg_temp.refill(n text) returns jsonb language plpgsql as $$ begin perform pg_temp.as_(n); return public.game_admin_refill_energy(); end $$;

do $$
declare n text; r jsonb;
begin
  perform pg_temp.mod(true);
  foreach n in array array['Admin','Org','Ann','Bob'] loop perform pg_temp.st(n); end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Bob'), 'moderator', 'moderatore di prova');
  update public.game_heroes set energy = 12, energy_at = now() where user_id in (pg_temp.uid('Admin'), pg_temp.uid('Org'), pg_temp.uid('Ann'), pg_temp.uid('Bob'));

  -- X1 — solo l'amministratore
  assert not has_function_privilege('anon', 'public.game_admin_refill_energy()', 'execute') and has_function_privilege('authenticated', 'public.game_admin_refill_energy()', 'execute'), 'X1: permessi della funzione';
  foreach n in array array['Bob','Org','Ann'] loop
    assert pg_temp.err_as(n, 'select public.game_admin_refill_energy()') like '%Permessi insufficienti%', 'X1: ' || n || ' non può';
    assert abs(pg_temp.en(n) - 12) < 0.5, 'X1: l''energia di ' || n || ' non cambia';
  end loop;
  assert (select role from public.profiles where id = pg_temp.uid('Bob')) = 'moderator', 'X1: Bob è davvero moderatore';
  assert pg_temp.err('select public.game_admin_refill_energy()') is not null, 'X1: serve il login';
  assert pg_temp.err_auth('Ann', 'select public.game_admin_refill_energy()') like '%Permessi insufficienti%', 'X1: nemmeno dal ruolo del browser';
  assert (select count(*) from public.audit_logs where action = 'admin_game_refill_energy') = 0, 'X1: i rifiuti non lasciano tracce';
  insert into t_log (msg) values ('OK X1 — moderatore, organizzatore e duellante rifiutati, energia invariata, nessuna traccia');

  -- X2 — l'amministratore si ricarica
  r := pg_temp.refill('Admin');
  assert (r->>'energy')::int = public._game_energy_max() and abs((r->>'before')::numeric - 12) < 0.5, 'X2: risposta';
  assert pg_temp.en('Admin') = public._game_energy_max(), 'X2: energia al 100%';
  assert (select count(*) from public.audit_logs where action = 'admin_game_refill_energy' and actor_id = pg_temp.uid('Admin')) = 1, 'X2: audit';
  assert abs(pg_temp.en('Org') - 12) < 0.5, 'X2: gli altri non sono toccati';
  r := pg_temp.refill('Admin'); assert (r->>'before')::numeric = public._game_energy_max(), 'X2: si può ripetere anche se già piena';
  -- amministratore sospeso
  update public.profiles set suspended = true where id = pg_temp.uid('Admin');
  assert pg_temp.err_as('Admin', 'select public.game_admin_refill_energy()') like '%sospeso%', 'X2: un amministratore sospeso non può';
  update public.profiles set suspended = false where id = pg_temp.uid('Admin');
  -- modulo spento
  perform pg_temp.mod(false);
  assert pg_temp.err_as('Admin', 'select public.game_admin_refill_energy()') = 'Modulo non attivo', 'X2: a modulo spento no';
  perform pg_temp.mod(true);
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'X2: saldi = registro';
  insert into t_log (msg) values ('OK X2 — l''amministratore si ricarica e finisce nell''audit; sospeso e modulo spento no; nessun BC toccato');
end $$;

select msg from t_log order by n;
rollback;
