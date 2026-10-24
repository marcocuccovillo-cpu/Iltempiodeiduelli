-- =====================================================================
-- TEST DI «EFFETTI E CATENE» del Duel Simulator (black-market-duel-simulator-catene.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-duel-simulator.sql, black-market-duel-simulator-chat.sql
-- e black-market-duel-simulator-catene.sql.
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

-- =====================================================================
-- E1 — permessi, tabella chiusa
-- =====================================================================
do $$
begin
  assert pg_temp.err_auth('Ann', 'select * from public.sim_chain') like '%permission denied%', 'E1: sim_chain non leggibile';
  assert pg_temp.err_auth('Ann', 'insert into public.sim_chain (game_id, n, seat, code) values (1, 1, 1, 5)') like '%permission denied%', 'E1: sim_chain non scrivibile';
  assert pg_temp.err_auth('Ann', 'delete from public.sim_chain') like '%permission denied%', 'E1: sim_chain non cancellabile';
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.sim_activate(1, 1)') like '%Accesso richiesto%', 'E1: attivare senza accesso rifiutato';
  assert pg_temp.err('select public.sim_chain_resolve(1)') like '%Accesso richiesto%', 'E1: risolvere senza accesso rifiutato';
  assert pg_temp.err('select public.sim_chain_clear(1)') like '%Accesso richiesto%', 'E1: annullare senza accesso rifiutato';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_activate','sim_chain_resolve','sim_chain_clear') and grantee in ('anon','PUBLIC')) = 0, 'E1: nessun permesso ad anon/public';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_activate','sim_chain_resolve','sim_chain_clear') and grantee = 'authenticated') = 3, 'E1: permessi a authenticated';
  insert into t_log (msg) values ('OK E1 permessi');
end $$;

