-- =====================================================================
-- TEST DI «CHAT E SEGNALI» del Duel Simulator (black-market-duel-simulator-chat.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-duel-simulator.sql e black-market-duel-simulator-chat.sql.
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
-- C1 — tabella chiusa al browser, funzioni protette
-- =====================================================================
do $$
begin
  assert pg_temp.err_auth('Ann', 'select * from public.sim_chat') like '%permission denied%', 'C1: sim_chat non leggibile';
  assert pg_temp.err_auth('Ann', 'insert into public.sim_chat (lobby_id, n, seat, body) values (1, 1, 1, ''x'')') like '%permission denied%', 'C1: sim_chat non scrivibile';
  assert pg_temp.err_auth('Ann', 'delete from public.sim_chat') like '%permission denied%', 'C1: sim_chat non cancellabile';
  assert pg_temp.err_auth('Ann', 'update public.sim_players set sig = ''ok''') like '%permission denied%', 'C1: sim_players resta chiusa';
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.sim_chat_send(1, ''ciao'')') like '%Accesso richiesto%', 'C1: chat senza accesso rifiutata';
  assert pg_temp.err('select public.sim_signal(1, ''ok'')') like '%Accesso richiesto%', 'C1: segnale senza accesso rifiutato';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_chat_send','sim_signal') and grantee in ('anon','PUBLIC')) = 0, 'C1: nessun permesso ad anon/public';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_chat_send','sim_signal') and grantee = 'authenticated') = 2, 'C1: permessi a authenticated';
  insert into t_log (msg) values ('OK C1 permessi');
end $$;

-- =====================================================================
-- C2 — chat
-- =====================================================================
do $$
declare l bigint; s jsonb; t text; i integer; v0 bigint;
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(''Chat'')'))#>>'{}';
  s := pg_temp.x('Ann', format('public.sim_chat_send(%s, ''Ciao a tutti'')', l));
  assert s->'chat'->0->>'t' = 'Ciao a tutti' and (s->'chat'->0->>'seat')::int = 1 and (s->'chat'->0->>'n')::int = 1, 'C2: messaggio dell''host registrato';
  assert pg_temp.err_as('Cid', format('select public.sim_chat_send(%s, ''intruso'')', l)) = 'Non partecipi a questa partita', 'C2: l''estraneo non scrive';
  assert pg_temp.err_as('Cid', format('select public.sim_state(%s)', l)) = 'Non partecipi a questa partita', 'C2: l''estraneo non legge lo stato';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  assert pg_temp.err_as('Cid', format('select public.sim_chat_send(%s, ''intruso'')', l)) = 'Non partecipi a questa partita', 'C2: l''estraneo non scrive (lobby piena)';
  s := pg_temp.x('Bob', format('public.sim_chat_send(%s, %L)', l, '   Ciao Ann!  '));
  assert jsonb_array_length(s->'chat') = 2 and s->'chat'->1->>'t' = 'Ciao Ann!' and (s->'chat'->1->>'seat')::int = 2, 'C2: risposta di Bob, spazi tolti, posto 2';
  assert pg_temp.s('Ann', l)->'chat' = pg_temp.s('Bob', l)->'chat', 'C2: i due vedono la stessa chat';
  s := pg_temp.x('Ann', format('public.sim_chat_send(%s, %L)', l, E'riga1\nriga2\ttab'));
  assert s->'chat'->2->>'t' = 'riga1 riga2 tab', 'C2: a capo e tab diventano spazi';
  assert pg_temp.err_as('Ann', format('select public.sim_chat_send(%s, ''   '')', l)) = 'Scrivi qualcosa', 'C2: testo vuoto rifiutato';
  assert pg_temp.err_as('Ann', format('select public.sim_chat_send(%s, null)', l)) = 'Scrivi qualcosa', 'C2: null rifiutato';
  s := pg_temp.x('Bob', format('public.sim_chat_send(%s, %L)', l, repeat('x', 500)));
  assert char_length(s->'chat'->3->>'t') = 200, 'C2: tagliato a 200 caratteri';
  s := pg_temp.x('Ann', format('public.sim_chat_send(%s, %L)', l, '<b>x</b>'));
  assert s->'chat'->4->>'t' = '<b>x</b>', 'C2: testo conservato così com''è';
  v0 := (pg_temp.s('Ann', l)->>'v')::bigint;
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''v'')', l));
  assert (pg_temp.s('Ann', l)->>'v')::bigint > v0, 'C2: il numero di versione sale';
  assert (pg_temp.x('Ann', format('public.sim_state(%s, %s)', l, (pg_temp.s('Ann', l)->>'v'))))->>'same' = 'true', 'C2: senza novità risponde «same»';
  for i in 1..30 loop
    begin perform pg_temp.x('Bob', format('public.sim_chat_send(%s, %L)', l, 'm' || i)); exception when others then t := sqlerrm; exit; end;
  end loop;
  assert t = 'Troppi messaggi: aspetta qualche secondo', 'C2: limite di velocità';
  assert (select count(*) from public.sim_chat where lobby_id = l and seat = 2 and at > now() - interval '1 minute') = 20, 'C2: esattamente 20 messaggi di Bob nel minuto';
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''Ann può ancora scrivere'')', l));
  insert into public.sim_chat (lobby_id, n, seat, body, at)
    select l, 1000 + k, 1, 'vecchio ' || k, now() - interval '1 hour' from generate_series(1, 250) k;
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''ultimo'')', l));
  assert (select count(*) from public.sim_chat where lobby_id = l) = 200, 'C2: al massimo 200 messaggi';
  s := pg_temp.s('Bob', l);
  assert jsonb_array_length(s->'chat') = 80 and s->'chat'->79->>'t' = 'ultimo', 'C2: lo stato porta gli ultimi 80, in ordine';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova modulo');
  assert pg_temp.err_as('Ann', format('select public.sim_chat_send(%s, ''x'')', l)) = 'Modulo non attivo', 'C2: modulo spento -> chat rifiutata';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova modulo');
  perform pg_temp.x('Ann', 'public.sim_lobby_leave(' || l || ')');
  assert (select status from public.sim_lobbies where id = l) = 'cancelled', 'C2: lobby chiusa dall''host';
  assert pg_temp.err_as('Bob', format('select public.sim_chat_send(%s, ''x'')', l)) = 'La partita è chiusa', 'C2: lobby chiusa -> chat rifiutata';
  insert into t_log (msg) values ('OK C2 chat');
