-- Annulla la migrazione 045 (vetrina pubblica e primi passi). I bonus già pagati restano nel registro e nei saldi.
begin;
drop function if exists public.onboarding_claim(text);
drop function if exists public.onboarding_state();
drop function if exists public._onboarding_done(uuid, text);
drop function if exists public.public_showcase();
delete from public.system_settings where key in ('showcase_public','onboarding_enabled','onboarding_step_bc','unlock_matches');
commit;
