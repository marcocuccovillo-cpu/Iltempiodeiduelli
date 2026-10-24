-- =====================================================================
-- TEST DEI NUOVI BADGE (black-market-badge-extra.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO la Ladder, gli Eroi, le scommesse, il Duel Simulator e black-market-badge-extra.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
-- I dati di gioco (eroi, dungeon, scommesse, partite del simulatore) vengono scritti direttamente nelle tabelle: è ciò che fanno le funzioni del gioco.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) or exists (select 1 from public.ladder_matches) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-badge-extra-' || n)::uuid $$;
create function pg_temp.act(u uuid) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_(n text) returns text language sql as $$ select pg_temp.act(pg_temp.uid(n)) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.err_auth(n text, q text) returns text language plpgsql as $$
begin
  perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end;
end $$;
-- righe dei badge di un giocatore, visti da un altro (o da sé), come li vede il browser
create function pg_temp.bx(viewer text, target text default null) returns setof public.badge_extra_defs language plpgsql as $$
begin return; end $$;
create temp table t_rows (code text, family text, area text, tier smallint, metric text, kind text, threshold bigint, value bigint, earned boolean, earned_at timestamptz, hidden boolean, sort integer);
create function pg_temp.load(viewer text, target text default null) returns void language plpgsql as $$
begin
  truncate t_rows;
  perform pg_temp.as_(viewer);
  execute 'set local role authenticated';
  if target is null then
    insert into t_rows select * from public.badge_progress_extra();
  else
    insert into t_rows select * from public.badge_progress_extra(pg_temp.uid(target));
  end if;
  execute 'reset role';
end $$;
grant all on t_rows to authenticated;
create function pg_temp.val(c text) returns bigint language sql as $$ select value from t_rows where code = c $$;
create function pg_temp.got(c text) returns boolean language sql as $$ select earned from t_rows where code = c $$;
create function pg_temp.ngot(a text default null) returns bigint language sql as $$ select count(*) from t_rows where earned and (a is null or area = a) $$;

