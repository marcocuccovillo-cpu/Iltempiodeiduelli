-- =====================================================================
-- MIGRAZIONE 034 — La guerra degli Eroi: L'ALLENAMENTO
--   Una nuova attività per i giocatori che NON costa energia e NON dà XP né BC. Si apre dalla scheda «Allenamento».
--   Si sceglie UNA delle due forme (una alla volta):
--   1) ALLENAMENTO A TEMPO: si sceglie una statistica (Forza, Destrezza, Vigore, Spirito, Fortezza) e si lascia passare il tempo.
--      Finito il tempo la statistica sale di un «livello di allenamento» e ne guadagna un bonus permanente in %:
--        livello   ore     bonus totale sulla statistica
--           1       6         +1%
--           2       8         +2%
--           3      12         +3%
--           4      16         +4%
--           5      24         +5%
--           6      32         +6%
--           7      40         +7%
--           8      48         +8%
--           9      60         +9%
--          10      72        +10%        (massimo)
--      Il bonus si somma a quelli di oggetti, abilità e pet. Fermare un allenamento prima della fine ne fa perdere il progresso.
--   2) ALLENAMENTO IN AMICHEVOLE: combattimenti di prova contro un altro eroe che accetta sfide in Arena (lo stesso elenco dei duelli).
--      Non consumano energia, non danno XP né BC, non contano come duelli (niente vittorie/sconfitte in classifica, nessun effetto
--      sull'avversario). OGNI 50 COMBATTIMENTI VINTI (che contano) l'eroe guadagna 1 PUNTO ABILITÀ da distribuire nelle statistiche.
--      Contro gli abusi, valgono dei limiti al giorno (impostazioni modificabili da Admin):
--        * al massimo 10 vittorie al giorno contano per i punti (game_train_spar_day_wins),
--        * al massimo 3 vittorie al giorno contro lo stesso avversario (game_train_spar_pair_wins),
--        * al massimo 30 combattimenti al giorno in tutto (game_train_spar_day_fights).
--      Le vittorie oltre i limiti si possono fare ma NON contano. (10 al giorno = al massimo 1 punto ogni 5 giorni.)
--   MENTRE SI È IN ALLENAMENTO (a tempo non finito, oppure amichevole acceso) NON SI PUÒ ENTRARE NEI DUNGEON: né aprirne uno né
--   unirsi a una lobby. Si può fermare l'allenamento quando si vuole. Chi è in una lobby o in un dungeon in corso non può iniziare un
--   allenamento. La Torre Infinita e gli altri combattimenti non sono bloccati.
--   Si può rieseguire senza danni (livelli, vittorie e punti guadagnati restano).
--   Annullamento: black-market-eroi-allenamento-down.sql (rimette le funzioni di prima; i bonus e i punti dell'allenamento spariscono;
--   chi aveva distribuito più punti di quelli che gli restano deve ridistribuirli, gratis).
-- Da eseguire in Supabase (SQL Editor) DOPO le migrazioni della guerra degli Eroi, compresi i dungeon a scelte e Lo stagno (031).
-- Sostituisce tre funzioni esistenti: _game_calc (statistiche), _game_hero_json (scheda eroe) e game_set_stats (distribuzione dei punti).
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_heroes') is null or to_regclass('public.game_run_members') is null or to_regclass('public.game_runs') is null
     or to_regprocedure('public._game_calc(uuid)') is null or to_regprocedure('public._game_hero_json(uuid)') is null
     or to_regprocedure('public._game_pet_bonus(uuid)') is null or to_regprocedure('public._game_pet_card(uuid)') is null
     or to_regprocedure('public.game_set_stats(integer,integer,integer,integer,integer)') is null
     or to_regprocedure('public._game_sim(jsonb,jsonb)') is null or to_regprocedure('public._game_dng_expire()') is null then
    raise exception 'Prima esegui le migrazioni della guerra degli Eroi (dungeon a scelte e Lo stagno, 031, compresi). Non è stato modificato nulla.';
  end if;
end $$;

insert into public.system_settings (key, value_int, description) values
 ('game_train_spar_day_wins',   10, 'Allenamento amichevole: vittorie al giorno che contano per i punti abilità'),
 ('game_train_spar_pair_wins',   3, 'Allenamento amichevole: vittorie al giorno che contano contro lo stesso avversario'),
 ('game_train_spar_day_fights', 30, 'Allenamento amichevole: combattimenti al giorno in tutto (anche quelli persi)'),
 ('game_train_wins_per_point',  50, 'Allenamento amichevole: vittorie che contano per ogni punto abilità guadagnato')
on conflict (key) do nothing;

-- ---------- catalogo dei livelli di allenamento (si riscrive a ogni esecuzione) ----------
create table if not exists public.game_train_levels (
  level smallint primary key check (level between 1 and 99),
  hours integer not null check (hours > 0),
  bonus_pct integer not null check (bonus_pct > 0)
);
alter table public.game_train_levels enable row level security;
revoke all on public.game_train_levels from public, anon, authenticated;
insert into public.game_train_levels (level, hours, bonus_pct) values
  (1, 6, 1), (2, 8, 2), (3, 12, 3), (4, 16, 4), (5, 24, 5), (6, 32, 6), (7, 40, 7), (8, 48, 8), (9, 60, 9), (10, 72, 10)
on conflict (level) do update set hours = excluded.hours, bonus_pct = excluded.bonus_pct;

-- ---------- tabelle dei giocatori (chiuse al browser) ----------
create table if not exists public.game_training (          -- l'allenamento in corso (uno solo per eroe)
  user_id uuid primary key references public.profiles(id) on delete restrict,
  kind text not null check (kind in ('stat','spar')),
  stat text check (stat in ('for','des','vig','spi','frt')),
  target_level smallint check (target_level >= 1),
  started_at timestamptz not null default now(),
  ends_at timestamptz,
  check ((kind = 'stat' and stat is not null and target_level is not null and ends_at is not null) or (kind = 'spar' and stat is null and target_level is null and ends_at is null))
);
create table if not exists public.game_train_stats (       -- livelli di allenamento già completati, per statistica
  user_id uuid not null references public.profiles(id) on delete restrict,
  stat text not null check (stat in ('for','des','vig','spi','frt')),
  level smallint not null check (level >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, stat)
);
create table if not exists public.game_train_hero (        -- contatori dell'amichevole
  user_id uuid primary key references public.profiles(id) on delete restrict,
  spar_wins integer not null default 0 check (spar_wins >= 0),       -- vittorie che contano
  spar_fights integer not null default 0 check (spar_fights >= 0)
);
create table if not exists public.game_spar_log (          -- ogni combattimento amichevole
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  target_id uuid not null references public.profiles(id) on delete restrict,
  day date not null,
  won boolean not null,
  counted boolean not null,
  rounds integer,
  created_at timestamptz not null default now()
);
create index if not exists game_spar_log_user_day_idx on public.game_spar_log (user_id, day);
alter table public.game_training enable row level security;   revoke all on public.game_training from public, anon, authenticated;
alter table public.game_train_stats enable row level security; revoke all on public.game_train_stats from public, anon, authenticated;
alter table public.game_train_hero enable row level security;  revoke all on public.game_train_hero from public, anon, authenticated;
alter table public.game_spar_log enable row level security;    revoke all on public.game_spar_log from public, anon, authenticated;

-- ---------- funzioni interne ----------
-- livello di allenamento di una statistica: quelli completati, più quello dell'allenamento a tempo appena finito (si applica da solo, senza aspettare di riaprire la pagina)
create or replace function public._game_train_level(p_user uuid, p_stat text) returns integer language sql stable security definer set search_path = public as $$
  select greatest(coalesce((select s.level from public.game_train_stats s where s.user_id = p_user and s.stat = p_stat), 0),
                  coalesce((select t.target_level from public.game_training t where t.user_id = p_user and t.kind = 'stat' and t.stat = p_stat and t.ends_at <= now()), 0))::integer $$;

-- bonus % delle cinque statistiche (entra in _game_calc)
create or replace function public._game_train_bonus(p_user uuid) returns table (pf integer, pd integer, pv integer, ps integer, pr integer)
language sql stable security definer set search_path = public as $$
  select coalesce(max(case when x.stat = 'for' then l.bonus_pct end), 0)::integer, coalesce(max(case when x.stat = 'des' then l.bonus_pct end), 0)::integer,
         coalesce(max(case when x.stat = 'vig' then l.bonus_pct end), 0)::integer, coalesce(max(case when x.stat = 'spi' then l.bonus_pct end), 0)::integer,
         coalesce(max(case when x.stat = 'frt' then l.bonus_pct end), 0)::integer
  from (select s as stat, public._game_train_level(p_user, s) as lv from unnest(array['for','des','vig','spi','frt']) s) x
  left join public.game_train_levels l on l.level = x.lv $$;

-- punti abilità guadagnati con l'amichevole (uno ogni «game_train_wins_per_point» vittorie che contano)
create or replace function public._game_train_points(p_user uuid) returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select h.spar_wins / greatest(1, public._setting('game_train_wins_per_point')) from public.game_train_hero h where h.user_id = p_user), 0)::integer $$;

