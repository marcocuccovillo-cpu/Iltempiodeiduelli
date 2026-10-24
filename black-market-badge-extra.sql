-- =====================================================================
-- MIGRAZIONE — NUOVI BADGE DEL SENTIERO: Guerra degli Eroi, Scommesse e Duel Simulator
-- Da eseguire DOPO black-market-badge.sql, black-market-eroi*.sql, black-market-scommesse.sql e black-market-duel-simulator.sql.
--
-- Cosa fa (91 medaglie in 3 aree nuove + 1 speciale):
--  * badge_extra_defs: catalogo in sola lettura dei nuovi traguardi (stessa forma di badge_defs). Le soglie si cambiano solo con una nuova migrazione.
--  * badge_progress_extra(p_user): calcola ogni nuovo badge AL MOMENTO dai dati ufficiali (eroi, dungeon, scommesse, duelli del simulatore).
--    Restituisce le stesse colonne di badge_progress, così il Sentiero e i profili li uniscono ai badge di prima.
-- Garanzie: non scrive nulla (nessun badge è memorizzato: non si assegnano a mano né si barano dal browser), non dà Black Credits,
-- non tocca badge_defs, badge_progress, wallet, registro, taglie, Ladder, Eroi, scommesse, Shop o Duel Simulator. Si può rieseguire.
-- Privacy: le scommesse sono private. Chi guarda il profilo di un altro vede SOLO quali badge delle scommesse ha ottenuto
-- (mai quanto ha puntato, vinto o guadagnato): il progresso vero lo vedono solo il diretto interessato e l'amministratore.
-- Con il modulo Eroi o Duel Simulator spento i relativi badge spariscono (tornano identici alla riaccensione).
-- Annullamento: black-market-badge-extra-down.sql (non perde nulla: i badge sono derivati).
-- =====================================================================
begin;

create table if not exists public.badge_extra_defs (
  code text primary key,
  family text not null,
  area text not null check (area in ('eroi', 'bets', 'sim', 'special')),
  tier smallint not null check (tier between 1 and 5),
  metric text not null,
  kind text not null check (kind in ('count', 'max', 'sum')),
  threshold bigint not null check (threshold >= 1),
  sort integer not null
);
alter table public.badge_extra_defs enable row level security;
drop policy if exists badge_extra_defs_read on public.badge_extra_defs;
create policy badge_extra_defs_read on public.badge_extra_defs for select to authenticated using (true);
revoke all on public.badge_extra_defs from public, anon, authenticated;
grant select on public.badge_extra_defs to authenticated;