do $$
declare n text;
begin
  foreach n in array array['Admin','Ann','Bob','Cyr','Dia'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
  end loop;
  insert into t_log (msg) values ('OK Preparazione: 5 utenti, Admin = primo registrato');
end $$;

-- ===== B1 catalogo e permessi =====
do $$
declare bad bigint;
begin
  assert (select count(*) from public.badge_extra_defs) = 91, 'B1: ' || 91 || ' nuovi badge nel catalogo';
  assert (select count(distinct family) from public.badge_extra_defs) = 26, 'B1: 26 famiglie';
  assert (select count(*) from public.badge_extra_defs where area = 'eroi') > 0 and (select count(*) from public.badge_extra_defs where area = 'bets') > 0
     and (select count(*) from public.badge_extra_defs where area = 'sim') > 0, 'B1: le tre aree esistono';
  select count(*) into bad from public.badge_extra_defs a join public.badge_extra_defs b on a.family = b.family and b.tier = a.tier + 1 and b.threshold <= a.threshold where a.tier < 5;
  assert bad = 0, 'B1: soglie crescenti dentro ogni famiglia';
  assert (select count(*) from public.badge_extra_defs where tier = 5) = 2, 'B1: due traguardi unici (Triade Perfetta, Signore dei Tre Mondi)';
  assert not exists (select 1 from public.badge_extra_defs d where d.code <> d.family || '_' || (select count(*) from public.badge_extra_defs x where x.family = d.family and x.threshold <= d.threshold)), 'B1: codici = famiglia_livello';
  perform pg_temp.as_('Ann');
  assert pg_temp.err_auth('Ann', 'insert into public.badge_extra_defs (code, family, area, tier, metric, kind, threshold, sort) values (''x'', ''x'', ''eroi'', 1, ''e_boss'', ''count'', 1, 1)') like '%permission denied%', 'B1: il browser non scrive il catalogo';
  assert pg_temp.err_auth('Ann', 'update public.badge_extra_defs set threshold = 1') like '%permission denied%', 'B1: il browser non cambia le soglie';
  assert pg_temp.err_auth('Ann', 'delete from public.badge_extra_defs') like '%permission denied%', 'B1: il browser non cancella il catalogo';
  assert pg_temp.err_auth('Ann', 'select count(*) from public.badge_extra_defs') is null, 'B1: il catalogo si legge';
  assert (select provolatile from pg_proc where proname = 'badge_progress_extra') = 's', 'B1: la funzione è di sola lettura (stable)';
  insert into t_log (msg) values ('OK B1: catalogo di 91 badge in 26 famiglie, sola lettura dal browser');
end $$;

-- ===== B2 nuovo iscritto: tutto a zero =====
do $$
begin
  perform pg_temp.load('Ann');
  assert (select count(*) from t_rows) = 91, 'B2: una riga per ogni nuovo badge';
  assert pg_temp.ngot() = 0, 'B2: nessun badge per chi non ha giocato';
  assert (select coalesce(sum(value), 0) from t_rows) = 0, 'B2: tutti i progressi a zero';
  assert not exists (select 1 from t_rows where hidden), 'B2: nessuno nascosto con i moduli accesi';
  assert (select count(*) from t_rows where earned_at is not null) = 0, 'B2: nessuna data di sblocco';
  insert into t_log (msg) values ('OK B2: nuovo iscritto = 91 righe a zero');
end $$;

-- ===== B3 Guerra degli Eroi =====
do $$
declare lb bigint; r1 uuid := gen_random_uuid(); r2 uuid := gen_random_uuid(); r3 uuid := gen_random_uuid(); r4 uuid := gen_random_uuid(); i integer; t0 timestamptz := '2026-03-01 10:00+00';
begin
  alter table public.game_duels disable trigger user;
  insert into public.game_heroes (user_id, level) values (pg_temp.uid('Ann'), 12), (pg_temp.uid('Bob'), 3);
  insert into public.game_days (day, boss_no, max_hp, hp) values ('2026-03-01', 1, 1000, 0);
  insert into public.game_lobbies (day, max_hp, hp, created_by) values ('2026-03-01', 1000, 0, pg_temp.uid('Ann')) returning id into lb;
  -- 5 boss sconfitti da Ann (giorni diversi), 1 da Bob
  for i in 1..5 loop
    insert into public.game_rewards (day, user_id, boss_no, bc, xp) values ('2026-03-01'::date + i, pg_temp.uid('Ann'), 1, 10, 10);
    update public.game_rewards set created_at = t0 + i * interval '1 day' where day = '2026-03-01'::date + i and user_id = pg_temp.uid('Ann');
  end loop;
  insert into public.game_rewards (day, user_id, boss_no, bc, xp) values ('2026-03-02', pg_temp.uid('Bob'), 1, 10, 10);
  -- duelli: Ann ne vince 3 e ne perde 2
  for i in 1..3 loop
    insert into public.game_duels (day, attacker_id, defender_id, winner_id, atk_level, def_level, rounds, created_at) values ('2026-03-01'::date + i, pg_temp.uid('Ann'), pg_temp.uid('Bob'), pg_temp.uid('Ann'), 12, 3, 5, t0 + i * interval '1 day');
  end loop;
  for i in 1..2 loop
    insert into public.game_duels (day, attacker_id, defender_id, winner_id, atk_level, def_level, rounds) values ('2026-03-10'::date + i, pg_temp.uid('Ann'), pg_temp.uid('Bob'), pg_temp.uid('Bob'), 12, 3, 5);
  end loop;
  -- dungeon: 3 conquistati, uno solo visitato (0 vittorie)
  insert into public.game_dungeon_progress (user_id, dungeon_no, clears, first_clear_at, last_clear_at) values
    (pg_temp.uid('Ann'), 1, 2, t0, t0), (pg_temp.uid('Ann'), 2, 1, t0 + interval '2 days', t0 + interval '2 days'), (pg_temp.uid('Ann'), 3, 1, t0 + interval '5 days', t0 + interval '5 days'), (pg_temp.uid('Ann'), 4, 0, null, null);
  -- spedizioni: due riuscite (Tank, Danni), una fallita (Supporto), una di Bob
  insert into public.game_runs (id, dungeon_no, leader_id, status, created_at, started_at, finished_at) values
    (r1, 1, pg_temp.uid('Ann'), 'cleared', t0, t0, t0 + interval '1 hour'),
    (r2, 2, pg_temp.uid('Ann'), 'cleared', t0 + interval '2 days', t0 + interval '2 days', t0 + interval '2 days 1 hour'),
    (r3, 3, pg_temp.uid('Ann'), 'failed', t0 + interval '3 days', t0 + interval '3 days', t0 + interval '3 days 1 hour'),
    (r4, 1, pg_temp.uid('Bob'), 'cleared', t0, t0, t0 + interval '1 hour');
  insert into public.game_run_members (run_id, user_id, role) values (r1, pg_temp.uid('Ann'), 'tank'), (r2, pg_temp.uid('Ann'), 'dps'), (r3, pg_temp.uid('Ann'), 'support'), (r4, pg_temp.uid('Bob'), 'support');
  -- azioni contro il boss: 12 attacchi, 6 cure, 5 guardie, 3 studi
  for i in 1..12 loop insert into public.game_day_log (day, user_id, action, lobby_id, created_at) values ('2026-03-01', pg_temp.uid('Ann'), 'attack', lb, t0 + i * interval '1 minute'); end loop;
  for i in 1..6 loop insert into public.game_day_log (day, user_id, action, lobby_id) values ('2026-03-01', pg_temp.uid('Ann'), 'heal', lb); end loop;
  for i in 1..5 loop insert into public.game_day_log (day, user_id, action, lobby_id) values ('2026-03-01', pg_temp.uid('Ann'), 'guard', lb); end loop;
  for i in 1..3 loop insert into public.game_day_log (day, user_id, action, lobby_id) values ('2026-03-01', pg_temp.uid('Ann'), 'study', lb); end loop;
  -- oggetti: 4 non iniziali + 1 iniziale (non conta)
  insert into public.game_inventory (user_id, item_id, source) select pg_temp.uid('Ann'), id, 'shop' from public.game_items where source = 'shop' order by id limit 4;
  insert into public.game_inventory (user_id, item_id, source) select pg_temp.uid('Ann'), id, 'start' from public.game_items where source = 'start' order by id limit 1;
  alter table public.game_duels enable trigger user;

  perform pg_temp.load('Ann');
  assert pg_temp.val('e_livello_1') = 12 and pg_temp.got('e_livello_1') and pg_temp.got('e_livello_2') and not pg_temp.got('e_livello_3'), 'B3: livello 12 = Emergente e Temprato, non Epico';
  assert pg_temp.val('e_boss_1') = 5 and pg_temp.got('e_boss_1') and pg_temp.got('e_boss_2') and not pg_temp.got('e_boss_3'), 'B3: 5 boss = primi due livelli';
  assert (select earned_at from t_rows where code = 'e_boss_2') = t0 + interval '5 days', 'B3: la data del 5° boss è quella del 5° premio';
  assert (select earned_at from t_rows where code = 'e_boss_1') = t0 + interval '1 day', 'B3: la data del 1° boss è quella del 1° premio';
  assert pg_temp.val('e_arena_1') = 3 and pg_temp.got('e_arena_1') and not pg_temp.got('e_arena_2'), 'B3: solo i duelli VINTI contano (3 su 5)';
  assert pg_temp.val('e_dungeon_1') = 3 and pg_temp.got('e_dungeon_1') and not pg_temp.got('e_dungeon_2'), 'B3: 3 dungeon conquistati (quello con 0 vittorie non conta)';
  assert pg_temp.val('e_squadra_1') = 2 and pg_temp.got('e_squadra_1') and not pg_temp.got('e_squadra_2'), 'B3: 2 spedizioni riuscite (la fallita non conta)';
  assert pg_temp.val('e_attacchi_1') = 12 and pg_temp.got('e_attacchi_1') and not pg_temp.got('e_attacchi_2'), 'B3: 12 attacchi';
  assert pg_temp.val('e_cure_1') = 6 and pg_temp.got('e_cure_1') and not pg_temp.got('e_cure_2'), 'B3: 6 cure';
  assert pg_temp.val('e_guardia_1') = 5 and pg_temp.got('e_guardia_1'), 'B3: 5 guardie = primo livello';
  assert pg_temp.val('e_arsenale_1') = 4 and pg_temp.got('e_arsenale_1') and not pg_temp.got('e_arsenale_2'), 'B3: 4 oggetti non iniziali (l’iniziale non conta)';
  assert pg_temp.val('e_ruoli_1') = 2 and not pg_temp.got('e_ruoli_1'), 'B3: Triade non ancora: solo Tank e Danni riusciti (Supporto fallito)';
  -- la riuscita da Supporto completa la triade, con la data dell’ultimo ruolo
  update public.game_runs set status = 'cleared' where id = r3;
  perform pg_temp.load('Ann');
  assert pg_temp.val('e_ruoli_1') = 3 and pg_temp.got('e_ruoli_1') and (select tier from t_rows where code = 'e_ruoli_1') = 5, 'B3: Triade Perfetta (unico, livello 5)';
  assert (select earned_at from t_rows where code = 'e_ruoli_1') = t0 + interval '3 days 1 hour', 'B3: data della Triade = ultimo ruolo completato';
  assert pg_temp.val('e_squadra_1') = 3, 'B3: ora 3 spedizioni riuscite';
  -- Bob, visto da Ann: i progressi degli eroi sono pubblici come quelli della Ladder
  perform pg_temp.load('Ann', 'Bob');
  assert pg_temp.val('e_livello_1') = 3 and not pg_temp.got('e_livello_1') and pg_temp.val('e_boss_1') = 1 and pg_temp.got('e_boss_1') and pg_temp.val('e_squadra_1') = 1, 'B3: Bob visto da Ann';
  assert pg_temp.val('e_arena_1') = 2 and pg_temp.got('e_arena_1') and not pg_temp.got('e_arena_2'), 'B3: Bob ha vinto 2 duelli in difesa: contano come vittorie';
  insert into t_log (msg) values ('OK B3: Eroi — livello, boss, Arena, dungeon, squadra, azioni, oggetti, Triade, date di sblocco');
end $$;

-- ===== B4 Scommesse =====
create function pg_temp.mk(a text, b text) returns uuid language plpgsql as $$
declare i uuid := gen_random_uuid();
begin
  insert into public.ladder_matches (id, challenger_id, opponent_id, format, kind, status) values (i, pg_temp.uid(a), pg_temp.uid(b), 'Advanced', 'ladder', 'closed');
  return i;
end $$;
create function pg_temp.bet(u text, st text, stake integer, quota integer, prob numeric, ret integer, at timestamptz) returns void language plpgsql as $$
begin
  insert into public.bets (user_id, match_id, pick, stake, quota, basis, prob_pct, status, returned, settle_seq, client_request_id, created_at, settled_at)
  values (pg_temp.uid(u), pg_temp.mk('Ann', 'Bob'), pg_temp.uid('Ann'), stake, quota, 'mix', prob, st, ret, 1, gen_random_uuid()::text, at - interval '1 hour', case when st = 'open' then null else at end);
end $$;
do $$
declare t0 timestamptz := '2026-04-01 12:00+00';
begin
  -- Cyr: V (quota 3,50 su 100, prob 25) · V (2,00 su 50, prob 50) · P 40 · P 60 · V (1,80 su 100, prob 55) · rimborsata 30 · V revocata (5,00 su 200) · aperta 20
  perform pg_temp.bet('Cyr', 'won', 100, 350, 25, 350, t0 + interval '1 day');
  perform pg_temp.bet('Cyr', 'won', 50, 200, 50, 100, t0 + interval '2 days');
  perform pg_temp.bet('Cyr', 'lost', 40, 250, 40, 0, t0 + interval '3 days');
  perform pg_temp.bet('Cyr', 'lost', 60, 250, 40, 0, t0 + interval '4 days');
  perform pg_temp.bet('Cyr', 'won', 100, 180, 55, 180, t0 + interval '5 days');
  perform pg_temp.bet('Cyr', 'refunded', 30, 200, 50, 30, t0 + interval '6 days');
  perform pg_temp.bet('Cyr', 'revoked', 200, 500, 20, 0, t0 + interval '7 days');
  perform pg_temp.bet('Cyr', 'open', 20, 200, 50, 0, t0 + interval '8 days');

  perform pg_temp.load('Cyr');
  assert pg_temp.val('b_puntate_1') = 8 and pg_temp.got('b_puntate_1') and not pg_temp.got('b_puntate_2'), 'B4: 8 scommesse piazzate (anche rimborsate/aperte/revocate)';
  assert pg_temp.val('b_vinte_1') = 3 and pg_temp.got('b_vinte_1') and not pg_temp.got('b_vinte_2'), 'B4: 3 vinte (la revocata non conta)';
  assert (select earned_at from t_rows where code = 'b_vinte_1') = t0 + interval '1 day', 'B4: data della prima vincita';
  assert pg_temp.val('b_serie_1') = 2 and not pg_temp.got('b_serie_1'), 'B4: serie massima 2 (V V P P V)';
  assert pg_temp.val('b_quota_1') = 350 and pg_temp.got('b_quota_1') and not pg_temp.got('b_quota_2'), 'B4: quota più alta vinta 3,50 (la 5,00 revocata non conta)';
  assert pg_temp.val('b_vincita_1') = 250 and pg_temp.got('b_vincita_1') and pg_temp.got('b_vincita_2') and not pg_temp.got('b_vincita_3'), 'B4: vincita più ricca = 250 BC';
  -- profitto: (350-100) + (100-50) + (180-100) - 40 - 60 = 280
  assert pg_temp.val('b_profitto_1') = 280 and pg_temp.got('b_profitto_1') and not pg_temp.got('b_profitto_2'), 'B4: profitto netto 280 (rimborsata, revocata e aperta non contano)';
  -- volume: 100+50+40+60+100+20 = 370 (esclusi rimborsata e revocata)
  assert pg_temp.val('b_volume_1') = 370 and not pg_temp.got('b_volume_1'), 'B4: totale puntato 370 (no rimborsata/revocata)';
  assert pg_temp.val('b_outsider_1') = 1 and pg_temp.got('b_outsider_1') and not pg_temp.got('b_outsider_2'), 'B4: una sola vincita contro pronostico (prob ≤ 30)';
  -- la serie arriva a 3 con altre due vittorie consecutive
  perform pg_temp.bet('Cyr', 'won', 10, 200, 50, 20, t0 + interval '9 days');
  perform pg_temp.bet('Cyr', 'won', 10, 200, 50, 20, t0 + interval '10 days');
  perform pg_temp.load('Cyr');
  assert pg_temp.val('b_serie_1') = 3 and pg_temp.got('b_serie_1'), 'B4: serie di 3 vittorie di fila';
  -- una scommessa persa dopo la serie non la cancella: resta la serie massima
  perform pg_temp.bet('Cyr', 'lost', 10, 200, 50, 0, t0 + interval '11 days');
  perform pg_temp.load('Cyr');
  assert pg_temp.val('b_serie_1') = 3, 'B4: dopo una persa la serie massima resta 3';
  insert into t_log (msg) values ('OK B4: scommesse — conteggi, serie, quota, vincita, profitto, volume, contro pronostico; revocate/rimborsate escluse');

  -- privacy: Dia vede Cyr solo come esito (mai importi)
  perform pg_temp.load('Dia', 'Cyr');
  assert pg_temp.got('b_vinte_1') and pg_temp.got('b_vincita_2') and pg_temp.got('b_quota_1'), 'B4p: gli altri vedono quali badge ha ottenuto';
  assert pg_temp.val('b_vincita_2') = 250 and pg_temp.val('b_vincita_3') = 0 and pg_temp.val('b_puntate_1') = 1 and pg_temp.val('b_volume_1') = 0 and pg_temp.val('b_profitto_1') = 200 and pg_temp.val('b_profitto_2') = 0,
         'B4p: gli altri non vedono importi (valore = soglia raggiunta o 0)';
  assert not exists (select 1 from t_rows where area = 'bets' and not earned and value <> 0), 'B4p: nessun progresso parziale delle scommesse visibile agli altri';
  perform pg_temp.load('Admin', 'Cyr');
  assert pg_temp.val('b_profitto_1') = 290 and pg_temp.val('b_volume_1') = 400, 'B4p: l’amministratore vede i valori veri';
  perform pg_temp.load('Cyr');
  assert pg_temp.val('b_profitto_1') = 290, 'B4p: il diretto interessato vede i valori veri';
  insert into t_log (msg) values ('OK B4p: privacy delle scommesse (altri = solo esito; interessato e admin = valori)');
end $$;

-- ===== B5 Duel Simulator =====
create function pg_temp.lobby(a text, b text, winner smallint, reason text, g1 smallint, g2 smallint, g3 smallint, at timestamptz, lp1 integer default 3000, lp2 integer default 3000) returns bigint language plpgsql as $$
declare l bigint; k smallint;
begin
  insert into public.sim_lobbies (host_id, status, game_no, wins_1, wins_2, winner_seat, end_reason, created_at, finished_at)
  values (pg_temp.uid(a), 'finished', 3, 0, 0, winner, reason, at - interval '1 hour', at) returning id into l;
  insert into public.sim_players (lobby_id, seat, user_id, active) values (l, 1, pg_temp.uid(a), false), (l, 2, pg_temp.uid(b), false);
  k := 0;
  if g1 is not null then k := 1; insert into public.sim_games (lobby_id, no, status, chooser_seat, winner_seat, lp_1, lp_2, ended_at) values (l, 1, 'finished', 1, g1, case when g1 = 1 then lp1 else 0 end, case when g1 = 2 then lp2 else 0 end, at - interval '40 minutes'); end if;
  if g2 is not null then insert into public.sim_games (lobby_id, no, status, chooser_seat, winner_seat, lp_1, lp_2, ended_at) values (l, 2, 'finished', 1, g2, case when g2 = 1 then lp1 else 0 end, case when g2 = 2 then lp2 else 0 end, at - interval '20 minutes'); end if;
  if g3 is not null then insert into public.sim_games (lobby_id, no, status, chooser_seat, winner_seat, lp_1, lp_2, ended_at) values (l, 3, 'finished', 1, g3, case when g3 = 1 then lp1 else 0 end, case when g3 = 2 then lp2 else 0 end, at - interval '5 minutes'); end if;
  return l;
end $$;
do $$
declare t0 timestamptz := '2026-05-01 20:00+00';
begin
  -- Ann (seat 1) contro Bob: 1) persa il primo duello e vinta la partita con una vittoria a 8500 LP: rimonta + a vita piena
  perform pg_temp.lobby('Ann', 'Bob', 1::smallint, 'normale', 2::smallint, 1::smallint, 1::smallint, t0, 8500, 3000);
  -- 2) vinta 2-0 (lp finale 3000: non a vita piena)
  perform pg_temp.lobby('Ann', 'Bob', 1::smallint, 'normale', 1::smallint, 1::smallint, null, t0 + interval '1 day');
  -- 3) persa 0-2
  perform pg_temp.lobby('Ann', 'Bob', 2::smallint, 'normale', 2::smallint, 2::smallint, null, t0 + interval '2 days');
  -- 4) abbandonata dall’avversario: non conta nulla
  perform pg_temp.lobby('Ann', 'Bob', 1::smallint, 'abbandono', 1::smallint, null, null, t0 + interval '3 days');
  -- 5) annullata prima di cominciare (nessun vincitore)
  insert into public.sim_lobbies (host_id, status, end_reason) values (pg_temp.uid('Ann'), 'cancelled', 'annullata');
  -- mazzi: 2 in libreria + 1 temporaneo
  insert into public.sim_decks (owner_id, name, temp, created_at) values (pg_temp.uid('Ann'), 'Drago', false, t0), (pg_temp.uid('Ann'), 'Mago', false, t0 + interval '1 day'), (pg_temp.uid('Ann'), 'Prova', true, t0);

  perform pg_temp.load('Ann');
  assert pg_temp.val('s_partite_1') = 3 and pg_temp.got('s_partite_1') and not pg_temp.got('s_partite_2'), 'B5: 3 incontri conclusi (abbandonato e annullato non contano)';
  assert pg_temp.val('s_vittorie_1') = 2 and pg_temp.got('s_vittorie_1') and not pg_temp.got('s_vittorie_2'), 'B5: 2 incontri vinti';
  assert (select earned_at from t_rows where code = 's_vittorie_1') = t0, 'B5: data della prima vittoria';
  -- duelli vinti da Ann: 1) 2 (gioco 2 e 3), 2) 2 (1 e 2), 3) 0, 4) escluso = 4
  assert pg_temp.val('s_duelli_1') = 4 and pg_temp.got('s_duelli_1') and not pg_temp.got('s_duelli_2'), 'B5: 4 duelli vinti';
  assert pg_temp.val('s_serie_1') = 2 and not pg_temp.got('s_serie_1'), 'B5: serie massima 2 (V V P)';
  assert pg_temp.val('s_rimonta_1') = 1 and pg_temp.got('s_rimonta_1') and not pg_temp.got('s_rimonta_2'), 'B5: una rimonta (persa la prima, vinto l’incontro)';
  assert pg_temp.val('s_mazzi_1') = 2 and pg_temp.got('s_mazzi_1') and not pg_temp.got('s_mazzi_2'), 'B5: 2 mazzi in libreria (il temporaneo non conta)';
  assert pg_temp.val('s_invitto_1') = 2 and pg_temp.got('s_invitto_1') and not pg_temp.got('s_invitto_2'), 'B5: due duelli vinti con 8000 LP o più';
  -- Bob, seat 2, visto da Ann
  perform pg_temp.load('Ann', 'Bob');
  assert pg_temp.val('s_partite_1') = 3 and pg_temp.val('s_vittorie_1') = 1 and pg_temp.got('s_vittorie_1'), 'B5: Bob: 3 incontri, 1 vinto';
  assert pg_temp.val('s_rimonta_1') = 0 and pg_temp.val('s_duelli_1') = 3 and pg_temp.got('s_duelli_1'), 'B5: Bob: nessuna rimonta, 3 duelli vinti (1 nel primo incontro, 2 nel terzo)';
  assert pg_temp.val('s_invitto_1') = 0, 'B5: Bob non ha vinto a vita piena';
  insert into t_log (msg) values ('OK B5: Duel Simulator — incontri, vittorie, duelli, serie, rimonta, mazzi, vita piena; abbandoni e annullate escluse');
