-- =====================================================================
-- TEST DI «ATTACCHI E BERSAGLI» del Duel Simulator (black-market-duel-simulator-attacchi.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO black-market-duel-simulator.sql, ...-chat.sql, ...-catene.sql e ...-attacchi.sql.
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
-- T1 — permessi, tabella chiusa
-- =====================================================================
do $$
begin
  assert pg_temp.err_auth('Ann', 'select * from public.sim_target') like '%permission denied%', 'T1: sim_target non leggibile';
  assert pg_temp.err_auth('Ann', 'insert into public.sim_target (game_id, card_id, seat, zone, turn) values (1, 1, 1, ''mz'', 1)') like '%permission denied%', 'T1: sim_target non scrivibile';
  assert pg_temp.err_auth('Ann', 'delete from public.sim_target') like '%permission denied%', 'T1: sim_target non cancellabile';
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select public.sim_attack(1, 1, null)') like '%Accesso richiesto%', 'T1: attacco senza accesso rifiutato';
  assert pg_temp.err('select public.sim_target(1, 1)') like '%Accesso richiesto%', 'T1: bersaglio senza accesso rifiutato';
  assert pg_temp.err('select public.sim_target_clear(1)') like '%Accesso richiesto%', 'T1: togli bersagli senza accesso rifiutato';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_attack','sim_target','sim_target_clear') and grantee in ('anon','PUBLIC')) = 0, 'T1: nessun permesso ad anon/public';
  assert (select count(*) from information_schema.routine_privileges where routine_name in ('sim_attack','sim_target','sim_target_clear') and grantee = 'authenticated') = 3, 'T1: permessi a authenticated';
  insert into t_log (msg) values ('OK T1 permessi');
end $$;

-- =====================================================================
-- T2 — attacchi: chi, con cosa, contro cosa, cosa si vede
-- =====================================================================
do $$
declare l bigint; s jsonb; sb jsonb; ids integer[]; bids integer[]; a1 integer; a2 integer; a3 integer; b1 integer; b2 integer; b3 integer; bcode2 integer; v0 bigint; before_ text; ca integer;
begin
  l := pg_temp.newmatch();
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  a1 := pg_temp.cid(l, ids[1]); a2 := pg_temp.cid(l, ids[2]); a3 := pg_temp.cid(l, ids[3]);
  select array_agg(id order by ord) into bids from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'hand';
  b1 := bids[1]; b2 := bids[2]; b3 := bids[3];
  bcode2 := (select code from public.sim_cards where id = b2 and game_id = pg_temp.gid(l));
  -- campo: Ann ha un mostro scoperto (a1) e uno coperto (a2); Bob ne ha uno scoperto (b1) e uno coperto (b2) e una carta in mano (b3)
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, a1));
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''def'', false)', l, a2));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, b1));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''def'', false)', l, b2));
  before_ := pg_temp.snap();
  v0 := (pg_temp.s('Bob', l)->>'v')::bigint;
  -- attacco diretto
  s := pg_temp.x('Ann', format('public.sim_attack(%s, %s, null)', l, a1));
  assert (pg_temp.s('Bob', l)->>'v')::bigint > v0, 'T2: la versione sale (Bob vede subito)';
  sb := pg_temp.s('Bob', l);
  assert exists (select 1 from jsonb_array_elements(sb->'log') e where e->>'kind' = 'attack' and (e->'data'->>'x')::int = ids[1] and (e->'data'->>'a')::int = a1 and (e->'data'->>'d')::boolean and e->'data'->'tx' = 'null'::jsonb and e->'data'->'t' = 'null'::jsonb), 'T2: registro: attacco diretto con la carta attaccante';
  -- attacco contro un mostro scoperto
  s := pg_temp.x('Ann', format('public.sim_attack(%s, %s, %s)', l, a1, b1));
  sb := pg_temp.s('Bob', l);
  assert exists (select 1 from jsonb_array_elements(sb->'log') e where e->>'kind' = 'attack' and not (e->'data'->>'d')::boolean and (e->'data'->>'t')::int = b1 and (e->'data'->>'tx')::int = (select code from public.sim_cards where id = b1 and game_id = pg_temp.gid(l))), 'T2: registro: contro un mostro scoperto compare il suo nome';
  -- attacco contro un mostro COPERTO: il nome non compare
  s := pg_temp.x('Ann', format('public.sim_attack(%s, %s, %s)', l, a1, b2));
  sb := pg_temp.s('Bob', l); s := pg_temp.s('Ann', l);
  assert exists (select 1 from jsonb_array_elements(s->'log') e where e->>'kind' = 'attack' and (e->'data'->>'t')::int = b2 and e->'data'->'tx' = 'null'::jsonb), 'T2: mostro coperto: nessun nome nel registro';
  assert not exists (select 1 from jsonb_array_elements(s->'cards') c where (c->>'i')::int = b2 and c->'x' <> 'null'::jsonb), 'T2: e Ann continua a non vederlo';
  assert s::text not like '%' || bcode2 || '%', 'T2: il codice della carta coperta di Bob non compare da nessuna parte nello stato di Ann';
  -- il database non cambia nulla se non il registro
  delete from public.sim_log where game_id = pg_temp.gid(l) and kind = 'attack';
  assert pg_temp.snap() = before_, 'T2: carte, partite, punti vita e wallet identici (tolto il registro degli attacchi)';
  -- rifiuti
  assert pg_temp.err_as('Cid', format('select public.sim_attack(%s, %s, null)', l, a1)) = 'Non partecipi a questa partita', 'T2: l''estraneo non attacca';
  assert pg_temp.err_as('Bob', format('select public.sim_attack(%s, %s, null)', l, a1)) = 'Puoi attaccare solo con i tuoi mostri sul campo', 'T2: Bob non attacca con il mostro di Ann';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, null)', l, a3)) = 'Puoi attaccare solo con i tuoi mostri sul campo', 'T2: dalla mano non si attacca';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, null)', l, a2)) = 'Solo un mostro scoperto può attaccare', 'T2: un mostro coperto non attacca';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, 999999, null)', l)) = 'Carta inesistente', 'T2: carta inesistente';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, 999999)', l, a1)) = 'Bersaglio inesistente', 'T2: bersaglio inesistente';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, %s)', l, a1, a2)) = 'Puoi attaccare solo un mostro dell''avversario', 'T2: non si attacca un proprio mostro';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, %s)', l, a1, b3)) = 'Puoi attaccare solo un mostro dell''avversario', 'T2: non si attacca una carta in mano';
  -- magie: non sono mostri
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''st'', null, null, true)', l, a3));
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, null)', l, a3)) = 'Puoi attaccare solo con i tuoi mostri sul campo', 'T2: una carta Magia/Trappola non attacca';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, %s)', l, a1, a3)) = 'Puoi attaccare solo un mostro dell''avversario', 'T2: né è un bersaglio d''attacco';
  -- segnalino e Zona Mostro Extra
  perform pg_temp.x('Ann', format('public.sim_token(%s)', l));
  ca := (select id from public.sim_cards where game_id = pg_temp.gid(l) and code = 0 limit 1);
  perform pg_temp.x('Ann', format('public.sim_attack(%s, %s, %s)', l, ca, b1));
  assert exists (select 1 from public.sim_log where game_id = pg_temp.gid(l) and kind = 'attack' and (data->>'x')::int = 0), 'T2: un segnalino può attaccare';
  -- carta di Bob in Zona Mostro Extra controllata da lui: Ann la attacca
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''emz'', 1, ''atk'', true)', l, (select id from public.sim_cards where game_id = pg_temp.gid(l) and owner = 2 and zone = 'extra' limit 1)));
  perform pg_temp.x('Ann', format('public.sim_attack(%s, %s, %s)', l, a1, (select id from public.sim_cards where game_id = pg_temp.gid(l) and zone = 'emz' limit 1)));
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK T2 attacchi');
end $$;