-- catalogo: si riscrive a ogni esecuzione (i valori sono quelli del gioco)
delete from public.badge_extra_defs;
insert into public.badge_extra_defs (code, family, area, tier, metric, kind, threshold, sort) values
 ('e_livello_1', 'e_livello', 'eroi', 1, 'e_level', 'max', 5, 1000),
 ('e_livello_2', 'e_livello', 'eroi', 2, 'e_level', 'max', 10, 1001),
 ('e_livello_3', 'e_livello', 'eroi', 3, 'e_level', 'max', 25, 1002),
 ('e_livello_4', 'e_livello', 'eroi', 4, 'e_level', 'max', 50, 1003),
 ('e_boss_1', 'e_boss', 'eroi', 1, 'e_boss', 'count', 1, 1004),
 ('e_boss_2', 'e_boss', 'eroi', 2, 'e_boss', 'count', 5, 1005),
 ('e_boss_3', 'e_boss', 'eroi', 3, 'e_boss', 'count', 15, 1006),
 ('e_boss_4', 'e_boss', 'eroi', 4, 'e_boss', 'count', 40, 1007),
 ('e_arena_1', 'e_arena', 'eroi', 1, 'e_arena', 'count', 1, 1008),
 ('e_arena_2', 'e_arena', 'eroi', 2, 'e_arena', 'count', 10, 1009),
 ('e_arena_3', 'e_arena', 'eroi', 3, 'e_arena', 'count', 30, 1010),
 ('e_arena_4', 'e_arena', 'eroi', 4, 'e_arena', 'count', 75, 1011),
 ('e_dungeon_1', 'e_dungeon', 'eroi', 1, 'e_dungeon', 'count', 1, 1012),
 ('e_dungeon_2', 'e_dungeon', 'eroi', 2, 'e_dungeon', 'count', 5, 1013),
 ('e_dungeon_3', 'e_dungeon', 'eroi', 3, 'e_dungeon', 'count', 15, 1014),
 ('e_dungeon_4', 'e_dungeon', 'eroi', 4, 'e_dungeon', 'count', 40, 1015),
 ('e_squadra_1', 'e_squadra', 'eroi', 1, 'e_squadra', 'count', 1, 1016),
 ('e_squadra_2', 'e_squadra', 'eroi', 2, 'e_squadra', 'count', 5, 1017),
 ('e_squadra_3', 'e_squadra', 'eroi', 3, 'e_squadra', 'count', 15, 1018),
 ('e_squadra_4', 'e_squadra', 'eroi', 4, 'e_squadra', 'count', 40, 1019),
 ('e_attacchi_1', 'e_attacchi', 'eroi', 1, 'e_attacchi', 'count', 10, 1020),
 ('e_attacchi_2', 'e_attacchi', 'eroi', 2, 'e_attacchi', 'count', 50, 1021),
 ('e_attacchi_3', 'e_attacchi', 'eroi', 3, 'e_attacchi', 'count', 150, 1022),
 ('e_attacchi_4', 'e_attacchi', 'eroi', 4, 'e_attacchi', 'count', 400, 1023),
 ('e_cure_1', 'e_cure', 'eroi', 1, 'e_cure', 'count', 5, 1024),
 ('e_cure_2', 'e_cure', 'eroi', 2, 'e_cure', 'count', 25, 1025),
 ('e_cure_3', 'e_cure', 'eroi', 3, 'e_cure', 'count', 75, 1026),
 ('e_cure_4', 'e_cure', 'eroi', 4, 'e_cure', 'count', 200, 1027),
 ('e_guardia_1', 'e_guardia', 'eroi', 1, 'e_guardia', 'count', 5, 1028),
 ('e_guardia_2', 'e_guardia', 'eroi', 2, 'e_guardia', 'count', 25, 1029),
 ('e_guardia_3', 'e_guardia', 'eroi', 3, 'e_guardia', 'count', 75, 1030),
 ('e_guardia_4', 'e_guardia', 'eroi', 4, 'e_guardia', 'count', 200, 1031),
 ('e_arsenale_1', 'e_arsenale', 'eroi', 1, 'e_arsenale', 'count', 3, 1032),
 ('e_arsenale_2', 'e_arsenale', 'eroi', 2, 'e_arsenale', 'count', 8, 1033),
 ('e_arsenale_3', 'e_arsenale', 'eroi', 3, 'e_arsenale', 'count', 15, 1034),
 ('e_arsenale_4', 'e_arsenale', 'eroi', 4, 'e_arsenale', 'count', 25, 1035),
 ('e_ruoli_1', 'e_ruoli', 'eroi', 5, 'e_ruoli', 'count', 3, 1036),
 ('b_puntate_1', 'b_puntate', 'bets', 1, 'b_puntate', 'count', 1, 1037),
 ('b_puntate_2', 'b_puntate', 'bets', 2, 'b_puntate', 'count', 10, 1038),
 ('b_puntate_3', 'b_puntate', 'bets', 3, 'b_puntate', 'count', 30, 1039),
 ('b_puntate_4', 'b_puntate', 'bets', 4, 'b_puntate', 'count', 75, 1040),
 ('b_vinte_1', 'b_vinte', 'bets', 1, 'b_vinte', 'count', 1, 1041),
 ('b_vinte_2', 'b_vinte', 'bets', 2, 'b_vinte', 'count', 5, 1042),
 ('b_vinte_3', 'b_vinte', 'bets', 3, 'b_vinte', 'count', 15, 1043),
 ('b_vinte_4', 'b_vinte', 'bets', 4, 'b_vinte', 'count', 40, 1044),
 ('b_serie_1', 'b_serie', 'bets', 1, 'b_serie', 'max', 3, 1045),
 ('b_serie_2', 'b_serie', 'bets', 2, 'b_serie', 'max', 5, 1046),
 ('b_serie_3', 'b_serie', 'bets', 3, 'b_serie', 'max', 8, 1047),
 ('b_quota_1', 'b_quota', 'bets', 1, 'b_quota', 'max', 300, 1048),
 ('b_quota_2', 'b_quota', 'bets', 2, 'b_quota', 'max', 500, 1049),
 ('b_quota_3', 'b_quota', 'bets', 3, 'b_quota', 'max', 800, 1050),
 ('b_vincita_1', 'b_vincita', 'bets', 1, 'b_vincita', 'max', 100, 1051),
 ('b_vincita_2', 'b_vincita', 'bets', 2, 'b_vincita', 'max', 250, 1052),
 ('b_vincita_3', 'b_vincita', 'bets', 3, 'b_vincita', 'max', 500, 1053),
 ('b_vincita_4', 'b_vincita', 'bets', 4, 'b_vincita', 'max', 1000, 1054),
 ('b_profitto_1', 'b_profitto', 'bets', 1, 'b_profitto', 'sum', 200, 1055),
 ('b_profitto_2', 'b_profitto', 'bets', 2, 'b_profitto', 'sum', 1000, 1056),
 ('b_profitto_3', 'b_profitto', 'bets', 3, 'b_profitto', 'sum', 3000, 1057),
 ('b_volume_1', 'b_volume', 'bets', 1, 'b_volume', 'sum', 500, 1058),
 ('b_volume_2', 'b_volume', 'bets', 2, 'b_volume', 'sum', 2500, 1059),
 ('b_volume_3', 'b_volume', 'bets', 3, 'b_volume', 'sum', 10000, 1060),
 ('b_volume_4', 'b_volume', 'bets', 4, 'b_volume', 'sum', 25000, 1061),
 ('b_outsider_1', 'b_outsider', 'bets', 1, 'b_outsider', 'count', 1, 1062),
 ('b_outsider_2', 'b_outsider', 'bets', 2, 'b_outsider', 'count', 5, 1063),
 ('b_outsider_3', 'b_outsider', 'bets', 3, 'b_outsider', 'count', 15, 1064),
 ('s_partite_1', 's_partite', 'sim', 1, 's_partite', 'count', 1, 1065),
 ('s_partite_2', 's_partite', 'sim', 2, 's_partite', 'count', 10, 1066),
 ('s_partite_3', 's_partite', 'sim', 3, 's_partite', 'count', 30, 1067),
 ('s_partite_4', 's_partite', 'sim', 4, 's_partite', 'count', 75, 1068),
 ('s_vittorie_1', 's_vittorie', 'sim', 1, 's_vittorie', 'count', 1, 1069),
 ('s_vittorie_2', 's_vittorie', 'sim', 2, 's_vittorie', 'count', 5, 1070),
 ('s_vittorie_3', 's_vittorie', 'sim', 3, 's_vittorie', 'count', 15, 1071),
 ('s_vittorie_4', 's_vittorie', 'sim', 4, 's_vittorie', 'count', 40, 1072),
 ('s_duelli_1', 's_duelli', 'sim', 1, 's_duelli', 'count', 3, 1073),
 ('s_duelli_2', 's_duelli', 'sim', 2, 's_duelli', 'count', 15, 1074),
 ('s_duelli_3', 's_duelli', 'sim', 3, 's_duelli', 'count', 50, 1075),
 ('s_duelli_4', 's_duelli', 'sim', 4, 's_duelli', 'count', 120, 1076),
 ('s_serie_1', 's_serie', 'sim', 1, 's_serie', 'max', 3, 1077),
 ('s_serie_2', 's_serie', 'sim', 2, 's_serie', 'max', 5, 1078),
 ('s_serie_3', 's_serie', 'sim', 3, 's_serie', 'max', 8, 1079),
 ('s_rimonta_1', 's_rimonta', 'sim', 1, 's_rimonta', 'count', 1, 1080),
 ('s_rimonta_2', 's_rimonta', 'sim', 2, 's_rimonta', 'count', 3, 1081),
 ('s_rimonta_3', 's_rimonta', 'sim', 3, 's_rimonta', 'count', 8, 1082),
 ('s_mazzi_1', 's_mazzi', 'sim', 1, 's_mazzi', 'count', 1, 1083),
 ('s_mazzi_2', 's_mazzi', 'sim', 2, 's_mazzi', 'count', 3, 1084),
 ('s_mazzi_3', 's_mazzi', 'sim', 3, 's_mazzi', 'count', 8, 1085),
 ('s_mazzi_4', 's_mazzi', 'sim', 4, 's_mazzi', 'count', 15, 1086),
 ('s_invitto_1', 's_invitto', 'sim', 1, 's_invitto', 'count', 1, 1087),
 ('s_invitto_2', 's_invitto', 'sim', 2, 's_invitto', 'count', 3, 1088),
 ('s_invitto_3', 's_invitto', 'sim', 3, 's_invitto', 'count', 10, 1089),
 ('x_tre_1', 'x_tre', 'special', 5, 'x_tre', 'count', 3, 1090);