end $$;

-- ===== B6 Signore dei Tre Mondi =====
do $$
begin
  perform pg_temp.load('Ann');
  assert pg_temp.val('x_tre_1') = 2 and not pg_temp.got('x_tre_1'), 'B6: Ann ha dungeon e Simulatore ma nessuna scommessa vinta (2/3)';
  assert (select area from t_rows where code = 'x_tre_1') = 'special' and (select tier from t_rows where code = 'x_tre_1') = 5, 'B6: traguardo speciale di livello unico';
  perform pg_temp.bet('Ann', 'won', 10, 200, 50, 20, '2026-06-01 10:00+00');
  perform pg_temp.load('Ann');
  assert pg_temp.val('x_tre_1') = 3 and pg_temp.got('x_tre_1'), 'B6: con una scommessa vinta i tre mondi sono completi';
  perform pg_temp.bet('Dia', 'lost', 10, 200, 50, 0, '2026-06-02 10:00+00');
  perform pg_temp.load('Dia');
  assert pg_temp.val('x_tre_1') = 0 and not pg_temp.got('x_tre_1'), 'B6: una scommessa PERSA non conta per i Tre Mondi (0/3)';
  insert into t_log (msg) values ('OK B6: Signore dei Tre Mondi (dungeon + scommessa vinta + incontro vinto)');