-- =====================================================================
-- T3 — bersagli
-- =====================================================================
do $$
declare l bigint; s jsonb; sb jsonb; ids integer[]; bids integer[]; a1 integer; a2 integer; a3 integer; a4 integer; a5 integer; b1 integer; b2 integer; b3 integer; b4 integer; g bigint;
begin
  l := pg_temp.newmatch(); g := pg_temp.gid(l);
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  a1 := pg_temp.cid(l, ids[1]); a2 := pg_temp.cid(l, ids[2]); a3 := pg_temp.cid(l, ids[3]); a4 := pg_temp.cid(l, ids[4]); a5 := pg_temp.cid(l, ids[5]);
  select array_agg(id order by ord) into bids from public.sim_cards where game_id = g and owner = 2 and zone = 'hand';
  b1 := bids[1]; b2 := bids[2]; b3 := bids[3]; b4 := bids[4];
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, a1));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, b1));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''st'', null, null, false)', l, b2));    -- coperta sul campo
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''banish'', null, null, true)', l, b3));  -- rimossa scoperta
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''banish'', null, null, false)', l, b4)); -- rimossa coperta
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''gy'')', l, a2));
  -- niente da togliere
  assert pg_temp.err_as('Ann', format('select public.sim_target_clear(%s)', l)) = 'Non ci sono bersagli', 'T3: senza bersagli non si toglie nulla';
  -- Ann segna il mostro scoperto di Bob
  s := pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  assert jsonb_array_length(s->'targets') = 1 and (s->'targets'->0->>'i')::int = b1 and (s->'targets'->0->>'seat')::int = 1 and s->'targets'->0->>'z' = 'mz', 'T3: bersaglio registrato';
  sb := pg_temp.s('Bob', l);
  assert jsonb_array_length(sb->'targets') = 1 and (sb->'targets'->0->>'i')::int = b1, 'T3: Bob vede il bersaglio';
  assert exists (select 1 from jsonb_array_elements(sb->'log') e where e->>'kind' = 'target' and (e->'data'->>'on')::boolean and (e->'data'->>'i')::int = b1 and (e->'data'->>'x')::int = (select code from public.sim_cards where id = b1 and game_id = g)), 'T3: registro con il nome della carta scoperta';
  -- toccare di nuovo (anche l'altro giocatore) lo toglie
  s := pg_temp.x('Bob', format('public.sim_target(%s, %s)', l, b1));
  assert jsonb_array_length(s->'targets') = 0, 'T3: tolto';
  assert exists (select 1 from public.sim_log where game_id = g and kind = 'target' and not (data->>'on')::boolean), 'T3: registro «tolto»';
  -- carta coperta sul campo: si può segnare, ma il nome non compare
  s := pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b2));
  sb := pg_temp.s('Bob', l); s := pg_temp.s('Ann', l);
  assert jsonb_array_length(s->'targets') = 1, 'T3: carta coperta sul campo segnata';
  assert not exists (select 1 from jsonb_array_elements(s->'cards') c where (c->>'i')::int = b2 and c->'x' <> 'null'::jsonb), 'T3: Ann non scopre la carta coperta';
  assert exists (select 1 from public.sim_log where game_id = g and kind = 'target' and (data->>'i')::int = b2 and data->'x' = 'null'::jsonb), 'T3: nel registro nessun nome';
  perform pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b2));
  -- Cimitero e rimosse scoperte: ok per chiunque; rimosse coperte dell'avversario: no, del proprietario: sì
  s := pg_temp.x('Bob', format('public.sim_target(%s, %s)', l, a2));
  assert jsonb_array_length(s->'targets') = 1 and s->'targets'->0->>'z' = 'gy', 'T3: Bob segna una carta nel Cimitero di Ann';
  s := pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b3));
  assert jsonb_array_length(s->'targets') = 2, 'T3: rimossa scoperta di Bob segnabile da Ann';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, b4)) = 'Non puoi vedere quella carta', 'T3: la rimossa coperta di Bob non si può segnare da Ann';
  s := pg_temp.x('Bob', format('public.sim_target(%s, %s)', l, b4));
  assert jsonb_array_length(s->'targets') = 3, 'T3: il proprietario segna la propria rimossa coperta';
  assert not exists (select 1 from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where (c->>'i')::int = b4 and c->'x' <> 'null'::jsonb), 'T3: Ann non vede quale sia';
  assert exists (select 1 from public.sim_log where game_id = g and kind = 'target' and (data->>'i')::int = b4 and data->'x' = 'null'::jsonb), 'T3: nel registro nessun nome per la rimossa coperta';
  -- non segnabili: mano, deck, Extra, materiali
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, a3)) like 'Puoi scegliere come bersaglio solo carte%', 'T3: dalla mano no';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, (select id from public.sim_cards where game_id = g and owner = 1 and zone = 'deck' limit 1))) like 'Puoi scegliere come bersaglio solo carte%', 'T3: dal deck no';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, (select id from public.sim_cards where game_id = g and owner = 1 and zone = 'extra' limit 1))) like 'Puoi scegliere come bersaglio solo carte%', 'T3: dall''Extra no';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, 999999)', l)) = 'Carta inesistente', 'T3: carta inesistente';
  assert pg_temp.err_as('Cid', format('select public.sim_target(%s, %s)', l, a1)) = 'Non partecipi a questa partita', 'T3: l''estraneo no';
  assert pg_temp.err_as('Cid', format('select public.sim_target_clear(%s)', l)) = 'Non partecipi a questa partita', 'T3: l''estraneo non toglie';
  -- limite di 5
  perform pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, a1));
  s := pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  assert jsonb_array_length(s->'targets') = 5, 'T3: 5 bersagli';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, b2)) = 'Puoi avere al massimo 5 bersagli: togline uno', 'T3: il sesto è rifiutato';
  s := pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  assert jsonb_array_length(s->'targets') = 4, 'T3: togliendone uno se ne può mettere un altro';
  -- se la carta cambia zona il bersaglio sparisce da solo
  s := pg_temp.x('Ann', format('public.sim_move(%s, %s, ''gy'')', l, a1));
  assert (select count(*) from jsonb_array_elements(s->'targets') t where (t->>'i')::int = a1) = 0 and jsonb_array_length(s->'targets') = 3, 'T3: carta spostata: bersaglio decaduto';
  -- togli tutti
  s := pg_temp.x('Bob', format('public.sim_target_clear(%s)', l));
  assert jsonb_array_length(s->'targets') = 0 and (select count(*) from public.sim_target where game_id = g) = 0, 'T3: tutti tolti';
  assert (select count(*) from public.sim_log where game_id = g and kind = 'target_clear') = 1, 'T3: registro «tolti tutti»';
  -- scadono a fine turno
  perform pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  assert jsonb_array_length(pg_temp.s('Bob', l)->'targets') = 1, 'T3: bersaglio presente';
  perform pg_temp.x('Ann', format('public.sim_end_turn(%s)', l));
  assert jsonb_array_length(pg_temp.s('Bob', l)->'targets') = 0 and jsonb_array_length(pg_temp.s('Ann', l)->'targets') = 0, 'T3: a fine turno i bersagli scadono';
  assert pg_temp.err_as('Bob', format('select public.sim_target_clear(%s)', l)) = 'Non ci sono bersagli', 'T3: nessun bersaglio dopo la scadenza';
  s := pg_temp.x('Bob', format('public.sim_target(%s, %s)', l, b1));
  assert jsonb_array_length(s->'targets') = 1, 'T3: nel turno nuovo si può rimettere';
  assert (select count(*) from public.sim_target where game_id = g) = 1, 'T3: le righe scadute sono state ripulite';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK T3 bersagli');