end $$;

-- =====================================================================
-- C3 — segnali Penso / OK
-- =====================================================================
do $$
declare l bigint; s jsonb; pa jsonb; pb jsonb; gs timestamptz; v0 bigint;
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(''Segnali'')'))#>>'{}';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  assert pg_temp.err_as('Ann', format('select public.sim_signal(%s, ''think'')', l)) = 'Il duello non è in corso', 'C3: in lobby non si segnala';
  perform pg_temp.x('Ann', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA')));
  perform pg_temp.x('Bob', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckB')));
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)'); perform pg_temp.x('Bob', 'public.sim_set_ready(' || l || ', true)');
  s := pg_temp.x('Ann', 'public.sim_start(' || l || ')');
  assert pg_temp.err_as('Ann', format('select public.sim_signal(%s, ''think'')', l)) = 'Il duello non è in corso', 'C3: prima della scelta di chi inizia non si segnala';
  perform pg_temp.x(case when (s#>>'{game,chooser}')::int = 1 then 'Ann' else 'Bob' end, 'public.sim_choose_first(' || l || ', 1::smallint)');
  s := pg_temp.s('Bob', l);
  assert (select count(*) from jsonb_array_elements(s->'players') p where p->>'sig' is not null) = 0, 'C3: all''inizio nessun segnale';
  gs := null; v0 := (pg_temp.s('Bob', l)->>'v')::bigint;
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''think'')', l));
  assert (pg_temp.s('Bob', l)->>'v')::bigint > v0, 'C3: il segnale fa salire il numero di versione';
  pb := pg_temp.s('Bob', l); pa := pg_temp.s('Ann', l);
  assert (select p->>'sig' from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 1) = 'think', 'C3: Bob vede che Ann pensa';
  assert (select p->>'sig' from jsonb_array_elements(pa->'players') p where (p->>'seat')::int = 1) = 'think', 'C3: Ann vede il proprio «penso»';
  assert (select p->>'sig' from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 2) is null, 'C3: Bob non risulta pensare';
  assert (select (p->>'sig_n')::int from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 1) = 1, 'C3: contatore del segnale = 1';
  perform pg_temp.x('Bob', format('public.sim_signal(%s, ''ok'')', l));
  pa := pg_temp.s('Ann', l);
  assert (select p->>'sig' from jsonb_array_elements(pa->'players') p where (p->>'seat')::int = 2) = 'ok', 'C3: Ann vede l''OK di Bob';
  assert (select p->>'sig' from jsonb_array_elements(pa->'players') p where (p->>'seat')::int = 1) = 'think', 'C3: l''OK di Bob non spegne il penso di Ann';
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''ok'')', l));
  pb := pg_temp.s('Bob', l);
  assert (select p->>'sig' from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 1) = 'ok', 'C3: l''OK sostituisce il penso';
  assert (select (p->>'sig_n')::int from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 1) = 2, 'C3: contatore sale a 2';
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''think'')', l));
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''clear'')', l));
  pb := pg_temp.s('Bob', l);
  assert (select p->>'sig' from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 1) is null, 'C3: clear spegne il segnale';
  assert (select (p->>'sig_n')::int from jsonb_array_elements(pb->'players') p where (p->>'seat')::int = 1) = 4, 'C3: il contatore sale anche con clear';
  assert pg_temp.err_as('Ann', format('select public.sim_signal(%s, ''boh'')', l)) = 'Segnale non valido', 'C3: tipo non valido';
  assert pg_temp.err_as('Ann', format('select public.sim_signal(%s, null)', l)) = 'Segnale non valido', 'C3: tipo null';
  assert pg_temp.err_as('Cid', format('select public.sim_signal(%s, ''ok'')', l)) = 'Non partecipi a questa partita', 'C3: l''estraneo non segnala';
  update public.sim_games set started_at = now() - interval '1 hour' where lobby_id = l and no = 1;   -- la prova gira in una sola transazione: sposto indietro l'inizio del duello
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''think'')', l));
  update public.sim_players set sig_at = now() - interval '4 minutes' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) = 'think', 'C3: dopo 4 minuti pensa ancora';
  update public.sim_players set sig_at = now() - interval '6 minutes' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) is null, 'C3: dopo 6 minuti il penso scade';
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''ok'')', l));
  update public.sim_players set sig_at = now() - interval '5 seconds' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) = 'ok', 'C3: dopo 5 secondi l''OK c''è ancora';
  update public.sim_players set sig_at = now() - interval '13 seconds' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) is null, 'C3: dopo 13 secondi l''OK scade';
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''think'')', l));
  update public.sim_games set started_at = now() - interval '1 minute' where lobby_id = l and no = 1;
  select started_at into gs from public.sim_games where lobby_id = l and no = 1;
  update public.sim_players set sig_at = gs - interval '1 minute' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) is null, 'C3: segnale di prima del duello ignorato (ancora dentro i 5 minuti)';
  update public.sim_players set sig_at = gs + interval '10 seconds' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) = 'think', 'C3: segnale dopo l''inizio del duello visibile';
  update public.sim_players set sig_at = gs - interval '1 minute' where lobby_id = l and seat = 1;
  assert (select p->>'sig' from jsonb_array_elements(pg_temp.s('Bob', l)->'players') p where (p->>'seat')::int = 1) is null, 'C3: segnale di prima del duello ignorato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova modulo');
  assert pg_temp.err_as('Ann', format('select public.sim_signal(%s, ''ok'')', l)) = 'Modulo non attivo', 'C3: modulo spento -> segnale rifiutato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova modulo');
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK C3 segnali');
end $$;

