-- =====================================================================
-- ANNULLAMENTO della MIGRAZIONE 031 (Lo stagno, pet companion)
-- Restituisce i BC dei pet comprati (movimento «admin_adjustment» nel registro), rimette le funzioni _game_calc, _game_hero_json e _game_add_xp
-- come prima, e toglie funzioni, tabelle e impostazioni dei pet. I tre pet base scelti e i livelli dei pet si perdono.
-- =====================================================================
begin;
do $$
declare r record; n integer := 0;
begin
  if to_regclass('public.game_hero_pets') is not null then
    for r in select hp.user_id, hp.pet_id, g.price_bc, g.name from public.game_hero_pets hp join public.game_pets g on g.id = hp.pet_id where g.price_bc > 0 order by hp.user_id, hp.pet_id loop
      perform public._ledger_move(r.user_id, r.price_bc, 'admin_adjustment', 'game_pet', null, 'gamepetdown:' || r.user_id::text || ':' || r.pet_id, 'Lo stagno: ' || r.name || ' rimborsato (annullamento della migrazione)');
      n := n + 1;
    end loop;
    if n > 0 then perform public._audit(null, 'pet_down_refund', 'game_pet', null, null, jsonb_build_object('refunded', n), 'annullamento della migrazione Lo stagno'); end if;
  end if;
end $$;

-- le funzioni tornano come prima (le versioni senza pet)
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
  t as (select b.pf + k.kf as tf, b.pd + k.kd as td, b.pv + k.kv as tv, b.ps + k.ks as ts, b.pr + k.kr as tr, b.px, b.pa, b.pq from b, k),
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
    'respec_count', h.respec_count, 'fights_total', h.fights_total,
    'equipped', coalesce((select jsonb_object_agg(e.slot, jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level,
        'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights, 'descr', i.descr))
      from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = h.user_id), '{}'::jsonb),
    'perm_skills', coalesce((select jsonb_agg(k.name order by k.stat, k.tier) from public.game_hero_skills s join public.game_skills k on k.id = s.skill_id where s.user_id = h.user_id), '[]'::jsonb),
    'temp_skills', coalesce((select jsonb_agg(jsonb_build_object('name', k.name, 'slot', k.slot, 'until', t.expires_at) order by t.expires_at)
                             from public.game_temp_skills t join public.game_skills k on k.id = t.skill_id where t.user_id = h.user_id and t.expires_at > now()), '[]'::jsonb))
  from public.game_heroes h join public.profiles p on p.id = h.user_id
  cross join lateral public._game_calc(h.user_id) c
  where h.user_id = p_user $$;

create or replace function public._game_add_xp(p_user uuid, p_xp bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; pct integer; add_ bigint; gained integer := 0; cap integer := public._game_level_cap(); lvl0 integer; refill boolean := false;
begin
  select * into h from public.game_heroes where user_id = p_user for update;
  if not found then raise exception 'Eroe inesistente'; end if;
  lvl0 := h.level;          -- livello di partenza: è questo che decide se la ricarica è ancora attiva
  select xp_pct into pct from public._game_calc(p_user);
  add_ := greatest(0, p_xp) * (100 + coalesce(pct, 0)) / 100;
  if h.level < cap then
    h.xp := h.xp + add_;
    while h.level < cap and h.xp >= public._game_xp_need(h.level) loop
      h.xp := h.xp - public._game_xp_need(h.level); h.level := h.level + 1; gained := gained + 1;
    end loop;
    if h.level >= cap then h.xp := 0; end if;
  else
    h.xp := 0;      -- già al limite (o oltre, se il limite è stato abbassato): il livello non cambia, l'XP in eccesso non si accumula
  end if;
  update public.game_heroes set level = h.level, xp = h.xp, total_xp = total_xp + add_ where user_id = p_user;
  if gained > 0 and lvl0 < public._game_refill_below_level() then      -- salire di livello ricarica la batteria al 100%, ma solo se si partiva sotto il livello 100
    update public.game_heroes set energy = public._game_energy_max(), energy_at = now() where user_id = p_user;
    refill := true;
  end if;
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level, 'energy_full', refill, 'cap', cap);
end $$;

revoke all on function public._game_calc(uuid), public._game_hero_json(uuid), public._game_add_xp(uuid, bigint) from public, anon, authenticated;

drop function if exists public.game_pet_activate(text);
drop function if exists public.game_pet_buy(text);
drop function if exists public.game_pet_choose(text);
drop function if exists public.game_pet_state();
drop function if exists public._game_pet_gain(uuid, bigint);
drop function if exists public._game_pet_card(uuid);
drop function if exists public._game_pet_bonus(uuid);
drop function if exists public._game_pet_value(integer, integer, integer, integer);
drop function if exists public._game_pet_max_level();
drop function if exists public._game_pet_xp_pct();
drop table if exists public.game_hero_pets;
drop table if exists public.game_pet_lines;
drop table if exists public.game_pets;
delete from public.system_settings where key in ('game_pet_xp_pct', 'game_pet_max_level');
commit;