end $$;

-- ===== B7 moduli spenti e riaccesi =====
do $$
declare before_ text; after_ text; off_ text;
begin
  perform pg_temp.load('Ann');
  select string_agg(code || ':' || value || ':' || earned, ',' order by code) into before_ from t_rows;
  update public.system_settings set value_int = 0 where key = 'module_heroes';
  perform pg_temp.load('Ann');
  assert (select count(*) from t_rows where hidden and area = 'eroi') = (select count(*) from t_rows where area = 'eroi'), 'B7: Eroi spenti = tutti i badge degli Eroi nascosti';
  assert not exists (select 1 from t_rows where hidden and (earned or value <> 0)), 'B7: i nascosti non risultano né ottenuti né con progresso';
  assert (select hidden from t_rows where code = 'x_tre_1'), 'B7: anche i Tre Mondi spariscono (dipendono dagli Eroi)';
  assert pg_temp.got('b_vinte_1') and not (select hidden from t_rows where code = 'b_vinte_1') and pg_temp.got('s_vittorie_1'), 'B7: scommesse e Simulatore restano';
  update public.system_settings set value_int = 1 where key = 'module_heroes';
  update public.system_settings set value_int = 0 where key = 'module_duel';
  perform pg_temp.load('Ann');
  assert (select count(*) from t_rows where hidden and area = 'sim') = (select count(*) from t_rows where area = 'sim'), 'B7: Duel Simulator spento = badge del Simulatore nascosti';
  assert pg_temp.got('e_boss_1') and (select hidden from t_rows where code = 'x_tre_1'), 'B7: gli Eroi tornano, i Tre Mondi restano nascosti';
  update public.system_settings set value_int = 1 where key = 'module_duel';
  perform pg_temp.load('Ann');
  select string_agg(code || ':' || value || ':' || earned, ',' order by code) into after_ from t_rows;
  assert before_ = after_, 'B7: alla riaccensione i badge tornano identici';
  insert into t_log (msg) values ('OK B7: moduli Eroi/Duel spenti = badge nascosti; riaccesi = identici');