-- si è impegnati in un allenamento (a tempo non ancora finito, oppure amichevole acceso)?
create or replace function public._game_train_busy(p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.game_training t where t.user_id = p_user and (t.kind = 'spar' or t.ends_at > now())) $$;

-- scheda breve per il cruscotto (nulla se non ci si sta allenando)
create or replace function public._game_train_card(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('kind', t.kind, 'stat', t.stat, 'target_level', t.target_level, 'ends_at', t.ends_at)
  from public.game_training t where t.user_id = p_user and (t.kind = 'spar' or t.ends_at > now()) $$;

-- un allenamento a tempo finito diventa un livello in più (e libera l'eroe); ritorna cosa è successo, o null
create or replace function public._game_train_settle(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.game_training%rowtype;
begin
  select * into t from public.game_training where user_id = p_user and kind = 'stat' and ends_at <= now() for update;
  if not found then return null; end if;
  insert into public.game_train_stats (user_id, stat, level) values (p_user, t.stat, t.target_level)
    on conflict (user_id, stat) do update set level = greatest(game_train_stats.level, excluded.level), updated_at = now();
  delete from public.game_training where user_id = p_user;
  return jsonb_build_object('stat', t.stat, 'level', t.target_level, 'bonus_pct', (select bonus_pct from public.game_train_levels where level = t.target_level));
end $$;

-- chi si allena non può entrare in un dungeon (né aprirlo né unirsi a una lobby): lo impedisce il database, qualunque funzione lo chieda
create or replace function public._trg_run_members_train() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public._game_train_busy(new.user_id) then
    raise exception 'Sei in allenamento: fermalo (scheda Allenamento) prima di entrare in un dungeon';
  end if;
  return new;
end $$;
drop trigger if exists game_run_members_train on public.game_run_members;
create trigger game_run_members_train before insert on public.game_run_members for each row execute function public._trg_run_members_train();

-- ---------- le funzioni esistenti, aggiornate ----------
-- statistiche reali: in più i bonus dell'allenamento a tempo
create or replace function public._game_calc(p_user uuid)
returns table (level integer, s_for bigint, s_des bigint, s_vig bigint, s_spi bigint, s_frt bigint, max_hp bigint, xp_pct integer, extra_actions integer, extra_fights integer,
               b_for integer, b_des integer, b_vig integer, b_spi integer, b_frt integer)
language sql stable security definer set search_path = public as $$
  with h as (select * from public.game_heroes where user_id = p_user),
  b as (select coalesce(sum(i.p_for),0) pf, coalesce(sum(i.p_des),0) pd, coalesce(sum(i.p_vig),0) pv, coalesce(sum(i.p_spi),0) ps, coalesce(sum(i.p_frt),0) pr,
               coalesce(sum(i.xp_pct),0) px, coalesce(sum(i.extra_actions),0) pa, coalesce(sum(i.extra_fights),0) pq
        from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = p_user),
  k as (select coalesce(sum(s.p_for),0) kf, coalesce(sum(s.p_des),0) kd, coalesce(sum(s.p_vig),0) kv, coalesce(sum(s.p_spi),0) ks, coalesce(sum(s.p_frt),0) kr
        from (select skill_id from public.game_hero_skills where user_id = p_user
              union all select skill_id from public.game_temp_skills where user_id = p_user and expires_at > now()) x
        join public.game_skills s on s.id = x.skill_id),
  pb as (select * from public._game_pet_bonus(p_user)),
  tn as (select * from public._game_train_bonus(p_user)),
  t as (select b.pf + k.kf + pb.pf + tn.pf as tf, b.pd + k.kd + pb.pd + tn.pd as td, b.pv + k.kv + pb.pv + tn.pv as tv, b.ps + k.ks + pb.ps + tn.ps as ts, b.pr + k.kr + pb.pr + tn.pr as tr, b.px + pb.px as px, b.pa + pb.pa as pa, b.pq + pb.pq as pq from b, k, pb, tn),
  s as (select h.level,
          round((5 + h.a_for::numeric * h.level) * (100 + t.tf) / 100)::bigint as sf,
          round((5 + h.a_des::numeric * h.level) * (100 + t.td) / 100)::bigint as sd,
          round((5 + h.a_vig::numeric * h.level) * (100 + t.tv) / 100)::bigint as sv,
          round((5 + h.a_spi::numeric * h.level) * (100 + t.ts) / 100)::bigint as ss,
          round((5 + h.a_frt::numeric * h.level) * (100 + t.tr) / 100)::bigint as sr,
          t.tf, t.td, t.tv, t.ts, t.tr, t.px, t.pa, t.pq from h, t)
  select s.level, s.sf, s.sd, s.sv, s.ss, s.sr, 50 + 12 * s.sv, s.px::integer, s.pa::integer, s.pq::integer, s.tf::integer, s.td::integer, s.tv::integer, s.ts::integer, s.tr::integer from s $$;

-- scheda dell'eroe: punti in più dall'allenamento e allenamento in corso
create or replace function public._game_hero_json(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user_id', h.user_id, 'nickname', p.nickname, 'avatar', p.avatar,
    'level', h.level, 'xp', h.xp, 'xp_need', public._game_xp_need(h.level),
    'alloc', jsonb_build_object('for', h.a_for, 'des', h.a_des, 'vig', h.a_vig, 'spi', h.a_spi, 'frt', h.a_frt),
    'points', public._game_points(h.level) + public._game_train_points(h.user_id), 'points_free', public._game_points(h.level) + public._game_train_points(h.user_id) - (h.a_for + h.a_des + h.a_vig + h.a_spi + h.a_frt),
    'train_points', public._game_train_points(h.user_id), 'training', public._game_train_card(h.user_id),
    'stats', jsonb_build_object('for', c.s_for, 'des', c.s_des, 'vig', c.s_vig, 'spi', c.s_spi, 'frt', c.s_frt),
    'bonus', jsonb_build_object('for', c.b_for, 'des', c.b_des, 'vig', c.b_vig, 'spi', c.b_spi, 'frt', c.b_frt),
    'max_hp', c.max_hp, 'xp_pct', c.xp_pct, 'extra_actions', c.extra_actions, 'extra_fights', c.extra_fights,
    'stats_set', h.stats_set, 'arena_open', h.arena_open, 'duels_won', h.duels_won, 'duels_lost', h.duels_lost, 'bosses_beaten', h.bosses_beaten,
    'respec_count', h.respec_count, 'fights_total', h.fights_total, 'pet', public._game_pet_card(h.user_id),
    'equipped', coalesce((select jsonb_object_agg(e.slot, jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level,
        'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights, 'descr', i.descr))
      from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = h.user_id), '{}'::jsonb),
    'perm_skills', coalesce((select jsonb_agg(k.name order by k.stat, k.tier) from public.game_hero_skills s join public.game_skills k on k.id = s.skill_id where s.user_id = h.user_id), '[]'::jsonb),
    'temp_skills', coalesce((select jsonb_agg(jsonb_build_object('name', k.name, 'slot', k.slot, 'until', t.expires_at) order by t.expires_at)
                             from public.game_temp_skills t join public.game_skills k on k.id = t.skill_id where t.user_id = h.user_id and t.expires_at > now()), '[]'::jsonb))
  from public.game_heroes h join public.profiles p on p.id = h.user_id
  cross join lateral public._game_calc(h.user_id) c
  where h.user_id = p_user $$;

-- distribuzione dei punti: il monte punti comprende quelli guadagnati con l'amichevole
create or replace function public.game_set_stats(p_for integer, p_des integer, p_vig integer, p_spi integer, p_frt integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; v_pool integer;
        v_cap integer; v_cost integer := public._setting('game_respec_cost'); v_paid boolean := false; v_less boolean;
begin
  perform public._require_module('heroes');
  if p_for is null or p_des is null or p_vig is null or p_spi is null or p_frt is null then raise exception 'Punti non validi'; end if;
  if least(p_for, p_des, p_vig, p_spi, p_frt) < 0 then raise exception 'Punti non validi'; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v for update;
  v_pool := public._game_points(h.level) + public._game_train_points(v);       -- i punti guadagnati con l'allenamento amichevole
  v_cap := greatest(1, public._setting('game_stat_cap')) + public._setting('game_points_per_level') * (h.level - 1);    -- il tetto sale con i livelli
  if greatest(p_for, p_des, p_vig, p_spi, p_frt) > v_cap then raise exception 'Massimo % punti su una singola statistica', v_cap; end if;
  if p_for + p_des + p_vig + p_spi + p_frt > v_pool then raise exception 'Hai solo % punti da distribuire', v_pool; end if;
  if h.stats_set and (h.a_for, h.a_des, h.a_vig, h.a_spi, h.a_frt) = (p_for, p_des, p_vig, p_spi, p_frt) then
    return public._game_hero_json(v) || jsonb_build_object('paid', 0);   -- nessuna modifica: niente da pagare
  end if;
  v_less := p_for < h.a_for or p_des < h.a_des or p_vig < h.a_vig or p_spi < h.a_spi or p_frt < h.a_frt;
  if h.stats_set and v_less and h.fights_total > 0 and v_cost > 0 then
    perform public._ledger_move(v, -v_cost, 'game_respec', 'game_hero', null, 'gamerespec:' || v::text || ':' || (h.respec_count + 1)::text, 'La guerra degli Eroi: nuova distribuzione dei punti');
    v_paid := true;
  end if;
  update public.game_heroes set a_for = p_for, a_des = p_des, a_vig = p_vig, a_spi = p_spi, a_frt = p_frt, stats_set = true,
         respec_count = respec_count + case when h.stats_set then 1 else 0 end where user_id = v;
  return public._game_hero_json(v) || jsonb_build_object('paid', case when v_paid then v_cost else 0 end);
end $$;

-- ---------- funzioni pubbliche ----------
create or replace function public.game_train_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := public._game_today(); fin jsonb; t public.game_training%rowtype;
        h public.game_train_hero%rowtype; wps integer := greatest(1, public._setting('game_train_wins_per_point')); mx integer; lv integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  fin := public._game_train_settle(v);
  select * into t from public.game_training where user_id = v;
  select * into h from public.game_train_hero where user_id = v;
  select max(level) into mx from public.game_train_levels;
  return jsonb_build_object(
    'finished', fin,
    'active', case when t.user_id is null then null else jsonb_build_object('kind', t.kind, 'stat', t.stat, 'target_level', t.target_level, 'started_at', t.started_at, 'ends_at', t.ends_at,
                 'seconds_left', case when t.ends_at is null then null else greatest(0, ceil(extract(epoch from (t.ends_at - now()))))::integer end) end,
    'max_level', mx,
    'levels', (select jsonb_agg(jsonb_build_object('level', l.level, 'hours', l.hours, 'bonus_pct', l.bonus_pct) order by l.level) from public.game_train_levels l),
    'stats', (select jsonb_agg(jsonb_build_object('stat', s.stat, 'level', s.lv, 'bonus_pct', coalesce(cl.bonus_pct, 0),
                'next', case when nl.level is null then null else jsonb_build_object('level', nl.level, 'hours', nl.hours, 'bonus_pct', nl.bonus_pct) end) order by s.ord)
              from (select x.stat, x.ord, public._game_train_level(v, x.stat) as lv from unnest(array['for','des','vig','spi','frt']) with ordinality as x(stat, ord)) s
              left join public.game_train_levels cl on cl.level = s.lv left join public.game_train_levels nl on nl.level = s.lv + 1),
    'spar', jsonb_build_object('wins', coalesce(h.spar_wins, 0), 'fights', coalesce(h.spar_fights, 0), 'per_point', wps, 'points', coalesce(h.spar_wins, 0) / wps,
                'to_next', wps - (coalesce(h.spar_wins, 0) % wps),
                'today', jsonb_build_object('fights', (select count(*) from public.game_spar_log q where q.user_id = v and q.day = d),
                                            'counted', (select count(*) from public.game_spar_log q where q.user_id = v and q.day = d and q.counted),
                                            'max_fights', public._setting('game_train_spar_day_fights'), 'max_wins', public._setting('game_train_spar_day_wins'), 'pair_max', public._setting('game_train_spar_pair_wins')),
                'pair', coalesce((select jsonb_object_agg(x.target_id::text, x.c) from (select q.target_id, count(*) as c from public.game_spar_log q where q.user_id = v and q.day = d and q.counted group by q.target_id) x), '{}'::jsonb)),
    'train_points', public._game_train_points(v),
    'in_dungeon', exists (select 1 from public.game_run_members m join public.game_runs r on r.id = m.run_id where m.user_id = v and r.status in ('lobby','active')));
end $$;

create or replace function public.game_train_start(p_kind text, p_stat text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); cur integer; l public.game_train_levels%rowtype;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform 1 from public.game_heroes where user_id = v for update;
  perform public._game_dng_expire();
  perform public._game_train_settle(v);
  if p_kind is null or p_kind not in ('stat','spar') then raise exception 'Scegli un tipo di allenamento'; end if;
  if exists (select 1 from public.game_training where user_id = v) then raise exception 'Hai già un allenamento in corso: fermalo prima'; end if;
  if exists (select 1 from public.game_run_members m join public.game_runs r on r.id = m.run_id where m.user_id = v and r.status in ('lobby','active')) then
    raise exception 'Sei in una lobby o in un dungeon: esci prima di iniziare un allenamento';
  end if;
  if p_kind = 'stat' then
    if p_stat is null or p_stat not in ('for','des','vig','spi','frt') then raise exception 'Scegli una statistica da allenare'; end if;
    cur := public._game_train_level(v, p_stat);
    select * into l from public.game_train_levels where level = cur + 1;
    if not found then raise exception 'Questa statistica è già al livello massimo di allenamento'; end if;
    insert into public.game_training (user_id, kind, stat, target_level, started_at, ends_at) values (v, 'stat', p_stat, l.level, now(), now() + make_interval(hours => l.hours));
  else
    insert into public.game_training (user_id, kind) values (v, 'spar');
  end if;
  return public.game_train_state();
end $$;

create or replace function public.game_train_stop() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); t public.game_training%rowtype; fin jsonb;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform 1 from public.game_heroes where user_id = v for update;
  fin := public._game_train_settle(v);
  select * into t from public.game_training where user_id = v for update;
  if not found then
    if fin is not null then return public.game_train_state() || jsonb_build_object('stopped', null, 'lost', false); end if;
    raise exception 'Nessun allenamento in corso';
  end if;
  delete from public.game_training where user_id = v;
  return public.game_train_state() || jsonb_build_object('stopped', t.kind, 'lost', t.kind = 'stat');
end $$;

-- combattimento amichevole: niente energia, XP, BC; non è un duello (non tocca vittorie/sconfitte, né l'avversario)
create or replace function public.game_spar(p_target uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := public._game_today();
  a public.game_heroes%rowtype; b public.game_heroes%rowtype; ca jsonb; cb jsonb; sim jsonb; v_win boolean; v_first uuid; v_second uuid; pn text;
  n_day integer; n_cnt integer; n_pair integer; v_counted boolean := false; v_reason text := null; wps integer := greatest(1, public._setting('game_train_wins_per_point'));
  w0 integer; w1 integer; hh public.game_train_hero%rowtype;
begin
  perform public._require_module('heroes');
  if p_target is null or p_target = v then raise exception 'Scegli un altro eroe con cui allenarti'; end if;
  perform public._game_ensure_hero(v);
  if not exists (select 1 from public.profiles where id = p_target and not suspended) then raise exception 'Eroe non disponibile'; end if;
  if not exists (select 1 from public.game_heroes where user_id = p_target) then raise exception 'Questo duellante non è ancora un eroe'; end if;
  v_first := least(v, p_target); v_second := greatest(v, p_target);                  -- blocco in ordine fisso (come i duelli)
  perform 1 from public.game_heroes where user_id = v_first for update;
  perform 1 from public.game_heroes where user_id = v_second for update;
  perform public._game_train_settle(v);
  if not exists (select 1 from public.game_training where user_id = v and kind = 'spar') then raise exception 'Per combattere in amichevole devi prima iniziare l''allenamento amichevole'; end if;
  select * into a from public.game_heroes where user_id = v;
  select * into b from public.game_heroes where user_id = p_target;
  if not a.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  if not b.stats_set then raise exception 'Questo eroe non ha ancora assegnato i suoi punti abilità'; end if;
  if not b.arena_open then raise exception 'Questo eroe non accetta sfide in Arena'; end if;
  select count(*) into n_day from public.game_spar_log where user_id = v and day = d;
  if n_day >= public._setting('game_train_spar_day_fights') then raise exception 'Hai fatto abbastanza amichevoli per oggi (%): riprova domani', public._setting('game_train_spar_day_fights'); end if;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  select to_jsonb(x) into cb from public._game_calc(p_target) x;
  sim := public._game_sim(ca, cb);
  v_win := sim->>'winner' = 'a';
  select count(*) into n_cnt from public.game_spar_log where user_id = v and day = d and counted;
  select count(*) into n_pair from public.game_spar_log where user_id = v and day = d and counted and target_id = p_target;
  if v_win then
    if n_cnt >= public._setting('game_train_spar_day_wins') then v_reason := 'day';
    elsif n_pair >= public._setting('game_train_spar_pair_wins') then v_reason := 'pair';
    else v_counted := true; end if;
  end if;
  insert into public.game_spar_log (user_id, target_id, day, won, counted, rounds) values (v, p_target, d, v_win, v_counted, (sim->>'rounds')::integer);
  insert into public.game_train_hero (user_id, spar_wins, spar_fights) values (v, case when v_counted then 1 else 0 end, 1)
    on conflict (user_id) do update set spar_wins = game_train_hero.spar_wins + case when v_counted then 1 else 0 end, spar_fights = game_train_hero.spar_fights + 1;
  select * into hh from public.game_train_hero where user_id = v;
  w1 := hh.spar_wins / wps; w0 := (hh.spar_wins - case when v_counted then 1 else 0 end) / wps;
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('friendly', true, 'won', v_win, 'counted', v_counted, 'reason', v_reason, 'opponent', pn, 'opponent_level', b.level, 'rounds', sim->'rounds',
           'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'spar_wins', hh.spar_wins, 'to_next', wps - (hh.spar_wins % wps), 'point_gained', w1 > w0,
           'today_counted', n_cnt + case when v_counted then 1 else 0 end, 'today_fights', n_day + 1);
end $$;

-- ---------- permessi ----------
revoke all on function public._game_train_level(uuid, text), public._game_train_bonus(uuid), public._game_train_points(uuid), public._game_train_busy(uuid),
  public._game_train_card(uuid), public._game_train_settle(uuid), public._trg_run_members_train() from public, anon, authenticated;
revoke all on function public.game_train_state(), public.game_train_start(text, text), public.game_train_stop(), public.game_spar(uuid) from public, anon;
grant execute on function public.game_train_state(), public.game_train_start(text, text), public.game_train_stop(), public.game_spar(uuid) to authenticated;
commit;
