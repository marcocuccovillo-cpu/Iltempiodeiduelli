-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 036: La guerra degli Eroi — Arena a classifica (punti Arena, leghe, stagioni mensili).
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni della guerra degli Eroi (serve almeno
-- black-market-eroi-ricarica-livello-100.sql). Si può rieseguire senza danni (punti e stagioni restano).
--
-- COME FUNZIONA
--  * PUNTI ARENA: ogni eroe parte da 1000 punti (impostazione game_arena_start). Quando SFIDI un altro eroe in Arena il tuo punteggio
--    cambia come l'Elo: vincere contro uno più forte (più punti) ne dà molti, contro uno più debole pochi (almeno +1); perdere ne toglie (almeno −1; molti di più se
--    l'avversario era più debole di te). Il fattore è game_arena_k (32). Il punteggio non scende sotto 0.
--  * CHI VIENE SFIDATO NON PERDE NÉ GUADAGNA PUNTI: la classifica si muove solo per chi si mette in gioco; chi accetta sfide non è
--    penalizzato quando è offline. Resta invariato tutto il resto del duello (energia, XP, vittorie e sconfitte).
--  * ANTI-ABUSO: contro lo stesso avversario contano per i punti al massimo 3 sfide al giorno (game_arena_pair_day). Le altre si
--    combattono (energia, XP) ma non cambiano i punti.
--  * LEGHE: Bronzo (da 0), Argento (900), Oro (1100), Platino (1300), Diamante (1500), Leggenda (1700). Tabella game_arena_leagues,
--    modificabile (soglie e nomi).
--  * STAGIONI: una al mese (mese di calendario secondo il giorno di gioco). A ogni nuova stagione i punti tornano a metà strada
--    verso 1000 (game_arena_soft_pct = 50): chi aveva 1600 riparte da 1300, chi aveva 600 riparte da 800. Le stagioni passate restano
--    consultabili: la classifica finale e il podio dell'ultima stagione (albo d'oro) compaiono nella scheda Arena.
--    Nessun premio in BC: l'Arena assegna solo punti, leghe e posizioni (la pagina mostra anche quanti punti sono in palio).
--  * CLASSIFICA: chi ha fatto almeno una sfida valida nella stagione compare in classifica.
--  * Gli allenamenti amichevoli e tutto il resto del gioco NON toccano i punti Arena. I duelli già fatti non vengono contati
--    (si parte da zero alla prima esecuzione).
--  Funzioni sostituite: game_duel (stesso funzionamento, in più registra i punti e li restituisce nel campo «arena») e game_arena_list
--  (in più: punti, lega, punti in palio, sfide valide rimaste con ciascun avversario; l'elenco è ordinato per vicinanza di punti).
--  Nuova funzione pubblica: game_arena_state() (stagione, la mia posizione, classifica, albo d'oro, ultime sfide con i punti).
--  Tabelle nuove chiuse al browser. Nessun movimento di BC.
--  ANNULLAMENTO: black-market-eroi-arena-down.sql (rimette le due funzioni com'erano e toglie tabelle e impostazioni: i punti spariscono).
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_duels') is null or to_regclass('public.game_heroes') is null
     or to_regprocedure('public.game_duel(uuid)') is null or to_regprocedure('public.game_arena_list()') is null
     or to_regprocedure('public._game_today()') is null or to_regprocedure('public._game_sim(jsonb,jsonb)') is null then
    raise exception 'Prima esegui le migrazioni della guerra degli Eroi. Non è stato modificato nulla.';
  end if;
  if position('energy_full' in pg_get_functiondef('public.game_duel(uuid)'::regprocedure)) = 0 then
    raise exception 'Prima esegui black-market-eroi-ricarica-livello-100.sql (il duello ha una versione più vecchia). Non è stato modificato nulla.';
  end if;
end $$;

insert into public.system_settings (key, value_int, description) values
 ('game_arena_start',    1000, 'Arena: punti di partenza di ogni eroe'),
 ('game_arena_k',          32, 'Arena: fattore di variazione dei punti per ogni sfida (come il K dell''Elo)'),
 ('game_arena_pair_day',    3, 'Arena: sfide al giorno contro lo stesso avversario che cambiano i punti'),
 ('game_arena_soft_pct',   50, 'Arena: a ogni nuova stagione si recupera questa percentuale della distanza dai punti di partenza')
on conflict (key) do nothing;

-- ---------- leghe ----------
create table if not exists public.game_arena_leagues (
  key text primary key check (key ~ '^[a-z]{2,20}$'),
  name text not null,
  min_points integer not null unique check (min_points >= 0),
  ord smallint not null
);
alter table public.game_arena_leagues enable row level security;
revoke all on public.game_arena_leagues from public, anon, authenticated;
insert into public.game_arena_leagues (key, name, min_points, ord) values
 ('bronzo', 'Bronzo', 0, 1), ('argento', 'Argento', 900, 2), ('oro', 'Oro', 1100, 3),
 ('platino', 'Platino', 1300, 4), ('diamante', 'Diamante', 1500, 5), ('leggenda', 'Leggenda', 1700, 6)
on conflict (key) do nothing;

-- ---------- punti per stagione e registro delle sfide ----------
create table if not exists public.game_arena_rating (
  user_id uuid not null references public.profiles(id) on delete cascade,
  season text not null check (season ~ '^[0-9]{4}-[0-9]{2}$'),
  points integer not null check (points >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  best integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, season)
);
create index if not exists game_arena_rating_season_idx on public.game_arena_rating (season, points desc);
alter table public.game_arena_rating enable row level security;
revoke all on public.game_arena_rating from public, anon, authenticated;

create table if not exists public.game_arena_log (
  duel_id uuid primary key references public.game_duels(id) on delete cascade,
  season text not null,
  day date not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  before_pts integer not null, delta integer not null, after_pts integer not null,
  counted boolean not null, reason text,
  at timestamptz not null default clock_timestamp()
);
create index if not exists game_arena_log_user_idx on public.game_arena_log (user_id, at desc);
create index if not exists game_arena_log_pair_idx on public.game_arena_log (user_id, target_id, day);
alter table public.game_arena_log enable row level security;
revoke all on public.game_arena_log from public, anon, authenticated;

-- ---------- funzioni interne ----------
create or replace function public._game_arena_season(p_day date default null) returns text language sql stable as $$
  select to_char(coalesce(p_day, public._game_today()), 'YYYY-MM') $$;

create or replace function public._game_arena_league(p_points integer) returns text language sql stable security definer set search_path = public as $$
  select key from public.game_arena_leagues where min_points <= greatest(0, p_points) order by min_points desc limit 1 $$;

-- punti di un eroe in una stagione: quelli salvati, oppure (se non ha ancora giocato) il reset morbido dell'ultima stagione giocata, oppure la partenza
create or replace function public._game_arena_points(p_user uuid, p_season text) returns integer language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.points from public.game_arena_rating r where r.user_id = p_user and r.season = p_season),
    (select (public._setting('game_arena_start') + round((r.points - public._setting('game_arena_start')) * least(100, greatest(0, public._setting('game_arena_soft_pct'))) / 100.0))::integer
       from public.game_arena_rating r where r.user_id = p_user and r.season < p_season order by r.season desc limit 1),
    public._setting('game_arena_start')) $$;

create or replace function public._game_arena_touch(p_user uuid, p_season text) returns integer language plpgsql security definer set search_path = public as $$
declare p integer;
begin
  p := public._game_arena_points(p_user, p_season);
  insert into public.game_arena_rating (user_id, season, points, best) values (p_user, p_season, p, p) on conflict do nothing;
  return (select points from public.game_arena_rating where user_id = p_user and season = p_season);
end $$;

-- variazione di punti di chi sfida (ra) un avversario (rd): vittoria almeno +1, sconfitta almeno −1
create or replace function public._game_arena_delta(ra integer, rd integer, p_won boolean) returns integer language sql stable security definer set search_path = public as $$
  select case when p_won then greatest(1, d) else least(-1, d) end
  from (select round(greatest(1, public._setting('game_arena_k')) * ((case when p_won then 1 else 0 end) - 1.0 / (1.0 + power(10.0, (rd - ra) / 400.0))))::integer as d) x $$;

-- registra l'esito di una sfida (chiamata da game_duel): cambia i punti di chi sfida, mai quelli dello sfidato
create or replace function public._game_arena_record(p_duel uuid, p_att uuid, p_def uuid, p_won boolean, p_day date) returns jsonb language plpgsql security definer set search_path = public as $$
declare s text := public._game_arena_season(p_day); ra integer; rd integer; n_pair integer; v_counted boolean; v_delta integer := 0; na integer;
        pm integer := greatest(1, public._setting('game_arena_pair_day')); lb text; la text; w integer;
begin
  ra := public._game_arena_touch(p_att, s);
  rd := public._game_arena_points(p_def, s);
  select count(*) into n_pair from public.game_arena_log l where l.user_id = p_att and l.target_id = p_def and l.day = p_day and l.counted;
  v_counted := n_pair < pm;
  na := ra;
  if v_counted then
    na := greatest(0, ra + public._game_arena_delta(ra, rd, p_won));
    v_delta := na - ra;
    update public.game_arena_rating set points = na, wins = wins + (p_won)::integer, losses = losses + (not p_won)::integer, best = greatest(best, na), updated_at = now()
      where user_id = p_att and season = s;
  end if;
  insert into public.game_arena_log (duel_id, season, day, user_id, target_id, before_pts, delta, after_pts, counted, reason)
    values (p_duel, s, p_day, p_att, p_def, ra, v_delta, na, v_counted, case when v_counted then null else 'pair' end);
  lb := public._game_arena_league(ra); la := public._game_arena_league(na);
  return jsonb_build_object('season', s, 'before', ra, 'delta', v_delta, 'points', na, 'counted', v_counted, 'reason', case when v_counted then null else 'pair' end,
           'pair_max', pm, 'pair_used', n_pair + (v_counted)::integer, 'opponent_points', rd, 'league_before', lb, 'league_after', la,
           'league_changed', lb is distinct from la);
end $$;

-- ---------- il duello: identico a prima, in più registra i punti ----------
CREATE OR REPLACE FUNCTION public.game_duel(p_target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date := public._game_today(); a public.game_heroes%rowtype; b public.game_heroes%rowtype; ca jsonb; cb jsonb; sim jsonb; v_en numeric; v_need integer; v_cost integer;
  v_win uuid; rt jsonb; v_xp bigint := 0; v_id uuid := gen_random_uuid(); rw jsonb; v_first uuid; v_second uuid; pn text;
begin
  perform public._require_module('heroes');
  if p_target is null or p_target = v then raise exception 'Scegli un altro eroe da sfidare'; end if;
  perform public._game_ensure_hero(v);
  if not exists (select 1 from public.profiles where id = p_target and not suspended) then raise exception 'Eroe non disponibile'; end if;
  if not exists (select 1 from public.game_heroes where user_id = p_target) then raise exception 'Questo duellante non è ancora un eroe'; end if;
  v_first := least(v, p_target); v_second := greatest(v, p_target);                  -- blocco in ordine fisso
  perform 1 from public.game_heroes where user_id = v_first for update;
  perform 1 from public.game_heroes where user_id = v_second for update;
  select * into a from public.game_heroes where user_id = v;
  select * into b from public.game_heroes where user_id = p_target;
  if not a.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  if not b.stats_set then raise exception 'Questo eroe non ha ancora assegnato i suoi punti abilità'; end if;
  if not b.arena_open then raise exception 'Questo eroe non accetta sfide in Arena'; end if;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  select to_jsonb(x) into cb from public._game_calc(p_target) x;
  v_need := greatest(public._setting('game_energy_win'), public._setting('game_energy_loss'));
  v_en := public._game_energy_of(v);
  if v_en < v_need then raise exception 'Energia insufficiente: per sfidare ne servono almeno % (ora %)', v_need, floor(v_en); end if;
  sim := public._game_sim(ca, cb);
  v_win := case when sim->>'winner' = 'a' then v else p_target end;
  if v_win = v then
    v_xp := greatest(1, round((40 + 2 * b.level) * least(2::numeric, greatest(0.25, b.level::numeric / a.level)))::bigint);
    rw := public._game_add_xp(v, v_xp);
    v_xp := (rw->>'xp')::bigint;
    update public.game_heroes set duels_won = duels_won + 1 where user_id = v;
  else
    rw := jsonb_build_object('xp', 0, 'levels', 0, 'level', a.level);
    update public.game_heroes set duels_lost = duels_lost + 1 where user_id = v;
  end if;
  v_cost := case when v_win = v then public._setting('game_energy_win') else public._setting('game_energy_loss') end;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1, energy = case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max() else greatest(0, v_en - v_cost) end, energy_at = now() where user_id = v;      -- se la ricarica scatta (sale di livello sotto il livello 100), l'energia torna al 100% (anche dopo il costo del duello)
  insert into public.game_duels (id, day, attacker_id, defender_id, winner_id, atk_level, def_level, xp_awarded, rounds, log)
    values (v_id, d, v, p_target, v_win, a.level, b.level, v_xp, (sim->>'rounds')::integer, sim->'log');
  rt := public._game_arena_record(v_id, v, p_target, v_win = v, d);
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('id', v_id, 'won', v_win = v, 'xp', v_xp, 'levels', (rw->>'levels')::integer, 'level', (rw->>'level')::integer, 'opponent', pn,
           'opponent_level', b.level, 'rounds', sim->'rounds', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'energy', case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max()::numeric else round(greatest(0, v_en - v_cost), 2) end, 'energy_cost', v_cost, 'energy_full', coalesce((rw->>'energy_full')::boolean, false)) || jsonb_build_object('arena', rt);
end $function$;

-- ---------- l'elenco dell'Arena: in più punti, lega e punti in palio ----------
create or replace function public.game_arena_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := public._game_today(); s text := public._game_arena_season(d);
        v_lvl integer; v_pts integer; pm integer := greatest(1, public._setting('game_arena_pair_day'));
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select level into v_lvl from public.game_heroes where user_id = v;
  v_pts := public._game_arena_touch(v, s);
  return coalesce((select jsonb_agg(x order by abs((x->>'points')::integer - v_pts), (x->>'gap')::integer, (x->>'level')::integer desc, x->>'nickname') from (
    select jsonb_build_object('user_id', t.user_id, 'nickname', t.nickname, 'avatar', t.avatar, 'level', t.level, 'bosses_beaten', t.bosses_beaten, 'duels_won', t.duels_won,
             'power', t.power, 'gap', abs(t.level - v_lvl),
             'fought_today', t.fights_today > 0, 'fights_today', t.fights_today,
             'points', t.pts, 'league', public._game_arena_league(t.pts), 'rated_today', t.rated, 'rated_left', greatest(0, pm - t.rated),
             'gain', public._game_arena_delta(v_pts, t.pts, true), 'loss', public._game_arena_delta(v_pts, t.pts, false)) as x
    from (select h.user_id, p.nickname, p.avatar, h.level, h.bosses_beaten, h.duels_won, c.s_for + c.s_des + c.s_vig + c.s_spi + c.s_frt as power,
                 public._game_arena_points(h.user_id, s) as pts,
                 (select count(*) from public.game_duels q where q.day = d and q.attacker_id = v and q.defender_id = h.user_id) as fights_today,
                 (select count(*) from public.game_arena_log l where l.day = d and l.user_id = v and l.target_id = h.user_id and l.counted) as rated
            from public.game_heroes h join public.profiles p on p.id = h.user_id cross join lateral public._game_calc(h.user_id) c
           where h.user_id <> v and h.stats_set and h.arena_open and not p.suspended
           order by abs(public._game_arena_points(h.user_id, s) - v_pts), abs(h.level - v_lvl), h.level desc limit 60) t) z), '[]'::jsonb);
end $$;

-- ---------- la scheda Arena: stagione, posizione, classifica, albo d'oro, ultime sfide ----------
create or replace function public.game_arena_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := public._game_today(); s text := public._game_arena_season(d);
        r public.game_arena_rating%rowtype; v_rank integer; v_tot integer; lg text; nx record; last_s text; ends date := (date_trunc('month', d) + interval '1 month - 1 day')::date;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform public._game_arena_touch(v, s);
  select * into r from public.game_arena_rating where user_id = v and season = s;
  lg := public._game_arena_league(r.points);
  select * into nx from public.game_arena_leagues where min_points > r.points order by min_points limit 1;
  select count(*) into v_tot from public.game_arena_rating q join public.profiles p on p.id = q.user_id where q.season = s and q.wins + q.losses > 0 and not p.suspended;
  v_rank := case when r.wins + r.losses = 0 then null else 1 + (select count(*) from public.game_arena_rating q join public.profiles p on p.id = q.user_id
              where q.season = s and q.wins + q.losses > 0 and not p.suspended and (q.points > r.points or (q.points = r.points and q.wins > r.wins))) end;
  select max(season) into last_s from public.game_arena_rating where season < s and wins + losses > 0;
  return jsonb_build_object(
    'season', s, 'ends_on', ends, 'days_left', (ends - d) + 1,
    'start', public._setting('game_arena_start'), 'k', public._setting('game_arena_k'), 'pair_max', public._setting('game_arena_pair_day'),
    'leagues', (select jsonb_agg(jsonb_build_object('key', l.key, 'name', l.name, 'min_points', l.min_points) order by l.ord) from public.game_arena_leagues l),
    'me', jsonb_build_object('points', r.points, 'league', lg, 'rank', v_rank, 'ranked', v_tot, 'wins', r.wins, 'losses', r.losses, 'best', r.best,
            'next_league', case when nx.key is null then null else jsonb_build_object('key', nx.key, 'name', nx.name, 'min_points', nx.min_points) end,
            'league_min', (select min_points from public.game_arena_leagues where key = lg)),
    'board', (select coalesce(jsonb_agg(jsonb_build_object('rank', b.rk, 'user_id', b.user_id, 'nickname', b.nickname, 'level', b.level, 'points', b.points, 'wins', b.wins, 'losses', b.losses,
                       'league', public._game_arena_league(b.points)) order by b.rk), '[]'::jsonb)
                from (select row_number() over (order by q.points desc, q.wins desc, p.nickname) as rk, q.user_id, p.nickname, h.level, q.points, q.wins, q.losses
                        from public.game_arena_rating q join public.profiles p on p.id = q.user_id join public.game_heroes h on h.user_id = q.user_id
                       where q.season = s and q.wins + q.losses > 0 and not p.suspended order by q.points desc, q.wins desc, p.nickname limit 20) b),
    'last_season', case when last_s is null then null else jsonb_build_object('season', last_s,
        'top', (select coalesce(jsonb_agg(jsonb_build_object('rank', b.rk, 'user_id', b.user_id, 'nickname', b.nickname, 'points', b.points, 'league', public._game_arena_league(b.points)) order by b.rk), '[]'::jsonb)
                  from (select row_number() over (order by q.points desc, q.wins desc, p.nickname) as rk, q.user_id, p.nickname, q.points
                          from public.game_arena_rating q join public.profiles p on p.id = q.user_id where q.season = last_s and q.wins + q.losses > 0 and not p.suspended
                         order by q.points desc, q.wins desc, p.nickname limit 3) b),
        'me', (select jsonb_build_object('rank', m.rk, 'points', m.points) from (select row_number() over (order by q.points desc, q.wins desc, p.nickname) as rk, q.user_id, q.points
                  from public.game_arena_rating q join public.profiles p on p.id = q.user_id where q.season = last_s and q.wins + q.losses > 0 and not p.suspended) m where m.user_id = v)) end,
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', z.duel_id, 'at', z.at, 'opponent_id', z.target_id, 'opponent', z.nickname, 'won', z.won, 'delta', z.delta, 'after', z.after_pts, 'counted', z.counted, 'reason', z.reason) order by z.at desc), '[]'::jsonb)
                 from (select l.duel_id, l.at, l.target_id, p.nickname, (g.winner_id = v) as won, l.delta, l.after_pts, l.counted, l.reason
                         from public.game_arena_log l join public.game_duels g on g.id = l.duel_id join public.profiles p on p.id = l.target_id
                        where l.user_id = v order by l.at desc limit 10) z));
end $$;

-- ---------- permessi ----------
revoke all on function public._game_arena_season(date), public._game_arena_league(integer), public._game_arena_points(uuid, text), public._game_arena_touch(uuid, text),
  public._game_arena_delta(integer, integer, boolean), public._game_arena_record(uuid, uuid, uuid, boolean, date) from public, anon, authenticated;
revoke all on function public.game_duel(uuid), public.game_arena_list(), public.game_arena_state() from public, anon;
grant execute on function public.game_duel(uuid), public.game_arena_list(), public.game_arena_state() to authenticated;
commit;
