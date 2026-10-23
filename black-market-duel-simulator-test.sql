-- =====================================================================
-- TEST DELLA MIGRAZIONE 025 (Duel Simulator)
-- Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…025 (black-market-setup.sql … black-market-duel-simulator.sql).
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

-- istantanea di TUTTO ciò che appartiene a Black Market, Ladder, eroi, taglie e notifiche (deve restare identica)
create function pg_temp.snap() returns text language sql as $$
  select md5(
    coalesce((select string_agg(w::text, ',' order by user_id) from public.wallets w), '') || '|' ||
    coalesce((select string_agg(e::text, ',' order by id) from public.ledger_entries e), '') || '|' ||
    coalesce((select string_agg(m::text, ',' order by id) from public.matches m), '') || '|' ||
    coalesce((select string_agg(m::text, ',' order by id) from public.ladder_matches m), '') || '|' ||
    coalesce((select string_agg(m::text, ',' order by user_id, format) from public.ladder_ratings m), '') || '|' ||
    coalesce((select string_agg(b::text, ',' order by id) from public.bounties b), '') || '|' ||
    coalesce((select string_agg(b::text, ',' order by id) from public.bounty_settlements b), '') || '|' ||
    coalesce((select string_agg(h::text, ',' order by user_id) from public.game_heroes h), '') || '|' ||
    coalesce((select string_agg(h::text, ',' order by user_id) from public.game_rewards h), '') || '|' ||
    coalesce((select string_agg(h::text, ',' order by id) from public.notifications h), '') || '|' ||
    coalesce((select string_agg(h::text, ',' order by id) from public.audit_logs h), '') || '|' ||
    coalesce((select string_agg(h::text, ',' order by id) from public.events h), '') || '|' ||
    coalesce((select string_agg(h::text, ',' order by id) from public.profiles h), '')) $$;

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