create or replace function public.badge_progress_extra(p_user uuid default null)
returns table (code text, family text, area text, tier smallint, metric text, kind text, threshold bigint, value bigint,
               earned boolean, earned_at timestamptz, hidden boolean, sort integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_u uuid := coalesce(p_user, auth.uid());
  v_self boolean;
  v_h boolean;
  v_s boolean;
begin
  if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
  if v_u is null or not exists (select 1 from public.profiles pr where pr.id = v_u) then return; end if;
  v_self := v_u = auth.uid() or public.is_admin();
  v_h := public._module_on('heroes');
  v_s := public._module_on('duel');

  return query
  with
  sl as (   -- incontri del Duel Simulator conclusi normalmente (chi abbandona non fa numero)
    select l.id, l.finished_at, l.winner_seat, sp.seat
      from public.sim_lobbies l join public.sim_players sp on sp.lobby_id = l.id and sp.user_id = v_u
     where l.status = 'finished' and l.winner_seat is not null and l.end_reason = 'normale'),
  sg as (   -- duelli singoli conclusi di quegli incontri
    select g.id, g.ended_at, g.winner_seat, g.lobby_id, g.no, sl.seat,
           case sl.seat when 1 then g.lp_1 else g.lp_2 end as my_lp
      from public.sim_games g join sl on sl.id = g.lobby_id
     where g.status = 'finished' and g.winner_seat is not null),
  m0 as (
    -- ===== Guerra degli Eroi =====
    select 'e_level'::text as metric, coalesce((select h.level from public.game_heroes h where h.user_id = v_u), 0)::bigint as v, null::timestamptz[] as ts
    union all select 'e_boss', count(*), array_agg(r.created_at order by r.created_at) from public.game_rewards r where r.user_id = v_u
    union all select 'e_arena', count(*), array_agg(d.created_at order by d.created_at) from public.game_duels d where d.winner_id = v_u
    union all select 'e_dungeon', count(*), array_agg(p.first_clear_at order by p.first_clear_at) from public.game_dungeon_progress p where p.user_id = v_u and p.clears > 0
    union all select 'e_squadra', count(*), array_agg(coalesce(r.finished_at, r.created_at) order by coalesce(r.finished_at, r.created_at))
      from public.game_runs r join public.game_run_members rm on rm.run_id = r.id and rm.user_id = v_u where r.status = 'cleared'
    union all select 'e_attacchi', count(*), array_agg(x.created_at order by x.created_at) from public.game_day_log x where x.user_id = v_u and x.action = 'attack'
    union all select 'e_cure', count(*), array_agg(x.created_at order by x.created_at) from public.game_day_log x where x.user_id = v_u and x.action = 'heal'
    union all select 'e_guardia', count(*), array_agg(x.created_at order by x.created_at) from public.game_day_log x where x.user_id = v_u and x.action = 'guard'
    union all select 'e_arsenale', count(*), array_agg(i.acquired_at order by i.acquired_at) from public.game_inventory i where i.user_id = v_u and i.source <> 'start'
    union all select 'e_ruoli', count(*), case when count(*) = 3 then array[null::timestamptz, null::timestamptz, max(f)] end
      from (select rm.role, min(coalesce(r.finished_at, r.created_at)) as f
              from public.game_runs r join public.game_run_members rm on rm.run_id = r.id and rm.user_id = v_u
             where r.status = 'cleared' group by rm.role) q
    -- ===== Scommesse =====
    union all select 'b_puntate', count(*), array_agg(b.created_at order by b.created_at) from public.bets b where b.user_id = v_u
    union all select 'b_vinte', count(*), array_agg(b.settled_at order by b.settled_at) from public.bets b where b.user_id = v_u and b.status = 'won'
    union all select 'b_serie', coalesce(max(c), 0), null
      from (select count(*) as c
              from (select (b.status = 'won') as w,
                           sum(case when b.status = 'won' then 0 else 1 end) over (order by b.settled_at, b.created_at, b.id) as g
                      from public.bets b where b.user_id = v_u and b.status in ('won', 'lost')) x
             where x.w group by x.g) y
    union all select 'b_quota', coalesce(max(b.quota), 0), null from public.bets b where b.user_id = v_u and b.status = 'won'
    union all select 'b_vincita', coalesce(max(b.returned - b.stake), 0), null from public.bets b where b.user_id = v_u and b.status = 'won'
    union all select 'b_profitto', greatest(0, coalesce(sum(case b.status when 'won' then b.returned - b.stake else -b.stake end), 0)), null
      from public.bets b where b.user_id = v_u and b.status in ('won', 'lost')
    union all select 'b_volume', coalesce(sum(b.stake), 0), null from public.bets b where b.user_id = v_u and b.status in ('open', 'won', 'lost')
    union all select 'b_outsider', count(*), array_agg(b.settled_at order by b.settled_at) from public.bets b where b.user_id = v_u and b.status = 'won' and b.prob_pct <= 30
    -- ===== Duel Simulator =====
    union all select 's_partite', count(*), array_agg(sl.finished_at order by sl.finished_at) from sl
    union all select 's_vittorie', count(*), array_agg(sl.finished_at order by sl.finished_at) from sl where sl.winner_seat = sl.seat
    union all select 's_duelli', count(*), array_agg(sg.ended_at order by sg.ended_at) from sg where sg.winner_seat = sg.seat
    union all select 's_serie', coalesce(max(c), 0), null
      from (select count(*) as c
              from (select (sl.winner_seat = sl.seat) as w,
                           sum(case when sl.winner_seat = sl.seat then 0 else 1 end) over (order by sl.finished_at, sl.id) as g
                      from sl) x
             where x.w group by x.g) y
    union all select 's_rimonta', count(*), array_agg(sl.finished_at order by sl.finished_at) from sl
      where sl.winner_seat = sl.seat
        and exists (select 1 from sg where sg.lobby_id = sl.id and sg.no = 1 and sg.winner_seat <> sl.seat)
    union all select 's_mazzi', count(*), array_agg(dk.created_at order by dk.created_at) from public.sim_decks dk where dk.owner_id = v_u and not dk.temp
    union all select 's_invitto', count(*), array_agg(sg.ended_at order by sg.ended_at) from sg where sg.winner_seat = sg.seat and sg.my_lp >= 8000
  ),
  m as (
    select m0.metric, m0.v, m0.ts from m0
    -- ===== Speciale: tre mondi =====
    union all select 'x_tre', (select (m0.v >= 1)::int from m0 where m0.metric = 'b_vinte')
                            + (select (m0.v >= 1)::int from m0 where m0.metric = 'e_dungeon')
                            + (select (m0.v >= 1)::int from m0 where m0.metric = 's_vittorie'), null::timestamptz[]
  ),
  r as (
    select d.code, d.family, d.area, d.tier, d.metric, d.kind, d.threshold, d.sort,
           (case when d.area = 'eroi' then not v_h when d.area = 'sim' then not v_s when d.metric = 'x_tre' then not (v_h and v_s) else false end) as hid,
           m.v, m.ts
      from public.badge_extra_defs d join m on m.metric = d.metric
  )
  select r.code, r.family, r.area, r.tier, r.metric, r.kind, r.threshold,
         (case when r.hid then 0
               when r.area = 'bets' and not v_self then (case when r.v >= r.threshold then r.threshold else 0 end)   -- privacy: altri vedono solo l'esito
               else r.v end)::bigint as value,
         (not r.hid and r.v >= r.threshold) as earned,
         (case when not r.hid and r.v >= r.threshold and r.ts is not null then r.ts[r.threshold::int] end) as earned_at,
         r.hid as hidden,
         r.sort
    from r
   order by r.sort;
end $$;

revoke all on function public.badge_progress_extra(uuid) from public, anon;
grant execute on function public.badge_progress_extra(uuid) to authenticated;

commit;
