-- =====================================================================
-- ANNULLAMENTO della migrazione 002 (black-market-moduli.sql).
-- ATTENZIONE: cancella le tabelle dei tre moduli e i loro dati (fazioni, membri, sfide, stagioni).
-- Non tocca nulla della migrazione 001: wallet, registro, taglie, match ed eventi restano com'erano.
-- Da usare solo se vuoi davvero rimuovere i moduli. Fai prima l'esportazione dal pannello Admin.
-- =====================================================================
begin;  -- tutto o niente: se qualcosa fallisce, non resta nulla a metà
drop view if exists public.hof_records_v, public.hof_milestones_v, public.hof_events_v, public.hof_rivalries_v,
  public.hof_claims_v, public.hof_season_stats_v, public.hof_player_stats_v, public.hof_matches_v,
  public.faction_members_v, public.faction_standings_v, public.faction_scored_matches_v, public.challenges_v;

drop function if exists public.admin_set_module(text, boolean, text), public.admin_create_season(text, date, date, text),
  public.create_faction(text, text, text), public.join_faction(uuid), public.leave_faction(), public.transfer_faction_leadership(uuid),
  public.kick_faction_member(uuid), public.update_faction(text, text),
  public.admin_faction_disband(uuid, text), public.admin_faction_rename(uuid, text, text), public.admin_faction_move_member(uuid, uuid, text),
  public.admin_faction_exclude_match(uuid, text), public.admin_faction_include_match(uuid, text),
  public.expire_challenges(), public.create_challenge(uuid, text, text), public.respond_challenge(uuid, boolean), public.cancel_challenge(uuid),
  public.link_challenge_match(uuid, uuid), public.complete_challenge(uuid), public.admin_cancel_challenge(uuid, text);

drop table if exists public.challenges, public.faction_match_exclusions, public.faction_members, public.factions, public.seasons;

drop function if exists public._require_module(text), public._module_on(text), public._no_delete();

delete from public.system_settings where key in ('module_hall_of_fame','module_faction_wars','module_underground','hof_rivalry_min_matches',
  'faction_points_per_win','faction_cooldown_days','faction_max_members','challenge_expiry_days','challenge_max_open');
-- Il registro di audit è immutabile: le righe scritte dai moduli restano, come previsto.

commit;