-- =====================================================================
-- E2 — dichiarare un effetto: chi, da dove, cosa si vede
-- =====================================================================
do $$
declare l bigint; s jsonb; sb jsonb; ids integer[]; a1 integer; a2 integer; b1 integer; i integer; cnt0 integer;
begin
  l := pg_temp.newmatch();
  -- scelgo carte note: Ann (codici 1xxxx) e Bob (2xxxx) hanno 5 carte in mano a testa
  s := pg_temp.s('Ann', l);
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  a1 := pg_temp.cid(l, ids[1]); a2 := pg_temp.cid(l, ids[2]);
  b1 := (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand' limit 1);
  -- prima volta: dalla mano
  s := pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, a1));
  assert jsonb_array_length(s->'chain') = 1 and (s->'chain'->0->>'n')::int = 1 and (s->'chain'->0->>'seat')::int = 1 and (s->'chain'->0->>'x')::int = ids[1] and (s->'chain'->0->>'res')::boolean = false, 'E2: primo anello registrato';
  assert pg_temp.zone_of(l, ids[1]) = 'hand', 'E2: la carta resta in mano (nessuno spostamento automatico)';
  sb := pg_temp.s('Bob', l);
  assert (sb->'chain'->0->>'x')::int = ids[1], 'E2: Bob vede il nome della carta dichiarata dalla mano';
  assert (sb->'chain'->0->'i') = 'null'::jsonb, 'E2: ma NON il suo identificativo (la carta è ancora in mano)';
  assert (s->'chain'->0->>'i')::int is null, 'E2: nemmeno Ann riceve l''id di una carta non pubblica';
  assert (select count(*) from jsonb_array_elements(sb->'cards') c where (c->>'i')::int = a1) = 0, 'E2: la carta resta invisibile a Bob (mano)';
  assert exists (select 1 from jsonb_array_elements(sb->'log') e where e->>'kind' = 'activate' and (e->'data'->>'x')::int = ids[1] and (e->'data'->>'n')::int = 1 and e->'data'->>'z' = 'hand'), 'E2: registro pubblico con carta, numero e provenienza';
  -- chi non è nel gioco / l'altro giocatore
  assert pg_temp.err_as('Cid', format('select public.sim_activate(%s, %s)', l, a1)) = 'Non partecipi a questa partita', 'E2: l''estraneo non dichiara';
  assert pg_temp.err_as('Bob', format('select public.sim_activate(%s, %s)', l, a1)) = 'Puoi dichiarare solo effetti delle tue carte', 'E2: Bob non dichiara la carta in mano ad Ann';
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, b1)) = 'Puoi dichiarare solo effetti delle tue carte', 'E2: Ann non dichiara la carta in mano a Bob';
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, 999999)', l)) = 'Carta inesistente', 'E2: carta inesistente';
  -- dal deck e dall''Extra: no
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' limit 1))) = 'Da qui non puoi dichiarare un effetto', 'E2: dal deck no';
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'extra' limit 1))) = 'Da qui non puoi dichiarare un effetto', 'E2: dall''Extra Deck no';
  -- carta coperta sul campo: si scopre
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''st'', null, null, false)', l, a2));
  assert (select face_up from public.sim_cards where game_id = pg_temp.gid(l) and id = a2) = false, 'E2: la carta è coperta';
  s := pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, a2));
  assert (select face_up from public.sim_cards where game_id = pg_temp.gid(l) and id = a2), 'E2: dichiarando si scopre';
  assert jsonb_array_length(s->'chain') = 2 and (s->'chain'->1->>'n')::int = 2, 'E2: secondo anello';
  sb := pg_temp.s('Bob', l);
  assert (sb->'chain'->1->>'i')::int = a2, 'E2: carta scoperta sul campo: l''id è pubblico e lo vede anche Bob';
  assert exists (select 1 from jsonb_array_elements(sb->'log') e where e->>'kind' = 'activate' and (e->'data'->>'fl')::boolean), 'E2: il registro dice che la carta è stata scoperta';
  -- carta di Bob sul campo: Ann non la dichiara
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'')', l, b1));
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, b1)) = 'Puoi dichiarare solo effetti delle tue carte', 'E2: Ann non dichiara la carta sul campo di Bob';
  -- cimitero e carte rimosse
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''gy'')', l, pg_temp.cid(l, ids[3])));
  s := pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[3])));
  assert jsonb_array_length(s->'chain') = 3, 'E2: dal Cimitero';
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''banish'')', l, pg_temp.cid(l, ids[4])));
  s := pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[4])));
  assert jsonb_array_length(s->'chain') = 4, 'E2: dalle carte rimosse';
  -- Bob può rispondere: Bob dichiara la sua carta sul campo
  s := pg_temp.x('Bob', format('public.sim_activate(%s, %s)', l, b1));
  assert jsonb_array_length(s->'chain') = 5 and (s->'chain'->4->>'seat')::int = 2, 'E2: Bob concatena il suo effetto (anello 5)';
  -- segnalino
  perform pg_temp.x('Ann', format('public.sim_token(%s)', l));
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and code = 0 limit 1))) = 'I segnalini non hanno effetti da dichiarare', 'E2: i segnalini non hanno effetti';
  -- materiale Xyz
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'')', l, pg_temp.cid(l, ids[5])));
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''ovl'', null, null, null, true, %s)', l, pg_temp.cid(l, ids[5]), (select id from public.sim_cards where game_id = pg_temp.gid(l) and code = 0 limit 1)));
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[5]))) = 'Da qui non puoi dichiarare un effetto', 'E2: un materiale non dichiara';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK E2 dichiarazione');
end $$;

