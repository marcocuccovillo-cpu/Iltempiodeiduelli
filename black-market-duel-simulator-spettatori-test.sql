-- =====================================================================
-- TEST DI «SPETTATORI» del Duel Simulator (black-market-duel-simulator-spettatori.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-duel-simulator.sql, ...-chat.sql, ...-catene.sql, ...-attacchi.sql e ...-spettatori.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- Se un controllo fallisce compare un errore con il nome dello scenario.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create temp table t_ctx (k text primary key, v text);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-duel-' || n)::uuid $$;
create function pg_temp.act(u uuid) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_(n text) returns text language sql as $$ select pg_temp.act(pg_temp.uid(n)) $$;
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
-- chiama una espressione come utente n e restituisce il risultato come jsonb
create function pg_temp.x(n text, expr text) returns jsonb language plpgsql as $$
declare r jsonb;
begin perform pg_temp.as_(n); execute 'select to_jsonb(' || expr || ')' into r; return r; end $$;
create function pg_temp.s(n text, l bigint) returns jsonb language sql as $$ select pg_temp.x(n, 'public.sim_state(' || l || ')') $$;

create function pg_temp.snap() returns text language sql as $$
  select md5(
    coalesce((select string_agg(w::text, ',' order by user_id) from public.wallets w), '') || '|' ||
    coalesce((select string_agg(e::text, ',' order by id) from public.ledger_entries e), '') || '|' ||
    coalesce((select string_agg(c::text, ',' order by id) from public.sim_cards c), '') || '|' ||
    coalesce((select string_agg(c::text, ',' order by game_id, n) from public.sim_log c), '') || '|' ||
    coalesce((select string_agg((g.id, g.turn_seat, g.phase, g.lp_1, g.lp_2, g.status)::text, ',' order by g.id) from public.sim_games g), '')) $$;
-- deck di prova: Main da 'nm' carte con codici base+1…, Extra 3 carte (base+501…), Side 2 carte (base+801…)
create function pg_temp.mkdeck(n text, nm text, base integer, nmain integer default 40) returns uuid language plpgsql as $$
declare r jsonb;
begin
  return (pg_temp.x(n, format('public.sim_deck_save(null, %L, (select array_agg(%s + k) from generate_series(1, %s) k), array[%s+501,%s+502,%s+503], array[%s+801,%s+802], false)',
          nm, base, nmain, base, base, base, base, base))#>>'{}')::uuid;
end $$;
create function pg_temp.gid(l bigint) returns bigint language sql as $$ select g.id from public.sim_games g join public.sim_lobbies b on b.id = l and g.lobby_id = b.id and g.no = b.game_no $$;
create function pg_temp.cid(l bigint, code integer) returns integer language sql as $$ select id from public.sim_cards where game_id = pg_temp.gid(l) and sim_cards.code = $2 $$;
create function pg_temp.zone_of(l bigint, code integer) returns text language sql as $$ select zone from public.sim_cards where game_id = pg_temp.gid(l) and sim_cards.code = $2 $$;
create function pg_temp.pcards(st jsonb, z text) returns jsonb language sql as $$ select coalesce(jsonb_agg(c), '[]') from jsonb_array_elements(st->'cards') c where c->>'z' = z $$;
create function pg_temp.logk(l bigint, k text) returns jsonb language sql as $$
  select coalesce(jsonb_agg(data order by n), '[]') from public.sim_log where game_id = pg_temp.gid(l) and kind = k $$;
create function pg_temp.mv(n text, l bigint, code integer, zone text, extra text default '') returns jsonb language plpgsql as $$
begin return pg_temp.x(n, format('public.sim_move(%s, %s, %L%s)', l, pg_temp.cid(l, code), zone, extra)); end $$;

-- nuovo incontro già avviato: Ann (posto 1) e Bob (posto 2), Ann gioca per prima
create function pg_temp.newmatch() returns bigint language plpgsql as $$
declare l bigint; s jsonb; ch text;
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(''Prova'')'))#>>'{}';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  perform pg_temp.x('Ann', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA')));
  perform pg_temp.x('Bob', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckB')));
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)');
  perform pg_temp.x('Bob', 'public.sim_set_ready(' || l || ', true)');
  s := pg_temp.x('Ann', 'public.sim_start(' || l || ')');
  ch := case when (s#>>'{game,chooser}')::int = 1 then 'Ann' else 'Bob' end;
  perform pg_temp.x(ch, 'public.sim_choose_first(' || l || ', 1::smallint)');
  return l;
end $$;
create function pg_temp.endmatch(l bigint) returns void language plpgsql as $$
begin
  if (select status from public.sim_lobbies where id = l) not in ('finished', 'cancelled') then perform pg_temp.x('Ann', 'public.sim_lobby_leave(' || l || ')'); end if;
  update public.sim_players set active = false where lobby_id = l;
end $$;
create function pg_temp.lpset(n text, l bigint, seat integer, val integer) returns jsonb language sql as $$ select pg_temp.x(n, format('public.sim_lp(%s, %s::smallint, null, %s)', l, seat, val)) $$;

-- Preparazione
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Ann','Bob','Cid','Dan','Mod'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di prova');
  perform public.admin_set_role(pg_temp.uid('Mod'), 'moderator', 'moderatore di prova');
  insert into t_log (msg) values ('OK Preparazione: 7 utenti');
end $$;


-- decks e incontro di partenza
do $$
begin
  perform pg_temp.as_('Ann');
  insert into t_ctx values ('deckA', pg_temp.mkdeck('Ann', 'MazzoA', 10000)::text), ('deckB', pg_temp.mkdeck('Bob', 'MazzoB', 20000)::text);
  insert into t_log (msg) values ('OK Deck di prova');
end $$;


-- aiuti specifici degli spettatori
create function pg_temp.ids(l bigint, o integer, z text) returns integer[] language sql as $$
  select coalesce(array_agg(id order by ord), '{}') from public.sim_cards where game_id = pg_temp.gid(l) and owner = o and zone = z $$;
-- codici che un osservatore NEUTRO non deve vedere (carte non pubbliche)
create function pg_temp.hidden(l bigint) returns integer[] language sql as $$
  select coalesce(array_agg(code), '{}') from public.sim_cards where game_id = pg_temp.gid(l) and not public._sim_pub(zone, face_up, revealed) $$;
-- quali dei codici indicati compaiono (come numero intero) nel JSON
create function pg_temp.leak(st jsonb, codes integer[]) returns integer[] language sql as $$
  select coalesce(array_agg(c order by c), '{}') from unnest(codes) c where st::text ~ ('[^0-9]' || c || '[^0-9]') $$;