end $$;

-- ===== B8 sicurezza e compatibilità =====
do $$
declare l0 bigint; w0 numeric; c0 bigint; l1 bigint; w1 numeric; c1 bigint;
begin
  select count(*), coalesce(sum(amount), 0) into l0, w0 from public.ledger_entries;
  select count(*) into c0 from public.bets;
  perform pg_temp.load('Ann'); perform pg_temp.load('Cyr'); perform pg_temp.load('Dia', 'Cyr'); perform pg_temp.load('Admin', 'Ann');
  select count(*), coalesce(sum(amount), 0) into l1, w1 from public.ledger_entries;
  select count(*) into c1 from public.bets;
  assert l0 = l1 and w0 = w1 and c0 = c1, 'B8: leggere i badge non muove BC né scommesse';
  -- senza accesso: errore; anon: nessun permesso
  perform set_config('request.jwt.claims', '', true);
  assert pg_temp.err('select * from public.badge_progress_extra()') like '%Accesso richiesto%', 'B8: senza accesso la funzione rifiuta';
  perform pg_temp.as_('Ann');
  assert pg_temp.err('set local role anon; select * from public.badge_progress_extra()') like '%permission denied%', 'B8: anon non può eseguire la funzione';
  reset role;
  perform pg_temp.as_('Ann');
  assert (select count(*) from public.badge_progress_extra(gen_random_uuid())) = 0, 'B8: utente inesistente = nessuna riga';
  assert not has_function_privilege('anon', 'public.badge_progress_extra(uuid)', 'execute') and has_function_privilege('authenticated', 'public.badge_progress_extra(uuid)', 'execute'), 'B8: permessi della funzione';
  assert not has_table_privilege('authenticated', 'public.badge_extra_defs', 'insert') and not has_table_privilege('authenticated', 'public.badge_extra_defs', 'update') and not has_table_privilege('authenticated', 'public.badge_extra_defs', 'delete'), 'B8: catalogo senza scritture';
  assert (select count(*) from public.badge_extra_defs where code in (select code from t_rows)) = 91, 'B8: ogni riga restituita ha un codice del catalogo';
  assert (select count(distinct code) from t_rows) = 91, 'B8: nessun codice duplicato';
  insert into t_log (msg) values ('OK B8: sola lettura, nessun BC mosso, permessi, accesso obbligatorio');
end $$;

select msg from t_log order by n;
rollback;