-- =====================================================================
-- E3 — numerazione, risoluzione al contrario, chiusura automatica
-- =====================================================================
do $$
declare l bigint; s jsonb; ids integer[]; v0 bigint;
begin
  l := pg_temp.newmatch();
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  assert pg_temp.err_as('Ann', format('select public.sim_chain_resolve(%s)', l)) = 'Non c''è nessuna catena da risolvere', 'E3: senza catena non si risolve';
  assert pg_temp.err_as('Ann', format('select public.sim_chain_clear(%s)', l)) = 'Non c''è nessuna catena', 'E3: senza catena non si annulla';
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1])));
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[2])));
  v0 := (pg_temp.s('Bob', l)->>'v')::bigint;
  s := pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1])));
  assert (pg_temp.s('Bob', l)->>'v')::bigint > v0, 'E3: dichiarare fa salire la versione (l''altro giocatore la vede)';
  assert (select string_agg((c->>'n') || ':' || (c->>'x'), ',' order by (c->>'n')::int) from jsonb_array_elements(s->'chain') c) = '1:' || ids[1] || ',2:' || ids[2] || ',3:' || ids[1], 'E3: numeri 1,2,3 (la stessa carta può comparire due volte)';
  v0 := (pg_temp.s('Bob', l)->>'v')::bigint;
  s := pg_temp.x('Bob', format('public.sim_chain_resolve(%s)', l));
  assert (select string_agg((c->>'n') || ':' || (c->>'res'), ',' order by (c->>'n')::int) from jsonb_array_elements(s->'chain') c) = '1:false,2:false,3:true', 'E3: si risolve l''ultimo anello (3)';
  assert (pg_temp.s('Ann', l)->>'v')::bigint > v0, 'E3: la versione sale';
  s := pg_temp.x('Ann', format('public.sim_chain_resolve(%s)', l));
  assert (select string_agg((c->>'n') || ':' || (c->>'res'), ',' order by (c->>'n')::int) from jsonb_array_elements(s->'chain') c) = '1:false,2:true,3:true', 'E3: poi il 2';
  s := pg_temp.x('Bob', format('public.sim_activate(%s, %s)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand' limit 1)));
  assert jsonb_array_length(s->'chain') = 4 and (s->'chain'->3->>'n')::int = 4 and (s->'chain'->3->>'res')::boolean = false, 'E3: si può aggiungere un anello nuovo (4) anche dopo risoluzioni parziali';
  s := pg_temp.x('Ann', format('public.sim_chain_resolve(%s)', l));
  assert (s->'chain'->3->>'res')::boolean and not (s->'chain'->0->>'res')::boolean, 'E3: l''anello 4 si risolve prima';
  s := pg_temp.x('Ann', format('public.sim_chain_resolve(%s)', l));
  assert jsonb_array_length(s->'chain') = 0, 'E3: risolti tutti gli anelli la catena si chiude';
  assert (select count(*) from public.sim_chain where game_id = pg_temp.gid(l)) = 0, 'E3: righe cancellate';
  assert (select count(*) from public.sim_log where game_id = pg_temp.gid(l) and kind = 'chain_end') = 1, 'E3: registro «catena finita»';
  assert (select count(*) from public.sim_log where game_id = pg_temp.gid(l) and kind = 'chain_res') = 4, 'E3: 4 risoluzioni registrate';
  assert (select string_agg(data->>'n', ',' order by n) from public.sim_log where game_id = pg_temp.gid(l) and kind = 'chain_res') = '3,2,4,1', 'E3: ordine registrato';
  -- una nuova catena riparte da 1
  s := pg_temp.x('Bob', format('public.sim_activate(%s, %s)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand' limit 1)));
  assert (s->'chain'->0->>'n')::int = 1, 'E3: la nuova catena riparte da 1';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK E3 catena e risoluzione');
end $$;