-- codici che con le maschere m1 (posto 1) e m2 (posto 2) devono essere visibili, calcolati in modo indipendente dal database
create function pg_temp.expected(l bigint, m1 integer, m2 integer) returns integer[] language sql as $$
  select coalesce(array_agg(code order by code), '{}') from public.sim_cards c where c.game_id = pg_temp.gid(l) and c.zone <> 'deck' and (
       public._sim_pub(c.zone, c.face_up, c.revealed)
    or (c.zone = 'hand'  and ((case when c.owner = 1 then m1 else m2 end) & 1) = 1)
    or (c.zone = 'extra' and ((case when c.owner = 1 then m1 else m2 end) & 4) = 4)
    or (c.zone in ('mz','emz','st','fz') and ((case when c.ctrl = 1 then m1 else m2 end) & 2) = 2)
    or (c.zone in ('gy','banish','ovl') and ((case when c.owner = 1 then m1 else m2 end) & 2) = 2)) $$;
create function pg_temp.xs(st jsonb) returns integer[] language sql as $$
  select coalesce(array_agg((c->>'x')::int order by (c->>'x')::int), '{}') from jsonb_array_elements(st->'cards') c where c->>'x' is not null $$;
create function pg_temp.grant_(n text, l bigint, spec text, m integer) returns jsonb language sql as $$
  select pg_temp.x(n, format('public.sim_spec_grant(%s, %s, %s)', l, case when spec is null then 'null' else quote_literal(pg_temp.uid(spec)::text) || '::uuid' end, m)) $$;
create function pg_temp.watch(n text, l bigint) returns jsonb language sql as $$ select pg_temp.x(n, 'public.sim_watch_join(' || l || ')') $$;

create function pg_temp.eco() returns text language sql as $$
  select md5(coalesce((select string_agg(w::text, ',' order by user_id) from public.wallets w), '') || '|' ||
             coalesce((select string_agg(e::text, ',' order by id) from public.ledger_entries e), '') || '|' ||
             coalesce((select string_agg(b::text, ',' order by id) from public.bounties b), '')) $$;
insert into t_ctx values ('eco', pg_temp.eco());

-- =====================================================================
-- T1 — permessi, tabelle chiuse
-- =====================================================================
do $$
begin
  assert pg_temp.err_auth('Ann', 'select * from public.sim_spectators') like '%permission denied%', 'T1: sim_spectators non leggibile';
  assert pg_temp.err_auth('Ann', 'select * from public.sim_spec_grants') like '%permission denied%', 'T1: sim_spec_grants non leggibile';
  assert pg_temp.err_auth('Ann', 'select * from public.sim_spec_bans') like '%permission denied%', 'T1: sim_spec_bans non leggibile';
  assert pg_temp.err_auth('Ann', 'insert into public.sim_spectators (lobby_id, user_id) values (1, gen_random_uuid())') like '%permission denied%', 'T1: sim_spectators non scrivibile';
  assert pg_temp.err_auth('Ann', 'insert into public.sim_spec_grants (lobby_id, seat, user_id, mask) values (1, 1, gen_random_uuid(), 7)') like '%permission denied%', 'T1: sim_spec_grants non scrivibile';
  assert pg_temp.err_auth('Ann', 'update public.sim_players set spec_all = 7') like '%permission denied%', 'T1: spec_all non modificabile dal browser';
  assert pg_temp.err_auth('Ann', 'update public.sim_lobbies set allow_spec = true') like '%permission denied%', 'T1: allow_spec non modificabile dal browser';
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.sim_watch_join(1)') like '%Accesso richiesto%', 'T1: entrare senza accesso rifiutato';
  assert pg_temp.err('select public.sim_watch_say(1, ''x'')') like '%Accesso richiesto%', 'T1: scrivere senza accesso rifiutato';
  assert pg_temp.err('select public.sim_watch_leave(1)') like '%Accesso richiesto%', 'T1: uscire senza accesso rifiutato';
  assert pg_temp.err('select public.sim_spec_grant(1, null, 7)') like '%Accesso richiesto%', 'T1: permesso senza accesso rifiutato';
  assert pg_temp.err('select public.sim_spec_kick(1, gen_random_uuid())') like '%Accesso richiesto%', 'T1: espulsione senza accesso rifiutata';
  assert pg_temp.err('select public.sim_spec_open(1, false)') like '%Accesso richiesto%', 'T1: chiusura senza accesso rifiutata';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_watch_join','sim_watch_leave','sim_watch_say','sim_spec_grant','sim_spec_kick','sim_spec_open','_sim_mask','_sim_vis_m','_sim_bump_ver','_sim_spec_clear') and grantee in ('anon','PUBLIC')) = 0, 'T1: nessun permesso ad anon/public';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_watch_join','sim_watch_leave','sim_watch_say','sim_spec_grant','sim_spec_kick','sim_spec_open') and grantee = 'authenticated') = 6, 'T1: sei funzioni a authenticated';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('_sim_mask','_sim_vis_m','_sim_bump_ver','_sim_spec_clear') and grantee = 'authenticated') = 0, 'T1: le funzioni interne non sono chiamabili dal browser';
  assert pg_temp.err_auth('Ann', 'select public._sim_mask(1, gen_random_uuid(), 1::smallint)') like '%permission denied%', 'T1: _sim_mask non chiamabile dal browser';
  assert pg_temp.err_auth('Ann', 'select public._sim_state(1, gen_random_uuid())') like '%permission denied%', 'T1: _sim_state resta chiusa';
  insert into t_log (msg) values ('OK T1 permessi e tabelle chiuse');
end $$;