end $$;

-- =====================================================================
-- T4 — carte rimosse: le scoperte le vedono entrambi, le coperte solo il proprietario
-- =====================================================================
do $$
declare l bigint; s0 jsonb; s1 jsonb; ids integer[]; c1 integer; c2 integer; c3 integer; code1 integer; code2 integer; code3 integer; g bigint;
begin
  l := pg_temp.newmatch(); g := pg_temp.gid(l);
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  code1 := ids[1]; code2 := ids[2]; code3 := ids[3];
  c1 := pg_temp.cid(l, code1); c2 := pg_temp.cid(l, code2); c3 := pg_temp.cid(l, code3);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''banish'', null, null, true)', l, c1));
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''banish'', null, null, false)', l, c2));
  s0 := pg_temp.s('Ann', l); s1 := pg_temp.s('Bob', l);
  assert (select (c->>'x')::int from jsonb_array_elements(s1->'cards') c where (c->>'i')::int = c1) = code1, 'T4: la rimossa scoperta la vede anche Bob';
  assert (select (c->>'x')::int from jsonb_array_elements(s0->'cards') c where (c->>'i')::int = c1) = code1, 'T4: e Ann';
  assert (select c->'x' from jsonb_array_elements(s1->'cards') c where (c->>'i')::int = c2) = 'null'::jsonb, 'T4: la rimossa coperta Bob NON la vede';
  assert (select (c->>'x')::int from jsonb_array_elements(s0->'cards') c where (c->>'i')::int = c2) = code2, 'T4: Ann sì';
  assert (s1->'counts'->'1'->>'banish')::int = 2, 'T4: Bob sa quante carte sono rimosse';
  assert s1::text not like '%' || code2 || '%', 'T4: il codice della rimossa coperta non compare nello stato di Bob (nemmeno nel registro)';
  -- una carta privata (mano) rimossa coperta: nessun nome nel registro
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''banish'', null, null, false)', l, c3));
  assert pg_temp.s('Bob', l)::text not like '%' || code3 || '%', 'T4: rimossa coperta dalla mano: Bob non la conosce';
  -- girarla scoperta la rende pubblica, coperta di nuovo la nasconde
  perform pg_temp.x('Ann', format('public.sim_set(%s, %s, null, true)', l, c2));
  assert (select (c->>'x')::int from jsonb_array_elements(pg_temp.s('Bob', l)->'cards') c where (c->>'i')::int = c2) = code2, 'T4: girata scoperta: Bob la vede';
  perform pg_temp.x('Ann', format('public.sim_set(%s, %s, null, false)', l, c2));
  assert (select c->'x' from jsonb_array_elements(pg_temp.s('Bob', l)->'cards') c where (c->>'i')::int = c2) = 'null'::jsonb, 'T4: girata coperta: Bob non la vede più';
  -- le rimosse dell'avversario
  assert (select (c->>'x')::int from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where (c->>'i')::int = c1) = code1, 'T4: simmetria';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK T4 rimosse scoperte e coperte');