-- =====================================================================
-- E4 — annulla, limite di 12 anelli, fine duello
-- =====================================================================
do $$
declare l bigint; s jsonb; ids integer[]; i integer; e text; cx integer; v0 bigint;
begin
  l := pg_temp.newmatch();
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1])));
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[2])));
  assert pg_temp.err_as('Cid', format('select public.sim_chain_clear(%s)', l)) = 'Non partecipi a questa partita', 'E4: l''estraneo non annulla';
  assert pg_temp.err_as('Cid', format('select public.sim_chain_resolve(%s)', l)) = 'Non partecipi a questa partita', 'E4: l''estraneo non risolve';
  v0 := (pg_temp.s('Ann', l)->>'v')::bigint;
  s := pg_temp.x('Bob', format('public.sim_chain_clear(%s)', l));
  assert (pg_temp.s('Ann', l)->>'v')::bigint > v0, 'E4: annullare fa salire la versione';
  assert jsonb_array_length(s->'chain') = 0 and (select count(*) from public.sim_chain where game_id = pg_temp.gid(l)) = 0, 'E4: annullata';
  assert (select count(*) from public.sim_log where game_id = pg_temp.gid(l) and kind = 'chain_clear') = 1, 'E4: registro «catena annullata»';
  for i in 1..12 loop
    perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1])));
  end loop;
  assert (select count(*) from public.sim_chain where game_id = pg_temp.gid(l)) = 12, 'E4: 12 anelli';
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1]))) = 'La catena ha già 12 anelli: risolvila o annullala', 'E4: il 13° è rifiutato';
  assert pg_temp.err_as('Bob', format('select public.sim_activate(%s, %s)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand' limit 1))) = 'La catena ha già 12 anelli: risolvila o annullala', 'E4: nemmeno per Bob';
  perform pg_temp.x('Ann', format('public.sim_chain_resolve(%s)', l));
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1]))) = 'La catena ha già 12 anelli: risolvila o annullala', 'E4: dopo una risoluzione parziale il numero 12 resta occupato: il 13° anello non entra';
  cx := pg_temp.cid(l, ids[1]);
  perform pg_temp.x('Ann', format('public.sim_concede(%s)', l)) ;
  s := pg_temp.s('Ann', l);
  assert s->'lobby'->>'status' = 'siding', 'E4: fine duello (resa)';
  assert jsonb_array_length(s->'chain') = 0, 'E4: a duello finito la catena non compare';
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, cx)) = 'Il duello non è in corso', 'E4: a duello finito non si dichiara';
  assert pg_temp.err_as('Ann', format('select public.sim_chain_resolve(%s)', l)) = 'Il duello non è in corso', 'E4: né si risolve';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK E4 annulla e limiti');
end $$;

-- =====================================================================
-- E5 — nessuna fuga di informazioni
-- =====================================================================
do $$
declare l bigint; s0 jsonb; s1 jsonb; ids integer[]; ca integer; gid bigint;
begin
  l := pg_temp.newmatch(); gid := pg_temp.gid(l);
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  ca := pg_temp.cid(l, ids[1]);
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, ca));
  -- Ann poi gioca la carta COPERTA nelle Magie/Trappole
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''st'', null, null, false)', l, ca));
  s1 := pg_temp.s('Bob', l);
  assert (s1->'chain'->0->>'x')::int = ids[1], 'E5: la catena conserva il nome dichiarato';
  assert (s1->'chain'->0->'i') = 'null'::jsonb, 'E5: ma non lo lega alla carta coperta che ora è sul campo';
  assert exists (select 1 from jsonb_array_elements(s1->'cards') c where (c->>'i')::int = ca and c->'x' = 'null'::jsonb and not (c->>'f')::boolean), 'E5: la carta sul campo resta coperta per Bob';
  -- stato di Bob: nessun altro codice di carte di Ann oltre a quello dichiarato
  assert (select count(*) from jsonb_array_elements(s1->'cards') c where (c->>'o')::int = 1 and c->'x' <> 'null'::jsonb) = 0, 'E5: Bob non conosce nessuna carta di Ann';
  assert (s1::text not like '%' || ids[2] || '%') and (s1::text not like '%' || ids[3] || '%'), 'E5: le altre carte in mano ad Ann non compaiono';
  -- dopo che la carta torna scoperta, l'id diventa pubblico
  perform pg_temp.x('Ann', format('public.sim_set(%s, %s, null, true)', l, ca));
  assert ((pg_temp.s('Bob', l))->'chain'->0->>'i')::int = ca, 'E5: carta scoperta: l''id compare';
  -- se la carta lascia il campo per la mano, l'id sparisce di nuovo
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''hand'')', l, ca));
  assert ((pg_temp.s('Bob', l))->'chain'->0->'i') = 'null'::jsonb, 'E5: tornata in mano: l''id sparisce';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK E5 privacy');