-- =====================================================================
-- T2 — regole di ingresso
-- =====================================================================
do $$
declare l bigint; l2 bigint; s jsonb;
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(''Prova'')'))#>>'{}';
  assert pg_temp.err_as('Cid', format('select public.sim_watch_join(%s)', l)) = 'Si può guardare solo una partita in corso', 'T2: una lobby non avviata non si guarda';
  assert pg_temp.err_as('Cid', 'select public.sim_watch_join(999999)') = 'Lobby inesistente', 'T2: lobby inesistente';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  perform pg_temp.x('Ann', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA')));
  perform pg_temp.x('Bob', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckB')));
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)');
  perform pg_temp.x('Bob', 'public.sim_set_ready(' || l || ', true)');
  assert pg_temp.err_as('Cid', format('select public.sim_watch_join(%s)', l)) = 'Si può guardare solo una partita in corso', 'T2: lobby piena ma non avviata non si guarda';
  perform pg_temp.x('Ann', 'public.sim_start(' || l || ')');
  s := pg_temp.watch('Cid', l);               -- in fase di scelta di chi inizia
  assert (s#>>'{me,spec}')::boolean and s#>>'{me,seat}' is null, 'T2: lo spettatore entra a partita avviata';
  assert pg_temp.watch('Cid', l) is not null, 'T2: rientrare è innocuo';
  assert (select count(*) from public.sim_spectators where lobby_id = l) = 1, 'T2: rientrare non duplica';
  assert pg_temp.err_as('Ann', format('select public.sim_watch_join(%s)', l)) like 'Stai giocando%', 'T2: un giocatore non guarda';
  assert pg_temp.err_as('Bob', format('select public.sim_watch_join(%s)', l)) like 'Stai giocando%', 'T2: nemmeno l’altro giocatore';
  -- un giocatore uscito (inattivo) della stessa partita non rientra come spettatore
  update public.sim_players set active = false where lobby_id = l and seat = 2;
  assert pg_temp.err_as('Bob', format('select public.sim_watch_join(%s)', l)) = 'Sei uno dei giocatori di questa partita', 'T2: un ex giocatore non guarda la propria partita';
  update public.sim_players set active = true where lobby_id = l and seat = 2;
  -- chi gioca altrove non guarda
  perform pg_temp.endmatch(l);
  l2 := (pg_temp.x('Dan', 'public.sim_lobby_create(''Altra'')'))#>>'{}';
  assert pg_temp.err_as('Dan', format('select public.sim_watch_join(%s)', l2)) like 'Stai giocando%', 'T2: chi è in lobby non guarda';
  perform pg_temp.x('Dan', 'public.sim_lobby_leave(' || l2 || ')');
  -- partita finita: non si entra
  assert (select status from public.sim_lobbies where id = l) = 'finished', 'T2: partita finita';
  assert pg_temp.err_as('Dan', format('select public.sim_watch_join(%s)', l)) = 'Si può guardare solo una partita in corso', 'T2: una partita finita non si guarda';
  assert (select count(*) from public.sim_spectators where lobby_id = l) = 1, 'T2: Cid era dentro e resta nell’elenco finché non esce';
  perform pg_temp.x('Cid', 'public.sim_watch_leave(' || l || ')');
  assert (select count(*) from public.sim_spectators where lobby_id = l) = 0, 'T2: uscita';
  perform pg_temp.x('Cid', 'public.sim_watch_leave(' || l || ')');    -- uscire due volte è innocuo
  insert into t_log (msg) values ('OK T2 regole di ingresso');
end $$;

-- =====================================================================
-- T3 — scenario: tavolo con carte in tutte le zone (resta aperto per i test seguenti)
-- =====================================================================
do $$
declare l bigint; h integer[]; bh integer[];
begin
  l := pg_temp.newmatch();
  h := pg_temp.ids(l, 1, 'hand'); bh := pg_temp.ids(l, 2, 'hand');
  assert cardinality(h) = 5 and cardinality(bh) = 5, 'T3: 5 carte in mano';
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, h[1]));
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''def'', false)', l, h[2]));
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''st'', null, null, false)', l, h[3]));
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''banish'', null, null, false)', l, h[4]));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, bh[1]));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''def'', false)', l, bh[2]));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''gy'')', l, bh[3]));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''st'', null, null, false)', l, bh[4]));
  insert into t_ctx values ('L', l::text);
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and zone = 'mz' and not face_up) = 2, 'T3: due mostri coperti';
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and zone = 'banish' and not face_up) = 1, 'T3: una carta rimossa coperta';
  assert cardinality(pg_temp.hidden(l)) > 80, 'T3: molte carte nascoste (deck, extra, mani, coperte)';
  insert into t_log (msg) values ('OK T3 scenario');
end $$;

