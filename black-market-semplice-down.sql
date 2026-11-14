-- Annulla la migrazione 045 (primi passi). Non tocca public_showcase(), che appartiene alla Home. I bonus già pagati restano nel registro e nei saldi.
begin;
drop function if exists public.onboarding_claim(text);
drop function if exists public.onboarding_state();
drop function if exists public._onboarding_done(uuid, text);
delete from public.system_settings where key in ('onboarding_enabled','onboarding_step_bc','unlock_matches');
commit;
