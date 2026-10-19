-- =====================================================================
-- TEST DELLA MIGRAZIONE 007 (badge e traguardi)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…007 (black-market-setup.sql … black-market-badge.sql).
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
create function pg_temp.set_(k text, v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting(k, v, 'impostazione di prova'); end $$;
-- badge_progress("target") visto da "viewer": earned / valore / data / nascosto
create function pg_temp.be(viewer text, target text, c text) returns boolean language plpgsql as $$
declare r boolean; begin perform pg_temp.as_(viewer); select earned into r from public.badge_progress(pg_temp.uid(target)) where code = c; return r; end $$;
create function pg_temp.bval(viewer text, target text, c text) returns integer language plpgsql as $$
declare r integer; begin perform pg_temp.as_(viewer); select value into r from public.badge_progress(pg_temp.uid(target)) where code = c; return r; end $$;
create function pg_temp.bat(viewer text, target text, c text) returns timestamptz language plpgsql as $$
declare r timestamptz; begin perform pg_temp.as_(viewer); select earned_at into r from public.badge_progress(pg_temp.uid(target)) where code = c; return r; end $$;
create function pg_temp.bhid(viewer text, target text, c text) returns boolean language plpgsql as $$
declare r boolean; begin perform pg_temp.as_(viewer); select hidden into r from public.badge_progress(pg_temp.uid(target)) where code = c; return r; end $$;
create function pg_temp.bcount(viewer text, target text) returns integer language plpgsql as $$
declare r integer; begin perform pg_temp.as_(viewer); select count(*) into r from public.badge_progress(pg_temp.uid(target)) where earned; return r; end $$;
-- inserisce direttamente una partita di Ladder conclusa (solo per il test: volumi e date controllate)
create function pg_temp.lins(a text, b text, res text, at timestamptz, ea integer, eb integer, da integer) returns void language plpgsql as $$
begin
  insert into public.ladder_matches (challenger_id, opponent_id, format, client_request_id, status, expires_at, reported_result, reported_score, closed_at,
                                     elo_challenger_before, elo_opponent_before, elo_challenger_delta, elo_opponent_delta, created_at)
  values (pg_temp.uid(a), pg_temp.uid(b), 'Advanced', gen_random_uuid()::text, 'closed', at + interval '1 day', res,
          case res when 'challenger' then '2-0' when 'opponent' then '0-2' else '1-1' end, at, ea, eb, da, -da, at - interval '1 hour');
end $$;
create function pg_temp.money2() returns text language sql as $$
  select md5(coalesce((select string_agg(user_id || ':' || balance, ',' order by user_id) from public.wallets), '')
          || (select count(*)::text || coalesce(sum(amount), 0)::text from public.ledger_entries)
          || (select count(*)::text from public.bounties) || (select count(*)::text from public.bounty_settlements)
          || (select count(*)::text from public.matches) || (select count(*)::text from public.ladder_matches)) $$;

-- B1 — Catalogo e permessi
do $$
begin
  assert (select count(*) from public.badge_defs) = 48, 'B1: 48 traguardi nel catalogo';
  assert (select count(distinct family) from public.badge_defs) = 16, 'B1: 16 famiglie';
  assert not exists (select 1 from public.badge_defs d where d.tier < 5 and d.family not in ('taglie','riscosse','ricercato','bottino','ufficiali','serie','presenza','arena','elo','furia','caccia','giganti','rivincita')), 'B1: famiglie previste';
  assert (select count(*) from public.badge_defs where area = 'special') = 3, 'B1: 3 badge speciali';
  assert not exists (select 1 from public.badge_defs a join public.badge_defs b on a.family = b.family and a.tier < b.tier and a.threshold >= b.threshold and a.kind = b.kind), 'B1: le soglie crescono con il livello';
  assert not has_function_privilege('anon', 'public.badge_progress(uuid)', 'execute'), 'B1: anon non legge i badge';
  assert has_function_privilege('authenticated', 'public.badge_progress(uuid)', 'execute'), 'B1: gli iscritti leggono i badge';
  assert (select provolatile from pg_proc where proname = 'badge_progress') = 's', 'B1: la funzione è di sola lettura (stable)';
  assert pg_temp.err_auth('Marco', 'insert into public.badge_defs (code,family,area,tier,metric,kind,threshold,sort) values (''x'',''x'',''duel'',1,''duel_win'',''count'',1,1)') like '%permission denied%', 'B1: nessuna scrittura sul catalogo';
  assert pg_temp.err_auth('Marco', 'update public.badge_defs set threshold = 1') like '%permission denied%', 'B1: nessuna modifica al catalogo';
  assert pg_temp.err_auth('Marco', 'delete from public.badge_defs') like '%permission denied%', 'B1: nessuna cancellazione';
  assert pg_temp.rows_as('Marco', 'select * from public.badge_defs') = 48, 'B1: il catalogo è leggibile dagli iscritti';
  assert (select relrowsecurity from pg_class where oid = 'public.badge_defs'::regclass), 'B1: RLS attiva su badge_defs';
  perform set_config('request.jwt.claims', '{}', true);
  assert pg_temp.err('select * from public.badge_progress(null)') like '%Accesso richiesto%', 'B1: senza accesso non si legge nulla';
  assert pg_temp.err_as('Marco', 'select * from public.badge_progress(gen_random_uuid())') like '%non trovato%', 'B1: utente inesistente';
  insert into t_log (msg) values ('OK B1 — catalogo 48 traguardi (16 famiglie), soglie crescenti, sola lettura, RLS, anon escluso, utente inesistente rifiutato');
end $$;

-- B2 — Un nuovo iscritto ha solo "Iniziato"
do $$
begin
  assert pg_temp.bcount('Marco', 'Povero') = 1 and pg_temp.be('Marco', 'Povero', 'iniziato'), 'B2: Povero ha solo Iniziato';
  assert pg_temp.bat('Marco', 'Povero', 'iniziato') = (select created_at from public.profiles where id = pg_temp.uid('Povero')), 'B2: data = iscrizione';
  assert pg_temp.be('Povero', 'Povero', 'ufficiali_1') is false and pg_temp.bval('Povero', 'Povero', 'ufficiali_1') = 0, 'B2: nessuna vittoria = valore 0';
  assert pg_temp.bat('Povero', 'Povero', 'ufficiali_1') is null, 'B2: badge non ottenuto = nessuna data';
  assert pg_temp.be('Povero', 'Povero', 'custode') is false, 'B2: un duellante semplice non ha il badge staff';
  insert into t_log (msg) values ('OK B2 — nuovo iscritto: solo Iniziato (con data di iscrizione), tutto il resto a zero');
end $$;

-- B3 — Match ufficiali, serie, eventi: soglie e date
do $$
declare ev uuid; m uuid; i integer; t0 timestamptz := '2026-03-01 20:00+00';
begin
  -- Marco vince 5 match ufficiali di fila in 5 eventi, contro avversari diversi
  for i in 1..5 loop
    ev := pg_temp.ev('Torneo badge ' || i);
    m := pg_temp.mm(ev, 1, 'Marco', case i % 2 when 0 then 'Luca' else 'Paolo' end, 'Marco');
    update public.matches set verified_at = t0 + (i || ' days')::interval where id = m;
  end loop;
  assert pg_temp.bval('Marco', 'Marco', 'ufficiali_1') = 5 and pg_temp.be('Marco', 'Marco', 'ufficiali_1') and pg_temp.be('Marco', 'Marco', 'ufficiali_2'), 'B3: 5 vittorie = livelli 1 e 2';
  assert not pg_temp.be('Marco', 'Marco', 'ufficiali_3'), 'B3: 15 vittorie non raggiunte';
  assert pg_temp.bat('Marco', 'Marco', 'ufficiali_1') = t0 + interval '1 day' and pg_temp.bat('Marco', 'Marco', 'ufficiali_2') = t0 + interval '5 days', 'B3: la data è quella della vittoria che sblocca il livello';
  assert pg_temp.bval('Marco', 'Marco', 'serie_1') = 5 and pg_temp.be('Marco', 'Marco', 'serie_2') and not pg_temp.be('Marco', 'Marco', 'serie_3'), 'B3: serie di 5 vittorie';
  assert pg_temp.bat('Marco', 'Marco', 'serie_1') = t0 + interval '3 days' and pg_temp.bat('Marco', 'Marco', 'serie_2') = t0 + interval '5 days', 'B3: la serie si sblocca alla vittoria giusta';
  assert pg_temp.bval('Marco', 'Marco', 'presenza_1') = 5 and pg_temp.be('Marco', 'Marco', 'presenza_2') and not pg_temp.be('Marco', 'Marco', 'presenza_3'), 'B3: 5 eventi';
  -- una sconfitta spezza la serie ma non cancella il record; la serie nuova riparte da 1
  ev := pg_temp.ev('Torneo badge 6'); m := pg_temp.mm(ev, 1, 'Marco', 'Luca', 'Luca'); update public.matches set verified_at = t0 + interval '6 days' where id = m;
  ev := pg_temp.ev('Torneo badge 7'); m := pg_temp.mm(ev, 1, 'Marco', 'Luca', 'Marco'); update public.matches set verified_at = t0 + interval '7 days' where id = m;
  assert pg_temp.bval('Marco', 'Marco', 'ufficiali_1') = 6 and pg_temp.bval('Marco', 'Marco', 'serie_1') = 5, 'B3: la sconfitta non annulla il record di serie (5) e le vittorie sono 6';
  -- match non verificati e match altrui non contano
  ev := pg_temp.ev('Torneo badge 8'); perform pg_temp.mm(ev, 1, 'Marco', 'Paolo', null);
  assert pg_temp.bval('Marco', 'Marco', 'ufficiali_1') = 6, 'B3: un match non verificato non conta';
  assert pg_temp.bval('Paolo', 'Paolo', 'ufficiali_1') = 0 and pg_temp.bval('Luca', 'Luca', 'ufficiali_1') = 1, 'B3: contano solo le vittorie proprie (Luca ne ha 1)';
  -- un altro iscritto vede gli stessi valori
  assert pg_temp.bval('Luca', 'Marco', 'ufficiali_1') = 6 and pg_temp.be('Povero', 'Marco', 'ufficiali_2'), 'B3: i badge di Marco sono visibili agli altri iscritti';
  insert into t_log (msg) values ('OK B3 — vittorie, serie ed eventi: soglie corrette, date degli sblocchi, la sconfitta spezza la serie, match non verificati ignorati');
end $$;

-- B4 — Black Market: taglie lanciate, ricevute, riscosse, bottino; taglie annullate escluse
do $$
declare i integer; tg text; b uuid; ev uuid; m uuid; r jsonb;
begin
  -- Paolo lancia 5 taglie su 5 bersagli diversi (Luca 150), Povero 1 taglia da 100 su Luca
  perform pg_temp.as_('Paolo');
  perform public.create_bounty(pg_temp.uid('Luca'), 150, null, 'badge-b4-1');
  perform public.create_bounty(pg_temp.uid('Marco'), 50, null, 'badge-b4-2');
  perform public.create_bounty(pg_temp.uid('Povero'), 50, null, 'badge-b4-3');
  perform public.create_bounty(pg_temp.uid('Org'), 50, null, 'badge-b4-4');
  perform public.create_bounty(pg_temp.uid('Admin'), 50, null, 'badge-b4-5');
  perform pg_temp.as_('Povero'); perform public.create_bounty(pg_temp.uid('Luca'), 100, null, 'badge-b4-6');
  assert pg_temp.bval('Marco', 'Paolo', 'taglie_1') = 5 and pg_temp.be('Marco', 'Paolo', 'taglie_2') and not pg_temp.be('Marco', 'Paolo', 'taglie_3'), 'B4: Paolo ha lanciato 5 taglie';
  assert pg_temp.bval('Marco', 'Luca', 'ricercato_1') = 2 and pg_temp.be('Marco', 'Luca', 'ricercato_1') and not pg_temp.be('Marco', 'Luca', 'ricercato_2'), 'B4: Luca ha ricevuto 2 taglie';
  assert pg_temp.bval('Marco', 'Marco', 'ricercato_1') = 1, 'B4: Marco ha ricevuto 1 taglia';
  -- una taglia annullata dallo staff non conta, né per chi l''ha lanciata né per chi l''ha ricevuta
  b := (select id from public.bounties where client_request_id = 'badge-b4-5');
  perform pg_temp.as_('Admin'); perform public.admin_cancel_bounty(b, 'annullamento di prova');
  assert pg_temp.bval('Marco', 'Paolo', 'taglie_1') = 4 and pg_temp.bval('Marco', 'Admin', 'ricercato_1') = 0, 'B4: le taglie annullate non contano';
  -- Marco batte Luca in un match ufficiale e riscuote: payout 250 (150 + 100 di altri)
  ev := pg_temp.ev('Torneo badge taglie'); m := pg_temp.mm(ev, 1, 'Marco', 'Luca', 'Marco');
  perform pg_temp.as_('Marco'); r := public.claim_bounty(m);
  assert (r->>'payout')::int = 250, 'B4: payout 250';
  assert pg_temp.bval('Marco', 'Marco', 'riscosse_1') = 1 and pg_temp.be('Marco', 'Marco', 'riscosse_1') and not pg_temp.be('Marco', 'Marco', 'riscosse_2'), 'B4: una riscossione';
  assert pg_temp.bval('Marco', 'Marco', 'bottino_1') = 250 and pg_temp.be('Marco', 'Marco', 'bottino_1') and not pg_temp.be('Marco', 'Marco', 'bottino_2'), 'B4: bottino 250 = livello 1 (100) sì, livello 2 (300) no';
  assert pg_temp.bat('Marco', 'Marco', 'riscosse_1') = (select created_at from public.bounty_settlements where match_id = m), 'B4: data = riscossione';
  assert pg_temp.bval('Marco', 'Luca', 'riscosse_1') = 0, 'B4: chi perde non guadagna il badge';
  -- privacy: autori nascosti -> "taglie lanciate" visibile solo a sé stessi e allo staff
  perform pg_temp.set_('show_bounty_authors', 0);
  assert pg_temp.bhid('Luca', 'Paolo', 'taglie_1') is true and pg_temp.bval('Luca', 'Paolo', 'taglie_1') = 0 and not pg_temp.be('Luca', 'Paolo', 'taglie_1'), 'B4: autori nascosti: gli altri non vedono le taglie lanciate';
  assert pg_temp.bhid('Paolo', 'Paolo', 'taglie_1') is false and pg_temp.bval('Paolo', 'Paolo', 'taglie_1') = 4, 'B4: ... ma l''interessato sì';
  assert pg_temp.bhid('Admin', 'Paolo', 'taglie_1') is false and pg_temp.bval('Admin', 'Paolo', 'taglie_1') = 4, 'B4: ... e l''amministratore';
  assert pg_temp.bval('Luca', 'Luca', 'ricercato_1') = 2 and pg_temp.bval('Luca', 'Marco', 'riscosse_1') = 1, 'B4: ricevute e riscosse restano pubbliche (già pubbliche nel registro)';
  perform pg_temp.set_('show_bounty_authors', 1);
  assert pg_temp.bhid('Luca', 'Paolo', 'taglie_1') is false and pg_temp.bval('Luca', 'Paolo', 'taglie_1') = 4, 'B4: autori di nuovo visibili';
  insert into t_log (msg) values ('OK B4 — taglie lanciate/ricevute/riscosse/bottino corrette, annullate escluse, privacy sugli autori rispettata');
end $$;

-- B5 — Ladder: vittorie, Elo massimo, serie, avversari, giganti, rivincite, Doppia Anima
do $$
declare t0 timestamptz := '2026-04-01 18:00+00'; r jsonb;
begin
  -- modulo spento: i badge Ladder sono nascosti
  perform pg_temp.mod('ladder', false);
  assert pg_temp.bhid('Marco', 'Marco', 'arena_1') is true and pg_temp.bval('Marco', 'Marco', 'arena_1') = 0, 'B5: modulo Ladder spento: badge nascosti';
  perform pg_temp.mod('ladder', true);
  assert pg_temp.bhid('Marco', 'Marco', 'arena_1') is false and pg_temp.bval('Marco', 'Marco', 'arena_1') = 0, 'B5: modulo acceso: visibili, valore 0';
  assert not pg_temp.be('Marco', 'Marco', 'doppia'), 'B5: senza vittorie in Ladder niente Doppia Anima';
  -- una partita vera (Marco batte Luca): vale per vittorie, Elo e rivincita
  r := pg_temp.play('Marco', 'Luca', 'challenger', '2-0', 'Marco');
  assert pg_temp.be('Marco', 'Marco', 'arena_1') and pg_temp.bval('Marco', 'Marco', 'arena_1') = 1, 'B5: prima vittoria in Ladder';
  assert pg_temp.bval('Marco', 'Marco', 'elo_1') = 1016, 'B5: Elo massimo 1016 (partenza 1000, +16)';
  assert pg_temp.bval('Marco', 'Luca', 'arena_1') = 0 and pg_temp.bval('Marco', 'Luca', 'elo_1') = 1000, 'B5: lo sconfitto non ottiene vittorie; il suo massimo resta 1000';
  assert pg_temp.be('Marco', 'Marco', 'doppia'), 'B5: vittoria in Ladder + riscossione = Doppia Anima';
  assert pg_temp.bat('Marco', 'Marco', 'doppia') = greatest(
    (select min(closed_at) from public.ladder_matches where status = 'closed' and ((challenger_id = pg_temp.uid('Marco') and reported_result = 'challenger') or (opponent_id = pg_temp.uid('Marco') and reported_result = 'opponent'))),
    (select min(created_at) from public.bounty_settlements where winner_id = pg_temp.uid('Marco'))), 'B5: Doppia Anima con la data del secondo dei due traguardi';
  assert not pg_temp.be('Luca', 'Luca', 'doppia'), 'B5: Luca non ha Doppia Anima';
  -- storia con date controllate (inserimento diretto, solo nel test)
  perform pg_temp.lins('Marco', 'Paolo',  'challenger', t0 + interval '1 day', 1016, 1000, 16);
  perform pg_temp.lins('Marco', 'Povero', 'challenger', t0 + interval '2 days', 1032, 1000, 16);
  perform pg_temp.lins('Marco', 'Org',    'challenger', t0 + interval '3 days', 1048, 1000, 16);
  perform pg_temp.lins('Marco', 'Admin',  'challenger', t0 + interval '4 days', 1064, 1000, 16);
  perform pg_temp.lins('Luca',  'Marco',  'challenger', t0 + interval '5 days', 984, 1080, 16);   -- sconfitta di Marco
  perform pg_temp.lins('Marco', 'Luca',   'challenger', t0 + interval '6 days', 1064, 1000, 16);  -- rivincita
  perform pg_temp.lins('Marco', 'Paolo',  'challenger', t0 + interval '7 days', 1064, 1200, 24);  -- contro uno con 136 Elo in più
  perform pg_temp.lins('Marco', 'Povero', 'challenger', t0 + interval '8 days', 1190, 1000, 10);  -- Elo 1200
  perform pg_temp.lins('Marco', 'Admin',  'draw',       t0 + interval '9 days', 1200, 1000, -8);  -- pareggio: spezza la serie
  assert pg_temp.bval('Marco', 'Marco', 'arena_1') = 8 and pg_temp.be('Marco', 'Marco', 'arena_2') is false, 'B5: 8 vittorie in Ladder, il pareggio non conta';
  assert pg_temp.bat('Marco', 'Marco', 'arena_1') = t0 + interval '1 day', 'B5: data della prima vittoria';
  assert pg_temp.bval('Marco', 'Marco', 'furia_1') = 4 and pg_temp.be('Marco', 'Marco', 'furia_1') and not pg_temp.be('Marco', 'Marco', 'furia_2'), 'B5: serie massima 4 (sconfitta e pareggio la spezzano)';
  assert pg_temp.bat('Marco', 'Marco', 'furia_1') = t0 + interval '3 days', 'B5: la serie di 3 si sblocca alla terza vittoria';
  assert pg_temp.bval('Marco', 'Marco', 'elo_1') = 1200 and pg_temp.be('Marco', 'Marco', 'elo_2') and not pg_temp.be('Marco', 'Marco', 'elo_3'), 'B5: Elo massimo 1200';
  assert pg_temp.bat('Marco', 'Marco', 'elo_2') = t0 + interval '8 days', 'B5: data del primo Elo >= 1200';
  assert pg_temp.bval('Marco', 'Marco', 'caccia_1') = 5 and pg_temp.be('Marco', 'Marco', 'caccia_1') and not pg_temp.be('Marco', 'Marco', 'caccia_2'), 'B5: 5 avversari diversi battuti (Luca due volte conta una)';
  assert pg_temp.bval('Marco', 'Marco', 'giganti_1') = 1 and pg_temp.be('Marco', 'Marco', 'giganti_1') and not pg_temp.be('Marco', 'Marco', 'giganti_2'), 'B5: una vittoria contro chi aveva 100+ Elo più di lui';
  assert pg_temp.bat('Marco', 'Marco', 'giganti_1') = t0 + interval '7 days', 'B5: data dell''impresa';
  assert pg_temp.bval('Marco', 'Marco', 'rivincita_1') = 2 and pg_temp.be('Marco', 'Marco', 'rivincita_1') and not pg_temp.be('Marco', 'Marco', 'rivincita_2'), 'B5: due rivincite su Luca (6° giorno e partita vera)';
  assert pg_temp.bat('Marco', 'Marco', 'rivincita_1') = t0 + interval '6 days', 'B5: la prima rivincita viene DOPO la sconfitta';
  -- Luca: una vittoria (quella sul 5° giorno), nessuna rivincita
  assert pg_temp.bval('Luca', 'Luca', 'arena_1') = 1 and pg_temp.bval('Luca', 'Luca', 'rivincita_1') = 0 and pg_temp.bval('Luca', 'Luca', 'giganti_1') = 0, 'B5: Luca ha battuto uno con 96 Elo in più: sotto la soglia di 100, nessun Ammazzagiganti';
  insert into t_log (msg) values ('OK B5 — Ladder: vittorie, Elo massimo, serie (sconfitta e pareggio la spezzano), avversari distinti, giganti, rivincite, Doppia Anima, date degli sblocchi');
end $$;

-- B6 — Badge speciali, modulo spento, nessun effetto sull'economia
do $$
declare m0 text; lg0 bigint; a0 timestamptz;
begin
  -- Custode: solo ruoli di staff (admin, moderatore, organizzatore)
  assert pg_temp.be('Marco', 'Org', 'custode') and pg_temp.be('Marco', 'Admin', 'custode'), 'B6: organizzatore e amministratore hanno Custode';
  assert not pg_temp.be('Marco', 'Marco', 'custode') and not pg_temp.be('Marco', 'Povero', 'custode'), 'B6: i duellanti no';
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Povero'), 'moderator', 'moderatore di prova');
  assert pg_temp.be('Marco', 'Povero', 'custode'), 'B6: il moderatore ha Custode';
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Povero'), 'user', 'ripristino');
  assert not pg_temp.be('Marco', 'Povero', 'custode'), 'B6: tolto il ruolo, il badge sparisce (è derivato dal ruolo attuale)';
  -- modulo Ladder spento: i badge Ladder spariscono ma i dati restano; riacceso ricompaiono identici
  m0 := pg_temp.money2(); lg0 := (select count(*) from public.ladder_matches);
  a0 := pg_temp.bat('Marco', 'Marco', 'elo_2');
  perform pg_temp.mod('ladder', false);
  assert pg_temp.bhid('Marco', 'Marco', 'elo_2') is true and not pg_temp.be('Marco', 'Marco', 'elo_2') and pg_temp.bat('Marco', 'Marco', 'elo_2') is null, 'B6: modulo spento: badge Ladder nascosti';
  assert not pg_temp.be('Marco', 'Marco', 'doppia'), 'B6: modulo spento: niente Doppia Anima';
  assert pg_temp.be('Marco', 'Marco', 'ufficiali_2') and pg_temp.be('Marco', 'Marco', 'riscosse_1'), 'B6: i badge dei match ufficiali e delle taglie restano';
  assert (select count(*) from public.ladder_matches) = lg0, 'B6: nessuna partita di Ladder toccata';
  perform pg_temp.mod('ladder', true);
  assert pg_temp.be('Marco', 'Marco', 'elo_2') and pg_temp.bat('Marco', 'Marco', 'elo_2') = a0 and pg_temp.be('Marco', 'Marco', 'doppia'), 'B6: modulo riacceso: tutto identico';
  -- leggere i badge non muove nulla (BC, registro, taglie, match, Ladder)
  assert pg_temp.money2() = m0, 'B6: nessun effetto su saldi, registro, taglie, match e Ladder';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'B6: saldi ancora riconciliati con il registro';
  insert into t_log (msg) values ('OK B6 — Custode derivato dal ruolo, modulo Ladder spento/acceso senza perdite, lettura dei badge senza effetti sull''economia, saldi riconciliati');
end $$;

-- B7 — Sicurezza e coerenza
do $$
begin
  assert (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) = 0, 'B7: RLS su tutte le tabelle';
  assert (select prosecdef from pg_proc where proname = 'badge_progress') and (select proconfig::text from pg_proc where proname = 'badge_progress') like '%search_path=public%', 'B7: security definer con search_path fisso';
  assert not exists (select 1 from information_schema.table_privileges where table_name = 'badge_defs' and grantee in ('anon','authenticated') and privilege_type <> 'SELECT'), 'B7: solo SELECT sul catalogo';
  assert not exists (select 1 from information_schema.table_privileges where table_name = 'badge_defs' and grantee = 'anon'), 'B7: anon non legge il catalogo';
  assert (select count(distinct code) from public.badge_progress(pg_temp.uid('Marco'))) = 48, 'B7: ogni utente riceve tutti i 48 traguardi';
  assert (select count(*) from public.badge_progress(pg_temp.uid('Marco')) where earned and earned_at is null) = 0, 'B7: ogni badge ottenuto ha una data';
  assert (select count(*) from public.badge_progress(pg_temp.uid('Marco')) where not earned and earned_at is not null) = 0, 'B7: nessuna data sui badge non ottenuti';
  insert into t_log (msg) values ('OK B7 — RLS ovunque, funzione security definer con search_path fisso, catalogo in sola lettura, coerenza earned/data');
end $$;

select n, msg from t_log order by n;
rollback;