-- =====================================================================
-- T4 — senza permessi lo spettatore vede SOLO il tavolo pubblico
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; s jsonb; sb jsonb; sa jsonb; hid integer[] := pg_temp.hidden(l);
begin
  s := pg_temp.watch('Cid', l);
  assert pg_temp.leak(s, hid) = '{}', 'T4: nessun codice di carta nascosta nell’intero stato (mano, deck, extra, coperte): ' || pg_temp.leak(s, hid)::text;
  assert s->'deckv' = '{}'::jsonb, 'T4: nessun ordine di deck';
  assert s#>'{me,mk}' = '[0,0]'::jsonb, 'T4: nessun permesso';
  assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand') = 0, 'T4: nessuna carta in mano nel JSON';
  assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'extra') = 0, 'T4: nessun extra coperto nel JSON';
  assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'deck') = 0, 'T4: nessuna carta del deck nel JSON';
  assert s#>>'{counts,1,hand}' = '1' and s#>>'{counts,2,hand}' = '1', 'T4: i contatori pubblici ci sono (1 carta in mano a testa)';
  assert (s#>>'{counts,1,deck}')::int = 35 and (s#>>'{counts,2,deck}')::int = 35, 'T4: contatori deck';
  -- i mostri coperti ci sono ma senza il nome
  assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'mz' and (c->>'f')::boolean = false and c->>'x' is null) = 2, 'T4: due mostri coperti senza nome';
  assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'st' and (c->>'f')::boolean = false and c->>'x' is null) = 2, 'T4: due magie coperte senza nome';
  assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'banish' and c->>'x' is null) = 1, 'T4: carta rimossa coperta senza nome';
  assert pg_temp.xs(s) = pg_temp.expected(l, 0, 0), 'T4: i nomi visibili sono esattamente quelli pubblici';
  -- stessa informazione che ha un giocatore sulle carte dell’altro: lo spettatore vede come l’avversario
  sb := pg_temp.s('Bob', l); sa := pg_temp.s('Ann', l);
  assert (select jsonb_agg(jsonb_build_object('i', c->'i', 'x', c->'x') order by (c->>'i')::int) from jsonb_array_elements(s->'cards') c where (c->>'o')::int = 1)
       = (select jsonb_agg(jsonb_build_object('i', c->'i', 'x', c->'x') order by (c->>'i')::int) from jsonb_array_elements(sb->'cards') c where (c->>'o')::int = 1), 'T4: le carte di Ann le vede come le vede Bob';
  assert (select jsonb_agg(jsonb_build_object('i', c->'i', 'x', c->'x') order by (c->>'i')::int) from jsonb_array_elements(s->'cards') c where (c->>'o')::int = 2)
       = (select jsonb_agg(jsonb_build_object('i', c->'i', 'x', c->'x') order by (c->>'i')::int) from jsonb_array_elements(sa->'cards') c where (c->>'o')::int = 2), 'T4: le carte di Bob le vede come le vede Ann';
  assert s->'log' = sa->'log' and s->'players' is not null and s->'game' = sa->'game' and s->'chain' = sa->'chain' and s->'targets' = sa->'targets', 'T4: registro, partita, catena e bersagli come i giocatori';
  assert s#>'{players,0}' ? 'deck_id' and s#>'{players,0,deck_id}' = 'null'::jsonb and s#>'{players,1,deck_id}' = 'null'::jsonb and s#>'{players,0,deck_name}' = 'null'::jsonb, 'T4: nome e id dei deck dei giocatori non arrivano';
  assert s#>'{me,cfg}' = 'null'::jsonb, 'T4: nessuna configurazione del side deck';
  -- un giocatore NON riceve nulla in più di prima
  assert (select count(*) from jsonb_array_elements(sa->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1) = 1, 'T4: Ann vede la propria mano';
  assert (select count(*) from jsonb_array_elements(sa->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 2) = 0, 'T4: Ann non vede la mano di Bob';
  assert sa#>>'{me,spec}' = 'false' and sa#>'{me,mk}' = 'null'::jsonb, 'T4: per i giocatori me.spec è falso';
  assert sa->'deckv' = '{}'::jsonb and sb->'deckv' = '{}'::jsonb, 'T4: i giocatori non ricevono l’ordine del deck';
  assert (select count(*) from jsonb_array_elements(sa->'cards') c where c->>'z' = 'extra' and (c->>'o')::int = 1 and c->>'x' is not null) = 3 and (select count(*) from jsonb_array_elements(sa->'cards') c where c->>'z' = 'extra' and (c->>'o')::int = 2) = 0, 'T4: Ann vede il proprio extra e non quello di Bob';
  insert into t_log (msg) values ('OK T4 vista neutrale e riservatezza');
end $$;

-- =====================================================================
-- T5 — nessuna azione di gioco per gli spettatori
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; before_ text := pg_temp.snap(); h integer[] := pg_temp.ids(l, 1, 'hand'); q text; e text;
begin
  foreach q in array array[
    'public.sim_draw(%s, 1)', 'public.sim_move(%s, %s, ''gy'')', 'public.sim_set(%s, %s, ''mz'', true)', 'public.sim_counter(%s, %s, 1)',
    'public.sim_token(%s, ''mz'', null, ''atk'')', 'public.sim_reveal(%s, %s, true)', 'public.sim_shuffle(%s)', 'public.sim_search(%s)', 'public.sim_peek(%s, 3)',
    'public.sim_top(%s, 1, ''gy'', true)', 'public.sim_lp(%s, 1::smallint, 100, null)', 'public.sim_phase(%s, ''main1'')', 'public.sim_end_turn(%s)',
    'public.sim_coin(%s, 1)', 'public.sim_dice(%s, 1)', 'public.sim_say(%s, ''ciao'')', 'public.sim_concede(%s)', 'public.sim_chat_send(%s, ''ciao'')',
    'public.sim_signal(%s, ''ok'')', 'public.sim_lobby_leave(%s)', 'public.sim_lobby_kick(%s)', 'public.sim_propose(%s, ''draw'', null)', 'public.sim_respond(%s, true)',
    'public.sim_confirm_end(%s)', 'public.sim_attack(%s, %s, null)', 'public.sim_target(%s, %s)', 'public.sim_target_clear(%s)', 'public.sim_spec_open(%s, false)',
    'public.sim_set_ready(%s, true)', 'public.sim_start(%s)', 'public.sim_reorder(%s, array[%s])'] loop
    e := pg_temp.err_as('Cid', 'select ' || case when q like '%%s, %%s%%' or q like '%s, %s%' then format(q, l, h[1]) else format(q, l) end);
    assert e = 'Non partecipi a questa partita', 'T5: lo spettatore non può eseguire ' || q || ' (ricevuto: ' || coalesce(e, 'NESSUN ERRORE') || ')';
  end loop;
  assert pg_temp.err_as('Cid', format('select public.sim_spec_grant(%s, null, 7)', l)) = 'Non partecipi a questa partita', 'T5: lo spettatore non si dà permessi da solo';
  assert pg_temp.err_as('Cid', format('select public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Dan'))) = 'Non partecipi a questa partita', 'T5: lo spettatore non caccia nessuno';
  assert pg_temp.snap() = before_, 'T5: nessuna carta, registro o punto vita è cambiato';
  assert (select count(*) from public.sim_spec_grants) = 0, 'T5: nessun permesso concesso';
  insert into t_log (msg) values ('OK T5 gli spettatori non giocano');
end $$;

-- =====================================================================
-- T6 — tutte le combinazioni di permessi (64): ciò che arriva = ciò che è consentito, niente di più
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; m1 integer; m2 integer; s jsonb; allc integer[]; exp_ integer[]; hid integer[]; deck1 integer[]; deck2 integer[]; bad integer[];
begin
  select array_agg(code) into allc from public.sim_cards where game_id = pg_temp.gid(l);
  select array_agg(code order by ord desc, id) into deck1 from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck';
  select array_agg(code order by ord desc, id) into deck2 from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'deck';
  for m1 in 0..7 loop for m2 in 0..7 loop
    perform pg_temp.grant_('Ann', l, 'Cid', m1);
    perform pg_temp.grant_('Bob', l, 'Cid', m2);
    s := pg_temp.s('Cid', l);
    assert s#>'{me,mk}' = jsonb_build_array(m1, m2), format('T6: maschera %s/%s', m1, m2);
    exp_ := pg_temp.expected(l, m1, m2);
    assert pg_temp.xs(s) = exp_, format('T6: %s/%s nomi visibili diversi dal previsto', m1, m2);
    -- ogni codice che NON è nell’elenco previsto e NON è un deck concesso non deve comparire da nessuna parte
    bad := pg_temp.leak(s, (select coalesce(array_agg(c), '{}') from unnest(allc) c where c <> all (exp_)
              and not (c = any (case when (m1 & 4) = 4 then deck1 else '{}'::integer[] end) ) and not (c = any (case when (m2 & 4) = 4 then deck2 else '{}'::integer[] end))));
    assert bad = '{}', format('T6: %s/%s fuga di codici %s', m1, m2, bad::text);
    -- deck: arriva solo se concesso, nell’ordine reale (cima per prima)
    assert (s#>'{deckv,1}') is not distinct from (case when (m1 & 4) = 4 then to_jsonb(deck1) end), format('T6: %s/%s deck di Ann', m1, m2);
    assert (s#>'{deckv,2}') is not distinct from (case when (m2 & 4) = 4 then to_jsonb(deck2) end), format('T6: %s/%s deck di Bob', m1, m2);
    -- la mano concessa arriva con le carte in zona hand; senza permesso la zona è vuota
    assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1) = case when (m1 & 1) = 1 then 1 else 0 end, format('T6: %s/%s mano di Ann', m1, m2);
    assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 2) = case when (m2 & 1) = 1 then 1 else 0 end, format('T6: %s/%s mano di Bob', m1, m2);
    assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'extra' and (c->>'o')::int = 1) = case when (m1 & 4) = 4 then 3 else 0 end, format('T6: %s/%s extra di Ann', m1, m2);
    assert (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'extra' and (c->>'o')::int = 2) = case when (m2 & 4) = 4 then 3 else 0 end, format('T6: %s/%s extra di Bob', m1, m2);
  end loop; end loop;
  insert into t_log (msg) values ('OK T6 64 combinazioni di permessi');
end $$;

