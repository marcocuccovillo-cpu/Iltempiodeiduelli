-- =====================================================================
-- ANNULLAMENTO della migrazione 003 (black-market-ladder.sql).
-- ATTENZIONE: cancella la Ladder (sfide, risultati ed Elo) e le immagini avatar degli utenti.
-- Non tocca la 001 né la 002: wallet, registro, taglie, match, eventi, fazioni e sfide restano come sono.
-- Se hai applicato anche l'annullamento della 002, eseguilo DOPO questo file, non prima.
-- Fai prima l'esportazione dal pannello Admin (gli avatar e la Ladder non sono inclusi: salva ciò che ti serve).
-- =====================================================================
begin;
drop view if exists public.ladder_standings_v;
drop table if exists public.ladder_matches, public.ladder_ratings;
drop function if exists public._ladder_guard(), public._ladder_close(uuid, text, text, uuid, uuid, text),
  public.ladder_expire(), public.ladder_challenge(uuid, text, text, text), public.ladder_respond(uuid, boolean), public.ladder_cancel(uuid),
  public.ladder_report(uuid, text, text), public.ladder_confirm(uuid), public.ladder_dispute(uuid, text),
  public.admin_ladder_resolve(uuid, text, text, text), public.admin_ladder_void(uuid, text), public.set_my_avatar_img(text);
alter table public.profiles drop column if exists avatar_img;
delete from public.system_settings where key in ('module_ladder','ladder_start_elo','ladder_k','ladder_expiry_days','ladder_stale_days','ladder_max_open','ladder_max_pair_per_day');

-- ripristina admin_set_module com'era nella 002 (tre moduli)
create or replace function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui la migrazione 002'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;
-- Il registro di audit è immutabile: le righe scritte dalla Ladder restano, come previsto.
commit;
