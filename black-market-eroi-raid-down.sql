-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 039 (raid settimanale)
-- Torna il boss del giorno, tornano la vetrina e i badge di prima. Le tabelle del raid NON vengono cancellate (classifiche, premi e
-- registro restano consultabili e i BC già dati restano dove sono): si spengono funzioni e collegamenti.
-- Per cancellare anche i dati del raid, dopo questo file: drop table public.game_raid_rewards, public.game_raid_log, public.game_raid_damage,
-- public.game_raid_days, public.game_raids, public.game_raid_bosses;
-- =====================================================================
begin;
drop trigger if exists game_day_heroes_raid on public.game_day_heroes;
drop function if exists public._trg_raid_blocks_daily();
drop function if exists public.game_raid_act(text, uuid);
drop function if exists public.game_raid_state();
drop function if exists public._raid_settle(bigint);
drop function if exists public._raid_ensure();
drop function if exists public._raid_me(bigint, uuid);
drop function if exists public._raid_capacity(uuid);
-- badge: rimette la funzione originale
do $$ begin
  if to_regprocedure('public._badge_progress_extra_base(uuid)') is not null then
    drop function if exists public.badge_progress_extra(uuid);
    alter function public._badge_progress_extra_base(uuid) rename to badge_progress_extra;
    grant execute on function public.badge_progress_extra(uuid) to authenticated;
  end if;
end $$;
-- vetrina: rimette la funzione originale
do $$ begin
  if to_regprocedure('public._public_showcase_base()') is not null then
    drop function if exists public.public_showcase();
    alter function public._public_showcase_base() rename to public_showcase;
    grant execute on function public.public_showcase() to anon, authenticated;
  end if;
end $$;
drop function if exists public._raid_ends_at(date);
drop function if exists public._raid_week(date);
delete from public.system_settings where key = 'game_raid_enabled';   -- riapplicando la 039 il raid riparte acceso
commit;