-- =====================================================================
-- T7 — concedere e togliere permessi: chi può, a chi, cosa si legge nel registro
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; s jsonb; sa jsonb; before_ text; hA integer[]; hB integer[]; nlog integer;
begin
  perform pg_temp.grant_('Ann', l, 'Cid', 0); perform pg_temp.grant_('Bob', l, 'Cid', 0);
  assert (select count(*) from public.sim_spec_grants) = 0, 'T7: permessi azzerati';
  hA := array(select code from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand');
  hB := array(select code from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand');
  -- Ann concede la mano a Cid: vede la mano di Ann, NON quella di Bob
  s := pg_temp.grant_('Ann', l, 'Cid', 1);
  sa := pg_temp.s('Cid', l);
  assert pg_temp.leak(sa, hB) = '{}' and pg_temp.leak(sa, hA) = hA, 'T7: Cid vede la mano di Ann e non quella di Bob';
  -- Ann non può dare permessi sulle carte di Bob: la funzione agisce sempre sul posto di chi la chiama
  assert (select seat from public.sim_spec_grants) = 1, 'T7: il permesso è registrato sul posto di Ann';
  -- Bob concede a Dan (che entra ora): Dan vede la mano di Bob ma non quella di Ann; Cid non vede la mano di Bob
  assert pg_temp.watch('Dan', l) is not null, 'T7: Dan entra';
  perform pg_temp.grant_('Bob', l, 'Dan', 1);
  s := pg_temp.s('Dan', l);
  assert pg_temp.leak(s, hB) = hB and pg_temp.leak(s, hA) = '{}', 'T7: Dan vede la mano di Bob e non quella di Ann';
  s := pg_temp.s('Cid', l);
  assert pg_temp.leak(s, hB) = '{}', 'T7: Cid non vede la mano di Bob';
  -- il permesso è trasparente: i giocatori e gli spettatori vedono chi può guardare cosa
  s := pg_temp.s('Bob', l);
  assert (select jsonb_agg(e->'g' order by e->>'nickname') from jsonb_array_elements(s#>'{spec,list}') e) = '[[1,0],[0,1]]'::jsonb, 'T7: elenco spettatori con i permessi (Cid/Dan)';
  assert pg_temp.s('Cid', l)#>'{spec,list}' = s#>'{spec,list}', 'T7: lo spettatore vede lo stesso elenco';
  -- il registro pubblico riporta la concessione, con il nome di chi la riceve
  assert exists (select 1 from jsonb_array_elements(s->'log') e where e->>'kind' = 'spec' and e#>>'{data,n}' = 'Dan' and (e#>>'{data,m}')::int = 1 and (e#>>'{data,all}')::boolean = false), 'T7: la concessione è nel registro';
  -- validazioni
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, %L::uuid, 8)', l, pg_temp.uid('Cid'))) = 'Permesso non valido', 'T7: 8 non è valido';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, %L::uuid, -1)', l, pg_temp.uid('Cid'))) = 'Permesso non valido', 'T7: -1 non è valido';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, %L::uuid, null)', l, pg_temp.uid('Cid'))) = 'Permesso non valido', 'T7: nullo non è valido';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, %L::uuid, 7)', l, pg_temp.uid('Mod'))) = 'Quello spettatore non c’è più', 'T7: chi non guarda non riceve permessi';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, %L::uuid, 7)', l, pg_temp.uid('Bob'))) = 'Quello spettatore non c’è più', 'T7: l’avversario non è uno spettatore';
  assert pg_temp.err_as('Org', format('select public.sim_spec_grant(%s, null, 7)', l)) = 'Non partecipi a questa partita', 'T7: un estraneo non dà permessi';
  assert pg_temp.err_as('Mod', format('select public.sim_spec_grant(%s, null, 7)', l)) = 'Non partecipi a questa partita', 'T7: nemmeno un moderatore';
  assert pg_temp.err_as('Admin', format('select public.sim_spec_open(%s, false)', l)) = 'Non partecipi a questa partita', 'T7: nemmeno un admin chiude la partita altrui';
  -- permesso a tutti (anche a chi entrerà): vale per i nuovi arrivati
  perform pg_temp.grant_('Ann', l, null, 5);
  assert pg_temp.watch('Org', l) is not null, 'T7: Org entra';
  s := pg_temp.s('Org', l);
  assert s#>'{me,mk}' = '[5,0]'::jsonb and s#>'{spec,all}' = '[5,0]'::jsonb, 'T7: Org eredita il permesso a tutti (mano + deck di Ann)';
  assert pg_temp.leak(s, hA) = hA and jsonb_array_length(s#>'{deckv,1}') = 35 and s#>'{deckv,2}' is null, 'T7: Org vede mano e deck di Ann, non di Bob';
  assert exists (select 1 from jsonb_array_elements(s->'log') e where e->>'kind' = 'spec' and (e#>>'{data,all}')::boolean and (e#>>'{data,m}')::int = 5), 'T7: anche la concessione a tutti è nel registro';
  -- il permesso a tutti si somma a quello individuale
  s := pg_temp.s('Cid', l);
  assert s#>'{me,mk}' = '[5,0]'::jsonb, 'T7: Cid ha mano (individuale) + deck (a tutti)';
  perform pg_temp.grant_('Ann', l, null, 0);
  assert pg_temp.s('Org', l)#>'{me,mk}' = '[0,0]'::jsonb and pg_temp.s('Cid', l)#>'{me,mk}' = '[1,0]'::jsonb, 'T7: tolto il permesso a tutti restano quelli individuali';
  -- i permessi si tolgono subito
  perform pg_temp.grant_('Ann', l, 'Cid', 0);
  s := pg_temp.s('Cid', l);
  assert pg_temp.leak(s, hA) = '{}' and s#>'{me,mk}' = '[0,0]'::jsonb, 'T7: tolto il permesso, la mano sparisce subito';
  -- uscire fa perdere i permessi
  perform pg_temp.grant_('Ann', l, 'Cid', 7);
  assert (select count(*) from public.sim_spec_grants where user_id = pg_temp.uid('Cid')) = 1, 'T7: permesso di Cid registrato';
  perform pg_temp.x('Cid', 'public.sim_watch_leave(' || l || ')');
  assert (select count(*) from public.sim_spec_grants where user_id = pg_temp.uid('Cid')) = 0, 'T7: uscendo il permesso decade';
  perform pg_temp.watch('Cid', l);
  assert pg_temp.s('Cid', l)#>'{me,mk}' = '[0,0]'::jsonb, 'T7: rientrando non si ha nessun permesso';
  insert into t_log (msg) values ('OK T7 concessione e revoca dei permessi');
end $$;

-- =====================================================================
-- T8 — le carte cambiano: cosa vede lo spettatore
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; s jsonb; a2 integer; a2c integer; h5 integer; h5c integer;
begin
  -- Cid senza permessi (azzerati). Ann scopre il mostro coperto: ora lo spettatore ne legge il nome
  select id, code into a2, a2c from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'mz' and not face_up limit 1;
  assert not (a2c = any (pg_temp.xs(pg_temp.s('Cid', l)))), 'T8: prima il mostro coperto non si legge';
  perform pg_temp.x('Ann', format('public.sim_set(%s, %s, ''def'', true)', l, a2));
  assert a2c = any (pg_temp.xs(pg_temp.s('Cid', l))), 'T8: scoperto, il nome compare';
  perform pg_temp.x('Ann', format('public.sim_set(%s, %s, ''def'', false)', l, a2));
  assert not (a2c = any (pg_temp.xs(pg_temp.s('Cid', l)))), 'T8: ricoperto, il nome scompare dalle carte (nel registro resta, perché era stato mostrato)';
  -- mostrare una carta della mano la rende pubblica per tutti, spettatori compresi
  select id, code into h5, h5c from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand' limit 1;
  assert not (h5c = any (pg_temp.xs(pg_temp.s('Cid', l)))), 'T8: la carta in mano non si legge';
  perform pg_temp.x('Ann', format('public.sim_reveal(%s, %s, true)', l, h5));
  s := pg_temp.s('Cid', l);
  assert h5c = any (pg_temp.xs(s)) and (select count(*) from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand' and (c->>'r')::boolean) = 1, 'T8: la carta mostrata si vede';
  perform pg_temp.x('Ann', format('public.sim_reveal(%s, %s, false)', l, h5));
  assert not (h5c = any (pg_temp.xs(pg_temp.s('Cid', l)))), 'T8: nascosta di nuovo';
  -- una carta pescata da Ann non compare, ma il contatore sale
  s := pg_temp.s('Cid', l);
  perform pg_temp.x('Ann', format('public.sim_draw(%s, 2)', l));
  assert (pg_temp.s('Cid', l)#>>'{counts,1,hand}')::int = (s#>>'{counts,1,hand}')::int + 2, 'T8: il contatore della mano sale';
  assert pg_temp.xs(pg_temp.s('Cid', l)) = pg_temp.expected(l, 0, 0), 'T8: dopo la pesca i nomi visibili sono solo quelli pubblici';
  -- un attacco su un mostro coperto non rivela il nome (registro)
  insert into t_log (msg) values ('OK T8 carte che cambiano');
end $$;

-- =====================================================================
-- T9 — chat
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; s jsonb; i integer; e text; u0 timestamptz;
begin
  assert pg_temp.err_as('Mod', format('select public.sim_watch_say(%s, ''ciao'')', l)) = 'Non sei tra gli spettatori', 'T9: chi non guarda non scrive';
  assert pg_temp.err_as('Ann', format('select public.sim_watch_say(%s, ''ciao'')', l)) = 'Non sei tra gli spettatori', 'T9: un giocatore usa la sua chat';
  assert pg_temp.err_as('Cid', format('select public.sim_watch_say(%s, ''   '')', l)) = 'Scrivi qualcosa', 'T9: messaggio vuoto';
  update public.sim_lobbies set updated_at = now() - interval '1 hour' where id = l;
  select updated_at into u0 from public.sim_lobbies where id = l;
  s := pg_temp.x('Cid', format('public.sim_watch_say(%s, %L)', l, '   Forza Ann!  '));
  assert (select count(*) from jsonb_array_elements(s->'chat') c where c->>'t' = 'Forza Ann!' and (c->>'seat')::int = 0 and c->>'u' = 'Cid') = 1, 'T9: messaggio con nome e posto 0';
  assert (select updated_at from public.sim_lobbies where id = l) = u0, 'T9: scrivere in chat non allunga la vita di una partita ferma';
  assert (select count(*) from jsonb_array_elements(s->'chat') c where c->>'uid' = pg_temp.uid('Cid')::text and (c->>'seat')::int = 0) = 1, 'T9: il messaggio porta l’id dell’autore';
  -- i giocatori lo vedono, con il nome dello spettatore
  s := pg_temp.s('Bob', l);
  assert (select count(*) from jsonb_array_elements(s->'chat') c where c->>'u' = 'Cid' and c->>'t' = 'Forza Ann!') = 1, 'T9: Bob legge il messaggio dello spettatore';
  -- e i messaggi dei giocatori li vede lo spettatore
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, %L)', l, 'Grazie!'));
  s := pg_temp.s('Dan', l);
  assert (select count(*) from jsonb_array_elements(s->'chat') c where c->>'t' = 'Grazie!' and (c->>'seat')::int = 1 and c->'u' = 'null'::jsonb and c->'uid' = 'null'::jsonb) = 1, 'T9: lo spettatore legge i messaggi dei giocatori';
  -- pulizia di caratteri di controllo e lunghezza
  s := pg_temp.x('Cid', format('public.sim_watch_say(%s, %L)', l, 'a' || chr(10) || chr(7) || 'b' || repeat('x', 300)));
  assert (select c->>'t' from jsonb_array_elements(s->'chat') c order by (c->>'n')::int desc limit 1) = 'a  b' || repeat('x', 196), 'T9: caratteri di controllo tolti e testo tagliato a 200';
  -- il codice HTML non viene interpretato dal server: resta testo (il browser lo mostra con esc())
  s := pg_temp.x('Cid', format('public.sim_watch_say(%s, %L)', l, '<img src=x onerror=alert(1)>'));
  assert (select c->>'t' from jsonb_array_elements(s->'chat') c order by (c->>'n')::int desc limit 1) = '<img src=x onerror=alert(1)>', 'T9: il testo è conservato così com’è';
  -- limite: 12 messaggi al minuto per spettatore (ne ha già scritti 3)
  for i in 1..9 loop perform pg_temp.x('Cid', format('public.sim_watch_say(%s, %L)', l, 'm' || i)); end loop;
  e := pg_temp.err_as('Cid', format('select public.sim_watch_say(%s, ''troppi'')', l));
  assert e = 'Troppi messaggi: aspetta qualche secondo', 'T9: il tredicesimo messaggio è rifiutato (' || coalesce(e, 'nessun errore') || ')';
  perform pg_temp.x('Dan', format('public.sim_watch_say(%s, %L)', l, 'Dan può scrivere'));   -- il limite è per persona
  -- il limite dei 200 messaggi vale per tutti
  for i in 1..210 loop insert into public.sim_chat (lobby_id, n, seat, user_id, body) select l, coalesce(max(n), 0) + 1, 0, pg_temp.uid('Mod'), 'riempimento' from public.sim_chat where lobby_id = l; end loop;
  s := pg_temp.x('Dan', format('public.sim_watch_say(%s, ''ultimo'')', l)) ;
  assert (select count(*) from public.sim_chat where lobby_id = l) <= 200, 'T9: la chat è tagliata a 200 messaggi';
  assert jsonb_array_length(s->'chat') = 80, 'T9: lo stato porta gli ultimi 80';
  -- vincolo del database: un messaggio da spettatore deve avere l’autore, uno da giocatore no
  assert pg_temp.err('insert into public.sim_chat (lobby_id, n, seat, body) values (' || l || ', 99999, 0, ''x'')') like '%sim_chat_spec_chk%', 'T9: posto 0 senza autore rifiutato';
  assert pg_temp.err('insert into public.sim_chat (lobby_id, n, seat, user_id, body) values (' || l || ', 99998, 1, ''' || pg_temp.uid('Cid') || ''', ''x'')') like '%sim_chat_spec_chk%', 'T9: posto 1 con autore rifiutato';
  delete from public.sim_chat where lobby_id = l;
  insert into t_log (msg) values ('OK T9 chat degli spettatori');
end $$;

-- =====================================================================
-- T10 — versioni (polling) e «tenere sveglia» la partita
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; s jsonb; v0 bigint; u0 timestamptz; n0 integer;
begin
  v0 := (pg_temp.s('Cid', l)->>'v')::bigint;
  assert pg_temp.x('Cid', format('public.sim_state(%s, %s)', l, v0)) = jsonb_build_object('same', true, 'v', v0), 'T10: stessa versione, risposta breve';
  perform pg_temp.x('Ann', format('public.sim_phase(%s, ''battle'')', l));
  s := pg_temp.x('Cid', format('public.sim_state(%s, %s)', l, v0));
  assert s ? 'cards' and (s->>'v')::bigint > v0, 'T10: dopo una mossa lo spettatore riceve lo stato nuovo';
  v0 := (s->>'v')::bigint;
  perform pg_temp.grant_('Bob', l, 'Cid', 2);
  assert (pg_temp.x('Cid', format('public.sim_state(%s, %s)', l, v0))->>'v')::bigint > v0 and pg_temp.x('Cid', format('public.sim_state(%s, %s)', l, v0)) ? 'cards', 'T10: un nuovo permesso cambia la versione';
  v0 := (pg_temp.s('Cid', l)->>'v')::bigint;
  perform pg_temp.x('Mod', 'public.sim_home()');
  perform pg_temp.watch('Mod', l);
  assert (pg_temp.s('Cid', l)->>'v')::bigint > v0, 'T10: l’ingresso di un altro spettatore cambia la versione';
  perform pg_temp.x('Mod', 'public.sim_watch_leave(' || l || ')');
  update public.sim_lobbies set updated_at = now() - interval '1 hour' where id = l;
  select updated_at into u0 from public.sim_lobbies where id = l;
  perform pg_temp.watch('Mod', l); perform pg_temp.x('Mod', format('public.sim_watch_say(%s, ''x'')', l)); perform pg_temp.x('Mod', 'public.sim_watch_leave(' || l || ')');
  assert (select updated_at from public.sim_lobbies where id = l) = u0, 'T10: entrare, scrivere e uscire non tengono sveglia la partita';
  -- chi non partecipa (né gioca né guarda) non riceve lo stato
  assert pg_temp.err_as('Mod', format('select public.sim_state(%s)', l)) = 'Non partecipi a questa partita', 'T10: l’estraneo non legge lo stato';
  assert pg_temp.err_as('Mod', format('select public.sim_state(%s, 5)', l)) = 'Non partecipi a questa partita', 'T10: nemmeno con la versione';
  insert into t_log (msg) values ('OK T10 versioni e partita ferma');
end $$;

-- =====================================================================
-- T11 — home: partite da guardare
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; h jsonb; e jsonb;
begin
  h := pg_temp.x('Mod', 'public.sim_home()');
  assert jsonb_array_length(h->'live') = 1 and (h#>>'{live,0,id}')::bigint = l, 'T11: la partita in corso è tra quelle da guardare';
  assert h#>>'{live,0,players,0,nickname}' = 'Ann' and h#>>'{live,0,players,1,nickname}' = 'Bob' and (h#>>'{live,0,watchers}')::int = 3, 'T11: giocatori e numero di spettatori (Cid, Dan, Org)';
  assert h->'watching' = 'null'::jsonb, 'T11: Mod non sta guardando';
  assert h::text !~ 'deck_id|"x"', 'T11: nessun dato di carte nell’elenco';
  assert jsonb_array_length(pg_temp.x('Ann', 'public.sim_home()')->'live') = 0, 'T11: chi gioca non vede la propria partita tra quelle da guardare';
  assert (pg_temp.x('Cid', 'public.sim_home()')->>'watching')::bigint = l, 'T11: Cid sta guardando questa partita';
  -- chiusa agli spettatori: sparisce dall’elenco, gli spettatori escono e non rientrano
  perform pg_temp.grant_('Ann', l, null, 2); perform pg_temp.grant_('Bob', l, null, 1);
  assert (select spec_all from public.sim_players where lobby_id = l and seat = 1) = 2, 'T11: permesso a tutti impostato prima di chiudere';
  e := pg_temp.x('Ann', format('public.sim_spec_open(%s, false)', l));
  assert (e#>>'{spec,open}')::boolean = false and jsonb_array_length(e#>'{spec,list}') = 0, 'T11: chiudendo gli spettatori escono';
  assert (select count(*) from public.sim_spec_grants) = 0 and (select sum(spec_all) from public.sim_players where lobby_id = l) = 0, 'T11: i permessi decadono (anche quelli a tutti)';
  assert pg_temp.err_as('Cid', format('select public.sim_state(%s)', l)) = 'Non partecipi a questa partita', 'T11: chi guardava non riceve più lo stato';
  assert pg_temp.err_as('Cid', format('select public.sim_watch_join(%s)', l)) = 'I giocatori hanno chiuso la partita agli spettatori', 'T11: non si rientra';
  assert jsonb_array_length(pg_temp.x('Mod', 'public.sim_home()')->'live') = 0, 'T11: la partita chiusa non è elencata';
  e := pg_temp.x('Bob', format('public.sim_spec_open(%s, true)', l));
  assert (e#>>'{spec,open}')::boolean, 'T11: anche l’altro giocatore può riaprire';
  assert jsonb_array_length(pg_temp.x('Mod', 'public.sim_home()')->'live') = 1, 'T11: di nuovo elencata';
  assert pg_temp.watch('Cid', l) is not null, 'T11: si rientra';
  -- limite spettatori
  update public.system_settings set value_int = 2 where key = 'sim_max_spectators';
  perform pg_temp.watch('Dan', l);
  assert pg_temp.err_as('Org', format('select public.sim_watch_join(%s)', l)) = 'Ci sono già troppi spettatori', 'T11: oltre il limite si resta fuori';
  update public.system_settings set value_int = 8 where key = 'sim_max_spectators';
  assert pg_temp.watch('Org', l) is not null, 'T11: portato il limite a 8, Org entra';
  insert into t_log (msg) values ('OK T11 home, chiusura e limite');
end $$;

-- =====================================================================
-- T12 — espulsione
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; s jsonb;
begin
  perform pg_temp.grant_('Ann', l, 'Org', 7);
  s := pg_temp.x('Ann', format('public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Org')));
  assert not exists (select 1 from jsonb_array_elements(s#>'{spec,list}') e where e->>'nickname' = 'Org'), 'T12: Org non è più nell’elenco';
  assert (select count(*) from public.sim_spec_grants where user_id = pg_temp.uid('Org')) = 0, 'T12: i suoi permessi decadono';
  assert pg_temp.err_as('Org', format('select public.sim_state(%s)', l)) = 'Non partecipi a questa partita', 'T12: non riceve più lo stato';
  assert pg_temp.err_as('Org', format('select public.sim_watch_say(%s, ''ciao'')', l)) = 'Non sei tra gli spettatori', 'T12: non scrive più';
  assert pg_temp.err_as('Org', format('select public.sim_watch_join(%s)', l)) = 'Sei stato allontanato da questa partita', 'T12: non rientra';
  assert not exists (select 1 from jsonb_array_elements(pg_temp.x('Org', 'public.sim_home()')->'live') e where (e->>'id')::bigint = l), 'T12: la partita non gli è più proposta';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Org'))) = 'Quello spettatore non c’è più', 'T12: espellere due volte';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Bob'))) = 'Quello spettatore non c’è più', 'T12: non si caccia l’avversario';
  -- l’altro giocatore può cacciare chiunque
  perform pg_temp.x('Bob', format('public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Dan')));
  assert (select count(*) from public.sim_spectators where lobby_id = l) = 1, 'T12: resta solo Cid';
  insert into t_log (msg) values ('OK T12 espulsione');
end $$;

-- =====================================================================
-- T13 — diventare giocatore, fine partita, modulo spento
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L')::bigint; l2 bigint; s jsonb; h jsonb;
begin
  -- Cid guarda: se crea una lobby diventa giocatore e smette di guardare
  l2 := (pg_temp.x('Cid', 'public.sim_lobby_create(''Mia'')'))#>>'{}';
  assert (select count(*) from public.sim_spectators where user_id = pg_temp.uid('Cid')) = 0, 'T13: creare una lobby fa smettere di guardare';
  assert pg_temp.err_as('Cid', format('select public.sim_state(%s)', l)) = 'Non partecipi a questa partita', 'T13: la partita guardata non gli arriva più';
  perform pg_temp.x('Cid', 'public.sim_lobby_leave(' || l2 || ')');
  -- entrare come giocatore in una lobby altrui fa lo stesso (trigger)
  perform pg_temp.watch('Mod', l);
  assert (select count(*) from public.sim_spectators where user_id = pg_temp.uid('Mod')) = 1, 'T13: Mod guarda';
  insert into public.sim_lobbies (id, host_id, title) values (777, pg_temp.uid('Org'), 'x');
  insert into public.sim_players (lobby_id, seat, user_id) values (777, 1, pg_temp.uid('Org')), (777, 2, pg_temp.uid('Mod'));
  assert (select count(*) from public.sim_spectators where user_id = pg_temp.uid('Mod')) = 0, 'T13: il trigger toglie chi diventa giocatore';
  delete from public.sim_lobbies where id = 777;
  -- guardare un’altra partita sposta lo spettatore
  perform pg_temp.watch('Mod', l);
  assert (select count(*) from public.sim_spectators where user_id = pg_temp.uid('Mod')) = 1, 'T13: Mod guarda';
  -- fine della partita: lo spettatore vede la conclusione e il tavolo non rivela più nulla
  perform pg_temp.x('Ann', format('public.sim_concede(%s)', l));
  s := pg_temp.s('Mod', l);
  assert s#>>'{game,status}' = 'finished' and s->'cards' = '[]'::jsonb and s->'deckv' = '{}'::jsonb, 'T13: a duello finito nessuna carta nello stato';
  assert pg_temp.err_as('Mod', format('select public.sim_watch_say(%s, ''bella partita'')', l)) is null, 'T13: si può ancora salutare';
    perform pg_temp.endmatch(l);
  s := pg_temp.s('Mod', l);
  assert s#>>'{lobby,status}' = 'finished', 'T13: partita chiusa';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, null, 7)', l)) = 'La partita non è in corso', 'T13: a partita chiusa non si concedono permessi';
  h := pg_temp.x('Mod', 'public.sim_home()');
  assert h->'watching' = 'null'::jsonb and (select count(*) from public.sim_spectators where user_id = pg_temp.uid('Mod')) = 0, 'T13: la home libera chi guardava una partita finita';
  assert (select count(*) from public.sim_spectators) = 0, 'T13: nessuno spettatore rimasto';
  insert into t_log (msg) values ('OK T13 diventare giocatore e fine partita');
end $$;

do $$
declare l bigint; s jsonb;
begin
  -- modulo spento: tutto rifiutato
  l := pg_temp.newmatch();
  perform pg_temp.watch('Cid', l);
  -- guardare un’altra partita in corso sposta lo spettatore (una sola alla volta)
  insert into public.sim_lobbies (id, host_id, title, status) values (888, pg_temp.uid('Org'), 'altra', 'playing');
  insert into public.sim_players (lobby_id, seat, user_id) values (888, 1, pg_temp.uid('Org')), (888, 2, pg_temp.uid('Mod'));
  perform pg_temp.watch('Cid', 888);
  assert (select array_agg(lobby_id) from public.sim_spectators where user_id = pg_temp.uid('Cid')) = array[888::bigint], 'T14: Cid è passato alla partita 888';
  assert pg_temp.err_as('Cid', format('select public.sim_state(%s)', l)) = 'Non partecipi a questa partita', 'T14: la partita lasciata non gli arriva più';
  update public.sim_players set active = false where lobby_id = 888;
  delete from public.sim_lobbies where id = 888;
  perform pg_temp.watch('Cid', l);
  perform pg_temp.as_('Admin');
  perform public.admin_set_module('duel', false, 'prova modulo spento');
  assert pg_temp.err_as('Cid', format('select public.sim_watch_join(%s)', l)) = 'Modulo non attivo', 'T14: modulo spento, ingresso rifiutato';
  assert pg_temp.err_as('Cid', format('select public.sim_state(%s)', l)) = 'Modulo non attivo', 'T14: modulo spento, stato rifiutato';
  assert pg_temp.err_as('Cid', format('select public.sim_watch_say(%s, ''x'')', l)) = 'Modulo non attivo', 'T14: modulo spento, chat rifiutata';
  assert pg_temp.err_as('Cid', format('select public.sim_watch_leave(%s)', l)) = 'Modulo non attivo', 'T14: modulo spento, uscita rifiutata';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_grant(%s, null, 1)', l)) = 'Modulo non attivo', 'T14: modulo spento, permessi rifiutati';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Cid'))) = 'Modulo non attivo', 'T14: modulo spento, espulsione rifiutata';
  assert pg_temp.err_as('Ann', format('select public.sim_spec_open(%s, false)', l)) = 'Modulo non attivo', 'T14: modulo spento, chiusura rifiutata';
  perform pg_temp.as_('Admin');
  perform public.admin_set_module('duel', true, 'prova modulo riacceso');
  assert pg_temp.s('Cid', l) is not null, 'T14: riacceso, tutto torna';
  -- la partita viene cancellata: spettatori, permessi, divieti e chat spariscono con lei
  perform pg_temp.grant_('Ann', l, 'Cid', 3);
  perform pg_temp.x('Cid', format('public.sim_watch_say(%s, ''x'')', l));
  perform pg_temp.x('Bob', format('public.sim_spec_kick(%s, %L::uuid)', l, pg_temp.uid('Cid')));
  perform pg_temp.endmatch(l);
  delete from public.sim_lobbies where id = l;
  assert (select count(*) from public.sim_spectators where lobby_id = l) + (select count(*) from public.sim_spec_grants where lobby_id = l) + (select count(*) from public.sim_spec_bans where lobby_id = l) + (select count(*) from public.sim_chat where lobby_id = l) = 0, 'T14: cancellando la partita spariscono tutti i dati degli spettatori';
  insert into t_log (msg) values ('OK T14 modulo e pulizia');
end $$;

-- =====================================================================
-- T15 — nessun effetto fuori dal Duel Simulator
-- =====================================================================
do $$
begin
  assert pg_temp.eco() = (select v from t_ctx where k = 'eco'), 'T15: portafogli, registro contabile e taglie identici a prima';
  insert into t_log (msg) values ('OK T15 nessun effetto fuori dal simulatore');
end $$;

select msg from t_log order by n;
rollback;
