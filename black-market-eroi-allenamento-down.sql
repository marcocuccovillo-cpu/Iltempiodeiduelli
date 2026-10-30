-- =====================================================================
-- ANNULLA la migrazione 034 (Allenamento): rimette le funzioni di prima e toglie tabelle, controllo sui dungeon e impostazioni.
-- Si perdono i livelli di allenamento, i bonus %, le vittorie in amichevole e i PUNTI ABILITÀ guadagnati con l'allenamento.
-- Chi ha distribuito più punti di quelli che gli restano (livello + base) viene rimesso a «punti da distribuire» e li ridistribuisce
-- gratis (nessun costo di nuova distribuzione). Gli altri eroi non cambiano. Si può rieseguire senza danni.
-- =====================================================================
begin;

drop trigger if exists game_run_members_train on public.game_run_members;
drop function if exists public._trg_run_members_train();

-- funzioni com'erano prima (copie delle versioni della migrazione 031 e della 023)
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
  t as (select b.pf + k.kf + pb.pf as tf, b.pd + k.kd + pb.pd as td, b.pv + k.kv + pb.pv as tv, b.ps + k.ks + pb.ps as ts, b.pr + k.kr + pb.pr as tr, b.px + pb.px as px, b.pa + pb.pa as pa, b.pq + pb.pq as pq from b, k, pb),
  s as (select h.level,
          round((5 + h.a_for::numeric * h.level) * (100 + t.tf) / 100)::bigint as sf,
          round((5 + h.a_des::numeric * h.level) * (100 + t.td) / 100)::bigint as sd,
          round((5 + h.a_vig::numeric * h.level) * (100 + t.tv) / 100)::bigint as sv,
          round((5 + h.a_spi::numeric * h.level) * (100 + t.ts) / 100)::bigint as ss,
          round((5 + h.a_frt::numeric * h.level) * (100 + t.tr) / 100)::bigint as sr,
          t.tf, t.td, t.tv, t.ts, t.tr, t.px, t.pa, t.pq from h, t)
  select s.level, s.sf, s.sd, s.sv, s.ss, s.sr, 50 + 12 * s.sv, s.px::integer, s.pa::integer, s.pq::integer, s.tf::integer, s.td::integer, s.tv::integer, s.ts::integer, s.tr::integer from s $$;

create or replace function public._game_hero_json(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user_id', h.user_id, 'nickname', p.nickname, 'avatar', p.avatar,
    'level', h.level, 'xp', h.xp, 'xp_need', public._game_xp_need(h.level),
    'alloc', jsonb_build_object('for', h.a_for, 'des', h.a_des, 'vig', h.a_vig, 'spi', h.a_spi, 'frt', h.a_frt),
    'points', public._game_points(h.level), 'points_free', public._game_points(h.level) - (h.a_for + h.a_des + h.a_vig + h.a_spi + h.a_frt),
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

create or replace function public.game_set_stats(p_for integer, p_des integer, p_vig integer, p_spi integer, p_frt integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; v_pool integer;
        v_cap integer; v_cost integer := public._setting('game_respec_cost'); v_paid boolean := false; v_less boolean;
begin
  perform public._require_module('heroes');
  if p_for is null or p_des is null or p_vig is null or p_spi is null or p_frt is null then raise exception 'Punti non validi'; end if;
  if least(p_for, p_des, p_vig, p_spi, p_frt) < 0 then raise exception 'Punti non validi'; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v for update;
  v_pool := public._game_points(h.level);
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

-- chi ha più punti distribuiti di quelli che gli spettano senza l'allenamento: ridistribuzione gratuita
update public.game_heroes set a_for = 0, a_des = 0, a_vig = 0, a_spi = 0, a_frt = 0, stats_set = false
  where a_for + a_des + a_vig + a_spi + a_frt > public._game_points(level);

drop function if exists public.game_spar(uuid);
drop function if exists public.game_train_stop();
drop function if exists public.game_train_start(text, text);
drop function if exists public.game_train_state();
drop function if exists public._game_train_settle(uuid);
drop function if exists public._game_train_card(uuid);
drop function if exists public._game_train_busy(uuid);
drop function if exists public._game_train_points(uuid);
drop function if exists public._game_train_bonus(uuid);
drop function if exists public._game_train_level(uuid, text);
drop table if exists public.game_spar_log;
drop table if exists public.game_train_hero;
drop table if exists public.game_train_stats;
drop table if exists public.game_training;
drop table if exists public.game_train_levels;
delete from public.system_settings where key in ('game_train_spar_day_wins', 'game_train_spar_pair_wins', 'game_train_spar_day_fights', 'game_train_wins_per_point');
commit;