end $$;

-- =====================================================================
-- T5 — isolamento: attacchi e bersagli non toccano il resto
-- =====================================================================
do $$
declare l bigint; before_ text; ids integer[]; a1 integer; b1 integer; g bigint; s0 jsonb; s1 jsonb;
begin
  l := pg_temp.newmatch(); g := pg_temp.gid(l);
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  a1 := pg_temp.cid(l, ids[1]); b1 := (select id from public.sim_cards where game_id = g and owner = 2 and zone = 'hand' limit 1);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, a1));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, b1));
  s0 := pg_temp.s('Bob', l);
  before_ := pg_temp.snap();
  perform pg_temp.x('Ann', format('public.sim_attack(%s, %s, %s)', l, a1, b1));
  perform pg_temp.x('Ann', format('public.sim_attack(%s, %s, null)', l, a1));
  perform pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  perform pg_temp.x('Bob', format('public.sim_target(%s, %s)', l, a1));
  perform pg_temp.x('Bob', format('public.sim_target_clear(%s)', l));
  delete from public.sim_log where game_id = g and kind in ('attack', 'target', 'target_clear');
  assert pg_temp.snap() = before_, 'T5: carte, partite, wallet, registro contabile identici';
  s1 := pg_temp.s('Bob', l);
  assert s0->'cards' = s1->'cards' and s0->'counts' = s1->'counts' and s0->'game' = s1->'game', 'T5: carte e contatori identici';
  assert (select count(*) from pg_proc p where p.proname in ('sim_attack','sim_target','sim_target_clear') and (pg_get_function_arguments(p.oid) ilike '%seat%' or pg_get_function_arguments(p.oid) ilike '%user%')) = 0, 'T5: nessun posto o utente fidato dal browser';
  assert not exists (select 1 from public.sim_log where game_id = g and kind = 'attack') , 'T5: (log pulito)';
  perform pg_temp.x('Ann', format('public.sim_attack(%s, %s, null)', l, a1));
  assert not exists (select 1 from public.sim_log where game_id = g and kind = 'attack' and exists (select 1 from jsonb_object_keys(data) k where k not in ('x','a','d','tx','t'))), 'T5: il registro non contiene altri campi';
  perform pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  assert not exists (select 1 from public.sim_log where game_id = g and kind = 'target' and exists (select 1 from jsonb_object_keys(data) k where k not in ('x','i','on','z','o'))), 'T5: il registro dei bersagli non contiene altri campi';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK T5 isolamento');