-- =====================================================================
-- D1 — modulo, permessi, tabelle chiuse al browser
-- =====================================================================
do $$
declare t text; r jsonb;
begin
  assert (select value_int from public.system_settings where key = 'module_duel') = 1, 'D1: modulo acceso di default';
  -- il browser non vede nessuna tabella sim_* (né in lettura né in scrittura)
  foreach t in array array['sim_decks','sim_lobbies','sim_players','sim_games','sim_cards','sim_log'] loop
    assert pg_temp.err_auth('Ann', 'select * from public.' || t) like '%permission denied%', 'D1: ' || t || ' non leggibile';
    assert pg_temp.err_auth('Ann', 'delete from public.' || t) like '%permission denied%', 'D1: ' || t || ' non scrivibile';
  end loop;
  assert pg_temp.err_auth('Ann', 'insert into public.sim_decks (owner_id, name) values (''' || pg_temp.uid('Ann') || ''', ''x'')') like '%permission denied%', 'D1: insert diretto vietato';
  -- le funzioni di servizio non sono chiamabili
  assert pg_temp.err_auth('Ann', 'select public._sim_state(1, ''' || pg_temp.uid('Ann') || ''')') like '%permission denied%', 'D1: _sim_state non esposta';
  assert pg_temp.err_auth('Ann', 'select public._sim_finish_game(1, 1, ''x'')') like '%permission denied%', 'D1: _sim_finish_game non esposta';
  -- senza accesso
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.sim_home()') like '%Accesso richiesto%', 'D1: senza accesso rifiuta';
  -- modulo spento
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova modulo');
  assert pg_temp.err_as('Ann', 'select public.sim_home()') = 'Modulo non attivo', 'D1: modulo spento -> home rifiutata';
  assert pg_temp.err_as('Ann', 'select public.sim_lobby_create(null)') = 'Modulo non attivo', 'D1: modulo spento -> lobby rifiutata';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''x'', ''{}'', ''{}'', ''{}'', false)') = 'Modulo non attivo', 'D1: modulo spento -> deck rifiutato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova modulo');
  assert pg_temp.err_as('Ann', 'select public.admin_set_module(''duel'', false, ''abuso da utente'')') like '%Permessi insufficienti%', 'D1: solo l''admin accende il modulo';
  assert pg_temp.err_as('Admin', 'select public.admin_set_module(''altro'', false, ''motivo valido'')') = 'Modulo sconosciuto', 'D1: modulo sconosciuto rifiutato';
  -- gli altri moduli continuano a funzionare con la nuova versione di admin_set_module
  perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', true, 'prova ancora');
  -- tutti i ruoli giocano
  foreach t in array array['Ann','Org','Mod','Admin'] loop
    assert pg_temp.err_as(t, 'select public.sim_home()') is null, 'D1: ' || t || ' può usare il simulatore';
  end loop;
  -- sospeso
  update public.profiles set suspended = true where id = pg_temp.uid('Dan');
  assert pg_temp.err_as('Dan', 'select public.sim_home()') like '%sospeso%', 'D1: sospeso escluso';
  update public.profiles set suspended = false where id = pg_temp.uid('Dan');
  insert into t_log (msg) values ('OK D1 — tabelle chiuse al browser, modulo acceso/spento, ruoli, sospesi');
end $$;

-- =====================================================================
-- D2 — libreria deck
-- =====================================================================
do $$
declare r jsonb; d uuid; h jsonb; i integer;
begin
  d := pg_temp.mkdeck('Ann', 'Deck Ann', 10000);
  insert into t_ctx values ('deckA', d::text);
  insert into t_ctx values ('deckB', pg_temp.mkdeck('Bob', 'Deck Bob', 20000)::text);
  h := pg_temp.x('Ann', 'public.sim_home()');
  assert jsonb_array_length(h->'decks') = 1 and (h#>>'{decks,0,name}') = 'Deck Ann', 'D2: il deck compare in libreria';
  assert jsonb_array_length(h#>'{decks,0,main}') = 40 and jsonb_array_length(h#>'{decks,0,extra}') = 3 and jsonb_array_length(h#>'{decks,0,side}') = 2, 'D2: contenuto del deck';
  h := pg_temp.x('Bob', 'public.sim_home()');
  assert jsonb_array_length(h->'decks') = 1 and (h#>>'{decks,0,name}') = 'Deck Bob', 'D2: ognuno vede solo i propri deck';
  -- regole di formato
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Quattro'', array[1,1,1,1], ''{}'', ''{}'', false)') like '%più di 3 copie%', 'D2: 4 copie rifiutate';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Tre+1'', array[1,1], array[1], array[1], false)') like '%più di 3 copie%', 'D2: le copie si contano su Main+Extra+Side';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Tre'', array[1,1,1], ''{}'', ''{}'', false)') is null, 'D2: 3 copie ok';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''M61'', (select array_agg(k) from generate_series(1,61) k), ''{}'', ''{}'', false)') like '%60%', 'D2: Main oltre 60';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''E16'', ''{}'', (select array_agg(k) from generate_series(1,16) k), ''{}'', false)') like '%15%', 'D2: Extra oltre 15';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''S16'', ''{}'', ''{}'', (select array_agg(k) from generate_series(1,16) k), false)') like '%15%', 'D2: Side oltre 15';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Z'', array[0], ''{}'', ''{}'', false)') like '%non valido%', 'D2: codice 0 rifiutato';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Z'', array[-5], ''{}'', ''{}'', false)') like '%non valido%', 'D2: codice negativo rifiutato';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Z'', array[null::int], ''{}'', ''{}'', false)') like '%non valido%', 'D2: codice nullo rifiutato';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''  '', array[1], ''{}'', ''{}'', false)') like '%nome%', 'D2: nome vuoto';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, repeat(''a'', 41), array[1], ''{}'', ''{}'', false)') like '%nome%', 'D2: nome troppo lungo';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''deck ann'', array[1], ''{}'', ''{}'', false)') like '%già un deck con questo nome%', 'D2: nome doppio (senza badare alle maiuscole)';
  assert pg_temp.err_as('Bob', 'select public.sim_deck_save(null, ''Deck Ann'', array[1], ''{}'', ''{}'', false)') is null, 'D2: lo stesso nome su un altro profilo va bene';
  -- modifica: solo il proprietario
  assert pg_temp.err_as('Bob', format('select public.sim_deck_save(%L, ''Rubato'', array[1], ''{}'', ''{}'', false)', d)) = 'Deck non trovato', 'D2: non si modifica il deck altrui';
  assert pg_temp.err_as('Bob', format('select public.sim_deck_delete(%L)', d)) = 'Deck non trovato', 'D2: non si cancella il deck altrui';
  assert pg_temp.err_as('Ann', format('select public.sim_deck_save(%L, ''Deck Ann 2'', array[1,2,3], ''{}'', ''{}'', false)', d)) is null, 'D2: modifica propria';
  assert (select name from public.sim_decks where id = d) = 'Deck Ann 2', 'D2: nome aggiornato';
  perform pg_temp.x('Ann', format('public.sim_deck_save(%L, ''Deck Ann'', (select array_agg(10000 + k) from generate_series(1, 40) k), array[10501,10502,10503], array[10801,10802], false)', d));
  -- deck temporaneo: non compare in libreria
  r := pg_temp.x('Ann', 'public.sim_deck_save(null, ''Temp'', array[1,2], ''{}'', ''{}'', true)');
  h := pg_temp.x('Ann', 'public.sim_home()');
  assert jsonb_array_length(h->'decks') = 2 and jsonb_array_length(h->'temp_decks') = 1, 'D2: deck temporaneo separato';
  -- limite
  update public.system_settings set value_int = 3 where key = 'sim_max_decks';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Quarto'', array[1], ''{}'', ''{}'', false)') is null, 'D2: sotto il limite';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Quinto'', array[1], ''{}'', ''{}'', false)') like '%massimo di 3%', 'D2: limite di deck in libreria';
  assert pg_temp.err_as('Ann', 'select public.sim_deck_save(null, ''Temp2'', array[1], ''{}'', ''{}'', true)') is null, 'D2: i temporanei non contano nel limite';
  update public.system_settings set value_int = 30 where key = 'sim_max_decks';
  -- cancellazione
  perform pg_temp.x('Ann', format('public.sim_deck_delete(%L)', (select id from public.sim_decks where owner_id = pg_temp.uid('Ann') and name = 'Quarto')));
  perform pg_temp.x('Ann', format('public.sim_deck_delete(%L)', (select id from public.sim_decks where owner_id = pg_temp.uid('Ann') and name = 'Tre')));
  assert (select count(*) from public.sim_decks where owner_id = pg_temp.uid('Ann') and not temp) = 1, 'D2: cancellazione';
  delete from public.sim_decks where owner_id = pg_temp.uid('Ann') and name <> 'Deck Ann';
  delete from public.sim_decks where owner_id = pg_temp.uid('Bob') and name <> 'Deck Bob';
  insert into t_log (msg) values ('OK D2 — libreria deck: formato, 3 copie, nomi, proprietà, limite, temporanei');
end $$;

-- =====================================================================
-- D3 — lobby: crea, entra, esci, caccia
-- =====================================================================
do $$
declare l bigint; h jsonb; s jsonb; l2 bigint;
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(''La mia sfida'')'))#>>'{}';
  assert pg_temp.err_as('Ann', 'select public.sim_lobby_create(null)') like '%già in una lobby%', 'D3: una lobby alla volta';
  assert pg_temp.err_as('Ann', 'select public.sim_lobby_create(repeat(''t'', 31))') like '%30 caratteri%' or pg_temp.err_as('Bob', 'select public.sim_lobby_create(repeat(''t'', 31))') like '%30 caratteri%', 'D3: titolo troppo lungo';
  h := pg_temp.x('Bob', 'public.sim_home()');
  assert jsonb_array_length(h->'lobbies') = 1 and (h#>>'{lobbies,0,nickname}') = 'Ann' and (h#>>'{lobbies,0,title}') = 'La mia sfida', 'D3: la lobby è visibile agli altri';
  h := pg_temp.x('Ann', 'public.sim_home()');
  assert jsonb_array_length(h->'lobbies') = 0 and (h->>'mine')::bigint = l, 'D3: l''host non vede la propria lobby nell''elenco ma sa qual è';
  assert pg_temp.err_as('Ann', 'select public.sim_lobby_join(' || l || ')') like '%già in una lobby%', 'D3: l''host non entra nella propria lobby';
  assert pg_temp.err_as('Bob', 'select public.sim_lobby_join(99999)') = 'Lobby inesistente', 'D3: lobby inesistente';
  s := pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  assert (s#>>'{me,seat}')::int = 2 and jsonb_array_length(s->'players') = 2, 'D3: Bob entra al posto 2';
  assert pg_temp.err_as('Cid', 'select public.sim_lobby_join(' || l || ')') like '%non è più disponibile%' or pg_temp.err_as('Cid', 'select public.sim_lobby_join(' || l || ')') like '%piena%', 'D3: lobby piena';
  assert jsonb_array_length((pg_temp.x('Cid', 'public.sim_home()'))->'lobbies') = 0, 'D3: la lobby piena sparisce dall''elenco';
  assert pg_temp.err_as('Cid', 'select public.sim_state(' || l || ')') like '%Non partecipi%', 'D3: un estraneo non vede lo stato';
  assert pg_temp.err_as('Cid', 'select public.sim_set_ready(' || l || ', true)') like '%Non partecipi%', 'D3: un estraneo non agisce';
  assert pg_temp.err_as('Bob', 'select public.sim_lobby_kick(' || l || ')') like '%Solo chi ha creato%', 'D3: solo l''host caccia';
  s := pg_temp.x('Ann', 'public.sim_lobby_kick(' || l || ')');
  assert jsonb_array_length(s->'players') = 1, 'D3: Bob cacciato';
  assert not exists (select 1 from public.sim_players where user_id = pg_temp.uid('Bob') and active), 'D3: Bob libero di nuovo';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  perform pg_temp.x('Bob', 'public.sim_lobby_leave(' || l || ')');
  assert (select count(*) from public.sim_players where lobby_id = l) = 1, 'D3: il guest esce';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  perform pg_temp.x('Ann', 'public.sim_lobby_leave(' || l || ')');
  assert (select status from public.sim_lobbies where id = l) = 'cancelled', 'D3: se esce l''host la lobby si chiude';
  assert pg_temp.err_as('Bob', 'select public.sim_state(' || l || ')') is null, 'D3: gli ex partecipanti leggono ancora lo stato';
  assert (pg_temp.s('Bob', l)#>>'{lobby,status}') = 'cancelled', 'D3: Bob vede la lobby annullata';
  assert not exists (select 1 from public.sim_players where lobby_id = l and active), 'D3: nessuno resta bloccato';
  -- ruoli diversi
  l2 := (pg_temp.x('Mod', 'public.sim_lobby_create(null)'))#>>'{}';
  perform pg_temp.x('Org', 'public.sim_lobby_join(' || l2 || ')');
  perform pg_temp.x('Org', 'public.sim_lobby_leave(' || l2 || ')'); perform pg_temp.x('Mod', 'public.sim_lobby_leave(' || l2 || ')');
  insert into t_log (msg) values ('OK D3 — lobby: creazione, ingresso, lobby piena, estranei esclusi, caccia, uscita');
end $$;

-- =====================================================================
-- D4 — scelta del deck, PRONTO, avvio
-- =====================================================================
do $$
declare l bigint; s jsonb; short uuid; i integer; pa jsonb;
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(null)'))#>>'{}';
  assert pg_temp.err_as('Ann', 'select public.sim_set_ready(' || l || ', true)') like '%Scegli prima un deck%', 'D4: PRONTO richiede un deck';
  perform pg_temp.x('Ann', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA')));
  assert pg_temp.err_as('Ann', 'select public.sim_set_ready(' || l || ', true)') like '%avversario%', 'D4: PRONTO richiede l''avversario';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  assert pg_temp.err_as('Bob', format('select public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA'))) = 'Deck non trovato', 'D4: non si usa il deck altrui';
  short := pg_temp.mkdeck('Bob', 'Corto', 30000, 39);
  perform pg_temp.x('Bob', format('public.sim_set_deck(%s, %L)', l, short));
  assert pg_temp.err_as('Bob', 'select public.sim_set_ready(' || l || ', true)') like '%almeno 40%', 'D4: Main sotto le 40 carte non può essere PRONTO';
  perform pg_temp.x('Bob', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckB')));
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)');
  assert pg_temp.err_as('Ann', 'select public.sim_start(' || l || ')') like '%PRONTI%', 'D4: non si parte senza entrambi PRONTI';
  -- l'avversario non vede quale deck ho scelto
  s := pg_temp.s('Bob', l);
  assert (s#>>'{players,0,deck_id}') is null and (s#>>'{players,0,deck_name}') is null and (s#>>'{players,0,deck_set}')::boolean, 'D4: Bob sa che Ann ha scelto, ma non quale deck';
  assert (s#>>'{players,1,deck_name}') = 'Deck Bob', 'D4: Bob vede il proprio deck';
  -- cambiare deck toglie il PRONTO; anche modificarlo
  perform pg_temp.x('Ann', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA')));
  assert not (select ready from public.sim_players where lobby_id = l and seat = 1), 'D4: cambiare deck toglie il PRONTO';
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)');
  perform pg_temp.x('Ann', format('public.sim_deck_save(%L, ''Deck Ann'', (select array_agg(10000 + k) from generate_series(1, 40) k), array[10501,10502,10503], array[10801,10802], false)', (select v from t_ctx where k = 'deckA')));
  assert not (select ready from public.sim_players where lobby_id = l and seat = 1), 'D4: modificare il deck scelto toglie il PRONTO';
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)');
  perform pg_temp.x('Bob', 'public.sim_set_ready(' || l || ', true)');
  assert pg_temp.err_as('Bob', 'select public.sim_start(' || l || ')') like '%Solo chi ha creato%', 'D4: solo l''host avvia';
  assert pg_temp.err_as('Ann', 'select public.sim_draw(' || l || ', 1)') like '%non è in corso%', 'D4: niente mosse prima dell''avvio';
  -- un deck cancellato mentre si è nella lobby toglie la scelta
  s := pg_temp.x('Ann', 'public.sim_start(' || l || ')');
  assert (s#>>'{lobby,status}') = 'playing' and (s#>>'{lobby,game_no}')::int = 1 and (s#>>'{game,status}') = 'choosing', 'D4: partita avviata, si sceglie chi inizia';
  assert (s#>>'{game,chooser}')::int in (1, 2), 'D4: sceglie uno dei due';
  assert pg_temp.err_as('Ann', 'select public.sim_start(' || l || ')') like '%già iniziata%', 'D4: non si avvia due volte';
  assert (select cfg_main is not null from public.sim_players where lobby_id = l and seat = 1), 'D4: deck copiato nell''incontro';
  -- la modifica del deck dopo l'avvio non cambia la partita
  perform pg_temp.x('Ann', format('public.sim_deck_save(%L, ''Deck Ann'', array[1,2,3], ''{}'', ''{}'', false)', (select v from t_ctx where k = 'deckA')));
  assert cardinality((select cfg_main from public.sim_players where lobby_id = l and seat = 1)) = 40, 'D4: la copia dell''incontro non cambia';
  perform pg_temp.x('Ann', format('public.sim_deck_save(%L, ''Deck Ann'', (select array_agg(10000 + k) from generate_series(1, 40) k), array[10501,10502,10503], array[10801,10802], false)', (select v from t_ctx where k = 'deckA')));
  perform pg_temp.endmatch(l);
  delete from public.sim_decks where id = short;
  insert into t_log (msg) values ('OK D4 — scelta deck, PRONTO, avvio solo dell''host, deck dell''avversario nascosto');
end $$;

-- =====================================================================
-- D5/D6 — inizio del duello e INFORMAZIONI NASCOSTE
-- =====================================================================
do $$
declare l bigint; s jsonb; sa jsonb; sb jsonb; ch text; oth text; cr record; bob_hand integer; n integer; ids integer[];
begin
  l := (pg_temp.x('Ann', 'public.sim_lobby_create(null)'))#>>'{}';
  perform pg_temp.x('Bob', 'public.sim_lobby_join(' || l || ')');
  perform pg_temp.x('Ann', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckA')));
  perform pg_temp.x('Bob', format('public.sim_set_deck(%s, %L)', l, (select v from t_ctx where k = 'deckB')));
  perform pg_temp.x('Ann', 'public.sim_set_ready(' || l || ', true)'); perform pg_temp.x('Bob', 'public.sim_set_ready(' || l || ', true)');
  s := pg_temp.x('Ann', 'public.sim_start(' || l || ')');
  ch := case when (s#>>'{game,chooser}')::int = 1 then 'Ann' else 'Bob' end; oth := case when ch = 'Ann' then 'Bob' else 'Ann' end;
  assert pg_temp.err_as(oth, format('select public.sim_choose_first(%s, 1::smallint)', l)) like '%Non tocca a te%', 'D5: sceglie solo chi ne ha diritto';
  assert pg_temp.err_as(ch, format('select public.sim_choose_first(%s, 3::smallint)', l)) like '%non valida%', 'D5: scelta non valida';
  assert pg_temp.err_as(ch, format('select public.sim_draw(%s, 1)', l)) like '%non è in corso%', 'D5: niente mosse prima della scelta';
  s := pg_temp.x(ch, format('public.sim_choose_first(%s, 2::smallint)', l));
  assert (s#>>'{game,status}') = 'playing' and (s#>>'{game,first}')::int = 2 and (s#>>'{game,turn_seat}')::int = 2 and (s#>>'{game,phase}') = 'draw' and (s#>>'{game,turn_no}')::int = 1, 'D5: inizia chi è stato scelto';
  assert (s#>>'{game,lp,0}')::int = 8000 and (s#>>'{game,lp,1}')::int = 8000, 'D5: 8000 LP a testa';
  assert pg_temp.err_as(ch, format('select public.sim_choose_first(%s, 1::smallint)', l)) like '%già iniziato%', 'D5: non si sceglie due volte';
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand') = 5 and (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand') = 5, 'D5: 5 carte in mano a testa';
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck') = 35 and (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'extra') = 3, 'D5: 35 nel deck e 3 nell''Extra';
  -- gli id sono casuali: non ripetono l'ordine del deck
  assert (select count(distinct id) from public.sim_cards where game_id = pg_temp.gid(l)) = 86, 'D5: 86 carte con id diversi';
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and code = 10001 + (id - 1) % 40 and id <= 40) < 40, 'D5: gli id non seguono l''ordine delle carte';

  -- D6: cosa vede Ann (posto 1) di Bob (posto 2)
  sa := pg_temp.s('Ann', l); sb := pg_temp.s('Bob', l);
  assert not exists (select 1 from jsonb_array_elements(sa->'cards') c where (c->>'x')::int between 20000 and 29999), 'D6: Ann non vede nessuna carta di Bob';
  assert not exists (select 1 from jsonb_array_elements(sb->'cards') c where (c->>'x')::int between 10000 and 19999), 'D6: Bob non vede nessuna carta di Ann';
  assert not exists (select 1 from jsonb_array_elements(sa->'cards') c where c->>'z' = 'deck'), 'D6: il deck non esce mai (nemmeno il proprio)';
  assert not exists (select 1 from jsonb_array_elements(sa->'cards') c where (c->>'o')::int = 2 and c->>'z' in ('hand', 'extra')), 'D6: mano ed Extra dell''avversario non compaiono';
  assert jsonb_array_length(pg_temp.pcards(sa, 'hand')) = 5 and jsonb_array_length(pg_temp.pcards(sa, 'extra')) = 3, 'D6: Ann vede la propria mano e il proprio Extra';
  assert not exists (select 1 from jsonb_array_elements(pg_temp.pcards(sa, 'hand')) c where (c->>'x')::int not between 10000 and 19999), 'D6: la mano di Ann ha i codici di Ann';
  assert (sa#>>'{counts,2,hand}')::int = 5 and (sa#>>'{counts,2,deck}')::int = 35 and (sa#>>'{counts,2,extra}')::int = 3, 'D6: dell''avversario si vedono solo i conteggi';
  assert (sa#>>'{counts,1,deck}')::int = 35, 'D6: e del proprio deck il conteggio';
  assert (sa::text !~ '"deck_id": "') or (sa#>>'{players,1,deck_id}') is null, 'D6: nessun deck_id altrui';
  assert (sa#>>'{players,1,deck_id}') is null, 'D6: il deck dell''avversario resta nascosto';
  -- il registro pubblico non contiene codici nascosti
  assert not exists (select 1 from jsonb_array_elements(sa->'log') e where e::text ~ '"x": [0-9]'), 'D6: registro iniziale senza codici';

  -- mano -> campo coperta (Bob mette una carta in zona mostro in difesa coperta)
  select (c->>'x')::int as code into cr from jsonb_array_elements(pg_temp.pcards(sb, 'hand')) c limit 1;
  sb := pg_temp.mv('Bob', l, cr.code, 'mz', ', null, ''def'', false');
  sa := pg_temp.s('Ann', l);
  assert exists (select 1 from jsonb_array_elements(sa->'cards') k where k->>'z' = 'mz' and (k->>'o')::int = 2 and k->>'x' is null and k->>'p' = 'def' and (k->>'f')::boolean = false), 'D6: Ann vede la carta coperta di Bob ma non cosa sia (posizione sì)';
  assert exists (select 1 from jsonb_array_elements(sb->'cards') k where k->>'z' = 'mz' and (k->>'x')::int = cr.code), 'D6: Bob la vede';
  assert not exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind = 'move' and (data->>'x') is not null), 'D6: il registro non rivela la carta coperta';
  assert (sa#>>'{counts,2,hand}')::int = 4, 'D6: la mano di Bob scende a 4';
  -- Bob la gira: ora la vedono tutti
  perform pg_temp.x('Bob', format('public.sim_set(%s, %s, ''atk'', true)', l, pg_temp.cid(l, cr.code)));
  sa := pg_temp.s('Ann', l);
  assert exists (select 1 from jsonb_array_elements(sa->'cards') k where k->>'z' = 'mz' and (k->>'x')::int = cr.code and k->>'p' = 'atk'), 'D6: girata, la carta è visibile a entrambi';
  assert exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind = 'set' and (data->>'x')::int = cr.code), 'D6: la rivelazione compare nel registro';
  -- Bob la rimette in mano: da pubblica a nascosta, ma il registro la nomina perché prima era scoperta
  perform pg_temp.mv('Bob', l, cr.code, 'hand');
  sa := pg_temp.s('Ann', l);
  assert not exists (select 1 from jsonb_array_elements(sa->'cards') k where (k->>'x')::int = cr.code), 'D6: tornata in mano, sparisce dalla vista di Ann';
  -- mostrare una carta dalla mano
  perform pg_temp.x('Bob', format('public.sim_reveal(%s, %s, true)', l, pg_temp.cid(l, cr.code)));
  sa := pg_temp.s('Ann', l);
  assert exists (select 1 from jsonb_array_elements(pg_temp.pcards(sa, 'hand')) k where (k->>'x')::int = cr.code and (k->>'o')::int = 2), 'D6: la carta mostrata compare nella mano di Bob, e solo quella';
  assert (select count(*) from jsonb_array_elements(pg_temp.pcards(sa, 'hand')) k where (k->>'o')::int = 2) = 1, 'D6: le altre restano nascoste';
  perform pg_temp.x('Bob', format('public.sim_reveal(%s, %s, false)', l, pg_temp.cid(l, cr.code)));
  assert (select count(*) from jsonb_array_elements(pg_temp.pcards(pg_temp.s('Ann', l), 'hand')) k where (k->>'o')::int = 2) = 0, 'D6: nascosta di nuovo';
  assert pg_temp.err_as('Ann', format('select public.sim_reveal(%s, %s, true)', l, pg_temp.cid(l, cr.code))) like '%tua mano%', 'D6: non si mostra la carta altrui';
  -- ricerca e sguardo: solo il proprio deck
  ids := array(select (e->>'i')::int from jsonb_array_elements(pg_temp.x('Bob', 'public.sim_search(' || l || ')')) e);
  assert cardinality(ids) = 35, 'D6: Bob cerca nel proprio deck (35 carte)';
  assert not exists (select 1 from jsonb_array_elements(pg_temp.x('Ann', 'public.sim_search(' || l || ')')) e where (e->>'x')::int > 19999), 'D6: Ann cerca solo nel suo';
  assert (select jsonb_agg((e->>'x')::int order by ord) from jsonb_array_elements(pg_temp.x('Bob', 'public.sim_search(' || l || ')')) with ordinality t(e, ord))
       = (select jsonb_agg((e->>'x')::int order by (e->>'x')::int) from jsonb_array_elements(pg_temp.x('Bob', 'public.sim_search(' || l || ')')) e), 'D6: l''elenco è per codice, mai nell''ordine reale del deck';
  -- non si toccano le carte nascoste altrui
  select id into n from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand' limit 1;
  assert pg_temp.err_as('Ann', format('select public.sim_move(%s, %s, ''gy'')', l, n)) like '%Non puoi muovere%', 'D6: la mano altrui non si tocca';
  select id into n from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'deck' limit 1;
  assert pg_temp.err_as('Ann', format('select public.sim_move(%s, %s, ''gy'')', l, n)) like '%Non puoi muovere%', 'D6: il deck altrui non si tocca';
  select id into n from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'extra' limit 1;
  assert pg_temp.err_as('Ann', format('select public.sim_move(%s, %s, ''gy'')', l, n)) like '%Non puoi muovere%', 'D6: l''Extra altrui non si tocca';
  assert pg_temp.err_as('Ann', format('select public.sim_reveal(%s, %s, true)', l, n)) like '%tua mano%', 'D6: niente reveal sulle carte altrui';
  insert into t_ctx values ('L6', l::text);
  insert into t_log (msg) values ('OK D5/D6 — avvio, mani, id casuali, informazioni nascoste (mano/deck/Extra/coperte), reveal, registro pubblico');
end $$;

-- =====================================================================
-- D7 — spostamenti, zone, Xyz, segnalini, controllo
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L6')::bigint; sa jsonb; sb jsonb; a int[]; b int[]; n integer; h integer; hid integer; m1 integer;
begin
  select array_agg(code order by ord) into a from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand';
  select array_agg(code order by ord) into b from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand';
  -- evocazione in attacco: zona libera automatica
  sa := pg_temp.mv('Ann', l, a[1], 'mz');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1] and zone = 'mz' and slot = 1 and pos = 'atk' and face_up and ctrl = 1), 'D7: evocazione nella prima zona libera';
  perform pg_temp.mv('Ann', l, a[2], 'mz');
  assert (select slot from public.sim_cards where game_id = pg_temp.gid(l) and code = a[2]) = 2, 'D7: seconda zona libera';
  assert pg_temp.err_as('Ann', format('select public.sim_move(%s, %s, ''mz'', 1)', l, pg_temp.cid(l, a[3]))) = 'Zona occupata', 'D7: zona occupata';
  assert pg_temp.err_as('Ann', format('select public.sim_move(%s, %s, ''mz'', 6)', l, pg_temp.cid(l, a[3]))) = 'Zona non valida', 'D7: zona fuori dal campo';
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', 5, ''def'', false)', l, pg_temp.cid(l, a[3])));
  assert (select pos || face_up::text from public.sim_cards where game_id = pg_temp.gid(l) and code = a[3]) = 'deffalse', 'D7: carta messa coperta in difesa';
  assert pg_temp.err_as('Ann', format('select public.sim_move(%s, %s, ''mz'', 4, ''boh'')', l, pg_temp.cid(l, a[4]))) = 'Posizione non valida', 'D7: posizione non valida';
  -- spell/trap e campo
  perform pg_temp.mv('Ann', l, a[4], 'st', ', 3, null, false');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = a[4] and zone = 'st' and slot = 3 and not face_up), 'D7: carta magia/trappola coperta nella zona 3';
  perform pg_temp.mv('Ann', l, a[5], 'fz');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = a[5] and zone = 'fz' and slot = 1 and face_up), 'D7: zona Terreno';
  -- cambio posizione e controllo di chi può farlo
  perform pg_temp.x('Ann', format('public.sim_set(%s, %s, ''def'', null)', l, pg_temp.cid(l, a[1])));
  assert (select pos from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1]) = 'def', 'D7: cambio di posizione';
  assert pg_temp.err_as('Bob', format('select public.sim_set(%s, %s, ''atk'', null)', l, pg_temp.cid(l, a[1]))) like '%Non puoi cambiare%', 'D7: non si gira la carta altrui';
  assert pg_temp.err_as('Ann', format('select public.sim_set(%s, %s, ''atk'', null)', l, pg_temp.cid(l, a[4]))) like '%Solo i mostri%', 'D7: solo i mostri hanno la posizione';
  -- segnalini
  perform pg_temp.x('Ann', format('public.sim_counter(%s, %s, 3)', l, pg_temp.cid(l, a[1])));
  assert (select counters from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1]) = 3, 'D7: segnalini';
  perform pg_temp.x('Ann', format('public.sim_counter(%s, %s, -9)', l, pg_temp.cid(l, a[1])));
  assert (select counters from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1]) = 0, 'D7: i segnalini non scendono sotto 0';
  assert pg_temp.err_as('Bob', format('select public.sim_counter(%s, %s, 1)', l, pg_temp.cid(l, a[1]))) like '%che controlli%', 'D7: niente segnalini sulle carte altrui';
  -- mostro che va nel cimitero e torna
  perform pg_temp.mv('Ann', l, a[1], 'gy');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1] and zone = 'gy' and face_up and slot is null and counters = 0), 'D7: cimitero, scoperta';
  sa := pg_temp.s('Bob', l);
  assert exists (select 1 from jsonb_array_elements(pg_temp.pcards(sa, 'gy')) k where (k->>'x')::int = a[1]), 'D7: il cimitero è pubblico';
  perform pg_temp.mv('Bob', l, a[1], 'banish');       -- l'avversario può togliere carte dal tuo cimitero
  assert (select zone from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1]) = 'banish', 'D7: carta del cimitero altrui rimossa dal gioco';
  perform pg_temp.mv('Ann', l, a[1], 'hand');
  assert (select zone || revealed::text from public.sim_cards where game_id = pg_temp.gid(l) and code = a[1]) = 'handfalse', 'D7: dal gioco alla mano';
  -- carta coperta di Bob tolta da Ann: finisce nel cimitero di BOB, scoperta
  perform pg_temp.mv('Bob', l, b[1], 'st', ', 1, null, false');
  perform pg_temp.mv('Ann', l, b[1], 'gy');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = b[1] and zone = 'gy' and owner = 2 and ctrl = 2 and face_up), 'D7: distrutta, va nel cimitero del proprietario';
  assert exists (select 1 from pg_temp.pcards(pg_temp.s('Ann', l), 'gy') j, jsonb_array_elements(j) k where (k->>'x')::int = b[1]), 'D7: ora Ann la vede (è nel cimitero)';
  -- prendere il controllo
  perform pg_temp.mv('Bob', l, b[2], 'mz');
  perform pg_temp.mv('Ann', l, b[2], 'mz');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = b[2] and zone = 'mz' and owner = 2 and ctrl = 1), 'D7: controllo cambiato, proprietario invariato';
  assert (select slot from public.sim_cards where game_id = pg_temp.gid(l) and code = b[2]) = 1, 'D7: nella prima zona libera di Ann';
  perform pg_temp.mv('Ann', l, b[2], 'gy');
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = b[2] and zone = 'gy' and owner = 2 and ctrl = 2), 'D7: dal cimitero torna al proprietario';
  -- Xyz: due materiali
  perform pg_temp.mv('Bob', l, b[3], 'mz');
  perform pg_temp.mv('Bob', l, b[4], 'mz');
  h := pg_temp.cid(l, b[3]);
  perform pg_temp.mv('Bob', l, b[4], 'ovl', format(', null, null, null, true, %s', h));
  perform pg_temp.mv('Bob', l, b[5], 'ovl', format(', null, null, null, true, %s', h));
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and host_id = h and zone = 'ovl') = 2, 'D7: due materiali';
  assert pg_temp.err_as('Bob', format('select public.sim_move(%s, %s, ''ovl'', null, null, null, true, %s)', l, pg_temp.cid(l, b[3]), h)) like '%materiale%', 'D7: un mostro non è materiale di se stesso';
  perform pg_temp.mv('Bob', l, b[3], 'gy');
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and zone = 'gy' and owner = 2 and code in (b[3], b[4], b[5])) = 3, 'D7: se il mostro Xyz va via, i materiali vanno nel cimitero';
  assert not exists (select 1 from public.sim_cards where zone = 'ovl' and game_id = pg_temp.gid(l)), 'D7: nessun materiale orfano';
  -- segnalini (token)
  sb := pg_temp.x('Bob', format('public.sim_token(%s)', l));
  assert exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = 0 and zone = 'mz' and owner = 2), 'D7: segnalino evocato';
  sa := pg_temp.s('Ann', l);
  assert exists (select 1 from jsonb_array_elements(sa->'cards') k where (k->>'x')::int = 0 and k->>'z' = 'mz'), 'D7: il segnalino è visibile a tutti';
  n := (select id from public.sim_cards where game_id = pg_temp.gid(l) and code = 0 limit 1);
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''gy'')', l, n));
  assert not exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l) and code = 0), 'D7: il segnalino che lascia il campo scompare';
  -- zona mostri extra condivisa
  perform pg_temp.x('Bob', format('public.sim_token(%s, ''emz'', 1)', l));
  assert pg_temp.err_as('Ann', format('select public.sim_token(%s, ''emz'', 1)', l)) = 'Zona occupata', 'D7: la zona mostri extra è condivisa';
  perform pg_temp.x('Ann', format('public.sim_token(%s, ''emz'', 2)', l));
  assert pg_temp.err_as('Ann', format('select public.sim_token(%s, ''emz'')', l)) = 'Nessuna zona libera', 'D7: entrambe le zone extra piene';
  delete from public.sim_cards where game_id = pg_temp.gid(l) and code = 0;
  -- tutte e cinque le zone mostri piene
  insert into t_log (msg) values ('OK D7 — spostamenti, zone, posizioni, segnalini, cimitero condiviso, controllo, Xyz, token, zone extra');
end $$;

-- =====================================================================
-- D8 — mazzo: pesca, ricerca, sguardo, riordino, mescola, mazzo vuoto
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L6')::bigint; r jsonb; before_ids int[]; top3 int[]; top3b int[]; c integer; s jsonb; ids int[]; d1 int;
begin
  -- pesca
  c := (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand');
  perform pg_temp.x('Ann', format('public.sim_draw(%s, 2)', l));
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand') = c + 2, 'D8: pesca 2';
  assert pg_temp.err_as('Ann', format('select public.sim_draw(%s, 0)', l)) like '%da 1 a 10%', 'D8: quantità non valida';
  assert pg_temp.err_as('Ann', format('select public.sim_draw(%s, 11)', l)) like '%da 1 a 10%', 'D8: massimo 10';
  -- sguardo alle prime 3: solo chi guarda le vede, ordine dall'alto
  r := pg_temp.x('Ann', format('public.sim_peek(%s, 3)', l));
  top3 := array(select (e->>'i')::int from jsonb_array_elements(r) e);
  assert cardinality(top3) = 3, 'D8: tre carte';
  assert (select array_agg(id order by ord desc) from (select id, ord from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord desc limit 3) q) = top3, 'D8: le prime 3 in ordine dall''alto';
  assert not exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind = 'peek' and data::text ~ '"x"'), 'D8: il registro non rivela cosa si è guardato';
  -- ne prendo una (la seconda) senza mescolare, poi rimetto le altre in cima nell'ordine che voglio
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''hand'', null, null, null, true, null, false)', l, top3[2]));
  assert (select zone from public.sim_cards where game_id = pg_temp.gid(l) and id = top3[2]) = 'hand', 'D8: presa dal deck';
  assert (select array_agg(id order by ord desc) from (select id, ord from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord desc limit 2) q) = array[top3[1], top3[3]], 'D8: senza mescolare l''ordine resta';
  perform pg_temp.x('Ann', format('public.sim_reorder(%s, array[%s, %s], false)', l, top3[3], top3[1]));
  assert (select array_agg(id order by ord desc) from (select id, ord from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord desc limit 2) q) = array[top3[3], top3[1]], 'D8: riordino in cima';
  perform pg_temp.x('Ann', format('public.sim_reorder(%s, array[%s], true)', l, top3[3]));
  assert (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord limit 1) = top3[3], 'D8: riordino in fondo';
  assert pg_temp.err_as('Ann', format('select public.sim_reorder(%s, array[%s], false)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'deck' limit 1))) like '%nel tuo deck%', 'D8: non si riordina il deck altrui';
  -- una ricerca (carta non in cima) mescola da sola e lo dichiara nel registro
  d1 := (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord limit 1);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''hand'')', l, d1));
  assert (select (data->>'sh')::boolean from public.sim_log where game_id = pg_temp.gid(l) and kind = 'move' order by n desc limit 1), 'D8: carta presa dal fondo = ricerca = deck mescolato';
  d1 := (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord desc limit 1);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''hand'')', l, d1));
  assert not (select (data->>'sh')::boolean from public.sim_log where game_id = pg_temp.gid(l) and kind = 'move' order by n desc limit 1), 'D8: carta in cima = pescata, nessun rimescolamento';
  -- mescola esplicita
  perform pg_temp.x('Ann', format('public.sim_shuffle(%s)', l));
  assert exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind = 'shuffle'), 'D8: mescolata nel registro';
  -- rimettere una carta nel deck (in fondo)
  d1 := (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'hand' order by ord limit 1);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''deck'', null, null, null, false)', l, d1));
  assert (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'deck' order by ord limit 1) = d1, 'D8: in fondo al deck';
  -- le prime n carte nel cimitero / rimosse dal gioco
  c := (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'gy');
  perform pg_temp.x('Ann', format('public.sim_top(%s, 3, ''gy'')', l));
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'gy') = c + 3, 'D8: 3 carte dal deck al cimitero';
  assert jsonb_array_length(((pg_temp.logk(l, 'top'))->0)->'codes') = 3, 'D8: nel registro i codici (cimitero = pubblico)';
  perform pg_temp.x('Ann', format('public.sim_top(%s, 2, ''banish'', false)', l));
  assert (select count(*) from public.sim_cards where game_id = pg_temp.gid(l) and owner = 1 and zone = 'banish' and not face_up) = 2, 'D8: 2 carte rimosse a faccia in giù';
  assert ((pg_temp.logk(l, 'top'))->1)->'codes' = 'null'::jsonb or ((pg_temp.logk(l, 'top'))->1)->>'codes' is null, 'D8: coperte, il registro non rivela i codici';
  s := pg_temp.s('Bob', l);
  assert exists (select 1 from jsonb_array_elements(pg_temp.pcards(s, 'banish')) k where (k->>'o')::int = 1 and k->>'x' is null), 'D8: Bob vede due carte rimosse coperte di Ann, senza codice';
  s := pg_temp.s('Ann', l);
  assert (select count(*) from jsonb_array_elements(pg_temp.pcards(s, 'banish')) k where (k->>'o')::int = 1 and k->>'x' is not null) = 2, 'D8: Ann le vede';
  -- mazzo vuoto: la pesca fallita crea una fine da confermare
  update public.sim_cards set zone = 'gy', ord = 9000 + id, face_up = true where game_id = pg_temp.gid(l) and owner = 2 and zone = 'deck';
  r := pg_temp.x('Bob', format('public.sim_draw(%s, 1)', l));
  assert (r#>>'{game,pending_end,reason}') = 'deckout' and (r#>>'{game,pending_end,loser}')::int = 2, 'D8: mazzo vuoto = fine in attesa di conferma';
  assert pg_temp.err_as('Bob', format('select public.sim_dismiss_end(%s)', l)) like '%solo l''avversario%', 'D8: non può annullarlo chi perderebbe';
  r := pg_temp.x('Ann', format('public.sim_dismiss_end(%s)', l));
  assert (r#>'{game,pending_end}') = 'null'::jsonb or (r#>>'{game,pending_end}') is null, 'D8: l''avversario può perdonare';
  perform pg_temp.x('Bob', format('public.sim_draw(%s, 1)', l));
  assert pg_temp.err_as('Ann', format('select public.sim_top(%s, 1, ''boh'')', l)) like '%non valida%', 'D8: destinazione non valida';
  insert into t_log (msg) values ('OK D8 — pesca, sguardo (privato), riordino, ricerca con mescolata dichiarata, mill, mazzo vuoto');
end $$;

-- =====================================================================
-- D9 — punti vita, turno, fasi, proposte, fine duello
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L6')::bigint; r jsonb;
begin
  r := pg_temp.x('Bob', format('public.sim_lp(%s, 1::smallint, -1500, null)', l));
  assert (r#>>'{game,lp,0}')::int = 6500 and (r#>>'{game,lp,1}')::int = 8000, 'D9: danno inflitto ad Ann da Bob';
  r := pg_temp.x('Ann', format('public.sim_lp(%s, 2::smallint, null, 4321)', l));
  assert (r#>>'{game,lp,1}')::int = 4321, 'D9: LP impostati';
  assert pg_temp.err_as('Ann', format('select public.sim_lp(%s, 1::smallint, null, null)', l)) like '%variazione oppure un valore%', 'D9: serve un valore';
  assert pg_temp.err_as('Ann', format('select public.sim_lp(%s, 1::smallint, 5, 5)', l)) like '%variazione oppure un valore%', 'D9: non tutti e due';
  assert pg_temp.err_as('Ann', format('select public.sim_lp(%s, 3::smallint, 5, null)', l)) like '%non valido%', 'D9: giocatore non valido';
  r := pg_temp.lpset('Ann', l, 1, 5000);
  r := pg_temp.x('Ann', format('public.sim_lp(%s, 1::smallint, -99999, null)', l));
  assert (r#>>'{game,lp,0}')::int = 0, 'D9: gli LP non scendono sotto 0';
  assert (r#>>'{game,pending_end,loser}')::int = 1 and (r#>>'{game,pending_end,reason}') = 'lp', 'D9: LP a zero = fine da confermare';
  assert pg_temp.err_as('Ann', format('select public.sim_dismiss_end(%s)', l)) like '%Niente da annullare%', 'D9: la fine per LP non si annulla, si corregge';
  r := pg_temp.lpset('Bob', l, 1, 100);
  assert (r#>>'{game,pending_end}') is null or (r#>'{game,pending_end}') = 'null'::jsonb, 'D9: LP corretti, la fine rientra';
  r := pg_temp.lpset('Bob', l, 1, 0); r := pg_temp.lpset('Bob', l, 2, 0);
  assert (r#>>'{game,pending_end,loser}')::int = 0, 'D9: entrambi a zero = pareggio';
  r := pg_temp.lpset('Bob', l, 1, 1000); r := pg_temp.lpset('Bob', l, 2, 1000);
  -- turno e fasi: solo chi ha il turno (Bob, posto 2, ha il primo turno)
  assert (r#>>'{game,turn_seat}')::int = 2, 'D9: il turno è di Bob';
  assert pg_temp.err_as('Ann', format('select public.sim_phase(%s, ''main1'')', l)) like '%Non è il tuo turno%', 'D9: fasi solo per chi ha il turno';
  assert pg_temp.err_as('Ann', format('select public.sim_end_turn(%s)', l)) like '%Non è il tuo turno%', 'D9: non si chiude il turno altrui';
  r := pg_temp.x('Bob', format('public.sim_phase(%s, ''battle'')', l));
  assert (r#>>'{game,phase}') = 'battle', 'D9: fase di battaglia';
  assert pg_temp.err_as('Bob', format('select public.sim_phase(%s, ''boh'')', l)) like '%Fase non valida%', 'D9: fase non valida';
  r := pg_temp.x('Bob', format('public.sim_end_turn(%s)', l));
  assert (r#>>'{game,turn_seat}')::int = 1 and (r#>>'{game,turn_no}')::int = 2 and (r#>>'{game,phase}') = 'draw', 'D9: tocca ad Ann, turno 2, fase di pescata';
  -- annunci, monete, dadi
  r := pg_temp.x('Ann', format('public.sim_say(%s, ''Attivo %s'')', l, 'Raigeki'));
  assert exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind = 'say' and data->>'t' = 'Attivo Raigeki'), 'D9: annuncio nel registro';
  assert pg_temp.err_as('Ann', format('select public.sim_say(%s, ''   '')', l)) like '%Scrivi%', 'D9: annuncio vuoto';
  perform pg_temp.x('Ann', format('public.sim_say(%s, repeat(''z'', 300))', l));
  assert (select length(data->>'t') from public.sim_log where game_id = pg_temp.gid(l) and kind = 'say' order by n desc limit 1) = 140, 'D9: annuncio limitato a 140 caratteri';
  r := pg_temp.x('Ann', format('public.sim_coin(%s, 3)', l));
  assert jsonb_array_length((pg_temp.logk(l, 'coin'))->0->'r') = 3, 'D9: tre monete';
  r := pg_temp.x('Ann', format('public.sim_dice(%s, 2)', l));
  assert not exists (select 1 from jsonb_array_elements((pg_temp.logk(l, 'dice'))->0->'r') e where (e#>>'{}')::int not between 1 and 6), 'D9: dadi da 1 a 6';
  assert pg_temp.err_as('Ann', format('select public.sim_coin(%s, 6)', l)) like '%1 a 5%', 'D9: massimo 5 monete';
  -- proposte
  r := pg_temp.x('Ann', format('public.sim_propose(%s, ''draw'')', l));
  assert (r#>>'{game,proposal,kind}') = 'draw' and (r#>>'{game,proposal,by}')::int = 1, 'D9: proposta di pareggio';
  assert pg_temp.err_as('Bob', format('select public.sim_propose(%s, ''win'', ''x'')', l)) like '%già una proposta%', 'D9: una proposta alla volta';
  assert pg_temp.err_as('Ann', format('select public.sim_respond(%s, true)', l)) like '%tua proposta%', 'D9: non si accetta la propria proposta';
  r := pg_temp.x('Ann', format('public.sim_respond(%s, false)', l));
  assert (r#>>'{game,proposal}') is null or r#>'{game,proposal}' = 'null'::jsonb, 'D9: ritirata';
  r := pg_temp.x('Ann', format('public.sim_propose(%s, ''win'', ''Exodia al completo'')', l));
  r := pg_temp.x('Bob', format('public.sim_respond(%s, false)', l));
  assert (r#>>'{game,proposal}') is null or r#>'{game,proposal}' = 'null'::jsonb, 'D9: rifiutata';
  assert pg_temp.err_as('Bob', format('select public.sim_respond(%s, true)', l)) like '%Nessuna proposta%', 'D9: niente da accettare';
  assert pg_temp.err_as('Bob', format('select public.sim_propose(%s, ''boh'')', l)) like '%non valida%', 'D9: proposta non valida';
  perform pg_temp.x('Ann', format('public.sim_propose(%s, ''win'', ''Exodia al completo'')', l));
  assert (select count(*) from public.sim_log where game_id = pg_temp.gid(l) and kind = 'propose' and data->>'reason' = 'Exodia al completo') >= 1, 'D9: la motivazione è nel registro';
  r := pg_temp.x('Bob', format('public.sim_respond(%s, true)', l));
  assert (r#>>'{lobby,status}') = 'siding' and (r#>'{lobby,wins}') = '[1, 0]'::jsonb, 'D9: accettata, vince Ann: 1-0 e si passa al side';
  assert (r#>>'{lobby,chooser}')::int = 2, 'D9: sceglie chi ha perso (Bob)';
  assert not exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l)), 'D9: a duello finito il tavolo viene ripulito';
  insert into t_log (msg) values ('OK D9 — LP, fine per LP, turni e fasi, annunci/monete/dadi, proposte (pareggio/vittoria)');
end $$;

-- =====================================================================
-- D10 — al meglio di 3 con side deck
-- =====================================================================
do $$
declare l bigint := (select v from t_ctx where k = 'L6')::bigint; r jsonb; ca jsonb; ma int[]; ea int[]; sa int[]; s jsonb; g2 bigint; old_main int; fa int;
begin
  assert (pg_temp.s('Ann', l)#>>'{lobby,status}') = 'siding', 'D10: si è nel side';
  assert pg_temp.err_as('Ann', format('select public.sim_draw(%s, 1)', l)) like '%non è in corso%', 'D10: niente mosse durante il side';
  ca := pg_temp.s('Ann', l)#>'{me,cfg}';
  assert jsonb_array_length(ca->'main') = 40 and jsonb_array_length(ca->'side') = 2 and jsonb_array_length(ca->'extra') = 3, 'D10: Ann riceve la propria configurazione';
  assert (pg_temp.s('Bob', l)#>'{me,cfg}'->'main'->>0)::int between 20000 and 29999, 'D10: Bob la sua';
  select array(select (e#>>'{}')::int from jsonb_array_elements(ca->'main') e), array(select (e#>>'{}')::int from jsonb_array_elements(ca->'extra') e), array(select (e#>>'{}')::int from jsonb_array_elements(ca->'side') e) into ma, ea, sa;
  -- side non valido
  assert pg_temp.err_as('Ann', format('select public.sim_side(%s, %L, %L, %L)', l, array_append(ma, 99999), ea, sa)) like '%né toglierne%', 'D10: non si aggiungono carte nuove';
  assert pg_temp.err_as('Ann', format('select public.sim_side(%s, %L, %L, %L)', l, ma[2:40] || ea[1], ea[2:3], array_append(sa, ma[1]))) like '%Side Deck deve restare di 2%', 'D10: il Side deve restare della stessa misura';
  assert pg_temp.err_as('Ann', format('select public.sim_side(%s, %L, %L, %L)', l, ma[2:40], ea || sa[1], array[sa[2], ma[1]])) like '%almeno 40%', 'D10: Main sotto 40 rifiutato';
  assert pg_temp.err_as('Ann', format('select public.sim_side(%s, %L, %L, %L)', l, (select array_agg(x) from unnest(ma) x where x <> ma[1]) || sa[1] || sa[2], ea, array[ma[1], ma[1]])) like '%né toglierne%', 'D10: copie non coerenti';
  -- side valido: scambio 2 contro 2
  r := pg_temp.x('Ann', format('public.sim_side(%s, %L, %L, %L)', l, array_prepend(sa[1], array_prepend(sa[2], ma[3:40])), ea, array[ma[1], ma[2]]));
  assert (r#>'{me,cfg,main}') @> to_jsonb(sa[1]) and (r#>'{me,cfg,side}') @> to_jsonb(ma[1]), 'D10: side applicato';
  assert (select cfg_main @> array[sa[1]] and not cfg_main @> array[ma[1]] from public.sim_players where lobby_id = l and seat = 1), 'D10: la nuova configurazione è salvata';
  -- PRONTO: dopo, il deck non si cambia più
  perform pg_temp.x('Ann', format('public.sim_set_ready(%s, true)', l));
  assert pg_temp.err_as('Ann', format('select public.sim_side(%s, %L, %L, %L)', l, ma, ea, sa)) like '%Togli il PRONTO%', 'D10: da PRONTO il deck è bloccato';
  s := pg_temp.s('Bob', l);
  assert (s#>>'{players,0,ready}')::boolean and not (s#>>'{players,1,ready}')::boolean, 'D10: Bob vede il PRONTO di Ann';
  assert (s#>>'{lobby,status}') = 'siding', 'D10: serve anche Bob';
  perform pg_temp.x('Bob', format('public.sim_set_ready(%s, true)', l));
  s := pg_temp.s('Bob', l);
  assert (s#>>'{lobby,status}') = 'playing' and (s#>>'{lobby,game_no}')::int = 2 and (s#>>'{game,status}') = 'choosing' and (s#>>'{game,chooser}')::int = 2, 'D10: partita 2, sceglie Bob (perdente)';
  assert pg_temp.err_as('Ann', format('select public.sim_choose_first(%s, 1::smallint)', l)) like '%Non tocca a te%', 'D10: Ann non sceglie';
  perform pg_temp.x('Bob', format('public.sim_choose_first(%s, 2::smallint)', l));
  g2 := pg_temp.gid(l);
  assert exists (select 1 from public.sim_cards where game_id = g2 and owner = 1 and code = sa[1] and zone in ('deck', 'hand')), 'D10: la carta entrata dal side è nel nuovo duello';
  assert not exists (select 1 from public.sim_cards where game_id = g2 and owner = 1 and code = ma[1]), 'D10: quella uscita no';
  assert (select count(*) from public.sim_cards where game_id = g2 and owner = 1) = 43, 'D10: 40 + 3 carte';
  assert (select turn_seat from public.sim_games where id = g2) = 2, 'D10: parte Bob';
  -- seconda partita: vince Bob (concede Ann) -> 1-1 e terza partita
  r := pg_temp.x('Ann', format('public.sim_concede(%s)', l));
  assert (r#>>'{lobby,status}') = 'siding' and (r#>'{lobby,wins}') = '[1, 1]'::jsonb and (r#>>'{lobby,chooser}')::int = 1, 'D10: 1-1, sceglie Ann (perdente)';
  assert jsonb_array_length(r->'games') = 2 and (r#>>'{games,1,result}') = 'concede', 'D10: storico dei duelli';
  perform pg_temp.x('Ann', format('public.sim_set_ready(%s, true)', l)); perform pg_temp.x('Bob', format('public.sim_set_ready(%s, true)', l));
  perform pg_temp.x('Ann', format('public.sim_choose_first(%s, 1::smallint)', l));
  assert (select no from public.sim_games where id = pg_temp.gid(l)) = 3, 'D10: terza partita';
  -- terza: Ann vince con LP a zero e conferma Bob
  perform pg_temp.lpset('Ann', l, 2, 0);
  r := pg_temp.x('Bob', format('public.sim_confirm_end(%s)', l));
  assert (r#>>'{lobby,status}') = 'finished' and (r#>>'{lobby,winner}')::int = 1 and (r#>'{lobby,wins}') = '[2, 1]'::jsonb, 'D10: incontro vinto 2-1 da Ann';
  assert not exists (select 1 from public.sim_players where lobby_id = l and active), 'D10: giocatori liberi a fine incontro';
  assert pg_temp.err_as('Ann', format('select public.sim_set_ready(%s, true)', l)) like '%momento%', 'D10: a incontro finito non si fa più nulla';
  assert pg_temp.err_as('Ann', format('select public.sim_draw(%s, 1)', l)) like '%non è in corso%', 'D10: né si gioca';
  assert pg_temp.err_as('Ann', 'select public.sim_lobby_create(null)') is null, 'D10: si può creare una nuova lobby';
  perform pg_temp.x('Ann', 'public.sim_lobby_leave((select id from public.sim_lobbies where status = ''lobby'' and host_id = ''' || pg_temp.uid('Ann') || '''))');
  assert (select count(*) from jsonb_array_elements(pg_temp.x('Ann', 'public.sim_home()')->'recent')) >= 1, 'D10: l''incontro compare tra i recenti';

  -- 2-0: l'incontro finisce senza terza partita
  l := pg_temp.newmatch();
  perform pg_temp.x('Bob', format('public.sim_concede(%s)', l));
  perform pg_temp.x('Ann', format('public.sim_set_ready(%s, true)', l)); perform pg_temp.x('Bob', format('public.sim_set_ready(%s, true)', l));
  perform pg_temp.x('Bob', format('public.sim_choose_first(%s, 1::smallint)', l));
  r := pg_temp.x('Bob', format('public.sim_concede(%s)', l));
  assert (r#>>'{lobby,status}') = 'finished' and (r#>>'{lobby,game_no}')::int = 2 and (r#>>'{lobby,winner}')::int = 1, 'D10: 2-0, nessuna terza partita';

  -- vittoria, sconfitta, pareggio: nessun vincitore dell'incontro
  l := pg_temp.newmatch();
  perform pg_temp.x('Bob', format('public.sim_concede(%s)', l));                                    -- Ann 1-0
  perform pg_temp.x('Ann', format('public.sim_set_ready(%s, true)', l)); perform pg_temp.x('Bob', format('public.sim_set_ready(%s, true)', l));
  perform pg_temp.x('Bob', format('public.sim_choose_first(%s, 1::smallint)', l));
  perform pg_temp.x('Ann', format('public.sim_concede(%s)', l));                                    -- 1-1
  perform pg_temp.x('Ann', format('public.sim_set_ready(%s, true)', l)); perform pg_temp.x('Bob', format('public.sim_set_ready(%s, true)', l));
  perform pg_temp.x('Ann', format('public.sim_choose_first(%s, 1::smallint)', l));
  perform pg_temp.x('Ann', format('public.sim_propose(%s, ''draw'')', l));
  r := pg_temp.x('Bob', format('public.sim_respond(%s, true)', l));
  assert (r#>>'{lobby,status}') = 'finished' and (r#>'{lobby,winner}') = 'null'::jsonb and (r#>'{lobby,wins}') = '[1, 1]'::jsonb, 'D10: 1-1 con terzo duello pari = incontro pari';
  assert (r#>>'{game,result}') = 'draw', 'D10: risultato del duello: pareggio';

  -- dopo un pareggio il primo a scegliere è casuale ma esiste
  l := pg_temp.newmatch();
  perform pg_temp.x('Ann', format('public.sim_propose(%s, ''draw'')', l)); r := pg_temp.x('Bob', format('public.sim_respond(%s, true)', l));
  assert (r#>>'{lobby,status}') = 'siding' and (r#>>'{lobby,chooser}')::int in (1, 2) and (r#>'{lobby,wins}') = '[0, 0]'::jsonb, 'D10: pareggio nel primo duello: 0-0, si prosegue';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK D10 — al meglio di 3: side valido/non valido, PRONTO, chi sceglie, 2-1, 2-0, incontro pari, pareggi');
end $$;

-- =====================================================================
-- D11 — uscita, abbandono, pulizia automatica
-- =====================================================================
do $$
declare l bigint; r jsonb;
begin
  l := pg_temp.newmatch();
  r := pg_temp.x('Bob', format('public.sim_lobby_leave(%s)', l));
  assert (select status || winner_seat || end_reason from public.sim_lobbies where id = l) = 'finished1forfeit', 'D11: chi esce a partita in corso perde l''incontro';
  assert not exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l)) and not exists (select 1 from public.sim_players where lobby_id = l and active), 'D11: tavolo ripulito, giocatori liberi';
  assert (pg_temp.s('Ann', l)#>>'{lobby,winner}')::int = 1, 'D11: Ann vede la vittoria per abbandono';
  -- uscita durante il side
  l := pg_temp.newmatch();
  perform pg_temp.x('Ann', format('public.sim_concede(%s)', l));
  perform pg_temp.x('Ann', format('public.sim_lobby_leave(%s)', l));
  assert (select winner_seat from public.sim_lobbies where id = l) = 2, 'D11: uscire durante il side = perdere l''incontro';
  -- lobby non avviata e scaduta
  l := (pg_temp.x('Cid', 'public.sim_lobby_create(null)'))#>>'{}';
  update public.sim_lobbies set updated_at = now() - interval '2 hours' where id = l;
  perform pg_temp.x('Dan', 'public.sim_home()');
  assert (select status from public.sim_lobbies where id = l) = 'cancelled' and not exists (select 1 from public.sim_players where lobby_id = l and active), 'D11: lobby ferma da ore chiusa da sola';
  -- duello fermo da troppo tempo
  l := pg_temp.newmatch();
  update public.sim_lobbies set updated_at = now() - interval '7 hours' where id = l;
  perform pg_temp.x('Dan', 'public.sim_home()');
  assert (select status || end_reason from public.sim_lobbies where id = l) = 'finishedabbandonata' and not exists (select 1 from public.sim_cards where game_id = pg_temp.gid(l)), 'D11: duello fermo da ore chiuso da solo';
  assert not exists (select 1 from public.sim_players where lobby_id = l and active), 'D11: giocatori liberi';
  -- le vecchie partite finite vengono eliminate dopo 30 giorni
  update public.sim_lobbies set finished_at = now() - interval '31 days' where id = l;
  perform pg_temp.x('Dan', 'public.sim_home()');
  assert not exists (select 1 from public.sim_lobbies where id = l) and not exists (select 1 from public.sim_log where game_id not in (select id from public.sim_games)), 'D11: pulizia dello storico (registro compreso)';
  -- una lobby fatta da un utente sospeso non è visibile / non si entra
  l := (pg_temp.x('Cid', 'public.sim_lobby_create(null)'))#>>'{}';
  update public.profiles set suspended = true where id = pg_temp.uid('Cid');
  assert jsonb_array_length(pg_temp.x('Dan', 'public.sim_home()')->'lobbies') = 0, 'D11: lobby di un sospeso nascosta';
  assert pg_temp.err_as('Dan', 'select public.sim_lobby_join(' || l || ')') like '%non è disponibile%', 'D11: e non ci si entra';
  update public.profiles set suspended = false where id = pg_temp.uid('Cid');
  perform pg_temp.x('Cid', 'public.sim_lobby_leave(' || l || ')');
  -- un sospeso a partita in corso non può più muovere
  l := pg_temp.newmatch();
  update public.profiles set suspended = true where id = pg_temp.uid('Bob');
  assert pg_temp.err_as('Bob', format('select public.sim_draw(%s, 1)', l)) like '%sospeso%', 'D11: sospeso, nessuna mossa';
  update public.profiles set suspended = false where id = pg_temp.uid('Bob');
  -- modulo spento a partita in corso
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova spegnimento');
  assert pg_temp.err_as('Ann', format('select public.sim_draw(%s, 1)', l)) = 'Modulo non attivo', 'D11: modulo spento, nessuna mossa';
  assert pg_temp.err_as('Ann', format('select public.sim_state(%s)', l)) = 'Modulo non attivo', 'D11: né lettura';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova riaccensione');
  assert pg_temp.err_as('Ann', format('select public.sim_draw(%s, 1)', l)) is null, 'D11: riacceso, si riprende';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK D11 — uscita = abbandono, pulizia lobby/duelli fermi, sospesi, modulo spento a metà partita');
end $$;

-- =====================================================================
-- D12 — sincronizzazione (versione) e isolamento da Black Market / Ladder / eroi / taglie
-- =====================================================================
do $$
declare l bigint; s jsonb; v1 bigint; before_ text; after_ text; fn text;
begin
  l := pg_temp.newmatch();
  s := pg_temp.x('Ann', 'public.sim_state(' || l || ')');
  v1 := (s->>'v')::bigint;
  assert (pg_temp.x('Ann', format('public.sim_state(%s, %s)', l, v1))->>'same')::boolean, 'D12: stato invariato = risposta minima';
  assert jsonb_array_length(coalesce((pg_temp.x('Ann', format('public.sim_state(%s, %s)', l, v1)))->'cards', '[]')) = 0, 'D12: nessun dato inutile';
  perform pg_temp.x('Bob', format('public.sim_lp(%s, 1::smallint, -100, null)', l));
  s := pg_temp.x('Ann', format('public.sim_state(%s, %s)', l, v1));
  assert s ? 'cards' and (s->>'v')::bigint > v1, 'D12: dopo una mossa dell''avversario lo stato cambia';
  perform pg_temp.endmatch(l);

  -- isolamento: nessuna funzione sim_* nomina Ladder, BC, taglie, XP, notifiche, eroi
  assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like '%sim\_%' escape '\'
     and p.prosrc ~* '(_ledger_move|ledger_entries|wallets|ladder_|bounty|bounties|_notify|notifications|_game_add_xp|game_heroes|game_rewards|matches)'), 'D12: nessuna funzione sim_* tocca Ladder, Black Market, XP o taglie';
  -- una partita intera, con ogni tipo di mossa, non cambia nulla altrove
  before_ := pg_temp.snap();
  l := pg_temp.newmatch();
  perform pg_temp.x('Ann', format('public.sim_draw(%s, 3)', l));
  perform pg_temp.x('Bob', format('public.sim_lp(%s, 1::smallint, -8000, null)', l));
  perform pg_temp.x('Ann', format('public.sim_confirm_end(%s)', l));
  perform pg_temp.x('Ann', format('public.sim_set_ready(%s, true)', l)); perform pg_temp.x('Bob', format('public.sim_set_ready(%s, true)', l));
  perform pg_temp.x('Ann', format('public.sim_choose_first(%s, 1::smallint)', l));
  perform pg_temp.x('Bob', format('public.sim_lp(%s, 2::smallint, -8000, null)', l));
  perform pg_temp.x('Ann', format('public.sim_confirm_end(%s)', l));
  assert (select status from public.sim_lobbies where id = l) = 'siding' and (select wins_1 + wins_2 from public.sim_lobbies where id = l) = 2, 'D12: (verifica interna) 1-1 e side';
  perform pg_temp.endmatch(l);
  after_ := pg_temp.snap();
  assert before_ = after_, 'D12: portafogli, registro BC, match, Ladder, taglie, eroi, premi, notifiche e audit sono identici dopo una partita completa';
  assert (select sum(balance) from public.wallets) = (select sum(amount) from public.ledger_entries), 'D12: saldi = registro';
  assert not exists (select 1 from public.ledger_entries where kind::text ~ 'sim|duel'), 'D12: nessuna voce di registro del simulatore';
  insert into t_log (msg) values ('OK D12 — versione/polling leggero, nessun accesso a Ladder, BC, XP, taglie, notifiche (stato identico dopo una partita completa)');
end $$;

select msg from t_log order by n;
rollback;