-- =====================================================================
-- C4 — isolamento: chat e segnali non toccano né carte, né registro, né BC
-- =====================================================================
do $$
declare l bigint; before_ text; after_ text; s0 jsonb; s1 jsonb;
begin
  l := pg_temp.newmatch();
  s0 := pg_temp.s('Bob', l);
  before_ := pg_temp.snap();
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''gg'')', l));
  perform pg_temp.x('Bob', format('public.sim_chat_send(%s, ''wp'')', l));
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''think'')', l));
  perform pg_temp.x('Bob', format('public.sim_signal(%s, ''ok'')', l));
  perform pg_temp.x('Ann', format('public.sim_signal(%s, ''clear'')', l));
  after_ := pg_temp.snap();
  assert before_ = after_, 'C4: carte, registro, partite, wallet e registro contabile invariati';
  s1 := pg_temp.s('Bob', l);
  assert s0->'cards' = s1->'cards' and s0->'log' = s1->'log' and s0->'counts' = s1->'counts' and s0->'game' = s1->'game', 'C4: lo stato di gioco è identico (carte, registro, contatori, partita)';
  assert (select count(*) from public.sim_log where kind in ('say', 'chat', 'signal')) = 0, 'C4: nessuna riga di registro per chat e segnali';
  assert not exists (select 1 from jsonb_array_elements(s1->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1), 'C4: Bob non vede la mano di Ann';
  assert (select count(*) from pg_proc p where p.proname in ('sim_chat_send','sim_signal') and pg_get_function_arguments(p.oid) ilike '%seat%') = 0, 'C4: nessun parametro «posto» fidato dal browser';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK C4 isolamento');
end $$;

-- =====================================================================
-- C5 — la chat continua tra un duello e l'altro e a fine incontro
-- =====================================================================
do $$
declare l bigint; s jsonb;
begin
  l := pg_temp.newmatch();
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''duello 1'')', l));
  perform pg_temp.x('Bob', format('public.sim_concede(%s)', l));
  s := pg_temp.s('Ann', l);
  assert s->'lobby'->>'status' = 'siding', 'C5: dopo la resa si passa al side';
  perform pg_temp.x('Bob', format('public.sim_chat_send(%s, ''ok per il side'')', l));
  s := pg_temp.s('Ann', l);
  assert jsonb_array_length(s->'chat') = 2, 'C5: la chat sopravvive al side';
  perform pg_temp.x('Bob', format('public.sim_lobby_leave(%s)', l));
  s := pg_temp.s('Ann', l);
  assert s->'lobby'->>'status' = 'finished', 'C5: incontro finito per abbandono';
  perform pg_temp.x('Ann', format('public.sim_chat_send(%s, ''bella partita'')', l));
  assert jsonb_array_length(pg_temp.s('Ann', l)->'chat') = 3, 'C5: si può salutare a incontro finito';
  insert into t_log (msg) values ('OK C5 chat tra i duelli');