end $$;

-- =====================================================================
-- E6 — isolamento: il resto del gioco, i BC e il Black Market non cambiano
-- =====================================================================
do $$
declare l bigint; before_ text; after_ text; ids integer[]; ca integer; s0 jsonb; s1 jsonb;
begin
  l := pg_temp.newmatch();
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  ca := pg_temp.cid(l, ids[1]);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''st'', null, null, true)', l, ca));
  s0 := pg_temp.s('Bob', l);
  before_ := pg_temp.snap();
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[2])));
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, ca));
  perform pg_temp.x('Bob', format('public.sim_chain_resolve(%s)', l));
  perform pg_temp.x('Bob', format('public.sim_chain_clear(%s)', l));
  after_ := pg_temp.snap();
  -- l'unica differenza ammessa nel gioco: le righe di registro
  assert (select count(*) from public.sim_log where game_id = pg_temp.gid(l) and kind in ('activate','chain_res','chain_clear')) = 4, 'E6: 4 righe di registro (2 dichiarazioni, 1 risoluzione, 1 annullo)';
  delete from public.sim_log where game_id = pg_temp.gid(l) and kind in ('activate','chain_res','chain_clear','chain_end');
  assert pg_temp.snap() = before_, 'E6: carte, partite, wallet e registro contabile identici (tolte le righe di registro nuove)';
  s1 := pg_temp.s('Bob', l);
  assert s0->'cards' = s1->'cards' and s0->'counts' = s1->'counts' and s0->'game' = s1->'game', 'E6: carte e contatori identici';
  assert (select count(*) from public.sim_chain where game_id = pg_temp.gid(l)) = 0, 'E6: nessuna catena rimasta';
  assert (select count(*) from pg_proc p where p.proname in ('sim_activate','sim_chain_resolve','sim_chain_clear') and pg_get_function_arguments(p.oid) ilike '%seat%') = 0, 'E6: nessun posto fidato dal browser';
  -- i dati del log sono solo quelli pubblici
  assert not exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind in ('activate','chain_res') and exists (select 1 from jsonb_object_keys(data) k where k not in ('x','n','z','fl'))), 'E6: il registro non contiene altri campi';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK E6 isolamento');
end $$;

-- =====================================================================
-- E7 — modulo spento e catena che sopravvive alle altre azioni
-- =====================================================================
do $$
declare l bigint; s jsonb; ids integer[];
begin
  l := pg_temp.newmatch();
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[1])));
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova modulo');
  assert pg_temp.err_as('Ann', format('select public.sim_activate(%s, %s)', l, pg_temp.cid(l, ids[2]))) = 'Modulo non attivo', 'E7: modulo spento -> dichiarare rifiutato';
  assert pg_temp.err_as('Ann', format('select public.sim_chain_resolve(%s)', l)) = 'Modulo non attivo', 'E7: modulo spento -> risolvere rifiutato';
  assert pg_temp.err_as('Ann', format('select public.sim_chain_clear(%s)', l)) = 'Modulo non attivo', 'E7: modulo spento -> annullare rifiutato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova modulo');
  perform pg_temp.x('Ann', format('public.sim_phase(%s, ''main1'')', l));
  perform pg_temp.x('Ann', format('public.sim_draw(%s, 1)', l));
  s := pg_temp.s('Bob', l);
  assert jsonb_array_length(s->'chain') = 1, 'E7: pescare e cambiare fase non toccano la catena';
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''ok'')', l));
  assert jsonb_array_length(pg_temp.s('Bob', l)->'chain') = 1, 'E7: la chat non tocca la catena';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK E7 modulo e interazioni');
end $$;

select msg from t_log order by n;
rollback;