end $$;

-- =====================================================================
-- T6 — modulo spento, duello finito, catene e altre azioni
-- =====================================================================
do $$
declare l bigint; s jsonb; ids integer[]; a1 integer; b1 integer; g bigint;
begin
  l := pg_temp.newmatch(); g := pg_temp.gid(l);
  select array_agg((c->>'x')::int order by (c->>'k')::int) into ids from jsonb_array_elements(pg_temp.s('Ann', l)->'cards') c where c->>'z' = 'hand' and (c->>'o')::int = 1;
  a1 := pg_temp.cid(l, ids[1]); b1 := (select id from public.sim_cards where game_id = g and owner = 2 and zone = 'hand' limit 1);
  perform pg_temp.x('Ann', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, a1));
  perform pg_temp.x('Bob', format('public.sim_move(%s, %s, ''mz'', null, ''atk'', true)', l, b1));
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', false, 'prova modulo');
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, null)', l, a1)) = 'Modulo non attivo', 'T6: modulo spento -> attacco rifiutato';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, b1)) = 'Modulo non attivo', 'T6: modulo spento -> bersaglio rifiutato';
  assert pg_temp.err_as('Ann', format('select public.sim_target_clear(%s)', l)) = 'Modulo non attivo', 'T6: modulo spento -> togli rifiutato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('duel', true, 'prova modulo');
  -- la catena e i bersagli convivono
  perform pg_temp.x('Ann', format('public.sim_activate(%s, %s)', l, a1));
  perform pg_temp.x('Ann', format('public.sim_target(%s, %s)', l, b1));
  s := pg_temp.s('Bob', l);
  assert jsonb_array_length(s->'chain') = 1 and jsonb_array_length(s->'targets') = 1, 'T6: catena e bersagli insieme';
  perform pg_temp.x('Bob', format('public.sim_chain_resolve(%s)', l));
  assert jsonb_array_length(pg_temp.s('Bob', l)->'targets') = 1, 'T6: risolvere la catena non toglie i bersagli';
  -- fine duello
  perform pg_temp.x('Ann', format('public.sim_concede(%s)', l));
  s := pg_temp.s('Ann', l);
  assert jsonb_array_length(s->'targets') = 0, 'T6: a duello finito nessun bersaglio nello stato';
  assert pg_temp.err_as('Ann', format('select public.sim_attack(%s, %s, null)', l, a1)) = 'Il duello non è in corso', 'T6: a duello finito non si attacca';
  assert pg_temp.err_as('Ann', format('select public.sim_target(%s, %s)', l, b1)) = 'Il duello non è in corso', 'T6: né si segna un bersaglio';
  perform pg_temp.endmatch(l);
  insert into t_log (msg) values ('OK T6 modulo e fine duello');
end $$;

select msg from t_log order by n;
rollback;