end $$;

-- =====================================================================
-- C6 — mischia mano
-- =====================================================================
do $$
declare l bigint; s jsonb; ids0 integer[]; ids1 integer[]; ord0 text; ord1 text; changed boolean := false; seen text[] := '{}'; v0 bigint; i integer; sb0 jsonb; before_ text; other0 text;
begin
  assert (select count(*) from information_schema.routine_privileges where routine_name = 'sim_shuffle_hand' and grantee in ('anon','PUBLIC')) = 0, 'C6: nessun permesso ad anon/public';
  assert (select count(*) from information_schema.routine_privileges where routine_name = 'sim_shuffle_hand' and grantee = 'authenticated') = 1, 'C6: permesso a authenticated';
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.sim_shuffle_hand(1)') like '%Accesso richiesto%', 'C6: senza accesso rifiutato';
  l := pg_temp.newmatch();
  s := pg_temp.s('Ann', l);
  select array_agg((c->>'i')::int order by (c->>'k')::int), string_agg(c->>'i', ',' order by (c->>'k')::int) into ids0, ord0
    from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  assert array_length(ids0, 1) = 5, 'C6: Ann ha 5 carte in mano';
  sb0 := pg_temp.s('Bob', l);
  other0 := (select string_agg(c::text, ',' order by c.id) from public.sim_cards c where c.game_id = (select id from public.sim_games where lobby_id = l and no = 1) and not (c.owner = 1 and c.zone = 'hand'));
  before_ := pg_temp.snap();
  v0 := (pg_temp.s('Ann', l)->>'v')::bigint;
  for i in 1..40 loop
    s := pg_temp.x('Ann', format('public.sim_shuffle_hand(%s)', l));
    select array_agg((c->>'i')::int order by (c->>'k')::int), string_agg(c->>'i', ',' order by (c->>'k')::int) into ids1, ord1
      from jsonb_array_elements(s->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
    assert (select array_agg(x order by x) from unnest(ids0) x) = (select array_agg(x order by x) from unnest(ids1) x), 'C6: stesse carte in mano dopo il mischia';
    if ord1 <> ord0 then changed := true; end if;
    if not ord1 = any(seen) then seen := seen || ord1; end if;
  end loop;
  assert (pg_temp.s('Bob', l)->>'v')::bigint >= v0 + 40, 'C6: ogni mischia fa salire il numero di versione (l''avversario se ne accorge)';
  assert changed, 'C6: l''ordine cambia davvero';
  assert cardinality(seen) >= 10, 'C6: ordini diversi a ogni mischia (a caso, non sempre lo stesso)';
  assert (select array_agg(ord order by ord) from public.sim_cards where game_id = (select id from public.sim_games where lobby_id = l and no = 1) and owner = 1 and zone = 'hand') = array[1,2,3,4,5], 'C6: ordine 1..5 senza buchi né doppioni';
  assert other0 = (select string_agg(c::text, ',' order by c.id) from public.sim_cards c where c.game_id = (select id from public.sim_games where lobby_id = l and no = 1) and not (c.owner = 1 and c.zone = 'hand')), 'C6: tutte le altre carte (anche l''altra mano) invariate';
  assert pg_temp.s('Bob', l)->'cards' = sb0->'cards' and pg_temp.s('Bob', l)->'counts' = sb0->'counts', 'C6: Bob non vede nulla di diverso nelle carte';
  assert (select count(*) from public.sim_log where game_id = (select id from public.sim_games where lobby_id = l and no = 1) and kind = 'shuffle_hand' and seat = 1) = 40, 'C6: una riga di registro per mischia';
  assert (select data from public.sim_log where kind = 'shuffle_hand' limit 1) = '{}'::jsonb, 'C6: il registro non porta alcuna informazione sulle carte';
  assert (select count(*) from jsonb_array_elements(pg_temp.s('Bob', l)->'log') e where e->>'kind' = 'shuffle_hand') > 0, 'C6: Bob vede nel registro che Ann ha mischiato';
  assert pg_temp.err_as('Cid', format('select public.sim_shuffle_hand(%s)', l)) = 'Non partecipi a questa partita', 'C6: l''estraneo non mischia';
  perform pg_temp.x('Bob', format('public.sim_shuffle_hand(%s)', l));
  assert (select array_agg(ord order by ord) from public.sim_cards where game_id = (select id from public.sim_games where lobby_id = l and no = 1) and owner = 2 and zone = 'hand') = array[1,2,3,4,5], 'C6: anche Bob mischia la sua mano';
  assert (select string_agg(c.id::text, ',' order by c.ord) from public.sim_cards c where c.game_id = (select id from public.sim_games where lobby_id = l and no = 1) and c.owner = 1 and c.zone = 'hand') = ord1, 'C6: il mischia di Bob non tocca la mano di Ann';
  perform pg_temp.x('Ann', format('public.sim_draw(%s, 1)', l));
  assert (select max(ord) from public.sim_cards where game_id = (select id from public.sim_games where lobby_id = l and no = 1) and owner = 1 and zone = 'hand') = 6, 'C6: la carta pescata dopo il mischia va in fondo alla mano';
  perform pg_temp.x('Ann', format('public.sim_reveal(%s, %s, true)', l, ids0[1]));
  perform pg_temp.x('Ann', format('public.sim_shuffle_hand(%s)', l));
  assert (select revealed from public.sim_cards where game_id = (select id from public.sim_games where lobby_id = l and no = 1) and id = ids0[1]) , 'C6: la carta mostrata resta mostrata';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova modulo');
  assert pg_temp.err_as('Ann', format('select public.sim_shuffle_hand(%s)', l)) = 'Modulo non attivo', 'C6: modulo spento -> rifiutato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova modulo');
  perform pg_temp.endmatch(l);
  assert pg_temp.err_as('Ann', format('select public.sim_shuffle_hand(%s)', l)) in ('Il duello non è in corso', 'Non è il momento del side deck'), 'C6: a duello finito non si mischia';
  insert into t_log (msg) values ('OK C6 mischia mano');
end $$;

select msg from t_log order by n;
rollback;
