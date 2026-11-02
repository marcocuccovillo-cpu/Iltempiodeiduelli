-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 037 (inviti e vetrina pubblica)
-- Toglie funzioni, trigger, tabelle e impostazioni degli inviti e la vetrina pubblica.
-- I movimenti già registrati (invite_reward, invite_bonus) RESTANO nel registro contabile, che non si cancella mai:
-- per questo i due tipi di movimento restano ammessi. Le notifiche degli inviti già inviate vengono cancellate.
-- =====================================================================
begin;
drop trigger if exists invite_on_ladder on public.ladder_matches;
drop trigger if exists invite_on_match on public.matches;
drop function if exists public._trg_invite_ladder();
drop function if exists public._trg_invite_match();
drop function if exists public._invite_check(uuid, uuid, text, uuid);
drop function if exists public.redeem_invite(text);
drop function if exists public.my_invite();
drop function if exists public.invite_info(text);
drop function if exists public._invite_has_played(uuid, uuid);
drop function if exists public.badge_progress_invite(uuid);
drop function if exists public.public_showcase();
drop table if exists public.invites;
drop table if exists public.invite_codes;
delete from public.system_settings where key in ('invite_enabled','invite_reward_bc','invite_bonus_bc','invite_max_rewards','invite_redeem_days');
delete from public.notifications where kind = 'invite_reward';
commit;
